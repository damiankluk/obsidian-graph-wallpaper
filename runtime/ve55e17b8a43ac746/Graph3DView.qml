pragma ComponentBehavior: Bound

import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "Cadence.js" as Cadence
import "GraphGeometry.js" as GraphGeometry

Item {
  id: root

  readonly property real sphereRadius: 440
  readonly property real cameraDistance: 1450
  readonly property real cameraFov: 50
  property var graph: ({ nodes: [], edges: [] })
  property var renderedGraph: ({ nodes: [], edges: [] })
  property var agentActivity: []
  property var recentlyChangedIds: []
  property string activeNoteTitle: ""
  property bool userActive: false
  property bool animationEnabled: false
  property bool gpuInterpolationEnabled: true
  property real shaderViewportLimit: 1240
  property bool firstFramePainted: false
  property bool pointerOver: false
  property bool frameProbeEnabled: false
  property int frameProbeCapacity: 16384
  property var frameProbeData: null
  property bool frameTimingProbeEnabled: false
  property var frameTimingProbeData: null
  readonly property bool effectReady: geometryReady
  readonly property real agentMotionLevel: agentLevel
  readonly property real thoughtMotionLevel: agentLevel
  readonly property real pointerMotionLevel: pointerLevel
  readonly property real keyboardMotionLevel: keyboardLevel
  readonly property int rendererReadyStatus: geometryReady ? 2 : 0
  readonly property int nodeCount: renderedGraph && renderedGraph.nodes ? renderedGraph.nodes.length : 0
  readonly property int edgeCount: geometryData ? geometryData.edgeCount : 0
  property bool geometryReady: false
  property var geometryData: null
  property var geometryBuild: null
  property int geometryBuildGeneration: 0
  property bool alternateGeometryActive: false
  property int completedGeometryGeneration: 0
  property real lastGeometryBuildDurationMs: 0
  property double lastGeometryBuildCompletedAt: 0
  property var labelIndices: []
  property var labelTexts: []
  property var labelX: new Float32Array(0)
  property var labelY: new Float32Array(0)
  property var labelOpacity: new Float32Array(0)
  property var labelVisible: new Uint8Array(0)
  property var labelOccupiedBoxes: new Float32Array(36 * 4)
  property var labelPointScratch: ({ x: 0, y: 0, z: 0 })
  property int labelRevision: 0
  property int focusedIndex: -1
  property int changedIndexA: -1
  property int changedIndexB: -1
  property int changedIndexC: -1

  property real elapsedSeconds: 0
  property real motionClock: 0
  property real orbitSpeed: 0.6
  property real yaw: 0
  property real pitch: 0.12
  property real roll: 0
  property real flowPhase: 0
  property real wavePhaseA: 0
  property real wavePhaseB: 0
  property real breathPhase: 0
  property real pointerPhase: 0
  property real agentLevel: 0
  property real pointerLevel: 0
  property real keyboardLevel: 0
  property var pointerInput: ({ x: 0, y: 0, lastX: -1, lastY: -1, activeUntilMs: 0 })
  property vector3d pointerLocalPosition: Qt.vector3d(0, 0, 440)
  property vector3d pointerTargetPosition: Qt.vector3d(0, 0, 440)
  property int animationScheduledInterval: 33

  function vector3List(values) {
    var result = new Array(values.length / 3)
    for (var i = 0, j = 0; i < values.length; i += 3, j++)
      result[j] = Qt.vector3d(values[i], values[i + 1], values[i + 2])
    return result
  }

  function vector4List(values) {
    var result = new Array(values.length / 4)
    for (var i = 0, j = 0; i < values.length; i += 4, j++)
      result[j] = Qt.vector4d(values[i], values[i + 1], values[i + 2], values[i + 3])
    return result
  }

  function vector2List(values) {
    var result = new Array(values.length / 2)
    for (var i = 0, j = 0; i < values.length; i += 2, j++)
      result[j] = Qt.vector2d(values[i], values[i + 1])
    return result
  }

  function intList(values) {
    var result = new Array(values.length)
    for (var i = 0; i < values.length; i++) result[i] = values[i]
    return result
  }

  function frameProbeReset() {
    frameProbeData = { stamps: new Float64Array(frameProbeCapacity), count: 0 }
  }

  function frameProbeIntervals() {
    var result = []
    var data = frameProbeData
    if (!data) return result
    for (var i = 1; i < data.count; i++) result.push(data.stamps[i] - data.stamps[i - 1])
    return result
  }

  function resetFrameTimingProbe() {
    frameTimingProbeData = { stamps: new Float32Array(16384), targets: new Uint8Array(16384), count: 0 }
  }

  function frameTimingProbeValues() {
    var result = [], data = frameTimingProbeData
    if (!data) return result
    for (var i = 0; i < data.count; i++) result.push(data.stamps[i] * 1000)
    return result
  }

  function frameTimingProbeTargets() {
    var result = [], data = frameTimingProbeData
    if (!data) return result
    for (var i = 0; i < data.count; i++) result.push(data.targets[i])
    return result
  }

  function rebuildGeometry() {
    var currentGraph = graph || ({ nodes: [], edges: [] })
    var nodeCount = Math.min(1200, currentGraph.nodes ? currentGraph.nodes.length : 0)
    var edgeCount = Math.min(4000, currentGraph.edges ? currentGraph.edges.length : 0)
    geometryBuildGeneration++
    geometryBuild = {
      generation: geometryBuildGeneration,
      startedAtMs: Date.now(),
      graph: currentGraph,
      nodeCount: nodeCount,
      edgeCount: edgeCount,
      nodeCursor: 0,
      edgeCursor: 0,
      builtEdgeCount: 0,
      stage: "build",
      arrays: { nodePositions: [], nodeUvs: [], nodeColors: [], nodeIndices: [],
                edgePositions: [], edgeUvs: [], edgeColors: [], edgeIndices: [] },
      conversions: null,
      conversionCursor: 0,
      conversionIndex: 0,
      converted: {}
    }
    geometryBuildTimer.restart()
  }

  function appendGeometryChunk(target, source, indexOffset) {
    for (var i = 0; i < source.length; i++)
      target.push(Number(source[i]) + (indexOffset || 0))
  }

  function startGeometryConversions(state) {
    state.stage = "convert"
    state.conversions = [
      ["nodePositions", "positions", 3], ["nodeUvs", "uvs", 2],
      ["nodeColors", "colors", 4], ["nodeIndices", "indices", 1],
      ["edgePositions", "positions", 3], ["edgeUvs", "uvs", 2],
      ["edgeColors", "colors", 4], ["edgeIndices", "indices", 1]
    ]
  }

  function convertGeometrySlice(state) {
    var descriptor = state.conversions[state.conversionIndex]
    if (!descriptor) return false
    var sourceName = descriptor[0], kind = descriptor[1], width = descriptor[2]
    var source = state.arrays[sourceName]
    var cursor = state.conversionCursor
    var end = Math.min(source.length, cursor + Math.floor(256 / width) * width)
    var outputName = sourceName.indexOf("node") === 0 ? "node" : "edge"
    var output = state.converted[outputName + kind]
    if (!output) output = state.converted[outputName + kind] = []
    if (kind === "positions") {
      for (var p = cursor; p < end; p += 3)
        output.push(Qt.vector3d(source[p], source[p + 1], source[p + 2]))
    } else if (kind === "uvs") {
      for (var u = cursor; u < end; u += 2)
        output.push(Qt.vector2d(source[u], source[u + 1]))
    } else if (kind === "colors") {
      for (var c = cursor; c < end; c += 4)
        output.push(Qt.vector4d(source[c], source[c + 1], source[c + 2], source[c + 3]))
    } else {
      for (var n = cursor; n < end; n++) output.push(source[n])
    }
    state.conversionCursor = end
    if (end >= source.length) {
      state.conversionIndex++
      state.conversionCursor = 0
    }
    return true
  }

  function finishGeometryBuild(state) {
    if (state.generation !== geometryBuildGeneration) return
    // Fill the detached mesh pair first, then switch both models to it in one
    // binding update. The renderer never observes half of a generation.
    var nextNodeGeometry = alternateGeometryActive ? nodeGeometry : nodeGeometryAlternate
    var nextEdgeGeometry = alternateGeometryActive ? edgeGeometry : edgeGeometryAlternate
    nextNodeGeometry.positions = state.converted.nodepositions || []
    nextNodeGeometry.uv0s = state.converted.nodeuvs || []
    nextNodeGeometry.colors = state.converted.nodecolors || []
    nextNodeGeometry.indexes = state.converted.nodeindices || []
    nextEdgeGeometry.positions = state.converted.edgepositions || []
    nextEdgeGeometry.uv0s = state.converted.edgeuvs || []
    nextEdgeGeometry.colors = state.converted.edgecolors || []
    nextEdgeGeometry.indexes = state.converted.edgeindices || []
    alternateGeometryActive = !alternateGeometryActive
    renderedGraph = state.graph
    geometryData = { nodeCount: state.nodeCount, edgeCount: state.builtEdgeCount }
    geometryReady = state.nodeCount > 0
    lastGeometryBuildDurationMs = Math.max(0, Date.now() - state.startedAtMs)
    lastGeometryBuildCompletedAt = Date.now()
    completedGeometryGeneration = state.generation
    geometryBuild = null
    updateLabels()
    updateFocus()
    updateChangedNodes()
    if (geometryReady && !firstFramePainted) firstFrameTimer.restart()
    return true
  }

  function processGeometryBuildSlice() {
    var state = geometryBuild
    if (!state) { geometryBuildTimer.stop(); return }
    if (state.generation !== geometryBuildGeneration) return
    if (state.stage === "build") {
      if (state.nodeCursor < state.nodeCount) {
        var nodeEnd = Math.min(state.nodeCount, state.nodeCursor + 24)
        var nodes = GraphGeometry.build(state.graph, {
          nodeStart: state.nodeCursor, nodeEnd: nodeEnd,
          edgeStart: 0, edgeEnd: 0, includeLabels: false
        })
        appendGeometryChunk(state.arrays.nodePositions, nodes.nodePositions)
        appendGeometryChunk(state.arrays.nodeUvs, nodes.nodeUvs)
        appendGeometryChunk(state.arrays.nodeColors, nodes.nodeColors)
        appendGeometryChunk(state.arrays.nodeIndices, nodes.nodeIndices,
                            state.arrays.nodePositions.length / 3 - nodes.nodePositions.length / 3)
        state.nodeCursor = nodeEnd
        return
      }
      if (state.edgeCursor < state.edgeCount) {
        var edgeEnd = Math.min(state.edgeCount, state.edgeCursor + 48)
        var edges = GraphGeometry.build(state.graph, {
          nodeStart: 0, nodeEnd: 0,
          edgeStart: state.edgeCursor, edgeEnd: edgeEnd, includeLabels: false
        })
        var edgeVertexOffset = state.arrays.edgePositions.length / 3
        appendGeometryChunk(state.arrays.edgePositions, edges.edgePositions)
        appendGeometryChunk(state.arrays.edgeUvs, edges.edgeUvs)
        appendGeometryChunk(state.arrays.edgeColors, edges.edgeColors)
        appendGeometryChunk(state.arrays.edgeIndices, edges.edgeIndices, edgeVertexOffset)
        state.builtEdgeCount = (state.builtEdgeCount || 0) + edges.edgeCount
        state.edgeCursor = edgeEnd
        return
      }
      startGeometryConversions(state)
      return
    }
    if (state.stage === "convert") {
      if (convertGeometrySlice(state)) return
      if (finishGeometryBuild(state)) geometryBuildTimer.stop()
    }
  }

  function updateLabels() {
    focusedIndex = GraphGeometry.uniqueTitleIndex(renderedGraph, activeNoteTitle)
    labelIndices = GraphGeometry.labelsFor(renderedGraph, focusedIndex)
    var texts = new Array(labelIndices.length)
    for (var i = 0; i < labelIndices.length; i++) {
      var value = String(renderedGraph.nodes[labelIndices[i]].label || "")
      texts[i] = value.length > 24 ? value.slice(0, 23) + "…" : value
    }
    labelTexts = texts
    labelX = new Float32Array(labelIndices.length)
    labelY = new Float32Array(labelIndices.length)
    labelOpacity = new Float32Array(labelIndices.length)
    labelVisible = new Uint8Array(labelIndices.length)
    positionLabels()
  }

  function updateFocus() {
    focusedIndex = GraphGeometry.uniqueTitleIndex(renderedGraph, activeNoteTitle)
    positionLabels()
  }

  function updateChangedNodes() {
    var ids = Array.isArray(recentlyChangedIds) ? recentlyChangedIds : []
    changedIndexA = ids.length > 0 ? GraphGeometry.indexForId(renderedGraph, ids[ids.length - 1]) : -1
    changedIndexB = ids.length > 1 ? GraphGeometry.indexForId(renderedGraph, ids[ids.length - 2]) : -1
    changedIndexC = ids.length > 2 ? GraphGeometry.indexForId(renderedGraph, ids[ids.length - 3]) : -1
  }

  function rotatePoint(x, y, z) {
    var cy = Math.cos(yaw), sy = Math.sin(yaw)
    var x1 = x * cy - z * sy, z1 = x * sy + z * cy
    var cp = Math.cos(pitch), sp = Math.sin(pitch)
    var y2 = y * cp - z1 * sp, z2 = y * sp + z1 * cp
    var cr = Math.cos(roll), sr = Math.sin(roll)
    return { x: x1 * cr - y2 * sr, y: x1 * sr + y2 * cr, z: z2 }
  }

  function movedPointInto(p, x, y, z) {
    var cy = Math.cos(yaw), sy = Math.sin(yaw)
    var x1 = x * cy - z * sy, z1 = x * sy + z * cy
    var cp = Math.cos(pitch), sp = Math.sin(pitch)
    var y1 = y * cp - z1 * sp, z2 = y * sp + z1 * cp
    var cr = Math.cos(roll), sr = Math.sin(roll)
    p.x = x1 * cr - y1 * sr
    p.y = x1 * sr + y1 * cr
    p.z = z2
    var r = Math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
    if (r < 0.001) return
    var nx = p.x / r, ny = p.y / r, nz = p.z / r
    var ux = nx * 2.4 + ny * 1.2 - nz * 1.7
    var uy = ny * 2.1 - nx * 1.3 + nz * 1.8
    var waveA = Math.sin(ux + wavePhaseA)
    var waveB = Math.sin(uy + wavePhaseB)
    var radial = (waveA * 0.62 + waveB * 0.38) * agentLevel * 0.035 * sphereRadius
    var breathe = Math.sin(breathPhase) * agentLevel * 0.018 * sphereRadius
    var body = Math.max(0, Math.min(1, (r / sphereRadius - 0.08) / 0.42))
    var amt = (radial + breathe) * body
    p.x += nx * amt + (-ny) * (waveA * waveB * agentLevel * 0.008 * sphereRadius * body)
    p.y += ny * amt + nx * (waveA * waveB * agentLevel * 0.008 * sphereRadius * body)
    p.z += nz * amt
  }

  function positionLabels() {
    if (!geometryData) return
    var occupied = labelOccupiedBoxes
    var occupiedCount = 0
    var scaleBase = height / (2 * cameraDistance * Math.tan(cameraFov * Math.PI / 360))
    for (var i = 0; i < labelIndices.length; i++) {
      var graphIndex = labelIndices[i]
      var note = renderedGraph.nodes[graphIndex]
      if (!note) { labelVisible[i] = 0; continue }
      var p = labelPointScratch
      movedPointInto(p, Number(note.x) * sphereRadius, Number(note.y) * sphereRadius, Number(note.z) * sphereRadius)
      if (p.z < -8 || cameraDistance - p.z <= 10) { labelVisible[i] = 0; continue }
      var scale = scaleBase * cameraDistance / (cameraDistance - p.z)
      var px = width * 0.5 + p.x * scale
      var py = height * 0.5 - p.y * scale
      var labelWidth = Math.min(180, Math.max(24, labelTexts[i].length * 7.0))
      var left = px + 8, top = py - 9, right = left + labelWidth, bottom = top + 17
      var visible = left >= 0 && top >= 0 && right <= width && bottom <= height
      for (var j = 0; visible && j < occupiedCount; j++) {
        var offset = j * 4
        if (left < occupied[offset + 2] + 5 && right + 5 > occupied[offset]
            && top < occupied[offset + 3] + 4 && bottom + 4 > occupied[offset + 1]) visible = false
      }
      labelX[i] = left
      labelY[i] = top
      labelVisible[i] = visible ? 1 : 0
      labelOpacity[i] = Math.max(0.28, Math.min(0.9, 0.5 + p.z / (sphereRadius * 2.4)))
      if (visible) {
        occupied[occupiedCount * 4] = left
        occupied[occupiedCount * 4 + 1] = top
        occupied[occupiedCount * 4 + 2] = right
        occupied[occupiedCount * 4 + 3] = bottom
        occupiedCount++
      }
    }
    labelRevision++
  }

  function updatePointerPosition(x, y) {
    var input = pointerInput
    var dx = x - input.lastX, dy = y - input.lastY
    var moved = input.lastX < 0 || input.lastY < 0 || dx * dx + dy * dy >= 9
    input.x = x; input.y = y; input.lastX = x; input.lastY = y
    if (!moved) return
    input.activeUntilMs = Date.now() + 220
    var scale = height / (2 * cameraDistance * Math.tan(cameraFov * Math.PI / 360))
    var sx = (x - width * 0.5) / scale
    var sy = (height * 0.5 - y) / scale
    var frontZ = Math.sqrt(Math.max(0, sphereRadius * sphereRadius - sx * sx - sy * sy))
    // Inverse of the shader's Y -> X -> Z rotation, keeping the ripple attached
    // to the same graph point as the camera turns.
    var cr = Math.cos(-roll), sr = Math.sin(-roll)
    var x1 = sx * cr - sy * sr, y1 = sx * sr + sy * cr
    var cp = Math.cos(-pitch), sp = Math.sin(-pitch)
    var y2 = y1 * cp - frontZ * sp, z2 = y1 * sp + frontZ * cp
    var cy = Math.cos(-yaw), syaw = Math.sin(-yaw)
    pointerTargetPosition = Qt.vector3d(x1 * cy - z2 * syaw, y2, x1 * syaw + z2 * cy)
  }

  function injectPointerPosition(x, y) {
    updatePointerPosition(x, y)
  }

  Connections {
    target: root.frameProbeEnabled ? root.Window.window : null
    function onFrameSwapped() {
      var data = root.frameProbeData
      if (data && data.count < data.stamps.length) data.stamps[data.count++] = Date.now()
    }
  }

  View3D {
    id: scene
    anchors.fill: parent
    environment: SceneEnvironment { backgroundMode: SceneEnvironment.Transparent }
    camera: PerspectiveCamera {
      position: Qt.vector3d(0, 0, root.cameraDistance)
      fieldOfView: root.cameraFov
      clipNear: 1
      clipFar: 3200
    }

    ProceduralMesh {
      id: nodeGeometry
      primitiveMode: ProceduralMesh.Triangles
    }
    ProceduralMesh {
      id: nodeGeometryAlternate
      primitiveMode: ProceduralMesh.Triangles
    }
    ProceduralMesh {
      id: edgeGeometry
      primitiveMode: ProceduralMesh.Lines
    }
    ProceduralMesh {
      id: edgeGeometryAlternate
      primitiveMode: ProceduralMesh.Lines
    }

    Model {
      geometry: root.alternateGeometryActive ? edgeGeometryAlternate : edgeGeometry
      materials: CustomMaterial {
        id: edgeMaterial
        shadingMode: CustomMaterial.Unshaded
        lineWidth: 1.2
        sourceBlend: CustomMaterial.SrcAlpha
        destinationBlend: CustomMaterial.OneMinusSrcAlpha
        cullMode: Material.NoCulling
        vertexShader: Qt.resolvedUrl("shaders/graph3d.vert")
        fragmentShader: Qt.resolvedUrl("shaders/graph3d.frag")
        property real uTime: root.elapsedSeconds
        property real uFlowPhase: root.flowPhase
        property real uWavePhaseA: root.wavePhaseA
        property real uWavePhaseB: root.wavePhaseB
        property real uBreathPhase: root.breathPhase
        property real uPointerPhase: root.pointerPhase
        property real uAgent: root.agentLevel
        property real uPointerLevel: root.pointerLevel
        property real uKeyboardLevel: root.keyboardLevel
        property real uYaw: root.yaw
        property real uPitch: root.pitch
        property real uRoll: root.roll
        property real uNodeCount: Math.max(1, root.nodeCount)
        property real uKind: 0
        property real uFocusIndex: root.focusedIndex
        property real uChangedA: root.changedIndexA
        property real uChangedB: root.changedIndexB
        property real uChangedC: root.changedIndexC
        property vector3d uPointerPosition: root.pointerLocalPosition
      }
    }
    Model {
      geometry: root.alternateGeometryActive ? nodeGeometryAlternate : nodeGeometry
      materials: CustomMaterial {
        id: nodeMaterial
        shadingMode: CustomMaterial.Unshaded
        sourceBlend: CustomMaterial.SrcAlpha
        destinationBlend: CustomMaterial.OneMinusSrcAlpha
        cullMode: Material.NoCulling
        vertexShader: Qt.resolvedUrl("shaders/graph3d.vert")
        fragmentShader: Qt.resolvedUrl("shaders/graph3d.frag")
        property real uTime: root.elapsedSeconds
        property real uFlowPhase: root.flowPhase
        property real uWavePhaseA: root.wavePhaseA
        property real uWavePhaseB: root.wavePhaseB
        property real uBreathPhase: root.breathPhase
        property real uPointerPhase: root.pointerPhase
        property real uAgent: root.agentLevel
        property real uPointerLevel: root.pointerLevel
        property real uKeyboardLevel: root.keyboardLevel
        property real uYaw: root.yaw
        property real uPitch: root.pitch
        property real uRoll: root.roll
        property real uNodeCount: Math.max(1, root.nodeCount)
        property real uKind: 1
        property real uFocusIndex: root.focusedIndex
        property real uChangedA: root.changedIndexA
        property real uChangedB: root.changedIndexB
        property real uChangedC: root.changedIndexC
        property vector3d uPointerPosition: root.pointerLocalPosition
      }
    }
  }

  Item {
    id: labelLayer
    anchors.fill: parent
    Repeater {
      id: labelRepeater
      model: root.labelIndices.length
      delegate: Text {
        required property int index
        text: root.labelTexts[index] || ""
        color: root.labelIndices[index] === root.focusedIndex ? "#f1f8ff" : "#c9dbf5"
        font.pixelSize: 12
        font.weight: root.labelIndices[index] === root.focusedIndex ? Font.DemiBold : Font.Normal
        width: Math.min(180, Math.max(24, text.length * 7.0))
        x: { var revision = root.labelRevision; return root.labelX[index] || 0 }
        y: { var revision = root.labelRevision; return root.labelY[index] || 0 }
        opacity: { var revision = root.labelRevision; return root.labelOpacity[index] || 0 }
        visible: { var revision = root.labelRevision; return root.labelVisible[index] === 1 }
        style: Text.Outline
        styleColor: "#30101c2a"
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
      }
    }
  }

  HoverHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onPointChanged: root.updatePointerPosition(point.position.x, point.position.y)
    onActiveChanged: {
      root.pointerOver = active
      if (!active) {
        root.pointerInput.lastX = -1
        root.pointerInput.lastY = -1
      }
    }
  }

  Timer {
    id: firstFrameTimer
    interval: 1
    repeat: false
    onTriggered: root.firstFramePainted = true
  }

  Timer {
    id: geometryBuildTimer
    interval: 1
    repeat: true
    running: false
    onTriggered: root.processGeometryBuildSlice()
  }

  Timer {
    id: animationTimer
    running: root.animationEnabled && root.visible && root.geometryReady
    repeat: true
    triggeredOnStart: true
    interval: Cadence.intervalMs({
      userActive: root.userActive,
      thoughtActive: root.agentActivity.length > 0,
      agentLevel: root.agentLevel,
      pointerLevel: root.pointerLevel,
      keyboardLevel: root.keyboardLevel
    })
    onRunningChanged: if (running) {
      root.elapsedSeconds = 0
      root.animationScheduledInterval = interval
    }
    onTriggered: {
      var dt = root.animationScheduledInterval / 1000
      var now = Date.now()
      if (root.elapsedSeconds > 0) dt = Math.max(0, Math.min(0.08, (now - animationTimer.lastTickMs) / 1000))
      animationTimer.lastTickMs = now
      if (root.frameTimingProbeEnabled && root.frameTimingProbeData) {
        var samples = root.frameTimingProbeData
        if (samples.count < samples.stamps.length) {
          samples.stamps[samples.count] = dt
          samples.targets[samples.count] = root.animationScheduledInterval
          samples.count++
        }
      }
      root.elapsedSeconds += dt
      root.agentLevel = Cadence.follow(root.agentLevel, root.agentActivity.length > 0 ? 1 : 0,
                                        dt, root.agentActivity.length > 0 ? 0.8 : 1.6)
      root.pointerLevel = Cadence.rippleLevel(root.pointerLevel,
          now < root.pointerInput.activeUntilMs, dt, 0.18, 0.95)
      root.keyboardLevel = Cadence.rippleLevel(root.keyboardLevel, root.userActive, dt, 0.22, 0.55)
      var orbitTarget = Cadence.orbitSpeedTarget(root.agentLevel, 0, root.pointerLevel, root.keyboardLevel)
      root.orbitSpeed = Cadence.follow(root.orbitSpeed, orbitTarget, dt, 0.65)
      var pointerFollow = 1 - Math.exp(-dt / 0.28)
      var pointerCurrent = root.pointerLocalPosition
      var pointerTarget = root.pointerTargetPosition
      root.pointerLocalPosition = Qt.vector3d(
          pointerCurrent.x + (pointerTarget.x - pointerCurrent.x) * pointerFollow,
          pointerCurrent.y + (pointerTarget.y - pointerCurrent.y) * pointerFollow,
          pointerCurrent.z + (pointerTarget.z - pointerCurrent.z) * pointerFollow)
      root.motionClock += dt * root.orbitSpeed
      var pose = Cadence.pose(root.motionClock)
      root.yaw = pose.yaw; root.pitch = pose.pitch; root.roll = pose.roll
      root.flowPhase = Cadence.advancePhase(root.flowPhase, dt, 1.25 + root.agentLevel * 2.1)
      root.wavePhaseA = Cadence.advancePhase(root.wavePhaseA, dt, 0.72)
      root.wavePhaseB = Cadence.advancePhase(root.wavePhaseB, dt, -0.61)
      root.breathPhase = Cadence.advancePhase(root.breathPhase, dt, 0.62)
      root.pointerPhase = Cadence.advancePhase(root.pointerPhase, dt, 1.3)
      root.animationScheduledInterval = animationTimer.interval
      root.positionLabels()
    }
    property double lastTickMs: 0
  }

  onGraphChanged: rebuildGeometry()
  onFrameProbeEnabledChanged: if (frameProbeEnabled && !frameProbeData) frameProbeReset()
  onActiveNoteTitleChanged: updateLabels()
  onRecentlyChangedIdsChanged: updateChangedNodes()
  onAgentActivityChanged: if (Array.isArray(agentActivity) && agentActivity.length > 0) firstFrameTimer.restart()
  Component.onCompleted: rebuildGeometry()
}
