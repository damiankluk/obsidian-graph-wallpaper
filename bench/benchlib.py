"""Deterministic graph fixtures and frame-interval statistics for the benchmark.

Pure Python with no live-session dependencies, so it is unit-testable.
"""

from __future__ import annotations

import math
import random

# name -> (notes, links, seed). "approved" is the real-vault size the spec
# measures; "limit" is the exporter's MAX_NOTES / MAX_EDGES ceiling.
FIXTURES = {
    "approved": (506, 1121, 506),
    "limit": (1200, 4000, 1200),
}
GROUP_COUNT = 9

# Cadence (frames per second) per injected state. The shipped view and the
# acceptance target now use the same fixed 30/60 Hz policy.
STATES = ("idle", "agent", "pointer", "keyboard", "combined")
TRANSITION_STATE = "transition"
CURRENT_FPS = {"idle": 30, "agent": 60, "pointer": 60, "keyboard": 60, "combined": 60}
TARGET_FPS = dict(CURRENT_FPS)


# Frame-pacing budget (spec): at both cadences p99 interval within 20% of nominal,
# no interval over 2x nominal, zero missed frames in a steady-state run.
BUDGET = {"p99_factor": 1.2, "max_interval_factor": 2.0, "missed_frames": 0}

# Resource ceilings, percent of one core / percent SM of the shell process.
# Keep unknown ceilings unset; ticket 02 freezes them from repeatable evidence.
CPU_CEILING_PERCENT = {state: None for state in STATES}
GPU_PROCESS_CEILING_PERCENT = {state: None for state in STATES}


def make_graph(notes: int, links: int, seed: int) -> dict:
    """Same shape as export_graph.export(): unit-sphere layout, string-pair edges."""
    if links > notes * (notes - 1) // 2:
        raise ValueError("more links than distinct pairs")
    rng = random.Random(seed)
    golden_angle = math.pi * (3 - math.sqrt(5))
    ids = [f"group-{index % GROUP_COUNT}/note-{index:04d}.md" for index in range(notes)]

    edges: set[tuple[int, int]] = set()
    # Spine so no note is isolated, then mostly-local plus some long-range links.
    for index in range(1, notes):
        edges.add((index - 1, index))
    while len(edges) < links:
        a = rng.randrange(notes)
        if rng.random() < 0.7:
            b = (a + 1 + int(rng.random() ** 2 * 40)) % notes
        else:
            b = rng.randrange(notes)
        if a != b:
            edges.add((min(a, b), max(a, b)))
    edges = set(sorted(edges)[:links]) if len(edges) > links else edges

    degree = [0] * notes
    for a, b in edges:
        degree[a] += 1
        degree[b] += 1

    nodes = []
    for index in range(notes):
        y = 1 - 2 * (index + 0.5) / notes
        radius = math.sqrt(max(0, 1 - y * y))
        angle = golden_angle * index
        nodes.append({
            "id": ids[index],
            "label": f"Note {index:04d}",
            "group": f"group-{index % GROUP_COUNT}",
            "groupIndex": index % GROUP_COUNT,
            "degree": degree[index],
            "x": round(math.cos(angle) * radius, 6),
            "y": round(y, 6),
            "z": round(math.sin(angle) * radius, 6),
        })
    return {
        "origin": "benchmark-fixture",
        "nodes": nodes,
        "edges": [[ids[a], ids[b]] for a, b in sorted(edges)],
        "stats": {"notes": notes, "links": len(edges), "noteLimit": 1200, "linkLimit": 4000},
    }


def make_fixture(name: str) -> dict:
    notes, links, seed = FIXTURES[name]
    return make_graph(notes, links, seed)


def percentile(sorted_values: list[float], fraction: float) -> float:
    """Linear-interpolated percentile of an already sorted list."""
    if not sorted_values:
        raise ValueError("no samples")
    position = (len(sorted_values) - 1) * fraction
    low = math.floor(position)
    high = math.ceil(position)
    return sorted_values[low] + (sorted_values[high] - sorted_values[low]) * (position - low)


def frame_stats(intervals_ms: list[float], nominal_fps: float) -> dict:
    """Interval percentiles plus pass/fail inputs against a nominal cadence.

    missed_frames counts skipped presentation slots (interval / nominal rounded,
    minus one). over_2x counts intervals longer than twice nominal. The 20%
    p99 check mirrors the spec budget; it is reported, not enforced here.
    """
    if not intervals_ms:
        return {"frames": 0, "nominal_fps": nominal_fps, "error": "no frame intervals recorded"}
    ordered = sorted(intervals_ms)
    nominal = 1000.0 / nominal_fps
    missed = sum(max(0, round(value / nominal) - 1) for value in intervals_ms)
    p99 = percentile(ordered, 0.99)
    return {
        "frames": len(intervals_ms),
        "nominal_fps": nominal_fps,
        "nominal_ms": round(nominal, 3),
        "mean_fps": round(1000.0 * len(intervals_ms) / sum(intervals_ms), 2),
        "p50_ms": round(percentile(ordered, 0.50), 3),
        "p95_ms": round(percentile(ordered, 0.95), 3),
        "p99_ms": round(p99, 3),
        "max_ms": round(ordered[-1], 3),
        "missed_frames": missed,
        "over_2x": sum(1 for value in intervals_ms if value > 2 * nominal),
        "p99_within_20pct": p99 <= nominal * 1.2,
    }


