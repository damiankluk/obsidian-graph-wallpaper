# Obsidian Graph Wallpaper

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

An animated, local-only graph wallpaper for an Obsidian vault. It projects linked Markdown notes into a slowly rotating 3D-style sphere on the largest display, leaving other monitors and the existing wallpaper untouched.

## Features

- Reads Markdown note names and local links from one configured Obsidian vault.
- Supports Obsidian wikilinks and ordinary Markdown links between notes.
- Projects a graph of local Markdown notes in Quickshell Canvas and uses a Qt ShaderEffect for the live orbit, liquid-like motion, and traveling link glow; it does not require QtQuick3D, WebGL, a CDN, or network access.
- Defaults to the display with the largest pixel area. Set `OMARCHY_OBSIDIAN_GRAPH_OUTPUT` to a connector name (for example `DP-2`) to pick a display explicitly.
- Responds to keyboard or pointer activity with a faster orbit; moving the pointer over the exposed desktop adds gentle camera parallax. When an Obsidian window is focused, the matching note node is highlighted by title.
- Watches Markdown files with Linux inotify and refreshes the graph shortly after a save; a bounded five-minute scan recovers from missed watcher events. If the vault is not mounted, it retries every ten seconds. Call `omarchy-shell io.github.damiankluk.obsidian-graph refresh` to refresh manually; this updates the existing surface without restarting the shell.
- Highlights recently edited notes briefly. Optional lifecycle hooks for Codex, Claude Code, and Antigravity make the whole graph breathe gently while an agent turn is active; the effect eases in and out without a separate activity badge.
- Targets a fixed 30 fps while idle and 60 fps while listening or an agent is working. Canvas rerasterizes on graph or highlight changes; the shader animates between those updates. Motion uses a 3D-style image-space warp of the perspective graph texture, keeping the animation on the GPU instead of redrawing every node in JavaScript each frame. A 30-second live-vault run on an RTX 2060 SUPER at 2560×1440 measured 2.2% CPU idle / 3.1% active with no RSS growth; `frameSwapped` averages were 30/60 per second, while p99 intervals were 41/21 ms, so tighter frame pacing remains a tuning target.
- Reads agent state from its small runtime JSON file with Quickshell's file watcher and expires stale leases in-process. A 15-second recovery read handles missed atomic file replacements without launching a Python process every second.
- Sends a faint thought wave from recently changed notes through at most two link hops and 24 nodes, repeating every five seconds while an agent is active. If no note changed yet, the wave starts at the most-connected note but remains bounded. A uniquely matched focused note brightens its direct neighbors and links; duplicate titles leave the graph unchanged.
- Keeps a private, short-lived graph cache under `$XDG_RUNTIME_DIR/obsidian-graph/` so the wallpaper can return immediately after a shell restart. It contains note labels and links, never note bodies, and is removed when the user session ends.
- Skips hidden folders, `.obsidian`, `.git`, `_trash`, `.trash`, and `node_modules`; also honors `userIgnoreFilters` from `.obsidian/app.json`.

This is a wallpaper visualization, not an interactive Obsidian workspace. It does not provide full parity with Obsidian's own link resolver: aliases and heading anchors point to their containing note when possible, but are not separate nodes; unresolved links, canvas files, and non-Markdown attachments are not rendered as nodes.

## Requirements

- Omarchy Quattro shell plugins.
- Python 3 and GNU Coreutils `timeout`.
- No extra Python packages, QtQuick3D module, credentials, or network connection.
- Linux inotify support (provided by the kernel; no `inotify-tools` package required).

## Install

```bash
omarchy plugin add https://github.com/damiankluk/obsidian-graph-wallpaper.git --enable
```

To install a local checkout manually, copy the repository to `~/.config/omarchy/plugins/io.github.damiankluk.obsidian-graph/`, run `omarchy-shell shell rescanPlugins`, then run `omarchy plugin enable io.github.damiankluk.obsidian-graph`.

The graph service stays mounted across plugin rescans to avoid blanking its display. When updating the service's QML or Python code, restart the Omarchy shell once to load the new code; the wallpaper returns from its runtime cache. A full shell restart briefly removes all layer surfaces, so Hyprland uses a matching dark fallback color during that interval.

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

`bash tests/run` runs portable checks, cadence simulation, shader-pack verification, and manifest validation. `python3 bench/run_benchmark.py --states idle,agent --duration 60` measures only real notes from the configured vault by default; synthetic stress fixtures are explicit with `--fixture approved` or `--fixture limit`. The timing probe records Quickshell `frameSwapped` timestamps, not compositor presentation or scanout.

See [LICENSE](LICENSE) for the MIT license. This repository is a community plugin candidate; a marketplace listing requires separate maintainer review and approval.
