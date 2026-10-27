#!/usr/bin/env python3
"""Export an Obsidian vault's local Markdown links as bounded graph JSON."""

from __future__ import annotations

import fnmatch
import json
import math
import re
import sys
from pathlib import Path
from urllib.parse import unquote

MAX_NOTES = 1200
MAX_FILE_BYTES = 1_000_000
MAX_EDGES = 4000
SKIP_DIRS = {".obsidian", ".git", ".trash", "_trash", "node_modules"}
WIKILINK_RE = re.compile(r"!?\[\[([^\]]+)\]\]")
MARKDOWN_LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")


def normalized_target(value: str) -> str:
    value = value.strip().split("|", 1)[0].split("#", 1)[0].strip()
    if value.startswith("<") and value.endswith(">"):
        value = value[1:-1]
    return unquote(value).replace("\\", "/").strip("/")


def ignore_patterns(vault: Path) -> list[str]:
    app_json = vault / ".obsidian" / "app.json"
    try:
        settings = json.loads(app_json.read_text(encoding="utf-8"))
        patterns = settings.get("userIgnoreFilters", [])
        return [str(p).strip().lstrip("/") for p in patterns if isinstance(p, str) and p.strip()]
    except (OSError, json.JSONDecodeError, AttributeError):
        return []


def ignored(relative: str, patterns: list[str]) -> bool:
    parts = Path(relative).parts
    if any(part.startswith(".") or part in SKIP_DIRS for part in parts[:-1]):
        return True
    return any(fnmatch.fnmatch(relative, pattern) or fnmatch.fnmatch(Path(relative).name, pattern) for pattern in patterns)


def resolve_note(target: str, source: Path, vault: Path, exact: dict[str, str], by_name: dict[str, list[str]]) -> str | None:
    target = normalized_target(target)
    if not target or "://" in target or target.startswith(("mailto:", "#")):
        return None
    candidate = Path(target)
    if candidate.suffix.lower() not in {".md", ".markdown"}:
        candidate = candidate.with_suffix(".md")

    relative_candidates = [source.parent / candidate, vault / candidate]
    for path in relative_candidates:
        try:
            relative = path.resolve(strict=False).relative_to(vault).as_posix()
        except ValueError:
            continue
        if relative in exact:
            return exact[relative]

    stem = candidate.stem.casefold()
    matches = by_name.get(stem, [])
    return matches[0] if matches else None


def export(vault: Path) -> dict:
    vault = vault.expanduser().resolve(strict=True)
    if not vault.is_dir():
        raise ValueError(f"Vault path is not a directory: {vault}")

    patterns = ignore_patterns(vault)
    files = []
    for path in vault.rglob("*.md"):
        relative = path.relative_to(vault).as_posix()
        if path.is_symlink() or not path.is_file() or ignored(relative, patterns):
            continue
        files.append((relative, path))
    files.sort(key=lambda item: item[0].casefold())
    files = files[:MAX_NOTES]

    exact: dict[str, str] = {relative: relative for relative, _ in files}
    by_name: dict[str, list[str]] = {}
    for relative, _ in files:
        by_name.setdefault(Path(relative).stem.casefold(), []).append(relative)

    edges: set[tuple[str, str]] = set()
    for relative, path in files:
        try:
            if path.stat().st_size > MAX_FILE_BYTES:
                continue
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        targets = [match.group(1) for match in WIKILINK_RE.finditer(content)]
        targets.extend(match.group(1).split(",", 1)[0].split(' "', 1)[0] for match in MARKDOWN_LINK_RE.finditer(content))
        for target in targets:
            destination = resolve_note(target, path, vault, exact, by_name)
            if destination and destination != relative:
                edge = tuple(sorted((relative, destination)))
                edges.add(edge)
                if len(edges) >= MAX_EDGES:
                    break
        if len(edges) >= MAX_EDGES:
            break

    ordered_files = [relative for relative, _ in files]
    groups = sorted({relative.split("/", 1)[0] if "/" in relative else "Vault" for relative in ordered_files})
    group_indexes = {group: index for index, group in enumerate(groups)}
    degree: dict[str, int] = {relative: 0 for relative in ordered_files}
    for source, destination in edges:
        degree[source] += 1
        degree[destination] += 1

    count = max(1, len(ordered_files))
    nodes = []
    golden_angle = math.pi * (3 - math.sqrt(5))
    for index, relative in enumerate(ordered_files):
        y = 1 - 2 * (index + 0.5) / count
        radius = math.sqrt(max(0, 1 - y * y))
        angle = golden_angle * index
        group = relative.split("/", 1)[0] if "/" in relative else "Vault"
        nodes.append({
            "id": relative,
            "label": Path(relative).stem,
            "group": group,
            "groupIndex": group_indexes[group],
            "degree": degree[relative],
            "x": round(math.cos(angle) * radius, 6),
            "y": round(y, 6),
            "z": round(math.sin(angle) * radius, 6),
        })

    return {
        "nodes": nodes,
        "edges": [list(edge) for edge in sorted(edges)],
        "stats": {"notes": len(nodes), "links": len(edges), "noteLimit": MAX_NOTES, "linkLimit": MAX_EDGES},
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: export_graph.py VAULT_PATH", file=sys.stderr)
        return 2
    try:
        print(json.dumps(export(Path(sys.argv[1])), separators=(",", ":")))
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
