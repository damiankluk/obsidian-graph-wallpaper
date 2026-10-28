# 01: Repeatable graph benchmark and current baseline

**What to build:** One repeatable command that renders the real graph view on the live compositor from a deterministic 506-node / 1,121-link fixture, with injected activity state (idle, agent, pointer, keyboard, combined), and reports measured frame pacing, CPU, GPU and memory for the code as it stands today. This is the measuring stick every later ticket is judged by, and it records the honest baseline of the current 20/10 FPS Canvas path.

**Blocked by:** None (can start immediately).

**Status:** done (all acceptance criteria met; evidence below)

- [x] A deterministic fixture at the approved size (506 notes / 1,121 links), plus synthetic fixtures up to the existing 1,200 / 4,000 limits, drive the real graph view without a vault or running agents.
- [x] Activity state (agent, pointer, keyboard) is injected through the view's property surface; no key values or pointer positions are logged or stored.
- [x] An opt-in frame-timing probe in the real rendering path records presentation intervals only (it records buffer-swap timestamps, not presentation or scanout times); it is off by default and adds no measurable cost when off.
- [x] One command runs each state for a fixed duration at native resolution on the largest display (currently DP-2) and reports frame-interval percentiles (p50/p95/p99/max), missed-frame count, shell-process CPU, GPU utilisation and memory (sampled with the GPU tools available on this machine), and process memory growth.
- [x] The report states its environment limits: panel refresh rate, compositor and GPU driver versions, other GPU clients, and the possibility that an occluded bottom-layer surface gets no frame callbacks.
- [x] Screenshots of each state at native resolution are captured and saved locally.
- [x] Baseline numbers for the current implementation are recorded in the ticket's notes or a local results file; failures such as stutter are reported as measured, not explained away.
- [x] Existing uncommitted changes are preserved; shaders are measured only as found.

## Implementation notes and baseline (2026-10-28)

**Command:** `python3 bench/run_benchmark.py --duration 60 --warmup 5 --states idle,agent --layer bottom`
(also `--fixture limit`, `--states pointer,keyboard,combined`, `--layer top`, `--probe on|off`). The probe A/B is `python3 bench/probe_ab.py --rounds 3 --duration 30`.

**Quickshell load fix:** Quickshell only resolves imports inside the config folder (`Module path ... is outside of the config folder`), so `import ".."` could never work. The harness stages `bench/shell.qml` in a temp dir (outside the plugin; plugin validation rejects symlinks) beside symlinks to the real `GraphView.qml` and `shaders/`, so the measured code is the plugin's files as found. The smoke run also exposed a race (the shell quit before the harness's last `/proc` read, giving `VmRSS not found`); the harness now owns the shell lifetime, and failures include the shell's output tail.

**Environment field corrected:** `wallpaper_instance_also_running` (a `pgrep -x quickshell` truthiness test) could not tell the Omarchy shell, a wallpaper and the benchmark child apart. It is replaced by `quickshell_processes_before_benchmark_child`, a count taken before the child launches (1 in the later `limit` run: the Omarchy desktop shell). The two 60 s reports below were produced before this change and still carry the old field, which was `True` and means only "some quickshell was running". The change is reporting-only, so the measurements were not rerun.

### Evidence (git-ignored, kept exactly as produced)

| run | states | path under `bench/results/` |
|---|---|---|
| 60 s each | idle, agent | `20261028-131325/` (`report.md`, `results.json`, `<state>.intervals.json`, `<state>.png`, `fixture.json`) |
| 60 s each | pointer, keyboard, combined | `20261028-131643/` (same files) |
| 15 s each, `limit` fixture (1,200 / 4,000) | idle, agent | `20261028-132113/` (smoke, run with the corrected report format) |

Other dirs there (`130906`, `131107`, `131149`, `131239`, `131550`) are failed or short development runs. Common to the baseline runs: DP-2 2560x1440 @ 180 Hz, scale 1, Hyprland v0.56.2, Quickshell 0.3.2, RTX 2060 SUPER driver 615.78.08, fixture 506 notes / 1,121 links, bottom layer. JSON keys named `paints_*` hold the coalesced-burst statistics (key names kept so stored results stay readable).

### Baseline for the current Canvas implementation (60 s per state)

"Raw swaps/s" is the count of `frameSwapped` events per second. "Est. redraws/s" is the coalesced swap-burst estimate (see below). CPU is the benchmark shell process's utime+stime ticks as a percentage of one core.