def transition_frame_stats(intervals_ms: list[float], target_ms: list[int]) -> dict:
    """Report cadence groups and intervals spanning a 30/60 Hz state switch."""
    if len(intervals_ms) != len(target_ms):
        return {"error": "timer intervals and cadence targets differ in length"}
    groups = {}
    for target in (17, 33):
        samples = [value for value, cadence in zip(intervals_ms, target_ms) if cadence == target]
        if samples:
            groups[str(target)] = frame_stats(samples, 60 if target == 17 else 30)
    boundaries = [{"from_ms": target_ms[index - 1], "to_ms": target_ms[index],
                   "interval_ms": intervals_ms[index]}
                  for index in range(1, len(target_ms)) if target_ms[index] != target_ms[index - 1]]
    switch_counts = {}
    switch_maxima = {}
    for item in boundaries:
        key = f"{item['from_ms']}->{item['to_ms']}"
        switch_counts[key] = switch_counts.get(key, 0) + 1
        switch_maxima[key] = max(switch_maxima.get(key, 0), item["interval_ms"])
    return {
        "groups": groups,
        "cadence_switches": boundaries,
        "cadence_switch_counts": switch_counts,
        "cadence_switch_maxima_ms": {key: round(value, 3) for key, value in switch_maxima.items()},
        "cadence_switch_max_ms": round(max((item["interval_ms"] for item in boundaries), default=0), 3)
            if boundaries else None,
    }


def budget_verdict(stats: dict, cpu_percent: float | None = None, cpu_ceiling: float | None = None) -> dict:
    """Apply frame pacing rules and an optional evidence-based CPU ceiling."""
    failures: list[str] = []
    if "error" in stats or stats.get("frames", 0) == 0:
        failures.append("no measured frames")
    else:
        if not stats.get("p99_within_20pct", False):
            failures.append("p99 frame interval exceeds 1.2x nominal")
        if stats.get("over_2x", 0):
            failures.append("frame interval exceeds 2x nominal")
        if stats.get("missed_frames", 0):
            failures.append("missed frame slots detected")
    if cpu_ceiling is not None:
        if cpu_percent is None:
            failures.append("CPU measurement unavailable for configured ceiling")
        elif cpu_percent > cpu_ceiling:
            failures.append(f"CPU {cpu_percent:.2f}% exceeds {cpu_ceiling:.2f}% ceiling")
    return {"pass": not failures, "failures": failures}


def coalesce_intervals(intervals_ms: list[float], merge_ms: float = 10.0) -> tuple[list[float], int]:
    """Merge swaps that follow the previous one within merge_ms into a single paint.

    Returns (paint-to-paint intervals measured from the first swap of each
    burst, number of swaps absorbed). A trailing burst has no following paint,
    so its partial span is dropped. Reported next to the raw intervals, never
    instead of them.
    """
    merged: list[float] = []
    span = 0.0
    absorbed = 0
    for value in intervals_ms:
        if value < merge_ms:
            span += value
            absorbed += 1
        else:
            merged.append(span + value)
            span = 0.0
    return merged, absorbed


def cpu_percent(ticks_start: int, ticks_end: int, seconds: float, clock_ticks: int) -> float:
    """CPU use as a percentage of one core from /proc utime+stime tick counts."""
    if seconds <= 0:
        return 0.0
    return 100.0 * (ticks_end - ticks_start) / clock_ticks / seconds


def rss_growth(samples_kib: list[int]) -> dict:
    """Start, end, peak and least-squares slope (KiB/min) of one-per-second RSS samples."""
    if len(samples_kib) < 2:
        return {"samples": len(samples_kib)}
    n = len(samples_kib)
    mean_x = (n - 1) / 2
    mean_y = sum(samples_kib) / n
    denominator = sum((i - mean_x) ** 2 for i in range(n))
    slope = sum((i - mean_x) * (v - mean_y) for i, v in enumerate(samples_kib)) / denominator
    return {
        "samples": n,
        "start_kib": samples_kib[0],
        "end_kib": samples_kib[-1],
        "peak_kib": max(samples_kib),
        "growth_kib": samples_kib[-1] - samples_kib[0],
        "slope_kib_per_min": round(slope * 60, 1),
    }


def parse_smaps_rollup(text: str) -> dict[str, int]:
    """Parse selected process memory categories from /proc/PID/smaps_rollup."""
    wanted = {"Rss", "Pss", "Shared_Clean", "Shared_Dirty", "Private_Clean", "Private_Dirty",
              "Anonymous", "Swap"}
    values = {}
    for line in text.splitlines():
        key, separator, rest = line.partition(":")
        if separator and key in wanted:
            fields = rest.split()
            if fields and fields[0].isdigit():
                values[key] = int(fields[0])
    return values
