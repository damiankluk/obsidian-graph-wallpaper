#!/usr/bin/env python3
"""Animation helpers and timer cadence, run through Qt's qml runner."""

from __future__ import annotations

import json
import math
import os
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
QML = "/usr/lib/qt6/bin/qml"


def run_probe() -> dict:
    # Qt logs to the journal unless forced to stderr.
    env = dict(os.environ, QT_FORCE_STDERR_LOGGING="1", QT_QPA_PLATFORM="offscreen")
    done = subprocess.run([QML, "-platform", "offscreen", str(ROOT / "tests" / "qml" / "cadence_probe.qml")],
                          capture_output=True, text=True, timeout=60, env=env)
    for line in done.stderr.splitlines():
        if "PROBE " in line:
            return json.loads(line.split("PROBE ", 1)[1])
    raise AssertionError(f"probe printed nothing (exit {done.returncode}): {done.stderr[-500:]}")


@unittest.skipUnless(os.path.exists(QML), "Qt qml runner not installed")
class CadenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.probe = run_probe()

    def test_timer_selects_only_the_requested_30_or_60_fps_cadence(self):
        intervals = self.probe["intervalMs"]
        self.assertEqual(intervals["idle"], 33)
        self.assertEqual(intervals["settled"], 33)
        self.assertEqual(intervals["pointerResting"], 33)
        for active in ("pointer", "keyboard", "agent"):
            self.assertEqual(intervals[active], 17)
        for tail in ("tailAgent", "tailThought", "tailPointer", "tailKeyboard"):
            self.assertEqual(intervals[tail], 17)

    def test_easing_is_exponential_and_composes_across_steps(self):
        e = self.probe["easing"]
        self.assertAlmostEqual(e["rise"], 1 - math.exp(-0.5 / 0.8), places=9)
        self.assertAlmostEqual(e["fall"], math.exp(-0.5 / 1.6), places=9)
        self.assertAlmostEqual(e["holds"], 0.4, places=9)
        # two steps of 0.1 + 0.4 s land where one step of 0.5 s lands
        self.assertAlmostEqual(e["rolling"], e["single"], places=9)

    def test_pose_is_bounded_and_moves_on_independent_axes(self):
        self.assertTrue(self.probe["poseReusesBuffer"])
        pose = self.probe["pose0"]
        self.assertAlmostEqual(pose["yaw"], 0.06 * math.sin(0.7), places=9)
        self.assertAlmostEqual(pose["pitch"], 0.12, places=9)
        self.assertAlmostEqual(pose["roll"], 0.10 * math.sin(1.1), places=9)
        later = self.probe["poseLater"]
        self.assertAlmostEqual(later["yaw"], 0.18 * math.sin(100 * 2 * math.pi / 47)
                               + 0.06 * math.sin(100 * 2 * math.pi / 83 + 0.7), places=9)
        self.assertAlmostEqual(later["pitch"], 0.12 + 0.12 * math.sin(100 * 2 * math.pi / 53), places=9)
        self.assertLessEqual(abs(later["yaw"]), 0.24)
        self.assertLessEqual(abs(later["roll"]), 0.10)

    def test_pulse_follows_the_agent_level(self):
        idle_pulse, agent_pulse = self.probe["pulse"]
        self.assertEqual(idle_pulse, 0)
        self.assertAlmostEqual(agent_pulse, 0.55 + (math.sin(0) + 1) * 0.075, places=9)

    def test_listening_ripple_rises_quickly_and_fades_within_two_seconds(self):
        self.assertAlmostEqual(self.probe["rippleRise"], 1 - math.exp(-0.1 / 0.08), places=9)
        self.assertLess(self.probe["rippleAfterTwoSeconds"], 0.05)

    def test_all_interaction_states_share_one_bounded_orbit_response(self):
        targets = self.probe["orbitTargets"]
        for actual, expected in zip(targets, [0.55, 0.775, 0.61, 0.61, 1.0]):
            self.assertAlmostEqual(actual, expected, places=9)
        self.assertGreater(targets[-1], max(targets[2:4]))

    def test_integrated_shader_phases_wrap_without_uptime_scaled_jumps(self):
        phases = self.probe["integratedPhases"]
        self.assertAlmostEqual(phases["flow"], (6.2 + 0.1 * 3.4) % (2 * math.pi), places=9)
        self.assertAlmostEqual(phases["thought"], 0.1, places=9)
        self.assertAlmostEqual((phases["next"] - phases["flow"]) % (2 * math.pi), 0.14, places=9)


if __name__ == "__main__":
    unittest.main()
