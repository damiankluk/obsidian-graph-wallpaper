#!/usr/bin/env python3
"""Install or remove optional local lifecycle hooks for supported agents."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

AGENT_HOOK_NAME = "obsidian-graph-agent-activity"


def command(helper: Path, agent: str, action: str) -> str:
    return "python3 " + shlex.quote(str(helper)) + " hook " + agent + " " + action


def handler(helper: Path, agent: str, action: str) -> dict:
    return {"type": "command", "command": command(helper, agent, action), "timeout": 2}


def event_group(helper: Path, agent: str, action: str) -> dict:
    return {"hooks": [handler(helper, agent, action)]}


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return data


def save_json(path: Path, data: dict, changed: bool) -> None:
    if not changed:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup = path.with_name(path.name + ".obsidian-graph-" + time.strftime("%Y%m%d-%H%M%S") + ".bak")
        shutil.copy2(path, backup)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    mode = (path.stat().st_mode & 0o777) if path.exists() else 0o600
    os.chmod(temporary, mode)
    os.replace(temporary, path)


def install_codex(path: Path, helper: Path) -> bool:
    data = load_json(path)
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError(f"Codex hooks must be an object in {path}")
    changed = False
    for event, action in (
        ("UserPromptSubmit", "active"),
        ("PreToolUse", "active"),
        ("PostToolUse", "active"),
        ("Stop", "idle"),
        ("Interrupt", "idle"),
        ("SessionEnd", "idle"),
    ):
        group = event_group(helper, "codex", action)
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            raise ValueError(f"Codex hook event {event} must be an array")
        if group not in entries:
            entries.append(group)
            changed = True
    save_json(path, data, changed)
    return changed


def install_claude(path: Path, helper: Path) -> bool:
    data = load_json(path)
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError(f"Claude hooks must be an object in {path}")
    changed = False
    for event, action in (
        ("UserPromptSubmit", "active"),
        ("PreToolUse", "active"),
        ("PostToolUse", "active"),
        ("Stop", "idle"),
        ("SessionEnd", "idle"),
    ):
        group = event_group(helper, "claude", action)
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            raise ValueError(f"Claude hook event {event} must be an array")
        if group not in entries:
            entries.append(group)
            changed = True
    save_json(path, data, changed)
    return changed


def install_antigravity(path: Path, helper: Path) -> bool:
    data = load_json(path)
    definition = data.setdefault(AGENT_HOOK_NAME, {})
    if not isinstance(definition, dict):
        raise ValueError(f"Antigravity hook definition {AGENT_HOOK_NAME} must be an object")
    changed = False
    for event, action in (("PreInvocation", "active"), ("PostInvocation", "active"), ("Stop", "idle")):
        entry = handler(helper, "antigravity", action)
        entries = definition.setdefault(event, [])
        if not isinstance(entries, list):
            raise ValueError(f"Antigravity hook event {event} must be an array")
        if entry not in entries:
            entries.append(entry)
            changed = True
    save_json(path, data, changed)
    return changed


def remove_plugin_handlers(value, helper_path: str):
    changed = False
    if isinstance(value, list):
        kept = []
        for item in value:
            updated, item_changed = remove_plugin_handlers(item, helper_path)
            changed |= item_changed
            if updated is not None and not (
                isinstance(updated, dict)
                and isinstance(updated.get("hooks"), list)
                and not updated["hooks"]
            ):
                kept.append(updated)
            else:
                changed = True
        return kept, changed
    if isinstance(value, dict):
        command_text = value.get("command", "")
        if helper_path in command_text:
            return None, True
        result = {}
        for key, item in value.items():
            updated, item_changed = remove_plugin_handlers(item, helper_path)
            changed |= item_changed
            if updated is not None:
                result[key] = updated
        return result, changed
    return value, False


def remove(path: Path, agent: str, helper: Path) -> bool:
    data = load_json(path)
    changed = False
    if agent == "antigravity":
        if AGENT_HOOK_NAME in data and str(helper) in json.dumps(data[AGENT_HOOK_NAME]):
            del data[AGENT_HOOK_NAME]
            changed = True
    else:
        key = "hooks" if agent == "codex" else "hooks"
        container = data.get(key)
        if isinstance(container, dict):
            updated, changed = remove_plugin_handlers(container, str(helper))
            data[key] = updated
            for event in list(updated):
                if updated[event] == []:
                    del updated[event]
            if not updated and agent == "codex":
                del data[key]
            elif not updated and agent == "claude":
                del data[key]
    save_json(path, data, changed)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "remove", "check"))
    parser.add_argument("--plugin-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.plugin_root.expanduser().resolve()
    helper = root / "agent_activity.py"
    if not helper.is_file():
        print(f"Missing helper: {helper}", file=sys.stderr)
        return 2
    home = Path.home()
    configs = {
        "codex": home / ".codex" / "hooks.json",
        "claude": home / ".claude" / "settings.json",
        "antigravity": home / ".gemini" / "config" / "hooks.json",
    }
    results = {}
    try:
        if args.action == "install":
            subprocess_results = {
                "codex": install_codex(configs["codex"], helper),
                "claude": install_claude(configs["claude"], helper),
                "antigravity": install_antigravity(configs["antigravity"], helper),
            }
            results = {agent: ("updated" if changed else "already configured") for agent, changed in subprocess_results.items()}
            subprocess.run([sys.executable, str(helper), "init"], check=True, stdout=subprocess.DEVNULL)
        elif args.action == "remove":
            results = {agent: ("removed" if remove(path, agent, helper) else "not configured") for agent, path in configs.items()}
        else:
            for agent, path in configs.items():
                data = load_json(path)
                serialized = json.dumps(data)
                results[agent] = "configured" if str(helper) in serialized else "missing"
    except (OSError, json.JSONDecodeError, ValueError, RuntimeError) as exc:
        print(f"Hook configuration error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0 if args.action != "check" or all(value == "configured" for value in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