| state | raw swaps/s | est. redraws/s | est. interval p50 / p99 / max (ms) | shell CPU (% of one core) | RSS start -> end (KiB) |
|---|---|---|---|---|---|
| idle | 20.02 | 10.18 | 100 / 103 / 106 | 8.95 | 374,108 -> 382,228 |
| agent | 39.74 | 25.35 (threshold-sensitive) | 46 / 55 / 62 | 131.08 | 389,032 -> 385,676 (peak 399,508) |
| pointer | 40.01 | 20.07 | 50 / 52 / 53 | 16.43 | RSS growth -2,408 |
| keyboard | 40.01 | 20.13 | 50 / 53 / 54 | 16.36 | RSS growth -2,056 |
| combined | 39.96 | 33.64 (threshold-sensitive) | 37 / 52 / 63 | 122.33 | RSS growth +3,908 |

**Conclusion: the current Canvas path fails the 30 / 60 FPS target in every state.** This does not depend on the burst heuristic: the raw swap rate is an upper bound on the redraw rate, and it is 20/s for idle (target 30) and at most 40/s for the active states (target 60). Against the target nominal intervals, coalesced p99 is 103 ms idle (33.3 ms nominal) and 52-55 ms for agent/pointer/keyboard/combined (16.7 ms nominal), and more than 1,190 intervals per state exceed 2x nominal. Against the *current* 10 / 20 Hz cadence no interval exceeded 2x nominal and no frame was missed.

Shell CPU is 9% of a core idle, about 16% for pointer or keyboard alone, and 122-131% (more than one core, so work off the GUI thread) once the agent effect is on. Idle is clearly cheaper than active; the agent cost is what ticket 02's GPU path must beat.

### Coalesced swap-burst intervals (estimated redraw cadence)

What is measured is `Window.frameSwapped` timestamps from `Date.now()`: 1 ms resolution, buffer-swap time, not compositor presentation or scanout (no `wp_presentation` feedback). These are not Canvas paint callbacks either. The raw events arrive in bursts (typically two a few ms apart per redraw), so the raw p50 understates the interval. To estimate redraw cadence, a swap less than **10 ms** after the previous one is merged into the same burst, and an interval runs from the first swap of one burst to the first swap of the next. The 10 ms threshold is a judgement. Idle, pointer and keyboard are bimodal and insensitive to it; agent and combined are not (estimated redraws/s by threshold):

| state | 5 ms | 8 ms | 10 ms | 12 ms | 20 ms |
|---|---|---|---|---|---|
| idle | 14.28 | 10.77 | 10.17 | 10.02 | 9.98 |
| agent | 38.18 | 32.03 | 25.33 | 22.20 | 20.20 |
| pointer | 26.02 | 20.67 | 20.05 | 20.02 | 19.98 |
| keyboard | 25.37 | 20.95 | 20.12 | 20.02 | 19.98 |
| combined | 39.83 | 38.32 | 33.62 | 28.12 | 20.08 |

(Computed from the saved `<state>.intervals.json`; the report's 10 ms figures differ from this table's 10 ms column by rounding only.) For agent and combined the true cadence can only be said to lie between about 20 and 40 per second. Why the swaps burst, and why agent cadence is irregular, has not been investigated.

### GPU

- **Whole-GPU load is not attributable.** `nvidia-smi` utilisation, memory and power cover every client (Hyprland, Xwayland, the Omarchy shell, a browser). Idle read 33% mean against 27% for agent, so the whole-device number is dominated by other clients. GPU memory was about 774 MiB in the idle/agent run.
- **Per-process GPU is sparse and indicative only:** SM % comes from 1 s `nvidia-smi pmon` samples, and only 7-13 samples per state were attributed to the shell pid (idle 15.4% mean / 18 max; agent 18.2 / 41; pointer 16.1; keyboard 18.7; combined 19.8).

### `limit` fixture smoke (15 s per state; 1,200 notes / 4,000 links)

The real view loaded and rendered it on the live compositor. idle: 20.06 raw swaps/s, 10.27 est. redraws/s, 11.02% CPU. agent: 28.36 raw swaps/s, 26.16 est. redraws/s, 172.14% CPU. **Agent RSS grew from 432,884 to 717,548 KiB (+284,664 KiB) in 15 s, still rising at the end.** The 15 s run is too short and was not repeated, so this is an unexplained measurement, not a diagnosed leak; the approved-size agent run showed no such growth over 60 s. It needs a longer limit-fixture run before anyone relies on the 1,200 / 4,000 bound.

