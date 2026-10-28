#!/usr/bin/env python3
"""Static GPU graph mesh construction and label identity checks."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
QML = "/usr/lib/qt6/bin/qml"


def run_probe() -> dict:
    env = dict(os.environ, QT_FORCE_STDERR_LOGGING="1", QT_QPA_PLATFORM="offscreen")
    result = subprocess.run([QML, "-platform", "offscreen", str(ROOT / "tests/qml/graphgeometry_probe.qml")],
                            capture_output=True, text=True, timeout=30, env=env)
    for line in result.stderr.splitlines():
        if "GEOMETRY " in line:
            return json.loads(line.split("GEOMETRY ", 1)[1])
    raise AssertionError(f"geometry probe failed ({result.returncode}): {result.stderr[-800:]}")


@unittest.skipUnless(os.path.exists(QML), "Qt qml runner not installed")
class GraphGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mesh = run_probe()

    def test_mesh_has_real_note_geometry_and_only_resolved_links(self):
        mesh = self.mesh
        self.assertEqual(mesh["nodeCount"], 2)
        self.assertEqual(mesh["edgeCount"], 1)
        self.assertEqual(mesh["chunkNodeVertices"], 24)
        self.assertAlmostEqual(mesh["chunkNodeUv"], 0.75)
        self.assertEqual(mesh["chunkEdgeVertices"], 13)
        self.assertEqual(mesh["chunkEdgeIndices"], 24)
        self.assertTrue(mesh["chunkReconstructionMatches"])
        self.assertEqual(mesh["nodeVertices"], 48)
        self.assertEqual(mesh["nodeIndices"], 48)
        self.assertEqual(mesh["edgeVertices"], 13)
        self.assertEqual(mesh["edgeIndices"], 24)
        self.assertAlmostEqual(mesh["edgeRadiusMin"], 440, places=3)
        self.assertAlmostEqual(mesh["edgeRadiusMax"], 440, places=3)
        self.assertAlmostEqual(mesh["endpoints"][0], 440, places=3)
        self.assertAlmostEqual(mesh["endpoints"][3], -440, places=3)

    def test_labels_and_focus_use_real_unique_note_titles(self):
        self.assertEqual(self.mesh["labels"], [0, 1])
        self.assertEqual(self.mesh["uniqueTitle"], 0)
        self.assertEqual(self.mesh["duplicateTitle"], -1)


if __name__ == "__main__":
    unittest.main()
