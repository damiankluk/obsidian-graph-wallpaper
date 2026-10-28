#!/usr/bin/env python3
"""Cadence policy: the real Cadence.js, run headless through Qt's qml runner.

The policy is a pure function of state (no feedback from measured frame time),
so these checks drive it with simulated display ticks.
"""

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

    def test_two_states_only(self):
        fps = self.probe["fps"]
        self.assertEqual(fps["idle"], 30)
        for active in ("pointer", "keyboard", "agent"):
            self.assertEqual(fps[active], 60)

    def test_easing_tail_stays_at_60_until_it_has_settled(self):
        fps = self.probe["fps"]
        for tail in ("tailAgent", "tailThought", "tailPointer", "tailKeyboard"):
            self.assertEqual(fps[tail], 60)
        self.assertEqual(fps["settled"], 30)

    def test_mean_rate_is_exact_on_every_common_refresh_rate(self):
        for hz, result in self.probe["sim"].items():
            for state, nominal in (("idle", 30), ("active", 60)):
                r = result[state]
                with self.subTest(hz=hz, state=state):
                    # one present of tolerance over 10 s
                    self.assertAlmostEqual(r["count"], nominal * 10, delta=1)

    def test_present_gaps_stay_within_one_display_tick_of_nominal(self):
        for hz, result in self.probe["sim"].items():
            tick = 1 / int(hz)
            for state, nominal in (("idle", 30), ("active", 60)):
                r = result[state]
                with self.subTest(hz=hz, state=state):
                    self.assertLessEqual(r["maxGap"], 1 / nominal + tick * 1.01)
                    self.assertGreaterEqual(r["minGap"], 1 / nominal - tick * 1.01)

    def test_scene_clock_receives_all_elapsed_time(self):
        # every presented frame carries the true elapsed time since the previous one
        for hz, result in self.probe["sim"].items():
            for state in ("idle", "active"):
                r = result[state]
                with self.subTest(hz=hz, state=state):
                    self.assertAlmostEqual(r["elapsed"], r["simulated"], delta=2 / int(hz) + 1 / 30)

    def test_idle_to_active_switch_has_no_burst_and_no_stall(self):
        sw = self.probe["switchOver"]
        self.assertLessEqual(sw["firstAfterGap"], 1 / 30 + 0.01)
        self.assertGreaterEqual(sw["minGapAfter"], 1 / 60 - 1 / 180 * 1.01)

    def test_easing_is_exponential_and_composes_across_steps(self):
        e = self.probe["easing"]
        self.assertAlmostEqual(e["rise"], 1 - math.exp(-0.5 / 0.8), places=9)
        self.assertAlmostEqual(e["fall"], math.exp(-0.5 / 1.6), places=9)
        self.assertAlmostEqual(e["holds"], 0.4, places=9)
        # two steps of 0.1 + 0.4 s land where one step of 0.5 s lands
        self.assertAlmostEqual(e["rolling"], e["single"], places=9)

    def test_pose_matches_existing_multi_axis_drift(self):
        pose = self.probe["pose0"]
        self.assertAlmostEqual(pose["yaw"], 0, places=9)
        self.assertAlmostEqual(pose["pitch"], 0.20, places=9)
        self.assertAlmostEqual(pose["roll"], 0.16 * math.sin(1.1), places=9)
        later = self.probe["poseLater"]
        self.assertAlmostEqual(later["yaw"], 100 * 0.045, places=9)
        self.assertAlmostEqual(later["pitch"], 0.20 + 0.22 * math.sin(100 * 2 * math.pi / 47), places=9)

    def test_pulse_follows_the_agent_level(self):
        idle_pulse, agent_pulse = self.probe["pulse"]
        self.assertEqual(idle_pulse, 0)
        self.assertAlmostEqual(agent_pulse, 0.70 + (math.sin(0) + 1) * 0.35, places=9)


if __name__ == "__main__":
    unittest.main()
