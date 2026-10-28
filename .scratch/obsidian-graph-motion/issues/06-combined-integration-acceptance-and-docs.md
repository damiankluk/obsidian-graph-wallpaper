# 06: Combined-state integration, measured performance acceptance, cleanup and documentation

**What to build:** When the agent and the user are active together, the agent bubble stays the primary motion and the local listening ripple layers on gently. The whole feature is then accepted by the full benchmark on the live compositor, obsolete or unproven code paths are removed or replaced, and the README states the real cadence, effects and measured numbers.

**Blocked by:** 04 (Visible whole-sphere agent-thinking bubble and neural-link flow at 60 FPS) and 05 (Distinct pointer and keyboard listening ripples with about two-second ease-out).

**Status:** ready-for-agent

- [ ] With agent and user input active together, the bubble amplitude remains primary and the ripple is layered at reduced strength; the rule is unit-tested as pure logic and shown in captures.
- [ ] The full benchmark runs idle, agent, listening and combined states on the 506-node graph at native resolution on the largest display, and every state meets the frozen budgets (frame-interval p99 and max, zero missed frames over 60 s, CPU, GPU).
- [ ] A 10-minute run shows no process-memory growth.
- [ ] A synthetic fixture near the 1,200 / 4,000 limits is measured and reported, with any shortfall stated plainly.
- [ ] The 20/10 FPS cadence, the unproven interpolation experiment, and any shader or Canvas code made obsolete by the renderer choice are removed or replaced; nothing unverified is left enabled.
- [ ] No adaptive slowdown or frame-rate reduction exists anywhere in the final code.
- [ ] The README describes the real behavior: 30 FPS idle, 60 FPS active, the three visual states, native resolution, the largest-display default, and the measured numbers with their environment limits.
- [ ] Privacy and resource-limit statements in the README remain accurate; the existing portable checks and runtime tests pass.
- [ ] Final benchmark output and captures are saved locally; failures or limits of the environment are reported honestly.
- [ ] Pre-existing uncommitted changes are preserved and no commit is made.
