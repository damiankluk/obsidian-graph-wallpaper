#!/usr/bin/env python3
"""Build Qt 6 shader packs and verify checked-in packs against their sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
SOURCES = ("bubble.vert", "bubble.frag")
MANIFEST = ROOT / "BUILD.json"


def find_qsb() -> str | None:
    return shutil.which("qsb") or ("/usr/lib/qt6/bin/qsb" if pathlib.Path("/usr/lib/qt6/bin/qsb").is_file() else None)


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_all(output: pathlib.Path) -> None:
    qsb = find_qsb()
    if not qsb:
        raise RuntimeError("Qt qsb tool was not found")
    output.mkdir(parents=True, exist_ok=True)
    for source_name in SOURCES:
        source = ROOT / source_name
        target = output / f"{source_name}.qsb"
        subprocess.run([qsb, "--qt6", "-o", str(target), str(source)], check=True)


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def make_manifest() -> dict:
    return {"schema": 1, "shaders": {
        f"{name}.qsb": {"source_sha256": digest(ROOT / name), "artifact_sha256": digest(ROOT / f"{name}.qsb")}
        for name in SOURCES
    }}


def check(manifest: dict | None = None) -> list[str]:
    problems: list[str] = []
    try:
        expected = manifest if manifest is not None else load_manifest()
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read shader manifest: {error}"]
    actual_names = {f"{name}.qsb" for name in SOURCES}
    if expected.get("schema") != 1 or set(expected.get("shaders", {})) != actual_names:
        return ["shader manifest does not list the complete bubble shader set"]
    for name in sorted(actual_names):
        item = expected["shaders"][name]
        source = ROOT / name.removesuffix(".qsb")
        artifact = ROOT / name
        if not source.is_file() or not artifact.is_file():
            problems.append(f"{name}: source or artifact is missing")
            continue
        if item.get("source_sha256") != digest(source):
            problems.append(f"{name}: source hash differs from BUILD.json")
        if item.get("artifact_sha256") != digest(artifact):
            problems.append(f"{name}: artifact hash differs from BUILD.json")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify checked-in artifacts without rebuilding")
    args = parser.parse_args()
    try:
        if not args.check:
            build_all(ROOT)
            MANIFEST.write_text(json.dumps(make_manifest(), indent=2) + "\n", encoding="utf-8")
        problems = check()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("Qt shader artifacts match their GLSL sources.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
