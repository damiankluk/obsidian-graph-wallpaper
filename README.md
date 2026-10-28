# Obsidian Graph Wallpaper

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

An animated, local-only graph wallpaper for an Obsidian vault. It projects linked Markdown notes into a slowly rotating 3D-style sphere on the largest display, leaving other monitors and the existing wallpaper untouched.

## Features

- Reads Markdown note names and local links from one configured Obsidian vault.
- Supports Obsidian wikilinks and ordinary Markdown links between notes.
- Builds the graph mesh once per vault generation with Qt Quick 3D; GPU shaders animate the sphere, flow light along real links, and add listening ripples. It creates no per-note or per-link QML objects.
- Builds changed graph generations in short event-loop slices while keeping the last complete mesh on screen. Mesh buffers swap only after the replacement is ready, avoiding a long synchronous pause during live vault updates.
- Defaults to the display with the largest pixel area. Set `OMARCHY_OBSIDIAN_GRAPH_OUTPUT` to a connector name (for example `DP-2`) to pick a display explicitly.
- Idle drift and activity share one eased orbit response: keyboard, pointer movement, or an active agent gradually raises the motion, then it settles back smoothly. Pointer motion also adds gentle camera parallax and a local listening ripple; keyboard activity adds a subtler center ripple. When an Obsidian window is focused, the matching note node is highlighted by title.
- Watches Markdown files with Linux inotify and refreshes the graph shortly after a save; a bounded five-minute scan recovers from missed watcher events. If the vault is not mounted, it retries every ten seconds. Call `omarchy-shell io.github.damiankluk.obsidian-graph refresh` to refresh manually; this updates the existing surface without restarting the shell.
- Highlights recently edited notes briefly. Optional lifecycle hooks for Codex, Claude Code, and Antigravity make the whole graph breathe gently while an agent turn is active; the effect eases in and out without a separate activity badge.
- Targets 30 fps while idle and 60 fps while listening or an agent is working. Motion runs on the GPU over static graph geometry; changed graph data is built in small QML slices and swapped as one completed generation. Timer callbacks and `frameSwapped` measurements are not proof of compositor scanout.
- Reads agent state from its small runtime JSON file with Quickshell's file watcher and expires stale leases in-process. A 15-second recovery read handles missed atomic file replacements without launching a Python process every second.
- Sends a faint thought wave from recently changed notes through at most two link hops and 24 nodes, repeating every five seconds while an agent is active. If no note changed yet, the wave starts at the most-connected note but remains bounded. A uniquely matched focused note brightens its direct neighbors and links; duplicate titles leave the graph unchanged.
- Keeps a private, short-lived graph cache under `$XDG_RUNTIME_DIR/obsidian-graph/` so the wallpaper can return immediately after a shell restart. It contains note labels and links, never note bodies, and is removed when the user session ends.
- Skips hidden folders, `.obsidian`, `.git`, `_trash`, `.trash`, and `node_modules`; also honors `userIgnoreFilters` from `.obsidian/app.json`.

This is a wallpaper visualization, not an interactive Obsidian workspace. It does not provide full parity with Obsidian's own link resolver: aliases and heading anchors point to their containing note when possible, but are not separate nodes; unresolved links, canvas files, and non-Markdown attachments are not rendered as nodes.

## Requirements

- Omarchy Quattro shell plugins.
- Qt 6.12 Qt Quick 3D (`qt6-quick3d` on Arch), Python 3, and GNU Coreutils `timeout`.
- No credentials or network connection.
- Linux inotify support (provided by the kernel; no `inotify-tools` package required).

## Install

```bash
omarchy plugin add https://github.com/damiankluk/obsidian-graph-wallpaper.git --enable
```

To install a local checkout manually, copy the repository to `~/.config/omarchy/plugins/io.github.damiankluk.obsidian-graph/`, run `omarchy-shell shell rescanPlugins`, then run `omarchy plugin enable io.github.damiankluk.obsidian-graph`.

