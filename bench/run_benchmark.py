#!/usr/bin/env python3
"""Repeatable graph benchmark: real GraphView, synthetic fixture and activity state.

Usage: bench/run_benchmark.py [--fixture approved|limit] [--states idle,agent,...]
                              [--duration 60] [--warmup 3] [--output DP-2]
                              [--layer bottom|top] [--probe on|off] [--results-dir DIR]

Each state runs in its own `quickshell -p bench/shell.qml` process so CPU and
memory are attributable to that process. Only synthetic state is injected; no
key values or pointer positions are read, logged or stored. Anything that
cannot be observed is recorded in the report as unavailable, never guessed.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import queue
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import benchlib  # noqa: E402

CLOCK_TICKS = os.sysconf("SC_CLK_TCK")


def run_text(command: list[str], timeout: float = 10) -> str | None:
    """stdout of a command, or None if it is missing or fails."""
    if shutil.which(command[0]) is None:
        return None
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def run_json(command: list[str]):
    text = run_text(command)
    try:
        return json.loads(text) if text else None
    except json.JSONDecodeError:
        return None


def largest_monitor(monitors: list[dict] | None) -> dict | None:
    if not monitors:
        return None
    return max(monitors, key=lambda m: (m["width"] * m["height"], m["name"]))


def environment(output: str | None) -> dict:
    """Facts the numbers depend on. Missing facts are reported as null."""
    monitors = run_json(["hyprctl", "monitors", "-j"])
    version = run_json(["hyprctl", "version", "-j"])
    target = next((m for m in monitors or [] if m["name"] == output), None) if output else largest_monitor(monitors)
    gpu = run_text(["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader"])
    clients = run_json(["hyprctl", "clients", "-j"])
    on_target = None
    if clients is not None and target is not None:
        # Count only: window titles/classes are deliberately not recorded.
        on_target = sum(
            1 for c in clients
            if c.get("mapped") and c.get("workspace", {}).get("id") == target.get("activeWorkspace", {}).get("id")
        )
    qs_version = run_text(["quickshell", "--version"])
    return {
        "target_output": target["name"] if target else output,
        "target_resolution": f'{target["width"]}x{target["height"]}' if target else None,
        "panel_refresh_hz": round(target["refreshRate"], 3) if target else None,
        "monitor_scale": target.get("scale") if target else None,
        "compositor": f'Hyprland {version.get("tag") or version.get("version")}' if version else None,
        "quickshell": qs_version.strip() if qs_version else None,
        "gpu": gpu.strip() if gpu else None,
        "gpu_other_clients": gpu_clients(),
        "mapped_windows_on_target_workspace": on_target,
        "quickshell_processes_before_benchmark_child": count_processes("quickshell"),
        "frame_callbacks_when_occluded": "not observable: a Bottom-layer surface covered by windows may get no "
                                          "frame callbacks, which would understate load",
        "probe_resolution": "Window frameSwapped, Date.now(): 1 ms resolution, buffer-swap time not scanout "
                            "(no wp_presentation feedback)",
    }


def count_processes(name: str) -> int | None:
    """Number of processes with exactly this name right now (None if pgrep is unavailable).

    Counted before the benchmark child is launched, so it is the other quickshell
    instances (the desktop shell, a running wallpaper) the child shares the GPU
    and compositor with. It cannot say which of them is the wallpaper.
    """
    text = run_text(["pgrep", "-x", name])
    return len(text.split()) if text else (0 if shutil.which("pgrep") else None)


def gpu_clients() -> list[str] | None:
    text = run_text(["nvidia-smi", "pmon", "-c", "1", "-s", "u"])
    if text is None:
        return None
    rows = [line.split() for line in text.splitlines() if line.strip() and not line.startswith("#")]
    return sorted({f"{row[2]}:{row[-1]}" for row in rows if len(row) > 3})  # type:command, no pids


PLUGIN_ROOT = HERE.parent


def stage_shell(out_dir: pathlib.Path) -> pathlib.Path:
    """Config folder for Quickshell: the bench shell beside symlinks to the real view and shaders.

    Quickshell cannot import a parent directory, and symlinks keep the measured
    code byte-for-byte the plugin's own GraphView.qml and shaders as found.
    """
    stage = out_dir  # a temp dir outside the plugin: symlinks inside it fail plugin validation
    for name in ("GraphView.qml", "Cadence.js", "shaders"):
        link = stage / name
        if not link.is_symlink():
            link.symlink_to(PLUGIN_ROOT / name)
    shell = stage / "shell.qml"
    shell.write_bytes((HERE / "shell.qml").read_bytes())
    return shell


class Run:
    """One quickshell child: line queue plus /proc sampling."""

    def __init__(self, command: list[str], env: dict):
        self.process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, bufsize=1, start_new_session=True)
        self.lines: queue.Queue[str] = queue.Queue()
        self.tail: list[str] = []
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for line in self.process.stdout:
            self.tail = (self.tail + [line.rstrip()])[-30:]
            if "OGBENCH" in line:
                self.lines.put(line.rstrip())
        self.lines.put("OGBENCH eof")

    def wait_for(self, kind: str, timeout: float) -> str:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(f"timed out waiting for {kind}")
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty:
                raise RuntimeError(f"timed out waiting for {kind}") from None
            match = re.search(r"OGBENCH (\S+) ?(.*)", line)
            if not match:
                continue
            if match.group(1) == kind:
                return match.group(2)
            if match.group(1) in ("error", "eof"):
                raise RuntimeError(f"benchmark shell reported {match.group(1)} {match.group(2)}")

    def cpu_ticks(self) -> int:
        fields = pathlib.Path(f"/proc/{self.process.pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(fields[11]) + int(fields[12])  # utime + stime

    def rss_kib(self) -> int:
        for line in pathlib.Path(f"/proc/{self.process.pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
        raise RuntimeError("VmRSS not found")

    def stop(self):
        if self.process.poll() is None:
            # Terminate the temporary shell as a process group so interrupted
            # benchmarks cannot leave a synthetic graph on the desktop.
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)


def gpu_sample() -> dict | None:
    text = run_text(["nvidia-smi", "--query-gpu=utilization.gpu,utilization.memory,memory.used,power.draw",
                     "--format=csv,noheader,nounits"])
    if not text:
        return None
    try:
        util, mem_util, mem_used, power = [float(v) for v in text.strip().split(",")]
    except ValueError:
        return None
    return {"gpu_util": util, "mem_util": mem_util, "mem_used_mib": mem_used, "power_w": power}


def process_gpu(pid: int, samples: list[str]) -> dict | None:
    """Per-process SM/mem % from `nvidia-smi pmon` rows, if the driver reports this pid at all."""
    sm, mem = [], []
    for line in samples:
        fields = line.split()
        if len(fields) >= 5 and fields[1] == str(pid):
            for target, raw in ((sm, fields[3]), (mem, fields[4])):
                if raw.isdigit():
                    target.append(int(raw))
    if not sm:
        return None
    return {"samples": len(sm), "sm_mean": round(sum(sm) / len(sm), 1), "sm_max": max(sm),
            "mem_mean": round(sum(mem) / len(mem), 1) if mem else None}


def measure_state(state: str, args, fixture_path: pathlib.Path, out_dir: pathlib.Path, output: str | None,
                  shell: pathlib.Path) -> dict:
    env = dict(os.environ,
               OGBENCH_FIXTURE=str(fixture_path), OGBENCH_STATE=state, OGBENCH_DURATION=str(args.duration),
               OGBENCH_WARMUP=str(args.warmup), OGBENCH_LAYER=args.layer, OGBENCH_PROBE=args.probe,
               OGBENCH_OUTPUT=output or "")
    run = Run(["quickshell", "-p", str(shell)], env)
    pmon = None
    try:
        run.wait_for("ready", 60)
        run.wait_for("start", args.warmup + 30)
        t0 = time.monotonic()
        ticks0, rss, gpu = run.cpu_ticks(), [run.rss_kib()], []
        pmon = (subprocess.Popen(["nvidia-smi", "pmon", "-s", "u", "-d", "1", "-c", str(int(args.duration))],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                if shutil.which("nvidia-smi") else None)
        shot = None
        while time.monotonic() - t0 < args.duration:
            time.sleep(1)
            rss.append(run.rss_kib())
            sample = gpu_sample()
            if sample:
                gpu.append(sample)
        elapsed = time.monotonic() - t0
        ticks1 = run.cpu_ticks()
        result = json.loads(run.wait_for("result", 30))
        pmon_rows = pmon.communicate(timeout=10)[0].splitlines() if pmon else []
    except Exception as exc:
        raise RuntimeError(f"{exc}; shell exit={run.process.poll()}; last shell output: {' | '.join(run.tail[-8:])}") from exc
    finally:
        run.stop()
        if pmon and pmon.poll() is None:
            pmon.kill()

    def mean(key):
        return round(sum(s[key] for s in gpu) / len(gpu), 2) if gpu else None

    process_cost = {
        "shell_cpu_percent_of_one_core": round(benchlib.cpu_percent(ticks0, ticks1, elapsed, CLOCK_TICKS), 2),
        "shell_cpu_ticks": ticks1 - ticks0,
        "rss": benchlib.rss_growth(rss),
        "gpu_whole_device": {
            "samples": len(gpu), "util_mean": mean("gpu_util"),
            "util_max": max((s["gpu_util"] for s in gpu), default=None),
            "mem_used_mib_mean": mean("mem_used_mib"), "power_w_mean": mean("power_w"),
        } if gpu else None,
        "gpu_this_process": process_gpu(run.process.pid, pmon_rows),
        "screenshot": str(shot) if shot else None,
        "measured_seconds": round(elapsed, 2),
    }
    base = {"state": state, "probe": args.probe, "nodes": result["nodes"], "edges": result["edges"],
            "screen": result["screen"], "view": result["view"]}
    if args.probe == "off":
        # Control run: no frame statistics exist by construction.
        return {**base, **process_cost}
    raw = result["intervals_ms"]
    (out_dir / f"{state}.intervals.json").write_text(json.dumps(raw), encoding="utf-8")
    paints, absorbed = benchlib.coalesce_intervals(raw)
    return {
        **base,
        "swap_events": len(raw) + 1, "swaps_absorbed_into_bursts": absorbed,
        "frames_current_cadence": benchlib.frame_stats(raw, benchlib.CURRENT_FPS[state]),
        "frames_target_cadence": benchlib.frame_stats(raw, benchlib.TARGET_FPS[state]),
        "paints_current_cadence": benchlib.frame_stats(paints, benchlib.CURRENT_FPS[state]),
        "paints_target_cadence": benchlib.frame_stats(paints, benchlib.TARGET_FPS[state]),
        **process_cost,
    }


def format_report(report: dict) -> str:
    env = report["environment"]
    lines = [f"# Graph benchmark {report['timestamp']}", "",
             f"Fixture: {report['fixture']} ({report['nodes']} notes / {report['edges']} links), "
             f"{report['duration_s']} s per state after {report['warmup_s']} s warm-up, layer={report['layer']}", "",
             "## Environment (limits on these numbers)"]
    for key, value in env.items():
        lines.append(f"- {key}: {value if value is not None else 'unavailable'}")
    if report.get("probe") == "off":
        lines += ["", "## Process cost with the frame probe OFF (control run)",
                  "No interval storage, no frameSwapped handler, no frame statistics. CPU is /proc utime+stime in",
                  f"clock ticks (1 tick = {1000 // CLOCK_TICKS} ms of CPU), so one tick over the run is a quantization step.",
                  "| state | CPU ticks | CPU % core | whole-GPU util % (not attributable) | RSS growth KiB |",
                  "|---|---|---|---|---|"]
        for r in report["states"]:
            g = r["gpu_whole_device"]
            lines.append(f"| {r['state']} | {r['shell_cpu_ticks']} | {r['shell_cpu_percent_of_one_core']} | "
                         f"{g['util_mean'] if g else 'n/a'} | {r['rss'].get('growth_kib', 'n/a')} |")
        return "\n".join(lines) + "\n"
    lines += ["", "## Raw frameSwapped intervals (ms), judged against the shipped 30/60 Hz cadence",
              "| state | swap intervals | mean swaps/s | p50 | p95 | p99 | max | missed | >2x | CPU % core | whole-GPU util % (not attributable) | per-process SM % (sparse, indicative) | RSS growth KiB |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in report["states"]:
        f = r["frames_current_cadence"]
        if "error" in f:
            lines.append(f"| {r['state']} | 0 | - | - | - | - | - | - | - | {r['shell_cpu_percent_of_one_core']} | - | - | - |")
            continue
        g = r["gpu_whole_device"]
        p = r["gpu_this_process"]
        lines.append(
            f"| {r['state']} | {f['frames']} | {f['mean_fps']} | {f['p50_ms']} | {f['p95_ms']} | {f['p99_ms']} | "
            f"{f['max_ms']} | {f['missed_frames']} | {f['over_2x']} | {r['shell_cpu_percent_of_one_core']} | "
            f"{g['util_mean'] if g else 'n/a'} | {p['sm_mean'] if p else 'not reported'} | {r['rss'].get('growth_kib', 'n/a')} |")
    lines += ["", "## Coalesced swap-burst intervals (estimated redraw cadence), shipped cadence",
              "Estimate only. Raw `frameSwapped` events arrive in bursts (typically two a few ms apart per redraw).",
              "Heuristic: a swap less than 10 ms after the previous one is treated as part of the same burst and merged;",
              "an interval then runs from the first swap of one burst to the first swap of the next. 10 ms is a judgement,",
              "not a measured property: it is under the 16.7 ms target frame time, but in-burst gaps of 10-19 ms also",
              "occur, so the estimate is threshold-sensitive wherever many raw intervals fall in that range (agent,",
              "combined). The raw swap rate is a hard upper bound on the redraw rate. These are not Canvas paint",
              "callbacks and not compositor presentation or scanout times.",
              "| state | swap events | absorbed | bursts | est. redraws/s | p50 | p95 | p99 | max | missed | >2x |",
              "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in report["states"]:
        f = r["paints_current_cadence"]
        if "error" in f:
            continue
        lines.append(f"| {r['state']} | {r['swap_events']} | {r['swaps_absorbed_into_bursts']} | {f['frames']} | "
                     f"{f['mean_fps']} | {f['p50_ms']} | {f['p95_ms']} | {f['p99_ms']} | {f['max_ms']} | "
                     f"{f['missed_frames']} | {f['over_2x']} |")
    lines += ["", "## Same intervals judged against the TARGET 30/60 Hz cadence (raw swaps, then coalesced bursts)",
              "| state | nominal ms | p99 | p99 within 20% | missed | >2x |", "|---|---|---|---|---|---|"]
    for r in report["states"]:
        f = r["frames_target_cadence"]
        if "error" in f:
            continue
        lines.append(f"| {r['state']} (raw swaps) | {f['nominal_ms']} | {f['p99_ms']} | {f['p99_within_20pct']} | "
                     f"{f['missed_frames']} | {f['over_2x']} |")
        c = r["paints_target_cadence"]
        if "error" not in c:
            lines.append(f"| {r['state']} (bursts) | {c['nominal_ms']} | {c['p99_ms']} | {c['p99_within_20pct']} | "
                         f"{c['missed_frames']} | {c['over_2x']} |")
    lines += ["", "## GPU notes",
              "Whole-GPU util/memory/power cover every client (compositor, Xwayland, other shells, browsers), so they",
              "cannot be attributed to the wallpaper. Per-process SM % is from 1 s `nvidia-smi pmon` samples and only a",
              "handful were attributed to the shell pid; treat as indicative.", "",
              "## Screenshots", "None captured during this performance run."]
    lines += [f"- {r['state']}: none" for r in report["states"]]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fixture", choices=["vault", *sorted(benchlib.FIXTURES)], default="vault",
                        help="vault uses only real Markdown notes; synthetic fixtures are explicit stress runs")
    parser.add_argument("--vault", type=pathlib.Path,
                        default=pathlib.Path(os.environ.get("OBSIDIAN_VAULT_PATH", "~/Documents/Agent_Vault")).expanduser())
    parser.add_argument("--states", default=",".join(benchlib.STATES))
    parser.add_argument("--duration", type=float, default=60)
    parser.add_argument("--warmup", type=float, default=3)
    parser.add_argument("--output", help="monitor name (default: largest by pixel area)")
    parser.add_argument("--layer", choices=("bottom", "top"), default="bottom")
    parser.add_argument("--probe", choices=("on", "off"), default="on",
                        help="off: leave the frame probe unused (A/B control); only CPU/RSS/GPU are reported")
    parser.add_argument("--results-dir", type=pathlib.Path, default=HERE / "results")
    args = parser.parse_args()

    states = args.states.split(",")
    unknown = [s for s in states if s not in benchlib.STATES]
    if unknown:
        parser.error(f"unknown states: {unknown}")
    for tool in ("quickshell",):
        if shutil.which(tool) is None:
            print(f"required tool not found: {tool}", file=sys.stderr)
            return 2

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = args.results_dir / stamp
    out_dir.mkdir(parents=True, exist_ok=True)
    if args.fixture == "vault":
        sys.path.insert(0, str(PLUGIN_ROOT))
        import export_graph  # noqa: E402
        fixture = export_graph.export(args.vault)
        fixture_name = "vault-live"
    else:
        fixture = benchlib.make_fixture(args.fixture)
        fixture_name = args.fixture
    fixture_path = out_dir / "fixture.json"
    fixture_path.write_text(json.dumps(fixture, separators=(",", ":")), encoding="utf-8")

    stage_dir = tempfile.TemporaryDirectory(prefix="ogbench-")
    shell = stage_shell(pathlib.Path(stage_dir.name))
    env = environment(args.output)
    output = env["target_output"]
    report = {"timestamp": stamp, "fixture": fixture_name, "nodes": len(fixture["nodes"]),
              "edges": len(fixture["edges"]), "duration_s": args.duration, "warmup_s": args.warmup,
              "layer": args.layer, "probe": args.probe, "environment": env, "states": []}
    for state in states:
        print(f"measuring {state} for {args.duration:g} s ...", flush=True)
        try:
            report["states"].append(measure_state(state, args, fixture_path, out_dir, output, shell))
        except RuntimeError as exc:
            print(f"{state}: FAILED: {exc}", file=sys.stderr)
            report["states"].append({"state": state, "failed": str(exc)})

    measured = [s for s in report["states"] if "failed" not in s]
    (out_dir / "results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if measured:
        text = format_report({**report, "states": measured})
        (out_dir / "report.md").write_text(text, encoding="utf-8")
        print(text)
    stage_dir.cleanup()
    print(f"results: {out_dir}")
    return 0 if len(measured) == len(states) else 1


if __name__ == "__main__":
    sys.exit(main())
