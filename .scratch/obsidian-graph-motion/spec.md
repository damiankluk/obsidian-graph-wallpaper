Status: approved (testing seam and six-ticket breakdown approved by the user); ready-for-agent

# Obsidian graph motion: idle flow, agent bubble, listening ripple, measured frame pacing

## Problem Statement

The wallpaper's graph does not feel alive, and it costs more than it should.

- Idle motion visibly stutters. The scene clock advances every display frame, but the graph is only repainted at 10 Hz idle and 20 Hz active, so motion arrives in coarse steps.
- Agent "thinking" is hard to see. Point motion and the thought wave are tiny (about 1-3% radial displacement) and the wave covers at most 24 nodes.
- Performance is poor under active highlighting. The graph (about 506 notes / 1,121 links, on a native-resolution canvas up to 1520x1440) is rasterised by a JavaScript Canvas 2D path on every paint, and uncommitted work layers an experimental shader on top without verified cost or appearance.
- Keyboard and pointer activity only speeds up the orbit and adds mild parallax. There is no distinct "listening" reaction.
- Nothing states what frame cadence, CPU cost or GPU cost is acceptable, or proves it.

## Solution

Three visible states, each readable at a glance, at a fixed cadence with measured cost.

1. **Idle**: slow, fluid, multi-axis motion (yaw, pitch, roll at independent periods) plus soft flowing glow along links. Continuous, not stepped.
2. **Agent thinking**: while a supported agent (Codex, Claude Code, Antigravity) has an active lifecycle lease, the whole sphere visibly deforms and wobbles like a water bubble, and links glow and carry flowing pulses. Eases in and out.
3. **User listening**: pointer movement gives a local ripple around the cursor; keyboard activity gives a subtler ripple from the graph centre. Both are gentler than the agent effect and ease away over about 2 seconds. With the agent also active, the bubble stays primary and the ripple layers on gently.

Cadence is fixed: 30 FPS idle, 60 FPS active. No adaptive slowdown, no lowering frame rate to hide cost. Native monitor resolution on the largest display (currently DP-2). Frame pacing, CPU and GPU cost are measured on the live compositor with the real 506-node graph, and the feature is not accepted until measured budgets are met.

## User Stories

1. As a desktop user, I want the idle graph to drift smoothly with no visible stepping, so that the wallpaper feels calm and alive.
2. As a desktop user, I want idle yaw, pitch and roll at independent slow periods, so that motion never looks like one repeating spin.
3. As a desktop user, I want links to softly glow and flow while idle, so that the graph reads as neural paths.
4. As a desktop user, I want the idle effect to stay subtle, so that it does not distract from windows on top.
5. As a developer running an agent, I want the whole sphere to wobble like a water bubble while an agent works, so that I can tell from across the room that it is thinking.
6. As a developer running an agent, I want stronger link glow and flowing pulses during agent activity, so that thinking shows in links as well as shape.
7. As a developer running an agent, I want the effect to ease in and out, so that short lease updates cause no snap or flicker.
8. As a Codex user, I want its lifecycle hooks to drive the effect, so that no process sniffing is needed.
9. As a Claude Code user, I want its lifecycle hooks to drive the effect, so that no process sniffing is needed.
10. As an Antigravity user, I want its lifecycle hooks to drive the effect, so that no process sniffing is needed.
11. As a user running two agents, I want one coherent bubble, so that effects do not stack into noise.
12. As a privacy-conscious user, I want the agent signal limited to agent names and short-lived hashed session leases, so that prompts, paths and arguments never reach the wallpaper.
13. As a privacy-conscious user, I want key values and pointer positions never stored or logged, so that listening feedback is not input logging.
14. As a user typing, I want a gentle ripple from the graph centre, so that the graph feels like it is listening.
15. As a user moving the mouse over the desktop, I want a local ripple around the cursor, so that the graph responds to where I am.
16. As a user, I want ripples to fade over about two seconds, so that they feel soft.
17. As a user, I want listening to look clearly different from the agent bubble, so that I can tell who caused a reaction.
18. As a user typing while an agent works, I want the bubble to stay dominant with a gentle ripple on top, so that agent state is never hidden.
19. As a user, I want pointer ripples only when the pointer is over the exposed wallpaper, so that behaviour matches what the surface can receive.
20. As a user, I want keyboard listening while another window has focus, without capturing keystrokes, matching the existing aggregate-activity behaviour.
21. As a user, I want a fixed 30 FPS cadence when idle, so that idle power use is predictable.
22. As a user, I want a fixed 60 FPS cadence when the agent or I am active, so that motion looks fluid.
23. As a user, I want stable frame intervals at both cadences, so that I see no judder or visible stalls.
24. As a user, I want the idle-to-active switch to happen without a hitch.
25. As a user, I want the graph never to drop frame rate silently under load, so that problems are visible and fixed.
26. As a user, I want native-resolution rendering, so that nodes, links and labels stay crisp.
27. As a multi-monitor user, I want rendering only on the largest display, so that other monitors are untouched.
28. As a maintainer, I want CPU and GPU cost measured on the live compositor with the real graph, so that "smooth" is a number.
29. As a maintainer, I want one repeatable benchmark command, so that I can re-run it after any change.
30. As a maintainer, I want it to report frame-interval percentiles, missed frames, CPU and GPU for idle, agent, listening and combined states.
31. As a maintainer, I want it to state environment limits (refresh rate, compositor, GPU driver, other load), so that results are honestly scoped.
32. As a maintainer, I want deterministic graph fixtures and injected activity state driving the real view, so that checks are repeatable without a vault or running agents.
33. As a maintainer, I want native-resolution screenshots of each state, so that I verify effects are visible, not just present in code.
34. As a maintainer, I want the experimental shader files assessed rather than assumed to work, so that broken experiments are proven or removed.
35. As a maintainer, I want the portable check script to stay runnable and honest.
36. As a maintainer, I want the README to describe real cadence, effects and measured cost.
37. As a user with a larger vault, I want the existing 1,200-node / 4,000-link limits to keep bounding cost.
38. As a user, I want a graph reload not to restart or snap the animation.
39. As a user, I want recently-edited and focused-note highlights to keep working.
40. As a user, I want the shell to stay responsive while the wallpaper animates.

