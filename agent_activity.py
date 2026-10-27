#!/usr/bin/env python3
"""Small local activity bridge for the Obsidian graph wallpaper hooks."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

AGENTS = {"codex", "claude", "antigravity"}
LEASE_SECONDS = 180


def runtime_dir() -> Path:
    value = os.environ.get("XDG_RUNTIME_DIR")
    if value:
        return Path(value) / "obsidian-graph"
    return Path(f"/run/user/{os.getuid()}/obsidian-graph")


def state_path() -> Path:
    return runtime_dir() / "agent-activity.json"


def read_state(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("agents"), dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {"version": 1, "agents": {}}


def write_state(path: Path, data: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd, temporary = tempfile.mkstemp(prefix=".agent-activity-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, separators=(",", ":"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def active_names(data: dict, now: int | None = None) -> list[str]:
    now = int(time.time()) if now is None else now
    names = []
    for agent, sessions in data.get("agents", {}).items():
        if any(int(expiry) > now for expiry in sessions.values()):
            names.append(agent)
    return sorted(names)


def update(agent: str, action: str, payload: dict) -> None:
    if agent not in AGENTS or action not in {"active", "idle"}:
        return
    raw_session = (payload.get("session_id") or payload.get("conversationId") or
                   payload.get("sessionId") or payload.get("turn_id") or "default")
    session = hashlib.sha256(str(raw_session).encode("utf-8", "replace")).hexdigest()[:20]
    path = state_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = path.with_suffix(".lock")
    with lock_path.open("a", encoding="utf-8") as lock:
        os.chmod(lock_path, 0o600)
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        now = int(time.time())
        data = read_state(path)
        agents = data.setdefault("agents", {})
        for name in list(agents):
            sessions = {key: int(expiry) for key, expiry in agents[name].items() if int(expiry) > now}
            if sessions:
                agents[name] = sessions
            else:
                del agents[name]
        if action == "active":
            agents.setdefault(agent, {})[session] = now + LEASE_SECONDS
        else:
            sessions = agents.get(agent, {})
            sessions.pop(session, None)
            if not sessions:
                agents.pop(agent, None)
        data["updatedAt"] = now
        write_state(path, data)


def hook(agent: str, action: str) -> int:
    try:
        payload = json.loads(sys.stdin.read(65537))
        if not isinstance(payload, dict):
            payload = {}
        update(agent, action, payload)
    except Exception:
        # Status visualization must never block or alter an agent action.
        pass
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init")
    sub.add_parser("snapshot")
    hook_parser = sub.add_parser("hook")
    hook_parser.add_argument("agent", choices=sorted(AGENTS))
    hook_parser.add_argument("action", choices=("active", "idle"))
    args = parser.parse_args()
    if args.command == "init":
        path = state_path()
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if not path.exists():
            write_state(path, {"version": 1, "updatedAt": int(time.time()), "agents": {}})
        print(path)
        return 0
    if args.command == "snapshot":
        data = read_state(state_path())
        print(json.dumps({"agents": active_names(data), "updatedAt": data.get("updatedAt")}, separators=(",", ":")))
        return 0
    return hook(args.agent, args.action)


if __name__ == "__main__":
    raise SystemExit(main())