### Environment limitations and what is unobserved

- The desktop was in normal use: one mapped window on DP-2's workspace partly covered the right of the graph, and the Omarchy shell was running. The surface did receive frame callbacks. Whether a fully occluded bottom-layer surface stops getting them is **not observable** here.
- Memory growth over the 10-minute run in the spec was **not run**; 60 s shows only that growth, if any, is small at the approved size (and the limit-fixture result above).
- The `top` layer was not measured.
- Screenshots are whole-output captures, so they include whatever windows were open (a browser with personal content in the ones viewed). Keep them local and do not share them. The graph is also partly hidden by that window.
- Experimental shaders were measured only as found: `gpuInterpolationEnabled` defaults to false, but the `ShaderEffect` is instantiated and logged "bubble shader compiled" at load, so both `.qsb` files compile on this GPU. Their visual output was not evaluated. `qsb`, `qml` and `qmllint` live in `/usr/lib/qt6/bin`, not on PATH.

### Checks

`bash tests/run` passes (4 runtime tests, 11 benchmark tests, manifest). `validate_plugin.py --json .` reports no errors and no warnings.

### Probe cost A/B (probe off vs on, controlled live run)

`--probe off` makes `bench/shell.qml` skip `frameProbeReset()` and `frameProbeEnabled = true`: no interval storage is allocated (the view's default store is a zero-length array), no `frameSwapped` handler is attached (`Connections.target` stays `null`), no intervals are reported, and the harness reports only process CPU/RSS and whole-device GPU. `--probe on` is the unchanged default.

Setup: `bench/probe_ab.py`, 3 rounds, order interleaved (off,on / on,off / off,on) so slow drift hits both modes alike; per run 30 s per state after 3 s warm-up, DP-2 2560x1440 @ 180 Hz, approved fixture 506 / 1,121, bottom layer, states idle and agent, same machine and desktop session. Summary: `bench/results/probe-ab-20261028-133045/summary.md`; runs in execution order: off `20261028-132405`, on `20261028-132511`, on `20261028-132618`, off `20261028-132725`, off `20261028-132832`, on `20261028-132938` (each with `results.json`).

CPU is the quickshell child's /proc utime+stime in clock ticks. One tick is 10 ms, i.e. 0.033% of one core over 30 s; this is the quantization step.

| state | mode | CPU ticks per run | mean ticks (% core) | spread max-min (ticks) |
|---|---|---|---|---|
| idle | off | 284, 270, 271 | 275.0 (9.11%) | 14 |
| idle | on | 254, 271, 265 | 263.3 (8.72%) | 17 |
| agent | off | 4050, 3976, 4002 | 4009.3 (133.08%) | 74 |
| agent | on | 4005, 4026, 4059 | 4030.0 (133.89%) | 54 |

Paired difference (on minus off, per round): idle -30, +1, -6 ticks (mean -11.7, -0.39% of a core); agent -45, +50, +57 (mean +20.7, +0.69% of a core, 0.5% relative). The per-round sign changes in both states and every mean difference is smaller than the within-mode spread (idle 17 ticks, agent 74 ticks). Whole-device GPU utilisation means (idle off 28.1 / 28.1 / 29.8, on 27.8 / 28.1 / 32.3; agent off 25.4 / 25.4 / 24.3, on 24.1 / 24.8 / 25.2 %) overlap likewise, and RSS growth per run is mixed in sign. In the off runs the report has no frame statistics, as designed.

**Result: no measurable cost.** At this resolution (3 repeats; noise about +/-17 ticks idle, about +/-74 ticks agent, i.e. roughly 0.6% and 2.5% of one core) enabling the probe is not distinguishable from not enabling it, and the off path does strictly less work than the on path, so the off cost is bounded by that same resolution. Limits of this claim: it cannot rule out an effect below that noise; it compares off against on, not against a GraphView built without any probe code (the always-present part is only the three property declarations and a `Connections` with a null target); three repeats is a small sample; the desktop was in normal use during the runs, so system noise is included in the spread, not removed; whole-device GPU is not attributable to the wallpaper.

### Acceptance criteria

All eight are met: see the checkboxes above. Standing limitations are listed under "Environment limitations and what is unobserved" (notably the 10-minute memory run, the fully occluded bottom-layer case and the `top` layer were not run) and the unexplained 285 MB agent RSS growth in the 15 s `limit` smoke; none of these is an acceptance criterion of this ticket.
