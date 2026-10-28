#!/usr/bin/env python3
"""Shader artifacts stay in sync with their sources.

shaders/build.py bakes the .qsb files from the GLSL sources with Qt's qsb and
records source and artifact hashes in shaders/BUILD.json. The hash check needs
no Qt tools; the rebuild check runs only where qsb is installed.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "shaders"))
import build  # noqa: E402


class ShaderBuildTests(unittest.TestCase):
    def test_every_artifact_is_listed_and_matches_its_recorded_hashes(self):
        self.assertEqual(build.check(), [])

    def test_stale_source_is_reported(self):
        manifest = build.load_manifest()
        name = next(iter(manifest["shaders"]))
        manifest["shaders"][name]["source_sha256"] = "0" * 64
        problems = build.check(manifest)
        self.assertEqual(len(problems), 1)
        self.assertIn(name, problems[0])

    def test_bubble_shader_pair_is_present(self):
        names = set(build.load_manifest()["shaders"])
        for expected in ("bubble.vert.qsb", "bubble.frag.qsb"):
            self.assertIn(expected, names)
            self.assertTrue((ROOT / "shaders" / expected).is_file())

    @unittest.skipUnless(build.find_qsb(), "qsb not installed")
    def test_rebuild_from_sources_reproduces_committed_artifacts(self):
        with tempfile.TemporaryDirectory(prefix="ogshader-") as out:
            build.build_all(pathlib.Path(out))
            for name in build.load_manifest()["shaders"]:
                self.assertEqual((pathlib.Path(out) / name).read_bytes(), (ROOT / "shaders" / name).read_bytes(),
                                 f"{name} differs from a fresh bake; run python3 shaders/build.py")

    @unittest.skipUnless(build.find_qsb(), "qsb not installed")
    def test_artifacts_target_the_qt_quick_backends(self):
        qsb = build.find_qsb()
        result = subprocess.run([qsb, "-d", str(ROOT / "shaders" / "bubble.vert.qsb")],
                                capture_output=True, text=True, check=True)
        info = result.stdout + result.stderr
        for target in ("SPIR-V", "GLSL 100 es", "GLSL 120", "GLSL 150", "HLSL 50", "MSL 12"):
            self.assertIn(target, info)


if __name__ == "__main__":
    unittest.main()
