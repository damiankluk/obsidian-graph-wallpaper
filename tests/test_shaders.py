#!/usr/bin/env python3
"""Contract checks for the single Qt Quick 3D graph renderer."""

from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class GraphRendererTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qml = (ROOT / "Graph3DView.qml").read_text(encoding="utf-8")
        cls.vertex = (ROOT / "shaders/graph3d.vert").read_text(encoding="utf-8")
        cls.fragment = (ROOT / "shaders/graph3d.frag").read_text(encoding="utf-8")

    def test_real_scene_uses_batched_procedural_geometry(self):
        self.assertIn("import QtQuick3D", self.qml)
        self.assertIn("import QtQuick3D.Helpers", self.qml)
        self.assertEqual(self.qml.count("ProceduralMesh {"), 4)
        self.assertIn("root.alternateGeometryActive ? nodeGeometryAlternate : nodeGeometry", self.qml)
        self.assertIn("root.alternateGeometryActive ? edgeGeometryAlternate : edgeGeometry", self.qml)
        self.assertNotIn("Canvas {", self.qml)
        self.assertNotIn("Repeater3D", self.qml)
        self.assertIn("primitiveMode: ProceduralMesh.Lines", self.qml)

    def test_vertex_shader_outputs_a_real_3d_position(self):
        for axis in ("rotateY", "rotateX", "rotateZ"):
            self.assertIn(axis, self.vertex)
        self.assertIn("POSITION = MODELVIEWPROJECTION_MATRIX * vec4(p, 1.0)", self.vertex)
        self.assertIn("float radialDisplacement", self.vertex)
        self.assertIn("float depthVisibility", self.fragment)
        self.assertNotIn("vec3(local / radius, 0.0)", self.vertex)

    def test_agent_and_listening_motion_are_gpu_driven(self):
        for token in ("uAgent", "uWavePhaseA", "uWavePhaseB", "uBreathPhase"):
            self.assertIn(token, self.vertex)
        for token in ("uPointerLevel", "uKeyboardLevel", "uPointerPhase"):
            self.assertIn(token, self.vertex)
        self.assertIn("uAgent *", self.fragment)
        self.assertIn("uFlowPhase", self.fragment)

    def test_every_shader_uniform_has_a_qml_property(self):
        properties = set(re.findall(r"property\s+(?:real|vector3d)\s+(u\w+)", self.qml))
        shader_names = set(re.findall(r"\bu[A-Z]\w*\b", self.vertex + self.fragment))
        self.assertEqual(shader_names - properties, set())

    def test_graph_arrays_are_released_after_mesh_upload(self):
        build = self.qml[self.qml.index("function rebuildGeometry"):self.qml.index("function updateLabels")]
        self.assertIn("geometryBuildTimer.restart()", build)
        self.assertIn("GraphGeometry.build(state.graph", build)
        self.assertIn("nextNodeGeometry.positions = state.converted.nodepositions", build)
        self.assertIn("nextEdgeGeometry.positions = state.converted.edgepositions", build)
        self.assertIn("alternateGeometryActive = !alternateGeometryActive", build)
        self.assertIn("geometryBuild = null", build)
        self.assertIn("geometryData = { nodeCount: state.nodeCount, edgeCount: state.builtEdgeCount }", build)
        self.assertNotIn("geometryData = next", build)


if __name__ == "__main__":
    unittest.main()
