# 03: Smooth idle motion at fixed 30 FPS with flowing link glow

**What to build:** On the chosen renderer, the idle wallpaper moves continuously and fluidly at a fixed 30 FPS: slow yaw, pitch and roll drifting on independent periods, with soft glow flowing along links between nodes. The cadence policy is a pure function of state (30 idle, 60 active) with no feedback from measured frame time and no adaptive slowdown. Native resolution and largest-display targeting are preserved.

**Blocked by:** 02 (GPU-rendering architecture spike and tested renderer choice).

**Status:** ready-for-agent

- [ ] Idle motion is continuous: every presented frame reflects the current scene time, with no stepped or low-rate geometry updates.
- [ ] Yaw, pitch and roll move on independent slow periods and never settle into a single repeating spin.
- [ ] Links show a soft, low-amplitude flowing glow that is visible in a native-resolution capture but does not distract from foreground windows.
- [ ] The cadence policy is implemented as a pure, unit-tested function (idle 30, active 60, easing tail keeps 60 until the visible effect ends) with no adaptive or load-based branch.
- [ ] The idle benchmark meets the frozen ticket 02 budgets at 30 FPS: p99 interval, max interval, zero missed frames over 60 s, CPU and GPU ceilings, and no memory growth.
- [ ] Switching between idle and active cadence causes no measurable hitch in the benchmark.
- [ ] Graph reloads from vault changes do not restart or snap the animation; recently-edited and focused-note highlights still work.
- [ ] Before/after captures and benchmark output are saved locally; the existing portable checks still pass.
- [ ] Existing uncommitted changes are built on, not reverted.