## Implementation Decisions

- One continuous scene clock drives all motion. Every presented frame shows current state; no scheme where the scene advances at display rate but geometry updates at a lower rate.
- Cadence policy: two states, 30 FPS idle and 60 FPS active. Active means agent activity, user activity, or an unfinished easing tail. It is a pure function of state with no feedback from measured frame time and no adaptive degradation.
- Render architecture: the dominant cost is rasterising about 1,121 links and 506 nodes per frame in JavaScript Canvas and uploading a large texture. Per-frame work must leave the JavaScript path. Preferred direction is GPU-side: static geometry uploaded once per graph change; the vertex stage applies rotation, perspective, bubble deformation and ripples from a few per-frame uniforms; the fragment stage produces link glow and flowing pulses. The first ticket is a spike benchmarking the current Canvas path against a GPU-driven candidate on the live compositor; the architecture choice follows that evidence. The existing experimental shaders are inputs to that assessment, not a trusted baseline. Shader compile tooling availability must be confirmed early (it was not on the default PATH).
- Idle: slow multi-axis drift plus low-amplitude flow-and-glow along links.
- Agent: whole-sphere low-order deformation modes (water-bubble wobble) with amplitude clearly visible at native resolution, stronger link glow and travelling pulses; distinct rise and fall time constants. The agent signal contract (set of active agent names from file-based leases) is unchanged.
- Listening: two ripple sources with separate envelopes. Pointer ripple is local, centred at the cursor mapped into the graph's frame. Keyboard ripple radiates from the graph centre at lower strength. Both decay over about two seconds. Keyboard relies on the aggregate idle signal; pointer position is used only in memory for the live ripple.
- Combination: agent bubble amplitude is primary; listening ripples are layered at reduced amplitude.
- Privacy boundary unchanged: hooks pass lifecycle JSON to the local helper, which discards prompts, arguments, paths and conversation identifiers and stores only agent names and hashed leases in a mode-600 runtime file. No new data channel.
- Display targeting unchanged: largest display by pixel area, native resolution, others untouched.
- Performance budgets (numeric CPU/GPU ceilings set from the spike, then frozen in the benchmark): at both cadences p99 frame interval within 20% of nominal; no interval over 2x nominal and zero missed frames in a 60 s steady-state run; shell CPU well under one core with idle clearly cheaper than active; GPU utilisation and memory sampled over the same run; no process-memory growth over a 10 minute run.
- Instrumentation: an opt-in frame-timing probe in the real rendering path records presentation intervals only, no user data.
- Fixtures: the view already takes graph, agent activity and activity state through its property surface, so fixtures and injected state drive the real view. Add a deterministic 506-node / 1,121-link fixture, plus synthetic fixtures up to the existing limits.
- Cleanup: the 20/10 FPS cadence, the interpolation experiment and the Canvas/shader split are replaced or removed per the spike. Existing uncommitted changes are built on, never reverted.

## Testing Decisions

- A good test exercises external behaviour: what the real view renders over time and what is measured, not private arrays. Pure policy (cadence, envelope decay, combination rule) gets unit tests; visual checks compare captures of named states; timing checks measure presented-frame intervals.
- Seam (proposed): deterministic fixtures and injected activity state through the real graph view in a real Quickshell/Qt render, with live-compositor performance and visual checks on the 506-node graph on the target display.
- Constraints and split: (a) live display, compositor and GPU only exist on this machine, so performance acceptance runs there and reports its environment; (b) headless QML tooling may be missing, so visual checks may use a windowed Quickshell run with screenshot capture; (c) real keyboard/pointer input cannot be injected without capturing keystrokes, so input is injected as state and one live pass confirms the real path.
- Modules: cadence policy (pure), real graph view under injected state (capture plus frame timing), service lease/activity handling and Python helpers (existing).
- Prior art: the existing runtime tests (exporter cache, watcher, agent lease expiry with privacy checks, hook-manager idempotence) run via the portable check script. The visual/performance benchmark is new.
- Acceptance is the measured benchmark plus before/after captures of each state.

## Out of Scope

- Changing supported agents, hook installation, or the privacy boundary.
- Rendering on more than the largest display or per-monitor settings.
- Changing layout, vault parsing, node/link limits, or note highlight semantics.
- Adaptive quality or adaptive frame rate.
- Interactive features (click, drag, selection).
- Publishing or external hosting; adding CLAUDE.md or AGENTS.md.

## Further Notes

- The working tree has substantial uncommitted changes snapshotted before planning; implementation builds on them.
- The portable check script references a manifest validator, demo launcher and demo fixture; all exist.
- Terms: "Graph view", "Agent activity", "Listening", "Thinking".
- State environment limits in benchmark output: panel refresh rate (30 FPS on a 60 Hz panel is every other vblank), NVIDIA driver and compositor version, other GPU clients, and that a bottom-layer surface may not receive frame callbacks when fully occluded.
- Tickets go in `.scratch/obsidian-graph-motion/issues/` only after the user approves the breakdown.
