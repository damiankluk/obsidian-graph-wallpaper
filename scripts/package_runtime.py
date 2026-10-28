#!/usr/bin/env python3
"""Create a content-addressed QML package to bypass Qt's stale URL cache.

Omarchy's plugin rescans can recreate a service without invalidating the
QQmlEngine component cache. Pointing the manifest at a new directory gives
Service.qml, Graph3DView.qml, and the shader resources fresh URLs on each code
change while preserving the conventional Service.qml filename.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import tempfile
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifest.json"
RUNTIME_ROOT = ROOT / "runtime"
SOURCES = (
    "Service.qml",
    "Graph3DView.qml",
    "GraphGeometry.js",
    "Cadence.js",
    "shaders/graph3d.frag",
    "shaders/graph3d.vert",
)
SERVICE_REWRITES = {
    'Qt.resolvedUrl("export_graph.py")': 'Qt.resolvedUrl("../../export_graph.py")',
    'Qt.resolvedUrl("watch_vault.py")': 'Qt.resolvedUrl("../../watch_vault.py")',
}


def package_digest() -> str:
    digest = hashlib.sha256(b"obsidian-graph-qml-runtime-v1\0")
    for relative in SOURCES:
        path = ROOT / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        digest.update(relative.encode("utf-8") + b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()[:16]


def packaged_files() -> dict[str, bytes]:
    files = {relative: (ROOT / relative).read_bytes() for relative in SOURCES if relative != "Service.qml"}
    service = (ROOT / "Service.qml").read_text(encoding="utf-8")
    for source, replacement in SERVICE_REWRITES.items():
        if service.count(source) != 1:
            raise ValueError(f"expected exactly one service path to rewrite: {source}")
        service = service.replace(source, replacement)
    files["Service.qml"] = service.encode("utf-8")
    return files


def expected_entrypoint() -> str:
    return f"runtime/v{package_digest()}/Service.qml"


def check() -> list[str]:
    errors: list[str] = []
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        expected = expected_entrypoint()
        package_dir = ROOT / expected.removesuffix("/Service.qml")
        if manifest.get("entryPoints", {}).get("service") != expected:
            errors.append(f"manifest service entry must be {expected}")
        for relative, content in packaged_files().items():
            target = package_dir / relative
            if not target.is_file():
                errors.append(f"runtime package is missing {target.relative_to(ROOT)}")
            elif target.is_symlink():
                errors.append(f"runtime package contains a symlink: {target.relative_to(ROOT)}")
            elif target.read_bytes() != content:
                errors.append(f"runtime package is stale: {target.relative_to(ROOT)}")
        if package_dir.is_dir():
            actual = {p.relative_to(package_dir).as_posix() for p in package_dir.rglob("*") if p.is_file()}
            wanted = set(packaged_files())
            if actual != wanted:
                errors.append(f"runtime package file set differs: extra={sorted(actual - wanted)}, missing={sorted(wanted - actual)}")
        if RUNTIME_ROOT.is_dir():
            stale = [p.name for p in RUNTIME_ROOT.iterdir()
                     if p.is_dir() and re.fullmatch(r"v[0-9a-f]{16}", p.name) and p.name != package_dir.name]
            if stale:
                errors.append(f"stale content-addressed runtime directories remain: {', '.join(sorted(stale))}")
    except (OSError, json.JSONDecodeError, ValueError) as error:
        errors.append(str(error))
    return errors


def write() -> None:
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    digest = package_digest()
    target = RUNTIME_ROOT / f"v{digest}"
    files = packaged_files()
    with tempfile.TemporaryDirectory(prefix=f".building-{digest}-", dir=RUNTIME_ROOT) as temporary:
        staging = pathlib.Path(temporary)
        for relative, content in files.items():
            output = staging / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(content)
        if target.exists():
            shutil.rmtree(target)
        os.replace(staging, target)

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    manifest.setdefault("entryPoints", {})["service"] = f"runtime/v{digest}/Service.qml"
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for child in RUNTIME_ROOT.iterdir():
        if child == target or not child.is_dir():
            continue
        if re.fullmatch(r"v[0-9a-f]{16}", child.name):
            shutil.rmtree(child)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true", help="write the current content-addressed runtime package")
    action.add_argument("--check", action="store_true", help="verify the manifest and generated package")
    args = parser.parse_args()
    if args.write:
        try:
            write()
        except (OSError, json.JSONDecodeError, ValueError) as error:
            print(error, file=sys.stderr)
            return 1
    errors = check()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Runtime package is current: {expected_entrypoint()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
