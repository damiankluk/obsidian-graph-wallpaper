import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Benchmark host for the production Graph3DView. Not loaded from bench/ directly: Quickshell
// refuses imports outside the config folder, so run_benchmark.py stages this file
// next to symlinks to the plugin's QML renderer and shaders/ and launches it there,
// where local imports resolve. Launched with
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
  readonly property real geometryRefreshSeconds: Number(Quickshell.env("OGBENCH_GEOMETRY_REFRESH") || 0)
  // "off" leaves the view's frame probe untouched: no storage allocated, no
  // frameSwapped handler attached, no intervals reported (the A/B control).
  readonly property bool probeOn: (Quickshell.env("OGBENCH_PROBE") || "on") !== "off"
  readonly property string layerName: Quickshell.env("OGBENCH_LAYER") || "bottom"
  readonly property string capturePath: Quickshell.env("OGBENCH_CAPTURE_PATH") || ""

  property var graph: ({ nodes: [], edges: [] })
  property var targetScreen: null
  property var view: null
  property bool readyStarted: false
  property bool transitionAgentOn: false
  property bool transitionKeyboardOn: false

  readonly property bool agentOn: stateName === "agent" || stateName === "combined"
      || (stateName === "transition" && transitionAgentOn)
  readonly property bool pointerOn: stateName === "pointer" || stateName === "combined"
  readonly property bool keyboardOn: stateName === "keyboard" || stateName === "combined"
  readonly property bool gpuOn: (Quickshell.env("OGBENCH_GPU") || "on") !== "off"
  readonly property bool compactSurface: (Quickshell.env("OGBENCH_SURFACE") || "compact") === "compact"
  readonly property real shaderViewportLimit: Number(Quickshell.env("OGBENCH_VIEWPORT") || "1240")

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

  function startMeasurement() {
    view.resetFrameTimingProbe()
    // Keep the control run free of both probes. The probes write only into
    // plain JS typed arrays when enabled, so they do not dirty QML bindings.
    view.frameTimingProbeEnabled = probeOn
    if (probeOn) {
      view.frameProbeReset()
      view.frameProbeEnabled = true
    }
    console.log("OGBENCH start")
    measure.start()
    if (geometryRefreshSeconds > 0) geometryRefresh.start()
    if (stateName === "transition") transitionToggle.start()
  }

  function captureThenMeasure() {
    if (capturePath === "") {
      startMeasurement()
      return
    }
    var scheduled = view.grabToImage(function(result) {
      var saved = result.saveToFile(capturePath)
      console.log("OGBENCH capture " + JSON.stringify({ saved: saved, path: capturePath,
                                                       width: result.image.width, height: result.image.height }))
      startMeasurement()
    })
    if (!scheduled) {
      console.log("OGBENCH capture " + JSON.stringify({ saved: false, path: capturePath, error: "grabToImage rejected" }))
      startMeasurement()
    }
  }

  Component.onCompleted: {
    targetScreen = pickScreen()
    // The renderer can finish geometry creation and shader compilation
    // before this ShellRoot finishes assigning the child to `view`. Recheck
    // once the reference is available so the benchmark cannot wait forever.
    Qt.callLater(startWhenReady)
  }

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
    onTriggered: bench.captureThenMeasure()
  }

  Timer {
    id: pointerStimulus
    interval: 80
    repeat: true
    running: bench.pointerOn
    triggeredOnStart: true
    onTriggered: {
      if (!bench.view) return
      var t = Date.now() / 1000
      var radius = Math.min(bench.view.width, bench.view.height) * 0.34 * 0.48
      bench.view.injectPointerPosition(bench.view.width * 0.5 + Math.cos(t * 1.7) * radius,
                                       bench.view.height * 0.5 + Math.sin(t * 1.3) * radius)
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
      bench.view.frameTimingProbeEnabled = false
      console.log("OGBENCH result " + JSON.stringify({
        state: bench.stateName,
        probe: bench.probeOn ? "on" : "off",
        intervals_ms: intervals,
        frame_time_ms: bench.view.frameTimingProbeValues(),
        frame_target_ms: bench.view.frameTimingProbeTargets(),
        motion_levels: { agent: bench.view.agentMotionLevel,
                         pointer: bench.view.pointerMotionLevel,
                         keyboard: bench.view.keyboardMotionLevel },
        listening_levels: { pointer: bench.view.pointerMotionLevel,
                            keyboard: bench.view.keyboardMotionLevel },
        nodes: bench.graph.nodes.length,
        edges: bench.graph.edges.length,
        geometryRefreshTriggered: geometryRefreshTriggered,
        screen: bench.targetScreen ? { name: String(bench.targetScreen.name), width: bench.targetScreen.width, height: bench.targetScreen.height } : null,
        view: { width: bench.view.width, height: bench.view.height,
                shaderViewport: bench.view.shaderViewportLimit }
      }))
      // The harness owns the process lifetime (it still reads /proc after this
      // line); quit by itself only if the harness has gone away.
      linger.start()
    }
  }

  property bool geometryRefreshTriggered: false

  Timer {
    id: geometryRefresh
    interval: Math.max(1, bench.geometryRefreshSeconds * 1000)
    repeat: false
    onTriggered: {
      if (!bench.graph.nodes.length) return
      var nodes = bench.graph.nodes.slice(0)
      var edges = bench.graph.edges.slice(0)
      var anchor = nodes[0]
      nodes.push({ id: "Benchmark/RefreshProbe.md", label: "Refresh Probe",
                   group: "Benchmark", groupIndex: Number(anchor.groupIndex) || 0,
                   degree: 1, x: 0.31, y: -0.77, z: 0.55 })
      edges.push(["Benchmark/RefreshProbe.md", anchor.id])
      bench.graph = { origin: bench.graph.origin, nodes: nodes, edges: edges,
                      stats: bench.graph.stats || {} }
      bench.geometryRefreshTriggered = true
      console.log("OGBENCH geometry-refresh " + JSON.stringify({ nodes: nodes.length, edges: edges.length }))
    }
  }

  Timer {
    id: transitionToggle
    // Thought level falls with a 1.6 s time constant. Leave enough idle time
    // for the easing tail to finish before activating the next interval.
    interval: 10000
    repeat: true
    onTriggered: {
      bench.transitionAgentOn = !bench.transitionAgentOn
      bench.transitionKeyboardOn = !bench.transitionKeyboardOn
      console.log("OGBENCH transition " + JSON.stringify({
        agent: bench.transitionAgentOn,
        keyboard: bench.transitionKeyboardOn
      }))
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
      anchors.top: true
      anchors.left: true
      anchors.right: !bench.compactSurface
      anchors.bottom: !bench.compactSurface
      implicitWidth: bench.compactSurface ? Math.min(modelData.width, 1520) : 0
      implicitHeight: bench.compactSurface ? modelData.height : 0
      margins.left: bench.compactSurface ? Math.max(0, Math.round((modelData.width - implicitWidth) / 2)) : 0
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "obsidian-graph-bench"
      WlrLayershell.layer: bench.layerName === "top" ? WlrLayer.Top : WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      Graph3DView {
        id: graphView
        anchors.fill: parent
        graph: bench.graph
        animationEnabled: true
        gpuInterpolationEnabled: bench.gpuOn
        shaderViewportLimit: bench.shaderViewportLimit
        userActive: bench.keyboardOn || bench.transitionKeyboardOn
        agentActivity: bench.agentOn ? ["benchmark-agent"] : []
        pointerOver: bench.pointerOn
        Component.onCompleted: {
          bench.view = graphView
          Qt.callLater(bench.startWhenReady)
        }
        onFirstFramePaintedChanged: {
          bench.startWhenReady()
        }
        onEffectReadyChanged: bench.startWhenReady()
      }
    }
  }
}
