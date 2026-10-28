#!/usr/bin/env python3
"""Checks for the benchmark's pure parts: fixtures and frame statistics.

The live compositor measurement itself is run by bench/run_benchmark.py.
"""

from __future__ import annotations

import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bench"))
import benchlib  # noqa: E402



class CadencePolicyTests(unittest.TestCase):
    def test_shipped_cadence_matches_the_30_60_hz_target(self):
        self.assertEqual(benchlib.CURRENT_FPS, benchlib.TARGET_FPS)
        self.assertEqual(benchlib.CURRENT_FPS, {
            "idle": 30, "agent": 60, "pointer": 60, "keyboard": 60, "combined": 60,
        })


class FixtureTests(unittest.TestCase):
    def test_approved_fixture_has_exact_size_and_is_deterministic(self):
        first = benchlib.make_fixture("approved")
        second = benchlib.make_fixture("approved")
        self.assertEqual(first["origin"], "benchmark-fixture")
        self.assertEqual(len(first["nodes"]), 506)
        self.assertEqual(len(first["edges"]), 1121)
        self.assertEqual(json.dumps(first), json.dumps(second))

    def test_limit_fixture_matches_exporter_ceilings(self):
        graph = benchlib.make_fixture("limit")
        self.assertEqual((len(graph["nodes"]), len(graph["edges"])), (1200, 4000))

    def test_fixture_edges_are_unique_valid_and_nodes_on_unit_sphere(self):
        graph = benchlib.make_fixture("approved")
        ids = {node["id"] for node in graph["nodes"]}
        pairs = {tuple(sorted(edge)) for edge in graph["edges"]}
        self.assertEqual(len(pairs), len(graph["edges"]))
        for a, b in pairs:
            self.assertIn(a, ids)
            self.assertIn(b, ids)
            self.assertNotEqual(a, b)
        for node in graph["nodes"]:
            self.assertAlmostEqual(node["x"] ** 2 + node["y"] ** 2 + node["z"] ** 2, 1, places=4)
        self.assertEqual(sum(node["degree"] for node in graph["nodes"]), 2 * len(graph["edges"]))


class StatsTests(unittest.TestCase):
    def test_percentile_interpolates(self):
        self.assertEqual(benchlib.percentile([10, 20, 30, 40], 0.5), 25)
        self.assertEqual(benchlib.percentile([10, 20, 30, 40], 1.0), 40)

    def test_steady_cadence_has_no_misses(self):
        stats = benchlib.frame_stats([33.0, 34.0] * 50, 30)
        self.assertEqual(stats["missed_frames"], 0)
        self.assertEqual(stats["over_2x"], 0)
        self.assertTrue(stats["p99_within_20pct"])

    def test_stall_is_counted_as_missed_frames(self):
        stats = benchlib.frame_stats([16.7] * 99 + [100.0], 60)
        self.assertEqual(stats["max_ms"], 100.0)
        self.assertEqual(stats["over_2x"], 1)
        self.assertEqual(stats["missed_frames"], 5)

    def test_coalesce_merges_back_to_back_swaps_into_one_paint(self):
        # swaps 4 ms apart belong to one paint; the paint-to-paint interval spans the whole gap
        merged, extra = benchlib.coalesce_intervals([4, 96, 4, 96, 100, 3, 97])
        self.assertEqual(merged, [100, 100, 100, 100])
        self.assertEqual(extra, 3)

    def test_coalesce_leaves_evenly_spaced_swaps_alone(self):
        merged, extra = benchlib.coalesce_intervals([16.0, 17.0, 16.0])
        self.assertEqual(merged, [16.0, 17.0, 16.0])
        self.assertEqual(extra, 0)

    def test_empty_intervals_are_reported_not_hidden(self):
        self.assertIn("error", benchlib.frame_stats([], 60))

    def test_transition_intervals_are_grouped_and_switch_gaps_reported(self):
        stats = benchlib.transition_frame_stats([17, 17, 34, 33, 17], [17, 17, 33, 33, 17])
        self.assertEqual(stats["groups"]["17"]["frames"], 3)
        self.assertEqual(stats["groups"]["33"]["frames"], 2)
        self.assertEqual(stats["cadence_switches"], [
            {"from_ms": 17, "to_ms": 33, "interval_ms": 34},
            {"from_ms": 33, "to_ms": 17, "interval_ms": 17},
        ])
        self.assertEqual(stats["cadence_switch_counts"], {"17->33": 1, "33->17": 1})
        self.assertEqual(stats["cadence_switch_maxima_ms"], {"17->33": 34, "33->17": 17})
        self.assertEqual(stats["cadence_switch_max_ms"], 34)
        self.assertIn("error", benchlib.transition_frame_stats([17], [17, 33]))

    def test_cpu_percent_and_rss_growth(self):
        self.assertAlmostEqual(benchlib.cpu_percent(100, 150, 10, 100), 5.0)
        growth = benchlib.rss_growth([1000, 1010, 1020, 1030])
        self.assertEqual(growth["growth_kib"], 30)
        self.assertEqual(growth["slope_kib_per_min"], 600.0)

    def test_parse_smaps_rollup_keeps_memory_categories(self):
        sample = "Rss: 120 kB\nPss: 80 kB\nPrivate_Dirty: 48 kB\nAnonymous: 32 kB\nSwap: 0 kB\n"
        self.assertEqual(benchlib.parse_smaps_rollup(sample), {
            "Rss": 120, "Pss": 80, "Private_Dirty": 48, "Anonymous": 32, "Swap": 0,
        })


