# 04: Visible whole-sphere agent-thinking bubble and neural-link flow at 60 FPS

**What to build:** While a supported agent (Codex, Claude Code, Antigravity) has an active lifecycle lease, the whole graph sphere visibly deforms and wobbles like a water bubble, and the neural paths glow and carry flowing pulses more strongly than at idle. The effect eases in when work starts and eases out when it ends, and runs at 60 FPS. The agent signal contract and privacy boundary are unchanged.

**Blocked by:** 03 (Smooth idle motion at fixed 30 FPS with flowing link glow).

**Status:** ready-for-agent

- [ ] The entire sphere (not just a local patch or a bounded node set) deforms with low-order modes, clearly visible in a native-resolution capture and readable from across the room.
- [ ] Links glow more strongly and show visible flowing pulses during agent activity.
- [ ] Amplitude eases in and out with separate rise and fall times; short lease updates, and a lease expiring and renewing, cause no snap or flicker.
- [ ] Two agents active at once produce one coherent bubble, not stacked effects.
- [ ] Agent activity is driven only by the existing hook-derived lease set; the helper still stores only agent names and hashed session leases, and the existing runtime tests for leases and privacy still pass unchanged.
- [ ] The agent-state benchmark runs at 60 FPS and meets the frozen budgets for p99 and max interval, missed frames, CPU, GPU and memory on the 506-node graph at native resolution.
- [ ] The effect still meets the budgets on a synthetic fixture near the 1,200 / 4,000 limits, or the shortfall is reported with data.
- [ ] No adaptive quality or reduced frame rate is used anywhere.
- [ ] Captures of idle versus agent state demonstrate the visible difference; results are saved locally.
