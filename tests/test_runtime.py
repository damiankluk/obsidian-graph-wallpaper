#!/usr/bin/env python3
"""Focused regression checks for the local watcher and optional agent hooks."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class RuntimeIntegrationTests(unittest.TestCase):
    def test_graph_export_writes_private_atomic_runtime_cache(self):
        with tempfile.TemporaryDirectory(prefix="graph-cache-") as temporary:
            root = pathlib.Path(temporary)
            vault = root / "vault"
            vault.mkdir()
            (vault / "A.md").write_text("[[B]]", encoding="utf-8")
            (vault / "B.md").write_text("# B", encoding="utf-8")
            cache = root / "runtime" / "obsidian-graph" / "graph.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "export_graph.py"), str(vault), "--cache", str(cache)],
                check=True, capture_output=True, text=True,
            )
            output = json.loads(result.stdout)
            saved = json.loads(cache.read_text(encoding="utf-8"))
            self.assertEqual(saved, output)
            self.assertEqual(saved["origin"], "obsidian-vault")
            self.assertEqual(len(saved["nodes"]), 2)
            node_ids = {node["id"] for node in saved["nodes"]}
            self.assertEqual(node_ids, {"A.md", "B.md"})
            self.assertTrue(all((vault / node_id).is_file() for node_id in node_ids))
            self.assertFalse(any("note-0135" in node_id for node_id in node_ids))
            self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
            self.assertEqual(cache.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(list(cache.parent.iterdir()), [cache])

    def test_watcher_reports_markdown_and_ignores_non_markdown(self):
        with tempfile.TemporaryDirectory(prefix="graph-watch-") as temporary:
            vault = pathlib.Path(temporary) / "vault"
            vault.mkdir()
            watcher = subprocess.Popen(
                [sys.executable, str(ROOT / "watch_vault.py"), str(vault)],
                stdout=subprocess.PIPE,
                text=True,
            )
            try:
                assert watcher.stdout is not None
                ready = json.loads(watcher.stdout.readline())
                self.assertEqual(ready["event"], "ready")
                (vault / "ignored.txt").write_text("not a note", encoding="utf-8")
                note = vault / "Live note.md"
                note.write_text("# Updated", encoding="utf-8")
                event = json.loads(watcher.stdout.readline())
                self.assertEqual(event, {"event": "change", "path": "Live note.md"})
            finally:
                watcher.terminate()
                watcher.wait(timeout=3)
                if watcher.stdout is not None:
                    watcher.stdout.close()

    def test_agent_activity_expires_and_does_not_store_hook_payload(self):
        with tempfile.TemporaryDirectory(prefix="graph-activity-") as runtime:
            environment = dict(os.environ, XDG_RUNTIME_DIR=runtime)
            helper = ROOT / "agent_activity.py"
            subprocess.run([sys.executable, str(helper), "init"], env=environment, check=True, capture_output=True)
            payload = json.dumps({"session_id": "test-session", "prompt": "private prompt"}).encode()
            subprocess.run(
                [sys.executable, str(helper), "hook", "codex", "active"],
                env=environment, input=payload, check=True,
            )
            path = pathlib.Path(runtime, "obsidian-graph", "agent-activity.json")
            saved = path.read_text(encoding="utf-8")
            self.assertNotIn("test-session", saved)
            self.assertNotIn("private prompt", saved)
            data = json.loads(saved)
            self.assertEqual(sorted(data["agents"]), ["codex"])
            self.assertEqual(
                sorted(data["agents"]["codex"]),
                [__import__("hashlib").sha256(b"test-session").hexdigest()[:20]],
            )
            subprocess.run(
                [sys.executable, str(helper), "hook", "codex", "idle"],
                env=environment, input=payload, check=True,
            )
            snapshot = json.loads(subprocess.check_output([sys.executable, str(helper), "snapshot"], env=environment))
            self.assertEqual(snapshot["agents"], [])

    def test_hook_manager_preserves_existing_hooks_and_is_idempotent(self):
        with tempfile.TemporaryDirectory(prefix="graph-hooks-") as temporary:
            home = pathlib.Path(temporary)
            (home / ".codex").mkdir()
            (home / ".claude").mkdir()
            (home / ".gemini/config").mkdir(parents=True)
            (home / ".codex/hooks.json").write_text(json.dumps({
                "SessionStart": [{"hooks": [{"type": "command", "command": "keep-codex"}] }]
            }), encoding="utf-8")
            (home / ".claude/settings.json").write_text(json.dumps({
                "model": "keep-model",
                "hooks": {"SessionStart": [{"matcher": "*", "hooks": [{"type": "command", "command": "keep-claude"}]}]},
            }), encoding="utf-8")
            (home / ".gemini/config/hooks.json").write_text(json.dumps({
                "herdr": {"Stop": [{"type": "command", "command": "keep-antigravity"}]}
            }), encoding="utf-8")
            environment = dict(os.environ, HOME=str(home), XDG_RUNTIME_DIR=str(home / "runtime"))
            manager = [sys.executable, str(ROOT / "scripts/manage_agent_hooks.py")]
            for action in ("install", "install", "check"):
                subprocess.run(manager + [action, "--plugin-root", str(ROOT)], env=environment, check=True, capture_output=True)

            codex = json.loads((home / ".codex/hooks.json").read_text(encoding="utf-8"))
            claude = json.loads((home / ".claude/settings.json").read_text(encoding="utf-8"))
            antigravity = json.loads((home / ".gemini/config/hooks.json").read_text(encoding="utf-8"))
            self.assertEqual(codex["SessionStart"][0]["hooks"][0]["command"], "keep-codex")
            self.assertEqual(claude["model"], "keep-model")
            self.assertEqual(claude["hooks"]["SessionStart"][0]["hooks"][0]["command"], "keep-claude")
            self.assertEqual(antigravity["herdr"]["Stop"][0]["command"], "keep-antigravity")
            self.assertIn("obsidian-graph-agent-activity", antigravity)

            subprocess.run(manager + ["remove", "--plugin-root", str(ROOT)], env=environment, check=True, capture_output=True)
            all_config = json.dumps([
                json.loads((home / ".codex/hooks.json").read_text(encoding="utf-8")),
                json.loads((home / ".claude/settings.json").read_text(encoding="utf-8")),
                json.loads((home / ".gemini/config/hooks.json").read_text(encoding="utf-8")),
            ])
            self.assertNotIn(str(ROOT / "agent_activity.py"), all_config)


if __name__ == "__main__":
    unittest.main()