class BudgetTests(unittest.TestCase):
    def verdict(self, intervals, fps, cpu=5.0, ceiling=10.0):
        return benchlib.budget_verdict(benchlib.frame_stats(intervals, fps), cpu, ceiling)

    def test_steady_run_inside_every_ceiling_passes(self):
        result = self.verdict([33.3, 33.4] * 100, 30)
        self.assertTrue(result["pass"], result)
        self.assertEqual(result["failures"], [])

    def test_p99_more_than_20_percent_over_nominal_fails(self):
        result = self.verdict([16.7] * 90 + [21.0] * 10, 60)
        self.assertFalse(result["pass"])
        self.assertTrue(any("p99" in f for f in result["failures"]))

    def test_one_interval_over_twice_nominal_fails_even_when_p99_is_fine(self):
        result = self.verdict([16.7] * 999 + [34.0], 60)
        self.assertFalse(result["pass"])
        self.assertTrue(any("2x" in f for f in result["failures"]))

    def test_any_missed_frame_fails(self):
        result = self.verdict([33.3] * 999 + [66.6], 30)
        self.assertFalse(result["pass"])
        self.assertTrue(any("missed" in f for f in result["failures"]))

    def test_cpu_over_ceiling_fails(self):
        result = self.verdict([16.7] * 100, 60, cpu=12.0, ceiling=10.0)
        self.assertFalse(result["pass"])
        self.assertTrue(any("CPU" in f for f in result["failures"]))

    def test_run_with_no_frames_fails_instead_of_passing_vacuously(self):
        self.assertFalse(self.verdict([], 30)["pass"])

    def test_frozen_ceilings_cover_every_state_and_idle_is_cheaper_than_active(self):
        for table in (benchlib.CPU_CEILING_PERCENT, benchlib.GPU_PROCESS_CEILING_PERCENT):
            self.assertEqual(set(table), set(benchlib.STATES))
        self.assertTrue(all(value is None or value > 0 for value in benchlib.CPU_CEILING_PERCENT.values()))
        self.assertTrue(all(value is None for value in benchlib.GPU_PROCESS_CEILING_PERCENT.values()))
        self.assertEqual(benchlib.BUDGET["p99_factor"], 1.2)
        self.assertEqual(benchlib.BUDGET["max_interval_factor"], 2.0)
        self.assertEqual(benchlib.BUDGET["missed_frames"], 0)


