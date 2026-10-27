import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var graphData: ({ nodes: [], edges: [] })
  property var agentActivity: []
  property var recentlyChangedIds: []
  property string errorText: ""
  property bool refreshQueued: false
  property bool vaultWatcherReady: false
  property double lastGraphRefresh: 0

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string vaultPath: Quickshell.env("OBSIDIAN_VAULT_PATH") || (home + "/Documents/Agent_Vault")
  readonly property string requestedOutput: Quickshell.env("OMARCHY_OBSIDIAN_GRAPH_OUTPUT") || "largest"
  readonly property string pluginId: "io.github.damiankluk.obsidian-graph"
  readonly property string exporterPath: decodeURIComponent(String(Qt.resolvedUrl("export_graph.py")).replace(/^file:\/\//, ""))
  readonly property string watcherPath: decodeURIComponent(String(Qt.resolvedUrl("watch_vault.py")).replace(/^file:\/\//, ""))
  readonly property string activityHelperPath: decodeURIComponent(String(Qt.resolvedUrl("agent_activity.py")).replace(/^file:\/\//, ""))
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

  function handleWatchEvent(line) {
    try {
      var event = JSON.parse(String(line).trim())
      if (event.event === "ready") {
        vaultWatcherReady = true
        return
      }
      if (event.event !== "change") return
      var relative = String(event.path || "")
      if (relative !== "") {
        var changed = recentlyChangedIds.slice(0)
        if (changed.indexOf(relative) < 0) changed.push(relative)
        recentlyChangedIds = changed
        changedNoteTimer.restart()
      }
      graphRefreshDebounce.restart()
    } catch (e) {
      console.warn("obsidian-graph: ignored a malformed vault watcher event")
    }
  }

  function applyAgentSnapshot(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      agentActivity = Array.isArray(parsed.agents) ? parsed.agents : []
    } catch (e) {
      agentActivity = []
    }
  }

  function applyOutput(output) {
    try {
      var parsed = JSON.parse(output)
      if (!parsed || !Array.isArray(parsed.nodes) || !Array.isArray(parsed.edges)) throw new Error("Unexpected graph data")
      graphData = parsed
      errorText = ""
      lastGraphRefresh = Date.now()
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
        activeAgents: root.agentActivity,
        vaultWatcher: root.vaultWatcherReady ? "ready" : "retrying",
        lastGraphRefresh: root.lastGraphRefresh,
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

  Process {
    id: vaultWatcher
    command: ["python3", root.watcherPath, root.vaultPath]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.handleWatchEvent(String(line)) }
    }
    onExited: function() {
      root.vaultWatcherReady = false
      vaultWatcherRestart.start()
    }
  }

  Process {
    id: agentActivityReader
    command: ["python3", root.activityHelperPath, "snapshot"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAgentSnapshot(text)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  // Snapshot reads are bounded and local; no agent prompt or transcript is read.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: if (!agentActivityReader.running) agentActivityReader.running = true
  }

  Timer {
    id: graphRefreshDebounce
    interval: 750
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: changedNoteTimer
    interval: 12000
    repeat: false
    onTriggered: root.recentlyChangedIds = []
  }

  Timer {
    id: vaultWatcherRestart
    interval: 5000
    repeat: false
    onTriggered: if (!vaultWatcher.running) vaultWatcher.running = true
  }

  Timer {
    // Keep a bounded full scan as a recovery path if inotify drops or fails.
    interval: root.graphData.nodes.length === 0 ? 10000 : (root.vaultWatcherReady ? 300000 : 15000)
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
        agentActivity: root.agentActivity
        recentlyChangedIds: root.recentlyChangedIds
      }
    }
  }
}
