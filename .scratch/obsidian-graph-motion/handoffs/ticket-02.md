# Claude handoff: ticket 02 renderer architecture spike

## Assignment

Use Claude Sonnet to complete only `.scratch/obsidian-graph-motion/issues/02-gpu-rendering-architecture-spike.md`. The user approved the overall six-ticket plan and explicitly assigned implementation to Claude Sonnet. Ticket 01 is complete. Preserve all existing uncommitted changes; do not commit or begin tickets 03-06.

## User-approved behavior and constraints

- Fixed cadence: 30 FPS idle, 60 FPS when active. Performance is a primary design and verification requirement.
- Preserve native resolution and render only on the largest monitor (DP-2, currently 2560x1440).
- Agent state should eventually animate the whole graph like a water bubble and flow light along links; input feedback is a distinct, gentler ripple.
- Preserve graph colors, links, depth, note highlighting, agent hooks, and privacy. Never collect key values or persist pointer positions.
- Do not lower cadence or resolution to make a benchmark pass.

## Ticket 01 evidence

Benchmark command is `python3 bench/run_benchmark.py`, with deterministic 506-node / 1,121-link fixture, real GraphView in a Quickshell window, and a QML `frameSwapped` probe. The probe measures buffer-swap timestamps at 1 ms `Date.now()` precision, not compositor presentation or scanout. A 10 ms coalescing heuristic estimates redraw cadence; it does not prove Canvas paint callbacks.

Baseline reports:
- `.scratch/obsidian-graph-motion/issues/01-repeatable-graph-benchmark-and-baseline.md`
- `bench/results/20261028-131325/report.md` (idle and agent)
- `bench/results/20261028-131643/report.md` (pointer, keyboard, combined)
- `bench/results/probe-ab-20261028-133045/summary.md` (3 interleaved 30 s probe on/off rounds)

Machine: DP-2 2560x1440 at 180 Hz; Hyprland 0.56.2; Quickshell 0.3.2; NVIDIA RTX 2060 SUPER, driver 615.78.08. With the existing 20/10 Hz Canvas path, estimated coalesced redraw cadence and one-core CPU were: idle 10.18/s and 8.95%; agent 25.35/s and 131.08%; pointer 20.07/s and 16.43%; keyboard 20.13/s and 16.36%; combined 33.64/s and 122.33%. These figures are estimated redraw cadence, not delivered frame rate. Whole-GPU load is not attributable to the plugin, and per-process GPU samples are sparse.

The 1,200-node / 4,000-link live smoke created `.scratch`-ignored results in `bench/results/20261028-132113/`; agent RSS rose by about 285 MiB over 15 s and the cause is unknown. Do not claim the maximum graph size is safe until a longer run is made.

## Architecture context and sources

The repo already contains an unverified `ShaderEffect` texture-wobble prototype in `GraphView.qml` and `shaders/bubble.vert` / `.frag` with compiled `.qsb` files. Shader tools exist at `/usr/lib/qt6/bin/qsb`, `/usr/lib/qt6/bin/qml`, and `/usr/lib/qt6/bin/qmllint` (not all are on PATH). The project is a QML-only Omarchy plugin; avoid adding a compiled C++ helper unless the measured spike proves it is viable within this plugin's install/update lifecycle.

Official Qt guidance:
- Canvas Image updates can upload textures on accelerated APIs; large canvases and frequent animated updates should generally be avoided: https://doc.qt.io/qt-6/qml-qtquick-canvas.html
- ShaderEffect renders a custom fragment shader across the effect rectangle, and `.qsb` is the runtime shader package: https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html
- Fragment effects execute per pixel; ShaderEffectSource can add an extra offscreen pass, so keep shaders simple and measure fill cost: https://doc.qt.io/qt-6/qtquick-performance.html

## Required outcome

Build and benchmark at least one GPU-driven candidate against the recorded Canvas baseline at unchanged resolution and target cadence. Check visual fidelity, 506/1,121 and the 1,200/4,000 stress fixture, CPU, attributable GPU where observable, memory and timing. Freeze numeric CPU/GPU budgets only when evidence supports them. Record the renderer choice, rejected options and limitations in ticket 02. Run focused tests and live Quickshell checks. Do not mislabel buffer swaps as presentation, and do not treat the 10 ms grouping estimate as measured paints.

## Additional exploratory result (short, not acceptance evidence)

On 2026-10-28, a 15 s per-mode A/B ran the current `GraphView` with its existing texture-wobble `ShaderEffect` disabled/enabled, on DP-2 with the approved 506/1,121 fixture and the agent state. The estimated coalesced redraw rate was 25.28/s with the effect off and 56.06/s with it on; Quickshell CPU was 137.46% vs 148.89% of one core. The probe therefore suggests the effect improves apparent motion cadence, but does not reduce Canvas CPU work and slightly increased CPU in this short, uncontrolled sample. Per-process GPU sampling was sparse (one sample off, four on), so do not treat it as a final GPU comparison. This was a temporary harness under `/tmp`; it made no source changes and retained no screenshots.
