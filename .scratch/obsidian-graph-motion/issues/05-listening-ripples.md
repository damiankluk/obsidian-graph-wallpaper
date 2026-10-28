# 05: Distinct pointer and keyboard listening ripples with about two-second ease-out

**What to build:** User input makes the graph feel like it is listening, in a way that is clearly different from and gentler than the agent bubble. Pointer movement over the exposed wallpaper produces a local ripple around the cursor; keyboard activity produces a subtler ripple radiating from the graph center. Both ease away over about two seconds. Active input runs at 60 FPS.

**Blocked by:** 03 (Smooth idle motion at fixed 30 FPS with flowing link glow). Can proceed in parallel with 04.

**Status:** ready-for-agent

- [ ] A pointer ripple is centered at the cursor position mapped into the graph's frame and visibly affects nearby nodes and links.
- [ ] A keyboard ripple radiates from the graph center at lower strength than the pointer ripple and works while another window has focus, using only the aggregate activity signal.
- [ ] Both ripples decay over about two seconds with a smooth envelope; repeated input extends or renews the effect without popping.
- [ ] The listening reaction is distinguishable from the agent bubble in captures (local and gentle versus sphere-wide).
- [ ] Key values and pointer positions are never persisted, logged or sent anywhere; pointer position is used in memory only for the live ripple.
- [ ] Pointer ripples occur only when the pointer is over the exposed wallpaper, matching what the surface can receive.
- [ ] Ripple envelope and decay are unit-tested as pure logic; input is otherwise injected as state through the real view, with one live pass confirming real pointer and keyboard input.
- [ ] The listening-state benchmark at 60 FPS meets the frozen budgets for frame pacing, CPU, GPU and memory, and returns to 30 FPS after the tail ends without a hitch.
- [ ] Captures and benchmark results are saved locally.
