import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
  property real renderedAgentLevel: 0
  property real renderedThoughtLevel: 0
  property int renderedShaderStatus: -1
  property bool freshGraphLoaded: false
  property double lastGraphRefresh: 0
  property var targetScreens: []
  property string targetScreenSignature: ""
  property int emptyGraphResults: 0

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string vaultPath: Quickshell.env("OBSIDIAN_VAULT_PATH") || (home + "/Documents/Agent_Vault")
  readonly property string requestedOutput: Quickshell.env("OMARCHY_OBSIDIAN_GRAPH_OUTPUT") || "largest"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + (Quickshell.env("UID") || "1000"))
  readonly property string graphCachePath: runtimeDir + "/obsidian-graph/graph.json"
  readonly property string pluginId: "io.github.damiankluk.obsidian-graph"
  readonly property string exporterPath: decodeURIComponent(String(Qt.resolvedUrl("export_graph.py")).replace(/^file:\/\//, ""))
  readonly property string watcherPath: decodeURIComponent(String(Qt.resolvedUrl("watch_vault.py")).replace(/^file:\/\//, ""))
  readonly property string agentActivityPath: runtimeDir + "/obsidian-graph/agent-activity.json"
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
      var area = screens[j].width * screens[j].height
      var largestArea = largest.width * largest.height
      if (area > largestArea || (area === largestArea && String(screens[j].name || "") < String(largest.name || "")))
        largest = screens[j]
    }
    return [largest]
  }

  function updateTargetScreens() {
    var next = selectedScreens()
    var signature = next.map(function(screen) {
      return String(screen.name || "") + ":" + screen.width + "x" + screen.height
    }).join("|")
    if (signature === targetScreenSignature) return
    targetScreenSignature = signature
    targetScreens = next
  }

  Component.onCompleted: Qt.callLater(root.updateTargetScreens)

  Connections {
    target: Quickshell
    function onScreensChanged() { Qt.callLater(root.updateTargetScreens) }
  }

  function refresh() {
    if (refreshProcess.running) {
      refreshQueued = true
      return
    }
    errorText = ""
    refreshProcess.command = ["timeout", "-k", "1", "30", "python3", exporterPath, vaultPath, "--cache", graphCachePath]
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
      var sessionsByAgent = parsed && parsed.agents && typeof parsed.agents === "object" ? parsed.agents : {}
      var nowSeconds = Math.floor(Date.now() / 1000)
      var names = []
      var nextExpiry = Infinity
      var agents = Object.keys(sessionsByAgent)
      for (var i = 0; i < agents.length; i++) {
        var sessions = sessionsByAgent[agents[i]]
        if (!sessions || typeof sessions !== "object") continue
        var expiries = Object.keys(sessions)
        for (var j = 0; j < expiries.length; j++) {
          var expiry = Number(sessions[expiries[j]])
          if (!Number.isFinite(expiry)) continue
          if (expiry > nowSeconds) {
            nextExpiry = Math.min(nextExpiry, expiry)
            if (names.indexOf(agents[i]) < 0) names.push(agents[i])
          }
        }
      }
      names.sort()
      if (names.length !== agentActivity.length || names.some(function(name, index) { return name !== agentActivity[index] }))
        agentActivity = names
      if (Number.isFinite(nextExpiry)) {
        agentLeaseExpiry.interval = Math.max(1, (nextExpiry - nowSeconds) * 1000 + 50)
        agentLeaseExpiry.restart()
      } else {
        agentLeaseExpiry.stop()
      }
    } catch (e) {
      if (agentActivity.length > 0) agentActivity = []
      agentLeaseExpiry.stop()
    }
  }

  function applyOutput(output) {
    try {
      var parsed = JSON.parse(output)
      if (!parsed || parsed.origin !== "obsidian-vault" || !Array.isArray(parsed.nodes) || !Array.isArray(parsed.edges))
        throw new Error("Graph data did not come from the configured Obsidian vault")
      if (parsed.nodes.length === 0 && graphData.nodes.length > 0) {
        emptyGraphResults += 1
        var cacheNeedsConfirmation = !freshGraphLoaded && emptyGraphResults < 2
        var recentGoodGraph = freshGraphLoaded && Date.now() - lastGraphRefresh < 30000
        if (cacheNeedsConfirmation || recentGoodGraph) {
          errorText = "Graph refresh returned an empty graph; keeping the last good snapshot briefly"
          console.warn("obsidian-graph: " + errorText)
          return
        }
      }
      emptyGraphResults = 0
      graphData = parsed
      freshGraphLoaded = true
      errorText = ""
      lastGraphRefresh = Date.now()
    } catch (e) {
      errorText = "Could not parse the vault graph: " + String(e)
      console.warn("obsidian-graph: " + errorText)
    }
  }

  function applyCachedOutput(output) {
    if (freshGraphLoaded || graphData.nodes.length > 0) return
    try {
      var parsed = JSON.parse(String(output || ""))
      if (!parsed || parsed.origin !== "obsidian-vault" || !Array.isArray(parsed.nodes) || !Array.isArray(parsed.edges)) {
        console.warn("obsidian-graph: ignored a graph cache without Obsidian-vault provenance")
        return
      }
      if (parsed.nodes.length > 1200 || parsed.edges.length > 4000) return
      graphData = parsed
    } catch (e) {
      console.warn("obsidian-graph: ignored an invalid cached graph")
    }
  }

  IpcHandler {
    target: root.pluginId
    function refresh(): void { root.refresh() }
    function status(): string {
      return JSON.stringify({
        diagnosticBuild: "7c83763",
        vaultPath: root.vaultPath,
        output: root.targetScreens.length ? String(root.targetScreens[0].name) : "not found",
        nodes: root.graphData.nodes.length,
        edges: root.graphData.edges.length,
        activity: root.userActive ? "active" : "idle",
        activeAgents: root.agentActivity,
        renderedAgentLevel: root.renderedAgentLevel,
        renderedThoughtLevel: root.renderedThoughtLevel,
        shaderStatus: root.renderedShaderStatus,
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

  FileView {
    path: root.graphCachePath
    watchChanges: false
    onLoaded: root.applyCachedOutput(text())
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

  FileView {
    id: agentActivityFile
    path: root.agentActivityPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyAgentSnapshot(text())
    onFileChanged: reload()
    onLoadFailed: root.applyAgentSnapshot("")
  }

  // Hooks update this small JSON file atomically. Watch changes immediately,
  // expire stale agent leases in-process, and retain a cheap recovery read in
  // case the filesystem watcher loses track of an atomic replacement.
  Timer {
    id: agentActivityFallback
    interval: 15000
    repeat: true
    running: true
    onTriggered: agentActivityFile.reload()
  }

  Timer {
    id: agentLeaseExpiry
    repeat: false
    onTriggered: agentActivityFile.reload()
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
      id: graphPanel
      required property var modelData
      screen: modelData
      readonly property var hyprlandMonitor: Hyprland.monitorFor(modelData)
      readonly property var activeWorkspace: hyprlandMonitor ? hyprlandMonitor.activeWorkspace : null
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "obsidian-graph"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      AgentGraphView {
        id: graphView
        anchors.fill: parent
        opacity: root.graphData.nodes.length > 0 && firstFramePainted ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        graph: root.graphData
        animationEnabled: root.graphData.nodes.length > 0
        userActive: root.userActive
        activeNoteTitle: root.activeNoteTitle
        agentActivity: root.agentActivity
        recentlyChangedIds: root.recentlyChangedIds
        onAgentMotionLevelChanged: {
          if (agentMotionLevel > 0.98 || agentMotionLevel < 0.02)
            root.renderedAgentLevel = agentMotionLevel
        }
        onThoughtMotionLevelChanged: {
          if (thoughtMotionLevel > 0.98 || thoughtMotionLevel < 0.02)
            root.renderedThoughtLevel = thoughtMotionLevel
        }
        onBubbleShaderStatusChanged: root.renderedShaderStatus = bubbleShaderStatus
        Component.onCompleted: {
          root.renderedAgentLevel = agentMotionLevel
          root.renderedThoughtLevel = thoughtMotionLevel
          root.renderedShaderStatus = bubbleShaderStatus
        }
      }
    }
  }
}
