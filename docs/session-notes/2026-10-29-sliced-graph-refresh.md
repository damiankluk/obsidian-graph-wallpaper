---
date: 2026-10-29
type: devlog
tags: [devlog, obsidian-graph, qml, performance]
project: "[[Projects/Obsidian Graph Wallpaper]]"
ai-first: true
updated: 2026-10-29
---

# Session log: sliced graph refresh

## For future agent
This note preserves the 2026-10-29 session that diagnosed and fixed visible pauses during real graph updates in the Obsidian Graph Wallpaper plugin. It includes the owner's visual requirements, prior failure patterns, implementation details, verification, and remaining acceptance work. The configured Obsidian vault was read-only during this session, so copy this note into `Dev Logs/` when the vault is writable.

## User intent and visual requirements
- The graph must represent real notes and links from the configured Obsidian vault. The owner explicitly rejects invented production nodes such as `Note 0135`.
- During Codex, Claude, or Antigravity work, the whole graph should communicate active thinking: stronger sphere movement and lit, traveling neuron paths. Earlier feedback rejected a separate pulsing circle as a substitute for whole-graph movement.
- Idle motion should stay slow and fluid across axes. Pointer and keyboard interaction should feel like the graph is listening; the previous mouse acceleration was too fast and visually strobing.
- Refreshes must preserve immersion. The owner reports visible point jumps and freezes around one third of a second during refresh.
- The repository work should be documented, committed, pushed, and this session captured before a safe shutdown.

## Diagnosis and implementation
`Service.qml` already skips replacing graph data when an export is identical. When a note or link really changes, `Graph3DView.qml` used to rebuild all vertex/index buffers and convert the whole graph to Qt vector objects in one QML callback. That blocks the event loop while geometry changes.

The graph now builds in short timer slices: up to 48 notes or 96 links per build step, then up to 512 scalar components per conversion step, aligned to whole vertex attributes. The previously rendered mesh and `renderedGraph` remain paired on screen during construction. The new buffers, node index mapping, and labels are applied as one completed generation. The synthetic benchmark can inject a test note/link only into an isolated fixture; it never writes fake notes into the production vault.

README documents this mechanism and the dynamic-refresh benchmark command. The manifest is version 0.5.3. The repository also now contains the approved motion spec and six ordered implementation tickets under `.scratch/obsidian-graph-motion/`.

## Verification and deployment
- `python3 scripts/package_runtime.py --write`: generated `runtime/v49825ccca9a0133c/Service.qml`.
- `git diff --check`, `bash tests/run`, `python3 scripts/validate_manifest.py .`, and `omarchy plugin validate .`: passed.
- Dynamic isolated benchmark: `python3 bench/run_benchmark.py --fixture approved --states idle --duration 10 --warmup 2 --geometry-refresh 3 --output DP-2 --gpu-sampling off`.
- The benchmark confirmed one synthetic generation update: 506 nodes / 1,121 links became 507 / 1,122. Timer interval p99/max was 34/35 ms; raw `frameSwapped` p99/max was 35/41 ms; missed frame slots and intervals over 2x the 30 fps target were both zero. This is not compositor scanout evidence.
- That short run reported 5.28% CPU of one core and +16,488 KiB RSS over 10 seconds. This includes startup/replacement allocation and is not a long-run memory verdict.
- Live IPC after settling: DP-2, 522 vault notes, 1,164 links, watcher ready, shader status 2, no error. Immediately after re-enable the renderer was still initializing; a later status showed it ready.
- The live GIF at `.scratch/obsidian-graph-sliced-refresh.gif` shows an unchanged refresh only. The synthetic benchmark above is the changed-generation evidence.
- Commit `d706940` was pushed to `origin/main` at `https://github.com/damiankluk/obsidian-graph-wallpaper`.

## Failures and lessons
- A no-op refresh did not exercise mesh rebuilding; performance checks must create a real graph-generation change.
- Synthetic names must stay inside benchmark fixtures. Never add filler nodes to production graph data.
- Retain the last complete graph until the new generation is ready; otherwise a refresh can reveal a blank or mixed-generation frame.
- `frameSwapped` measures buffer swaps, not compositor presentation or monitor scanout. Report the limitation and keep visual acceptance open.
- Earlier attempts also missed the user's intent when agent activity only changed a small pulse, thought paths were too faint, pointer motion accelerated too abruptly, or a different 2D/image-space visual replaced the desired 3D vault graph. Keep the agreed aesthetic while optimizing implementation.

## Remaining work
- Observe a real agent edit that adds or changes a link and ask the owner to confirm that the transition is now smooth.
- Move this note to the vault's `Dev Logs/` folder, update `Projects/Obsidian Graph Wallpaper` and the 2026-10-29 daily note, once `/home/loko/Documents/Agent_Vault` is writable again.
