# 02: GPU-rendering architecture spike and tested renderer choice

**What to build:** A time-boxed spike that builds a GPU-driven renderer candidate (static graph geometry uploaded once per graph change; rotation, perspective and later deformation from a few per-frame uniforms; link glow in the fragment stage) and compares it with the current Canvas path using the ticket 01 benchmark on the live compositor. The result is a recorded, evidence-based renderer choice and frozen numeric performance budgets.

**Blocked by:** 01 (Repeatable graph benchmark and current baseline).

**Status:** ready-for-agent

- [ ] Shader build tooling availability is confirmed (it was not on the default PATH when planning); how compiled shader artifacts are produced and kept in sync with sources is documented.
- [ ] The existing experimental shader files are assessed on their merits (compile status, visual result, cost); they are neither assumed to work nor silently discarded.
- [ ] The candidate renders the 506-node graph at native resolution on the target display with correct depth, node colors and links, verified by captures against the baseline.
- [ ] Benchmark results for baseline and candidate are compared at 30 FPS idle and 60 FPS active, with frame-interval percentiles, missed frames, CPU, GPU and memory.
- [ ] The chosen renderer and the reasons are written down, including any rejected option and its measured numbers.
- [ ] Numeric budgets are frozen in the benchmark: p99 frame interval within 20% of nominal, no interval over 2x nominal and zero missed frames in a 60 s run, plus CPU and GPU ceilings derived from the measurements.
- [ ] If neither option can meet the budgets, the ticket reports that plainly with data and does not lower the cadence or add adaptive degradation.
- [ ] Headroom is checked with a synthetic fixture near the 1,200 / 4,000 limits.
- [ ] Privacy boundary and largest-display targeting are unchanged.
