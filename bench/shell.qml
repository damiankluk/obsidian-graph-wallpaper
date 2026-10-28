import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Benchmark host for the real GraphView. Not loaded from bench/ directly: Quickshell
// refuses imports outside the config folder, so run_benchmark.py stages this file
// next to symlinks to the plugin's GraphView.qml and shaders/ and launches it there,
// where GraphView resolves as a same-directory type. Launched with
// OGBENCH_* environment variables; not part of the shipped plugin. Activity is
// injected as synthetic state only: the surface has an empty input region, so
// it never receives real pointer or keyboard input.
ShellRoot {
  id: bench

  readonly property string fixturePath: Quickshell.env("OGBENCH_FIXTURE") || ""
  readonly property string stateName: Quickshell.env("OGBENCH_STATE") || "idle"
  readonly property string outputName: Quickshell.env("OGBENCH_OUTPUT") || ""
  readonly property real warmupSeconds: Number(Quickshell.env("OGBENCH_WARMUP") || 3)
  readonly property real durationSeconds: Number(Quickshell.env("OGBENCH_DURATION") || 60)
  // "off" leaves the view's frame probe untouched: no storage allocated, no
  // frameSwapped handler attached, no intervals reported (the A/B control).
  readonly property bool probeOn: (Quickshell.env("OGBENCH_PROBE") || "on") !== "off"
  readonly property string layerName: Quickshell.env("OGBENCH_LAYER") || "bottom"

  property var graph: ({ nodes: [], edges: [] })
  property var targetScreen: null
  property var view: null
  property bool readyStarted: false

  readonly property bool agentOn: stateName === "agent" || stateName === "combined"
  readonly property bool pointerOn: stateName === "pointer" || stateName === "combined"
  readonly property bool keyboardOn: stateName === "keyboard" || stateName === "combined"

  function pickScreen() {
    var screens = Quickshell.screens || []
    var best = null
    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (outputName !== "") {
        if (String(screen.name) === outputName) return screen
        continue
      }
      if (!best || screen.width * screen.height > best.width * best.height) best = screen
    }
    return best
  }

  function startWhenReady() {
    if (readyStarted || !view || !view.firstFramePainted || !view.effectReady) return
    readyStarted = true
    console.log("OGBENCH ready")
    warmup.start()
  }

  Component.onCompleted: targetScreen = pickScreen()

  FileView {
    path: bench.fixturePath
    onLoaded: {
      try {
        bench.graph = JSON.parse(text())
      } catch (e) {
        console.log("OGBENCH error fixture: " + String(e))
        Qt.quit()
      }
    }
    onLoadFailed: function(error) {
      console.log("OGBENCH error fixture-load: " + String(error))
      Qt.quit()
    }
  }

  Timer {
    id: warmup
    interval: Math.max(0, bench.warmupSeconds * 1000)
    onTriggered: {
      if (bench.probeOn) {
        bench.view.frameProbeReset()
        bench.view.frameProbeEnabled = true
      }
      console.log("OGBENCH start")
      measure.start()
    }
  }

  Timer {
    id: measure
    interval: bench.durationSeconds * 1000
    onTriggered: {
      var intervals = null
      if (bench.probeOn) {
        bench.view.frameProbeEnabled = false
        intervals = bench.view.frameProbeIntervals()
      }
      console.log("OGBENCH result " + JSON.stringify({
        state: bench.stateName,
        probe: bench.probeOn ? "on" : "off",
        intervals_ms: intervals,
        nodes: bench.graph.nodes.length,
        edges: bench.graph.edges.length,
        screen: bench.targetScreen ? { name: String(bench.targetScreen.name), width: bench.targetScreen.width, height: bench.targetScreen.height } : null,
        view: { width: bench.view.width, height: bench.view.height }
      }))
      // The harness owns the process lifetime (it still reads /proc after this
      // line); quit by itself only if the harness has gone away.
      linger.start()
    }
  }

  Timer {
    id: linger
    interval: 120000
    onTriggered: Qt.quit()
  }

  Variants {
    model: bench.targetScreen && bench.graph.nodes.length > 0 ? [bench.targetScreen] : []

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "obsidian-graph-bench"
      WlrLayershell.layer: bench.layerName === "top" ? WlrLayer.Top : WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Empty input region: real input never reaches the injected-state view.
      mask: Region {}

      GraphView {
        id: graphView
        anchors.fill: parent
        graph: bench.graph
        animationEnabled: true
        userActive: bench.keyboardOn
        agentActivity: bench.agentOn ? ["benchmark-agent"] : []
        pointerOver: bench.pointerOn
        Component.onCompleted: bench.view = graphView
        onFirstFramePaintedChanged: {
          bench.startWhenReady()
        }
        onEffectReadyChanged: bench.startWhenReady()
      }
    }
  }
}
