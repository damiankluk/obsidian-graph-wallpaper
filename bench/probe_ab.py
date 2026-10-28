#!/usr/bin/env python3
"""Interleaved A/B of the frame probe's cost: probe off vs on, same everything else.

Usage: bench/probe_ab.py [--rounds 3] [--duration 30] [--warmup 3] [--states idle,agent]

Each round runs one `run_benchmark.py --probe off` and one `--probe on` (order
alternates per round, so slow drift hits both modes alike). Writes
bench/results/probe-ab-<stamp>/summary.md and lists the underlying run dirs.
CPU is /proc utime+stime ticks of the quickshell child, so it is quantized to
one clock tick (10 ms) per run; whole-machine noise is estimated from the spread
between repeats of the same mode, not assumed.
"""

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import statistics
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent


def run_once(probe: str, args) -> dict:
    command = [sys.executable, str(HERE / "run_benchmark.py"), "--probe", probe, "--states", args.states,
               "--duration", str(args.duration), "--warmup", str(args.warmup), "--layer", "bottom",
               "--fixture", args.fixture, "--output", args.output]
    done = subprocess.run(command, capture_output=True, text=True)
    lines = [line for line in done.stdout.splitlines() if line.startswith("results: ")]
    if done.returncode != 0 or not lines:
        raise SystemExit(f"{probe} run failed:\n{done.stdout[-1500:]}\n{done.stderr[-1500:]}")
    run_dir = pathlib.Path(lines[-1].split(": ", 1)[1])
    return {"dir": run_dir, "report": json.loads((run_dir / "results.json").read_text())}


def summarise(runs: list[dict], states: list[str], duration: float) -> str:
    out = ["# Frame probe A/B", "",
           f"{len(runs) // 2} rounds, {duration:g} s per state, order interleaved (see run list). "
           "CPU ticks are /proc utime+stime of the quickshell child; 1 tick = 10 ms = "
           f"{100 * 0.01 / duration:.3f} % of one core over {duration:g} s.", "",
           "| state | mode | CPU ticks per run | mean ticks | mean CPU % core | spread (max-min) ticks | RSS growth KiB per run |",
           "|---|---|---|---|---|---|---|"]
    table: dict[tuple[str, str], list[dict]] = {}
    for run in runs:
        for entry in run["report"]["states"]:
            table.setdefault((entry["state"], run["probe"]), []).append(entry)
    for state in states:
        for mode in ("off", "on"):
            entries = table[(state, mode)]
            ticks = [e["shell_cpu_ticks"] for e in entries]
            out.append(f"| {state} | {mode} | {ticks} | {statistics.mean(ticks):.1f} | "
                       f"{statistics.mean(e['shell_cpu_percent_of_one_core'] for e in entries):.2f} | "
                       f"{max(ticks) - min(ticks)} | {[e['rss'].get('growth_kib') for e in entries]} |")
    out += ["", "## Paired difference (probe on minus off, per round)", "",
            "| state | per-round diff (ticks) | mean diff ticks | mean diff % core | noise: larger within-mode spread (ticks) |",
            "|---|---|---|---|---|"]
    for state in states:
        off = [e["shell_cpu_ticks"] for e in table[(state, "off")]]
        on = [e["shell_cpu_ticks"] for e in table[(state, "on")]]
        diffs = [b - a for a, b in zip(off, on)]
        noise = max(max(off) - min(off), max(on) - min(on))
        out.append(f"| {state} | {diffs} | {statistics.mean(diffs):.1f} | "
                   f"{100 * 0.01 * statistics.mean(diffs) / duration:.3f} | {noise} |")
    out += ["", "## Runs (in execution order)"]
    out += [f"- {run['probe']}: {run['dir']}" for run in runs]
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--duration", type=float, default=30)
    parser.add_argument("--warmup", type=float, default=3)
    parser.add_argument("--states", default="idle,agent")
    parser.add_argument("--output", default="DP-2")
    parser.add_argument("--fixture", choices=("vault", "approved", "limit"), default="vault",
                        help="vault uses real notes; synthetic stress fixtures are opt-in")
    args = parser.parse_args()

    runs = []
    for round_index in range(args.rounds):
        order = ("off", "on") if round_index % 2 == 0 else ("on", "off")
        for probe in order:
            print(f"round {round_index + 1}/{args.rounds}: probe {probe} ...", flush=True)
            run = run_once(probe, args)
            run["probe"] = probe
            runs.append(run)

    # Pair rounds: runs[2i], runs[2i+1] are one round; reorder so per-mode lists follow round order.
    runs_sorted = []
    for i in range(args.rounds):
        pair = {r["probe"]: r for r in runs[2 * i:2 * i + 2]}
        runs_sorted += [pair["off"], pair["on"]]
    text = summarise(runs_sorted, args.states.split(","), args.duration)
    out_dir = HERE / "results" / f"probe-ab-{datetime.datetime.now():%Y%m%d-%H%M%S}"
    out_dir.mkdir(parents=True)
    # execution order, for the run list
    text = text.split("## Runs (in execution order)")[0] + "## Runs (in execution order)\n" + "\n".join(
        f"- {r['probe']}: {r['dir']}" for r in runs) + "\n"
    (out_dir / "summary.md").write_text(text, encoding="utf-8")
    print(text)
    print(f"summary: {out_dir / 'summary.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