class ImageDiffTests(unittest.TestCase):
    @staticmethod
    def png(width, height, pixel):
        import struct
        import zlib

        raw = b"".join(b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(width)) for y in range(height))

        def chunk(kind, data):
            body = kind + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

        header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

    def write(self, name, data):
        import tempfile

        path = pathlib.Path(self.tmp.name) / name
        path.write_bytes(data)
        return path

    def setUp(self):
        import tempfile

        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_identical_images_have_zero_difference(self):
        import imagediff

        a = self.write("a.png", self.png(4, 3, lambda x, y: (x * 10, y * 20, 7, 255)))
        stats = imagediff.compare(imagediff.read_png(a), imagediff.read_png(a))
        self.assertEqual(stats["mean_abs"], 0)
        self.assertEqual(stats["differing_fraction"], 0)

    def test_difference_is_measured_per_channel_and_located(self):
        import imagediff

        a = self.write("a.png", self.png(4, 4, lambda x, y: (0, 0, 0, 255)))
        b = self.write("b.png", self.png(4, 4, lambda x, y: (100, 0, 0, 255) if (x, y) == (1, 2) else (0, 0, 0, 255)))
        stats = imagediff.compare(imagediff.read_png(a), imagediff.read_png(b), threshold=8)
        self.assertEqual(stats["max_abs"], 100)
        self.assertAlmostEqual(stats["differing_fraction"], 1 / 16)
        self.assertAlmostEqual(stats["mean_abs"], 100 / (16 * 3))

    def test_size_mismatch_is_an_error_not_a_zero(self):
        import imagediff

        a = imagediff.read_png(self.write("a.png", self.png(2, 2, lambda x, y: (0, 0, 0, 255))))
        b = imagediff.read_png(self.write("b.png", self.png(3, 2, lambda x, y: (0, 0, 0, 255))))
        with self.assertRaises(ValueError):
            imagediff.compare(a, b)

    def test_reads_sub_filtered_rows(self):
        import imagediff
        import struct
        import zlib

        # row filter 1 (Sub): each byte stores the delta from the pixel to its left
        raw = b"\x01" + bytes([10, 20, 30, 255, 5, 5, 5, 0])
        def chunk(kind, data):
            body = kind + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
        data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 1, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
        image = imagediff.read_png(self.write("s.png", data))
        self.assertEqual(list(image["pixels"][:8]), [10, 20, 30, 255, 15, 25, 35, 255])


class ProbeOffReportTests(unittest.TestCase):
    def test_probe_off_report_has_process_cost_and_no_frame_stats(self):
        import run_benchmark

        state = {"state": "idle", "probe": "off", "shell_cpu_ticks": 530, "shell_cpu_percent_of_one_core": 17.67,
                 "gpu_whole_device": None, "rss": {"growth_kib": 12}, "memory_breakdown_kib": {},
                 "motion_levels": {"agent": 0.0, "pointer": 0.0, "keyboard": 0.0},
                 "listening_levels": {"pointer": 0.0, "keyboard": 0.0}}
        text = run_benchmark.format_report({
            "timestamp": "t", "fixture": "approved", "nodes": 506, "edges": 1121, "duration_s": 30, "warmup_s": 3,
            "layer": "bottom", "surface": "compact", "probe": "off",
            "environment": {"target_output": "DP-2"}, "states": [state]})
        self.assertIn("probe OFF", text)
        self.assertIn("| idle | 530 | 17.67 | n/a | 12 | n/a | n/a |", text)
        self.assertIn("## Rendered listening envelopes at measurement end", text)
        self.assertIn("| idle | 0.0 | 0.0 |", text)
        self.assertIn("## Rendered motion envelopes at measurement end", text)
        self.assertIn("| idle | 0.0 | 0.0 | 0.0 |", text)
        self.assertNotIn("swap intervals", text)


if __name__ == "__main__":
    unittest.main()
