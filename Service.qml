import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var graphData: ({ nodes: [], edges: [] })
  property string errorText: ""
  property bool refreshQueued: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string vaultPath: Quickshell.env("OBSIDIAN_VAULT_PATH") || (home + "/Documents/Agent_Vault")
  readonly property string requestedOutput: Quickshell.env("OMARCHY_OBSIDIAN_GRAPH_OUTPUT") || "largest"
  readonly property string pluginId: "io.github.damiankluk.obsidian-graph"
  readonly property string exporterPath: decodeURIComponent(String(Qt.resolvedUrl("export_graph.py")).replace(/^file:\/\//, ""))
  readonly property bool userActive: !activityMonitor.isIdle
  readonly property string activeNoteTitle: {
    var top = ToplevelManager.activeToplevel
    if (!top || !/obsidian/i.test(String(top.appId || ""))) return ""
    return String(top.title || "").replace(/\s*[-|]\s*Obsidian.*$/i, "").split(/\s+-\s+/)[0].trim()
  }

  function selectedScreens() {
    var screens = Quickshell.screens || []
    if (!screens.length) return []

    if (requestedOutput !== "largest") {
      var selected = []
      for (var i = 0; i < screens.length; i++) {
        if (String(screens[i].name || "") === requestedOutput) selected.push(screens[i])
      }
      return selected
    }

    var largest = screens[0]
    for (var j = 1; j < screens.length; j++) {
      if (screens[j].width * screens[j].height > largest.width * largest.height) largest = screens[j]
    }
    return [largest]
  }

  readonly property var targetScreens: selectedScreens()

  function refresh() {
    if (refreshProcess.running) {
      refreshQueued = true
      return
    }
    errorText = ""
    refreshProcess.command = ["timeout", "-k", "1", "30", "python3", exporterPath, vaultPath]
    refreshProcess.running = true
  }

  function applyOutput(output) {
    try {
      var parsed = JSON.parse(output)
      if (!parsed || !Array.isArray(parsed.nodes) || !Array.isArray(parsed.edges)) throw new Error("Unexpected graph data")
      graphData = parsed
      errorText = ""
    } catch (e) {
      errorText = "Could not parse the vault graph: " + String(e)
      console.warn("obsidian-graph: " + errorText)
    }
  }

  IpcHandler {
    target: root.pluginId
    function refresh(): void { root.refresh() }
    function status(): string {
      return JSON.stringify({
        vaultPath: root.vaultPath,
        output: root.targetScreens.length ? String(root.targetScreens[0].name) : "not found",
        nodes: root.graphData.nodes.length,
        edges: root.graphData.edges.length,
        activity: root.userActive ? "active" : "idle",
        error: root.errorText
      })
    }
  }

  // Quickshell reports aggregate idle state only. No key values or pointer
  // coordinates leave the background surface or enter persistent storage.
  IdleMonitor {
    id: activityMonitor
    enabled: true
    timeout: 2
    respectInhibitors: false
  }

  Process {
    id: refreshProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyOutput(text)
    }
    stderr: StdioCollector { id: refreshStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorText = String(refreshStderr.text || "Graph refresh failed")
        console.warn("obsidian-graph: " + root.errorText)
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        root.refresh()
      }
    }
  }

  Timer {
    // Removable vaults can mount after the shell starts. Retry quickly while
    // the graph is empty, then return to the normal two-minute refresh.
    interval: root.graphData.nodes.length === 0 ? 10000 : 120000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Variants {
    model: root.targetScreens

    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      GraphView {
        anchors.fill: parent
        graph: root.graphData
        animationEnabled: root.graphData.nodes.length > 0
        userActive: root.userActive
        activeNoteTitle: root.activeNoteTitle
      }
    }
  }
}
