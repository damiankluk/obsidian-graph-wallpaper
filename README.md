# Obsidian Graph Wallpaper

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

An animated, local-only graph wallpaper for an Obsidian vault. It projects linked Markdown notes into a slowly rotating 3D-style sphere on the largest display, leaving other monitors and the existing wallpaper untouched.

## Features

- Reads Markdown note names and local links from one configured Obsidian vault.
- Supports Obsidian wikilinks and ordinary Markdown links between notes.
- Renders a perspective projection with a slow orbit using Quickshell Canvas; it does not require QtQuick3D, WebGL, a CDN, or network access.
- Defaults to the display with the largest pixel area. Set `OMARCHY_OBSIDIAN_GRAPH_OUTPUT` to a connector name (for example `DP-2`) to pick a display explicitly.
- Responds to keyboard or pointer activity with a faster orbit; moving the pointer over the exposed desktop adds gentle camera parallax. When an Obsidian window is focused, the matching note node is highlighted by title.
- Watches Markdown files with Linux inotify and refreshes the graph shortly after a save; a bounded five-minute scan recovers from missed watcher events. If the vault is not mounted, it retries every ten seconds. Call `omarchy-shell io.github.damiankluk.obsidian-graph refresh` to refresh manually.
- Highlights recently edited notes briefly. Optional lifecycle hooks for Codex, Claude Code, and Antigravity make the graph glow while an agent turn is active; the small HUD names active agents.
- Reads only local Markdown files. Note bodies are not sent anywhere or stored; the graph data stays in memory.
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

The plugin runs unsandboxed inside `omarchy-shell`, as all Omarchy plugins do. Its bundled Python helper reads `.md` files under the selected vault and the `userIgnoreFilters` setting from `.obsidian/app.json`, then prints a bounded graph summary to the QML process. It reads no credentials and makes no network requests. It skips files larger than 1 MB, includes at most 1,200 notes and 4,000 links, and each scan is stopped after 30 seconds. Only labels, folder groups, coordinates, and links enter the in-memory visual model; note bodies are discarded after link extraction.

Input handling uses Quickshell's aggregate idle state and passive hover events on the background surface. It does not record key values or store pointer positions. Cursor parallax is available while the desktop background receives hover events; the activity-based orbit also responds while another window is focused. Agent activity uses supported lifecycle hooks; it does not infer work from process names.

## Development and validation

```bash
python3 scripts/validate_manifest.py .
omarchy plugin validate .
```

See [LICENSE](LICENSE) for the MIT license. This repository is a community plugin candidate; a marketplace listing requires separate maintainer review and approval.