QML releases are packaged under a content-addressed runtime path. This gives changed service, graph-view, and shader files new URLs so Qt cannot silently reuse a stale compiled component after an Omarchy plugin rescan. Run `python3 scripts/package_runtime.py --write` after changing runtime QML or shader sources; it updates the manifest entry point and verifies the packaged snapshot. The plugin's normal file watcher then reloads only this service; it does not restart the Omarchy shell or touch the other monitor.

### Optional agent activity pulse

Run the following after installing the plugin to add non-blocking lifecycle hooks to existing user configuration files:

```bash
python3 ~/.config/omarchy/plugins/io.github.damiankluk.obsidian-graph/scripts/manage_agent_hooks.py install
```

The installer preserves existing hooks and writes a timestamped `.bak` before changing each file. To remove only this plugin's hooks, run `.../scripts/manage_agent_hooks.py remove`. Codex may require reviewing the new hook in `/hooks`; Antigravity may need its hooks page refreshed or the app restarted.

The hooks only pass lifecycle JSON to the local helper. It discards prompts, tool arguments, transcripts, paths, and conversation IDs; it stores only active agent names and short-lived session hashes in a mode-600 file under `$XDG_RUNTIME_DIR/obsidian-graph/`. A three-minute lease clears activity if an agent exits without a stop event. Agent hooks are optional; vault watching works without them.

## Configure

The default vault path is `~/Documents/Agent_Vault`. Override it by exporting `OBSIDIAN_VAULT_PATH` before Omarchy starts. To select an output explicitly, set `OMARCHY_OBSIDIAN_GRAPH_OUTPUT` to its connector name; `largest` picks the highest-resolution display.

For example, add these lines to `~/.config/hypr/monitors.lua` and reload Hyprland:

```lua
hl.env("OBSIDIAN_VAULT_PATH", "/path/to/your/vault")
hl.env("OMARCHY_OBSIDIAN_GRAPH_OUTPUT", "DP-2")
```

Disable the plugin with `omarchy plugin disable io.github.damiankluk.obsidian-graph`. Remove it with `omarchy plugin remove io.github.damiankluk.obsidian-graph`. These commands do not modify or delete vault notes.

## Privacy and resource limits

The plugin runs unsandboxed inside `omarchy-shell`, as all Omarchy plugins do. Its bundled Python helper reads `.md` files under the selected vault and the `userIgnoreFilters` setting from `.obsidian/app.json`, then prints a bounded graph summary to the QML process. It reads no credentials and makes no network requests. It skips files larger than 1 MB, includes at most 1,200 notes and 4,000 links, and each scan is stopped after 30 seconds. Only labels, folder groups, coordinates, and links enter the visual model and the mode-600 runtime cache; note bodies are discarded after link extraction.

Input handling uses Quickshell's aggregate idle state and passive hover events on the background surface. It does not record key values or store pointer positions. Cursor parallax is available while the desktop background receives hover events; the activity-based orbit also responds while another window is focused. Agent activity uses supported lifecycle hooks; it does not infer work from process names.

## Development and validation

```bash
python3 scripts/validate_manifest.py .
omarchy plugin validate .
```

`bash tests/run` runs portable checks, cadence simulation, the 3D shader contract checks, runtime-package consistency, and manifest validation. `python3 bench/run_benchmark.py --states idle,agent --duration 60` measures only real notes from the configured vault by default. Synthetic stress fixtures are available for isolated development checks, and are never written to the production vault cache. The timing probe records Quickshell `frameSwapped` timestamps, not compositor presentation or scanout.

To measure a live geometry-generation swap in isolation, use a synthetic fixture and request one note/link addition during measurement:

```bash
python3 bench/run_benchmark.py --fixture approved --states idle --duration 10 --geometry-refresh 3
```

See [LICENSE](LICENSE) for the MIT license. This repository is a community plugin candidate; a marketplace listing requires separate maintainer review and approval.
