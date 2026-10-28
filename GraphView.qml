import QtQuick
import "Cadence.js" as Cadence

Item {
  id: view

  property real renderScale: 1.0
  // Canvas builds the graph texture when data/highlights change; the scene
  // shader moves it at the approved cadence without re-rasterizing the graph.
  property bool gpuInterpolationEnabled: true
  readonly property bool effectReady: gpuSurface.status === ShaderEffect.Compiled
  property alias graph: root.graph
  property alias animationEnabled: root.animationEnabled
  property alias firstFramePainted: root.firstFramePainted
  property alias userActive: root.userActive
  property alias activeNoteTitle: root.activeNoteTitle
  property alias agentActivity: root.agentActivity
  property alias recentlyChangedIds: root.recentlyChangedIds
  // Injection surface for the benchmark: the same properties the HoverHandler
  // drives, so synthetic pointer state exercises the real code path.
  property alias pointerOver: root.pointerOver
  property alias pointerTargetYaw: root.pointerTargetYaw
  property alias pointerTargetPitch: root.pointerTargetPitch

  // Opt-in frame-timing probe. Off by default: with it off the Connections
  // below has a null target, so nothing runs per frame. When on, it stores the
  // wall-clock time of each window buffer swap (millisecond resolution) and
  // nothing else; read the result with frameProbeIntervals().
  property bool frameProbeEnabled: false
  property int frameProbeCapacity: 16384
  property var frameProbeStamps: new Float64Array(0)
  property int frameProbeCount: 0

  function frameProbeReset() {
    frameProbeStamps = new Float64Array(frameProbeCapacity)
    frameProbeCount = 0
  }

  function frameProbeIntervals() {
    var out = []
    for (var i = 1; i < frameProbeCount; i++) out.push(frameProbeStamps[i] - frameProbeStamps[i - 1])
    return out
  }

  onFrameProbeEnabledChanged: if (frameProbeEnabled && frameProbeStamps.length === 0) frameProbeReset()

  Connections {
    target: view.frameProbeEnabled ? view.Window.window : null
    function onFrameSwapped() {
      if (view.frameProbeCount < view.frameProbeStamps.length)
        view.frameProbeStamps[view.frameProbeCount++] = Date.now()
    }
  }

  Canvas {
  id: root
  // Keep the full-size graph and its labels centered at native pixel scale,
  // but do not clear or upload the empty outer margins of a 2560px+ monitor.
  anchors.centerIn: parent
  // The projected graph is about 1020 px across at native scale. Keep enough
  // room for its 24 labels while avoiding a quarter of the unused texture area.
  width: Math.max(1, Math.min(view.width, 1520))
  height: Math.max(1, Math.min(view.height, 1440))
  scale: 1 / view.renderScale
  transformOrigin: Item.TopLeft
  smooth: true
  renderStrategy: Canvas.Threaded
  opacity: view.gpuInterpolationEnabled && gpuSurface.status === ShaderEffect.Compiled ? 0 : 1

  property var graph: ({ nodes: [], edges: [] })
  property bool animationEnabled: false
  property bool firstFramePainted: false
  property bool userActive: false
  property bool pointerOver: false
  property string activeNoteTitle: ""
  property var agentActivity: []
  property var recentlyChangedIds: []
  property real yaw: 0
  property real roll: 0
  property real orbitSpeed: 0.6
  property real motionClock: 0
  property real paintedMotionClock: 0
  property real pitch: 0.12
  property int frame: 0
  property real pointerYaw: 0
  property real pointerPitch: 0
  property real pointerTargetYaw: 0
  property real pointerTargetPitch: 0
  property real rasterPointerYaw: 0
  property real rasterPointerPitch: 0
  property real pointerU: 0
  property real pointerV: 0
  property real pointerLevel: 0
  property real keyboardLevel: 0
  property real agentLevel: 0
  property real elapsedSeconds: 0
  property var frameScheduler: Cadence.newScheduler()
  property var frameSchedulerState: ({})
  property real thoughtLevel: 0
  property real thoughtSeedX: 0
  property real thoughtSeedY: 0
  property real thoughtSeedZ: 0
  property real thoughtEpochSeconds: 0
  property real thoughtFieldSwitchTime: 0
  property string thoughtSignature: ""
  property var nodeIndex: Object.create(null)
  property var nodeIds: []
  property var nodeLabels: []
  property var nodeX: new Float32Array(0)
  property var nodeY: new Float32Array(0)
  property var nodeZ: new Float32Array(0)
  property var nodeRadius: new Float32Array(0)
  property var nodeDegrees: new Uint16Array(0)
  property var nodeGroups: new Uint16Array(0)
  property var groupGlowColors: []
  property var groupCoreColors: []
  property var adjacencyByNode: []
  property var thoughtDistances: new Int8Array(0)
  property var thoughtWaveSin: new Float32Array(0)
  property var thoughtWaveCos: new Float32Array(0)
  property var previousThoughtWaveSin: new Float32Array(0)
  property var previousThoughtWaveCos: new Float32Array(0)
  property var thoughtTangentX: new Float32Array(0)
  property var thoughtTangentY: new Float32Array(0)
  property var thoughtTangentZ: new Float32Array(0)
  property var previousThoughtTangentX: new Float32Array(0)
  property var previousThoughtTangentY: new Float32Array(0)
  property var previousThoughtTangentZ: new Float32Array(0)
  property var shapeModeA: new Float32Array(0)
  property var shapeModeB: new Float32Array(0)
  property var shapeModeC: new Float32Array(0)
  property var edgeSources: new Int32Array(0)
  property var edgeTargets: new Int32Array(0)
  property var edgeBands: new Uint8Array(0)
  property var edgeWaveHops: new Int8Array(0)
  property var edgeBandCounts: new Int32Array(4)
  property var edgeBandOffsets: new Int32Array(4)
  property var edgeBandCursors: new Int32Array(4)
  property var edgeBucketIndices: new Int32Array(0)
  property var focusEdgeIndices: new Int32Array(0)
  property int focusEdgeCount: 0
  property var edgeWaveBandCounts: new Int32Array(8)
  property var edgeWaveBandOffsets: new Int32Array(8)
  property var edgeWaveBandCursors: new Int32Array(8)
  property var edgeWaveBucketIndices: new Int32Array(0)
  property var projectedX: new Float32Array(0)
  property var projectedY: new Float32Array(0)
  property var projectedZ: new Float32Array(0)
  property var bucketCounts: new Int32Array(0)
  property var bucketOffsets: new Int32Array(0)
  property var bucketCursors: new Int32Array(0)
  property var bucketNodes: new Int32Array(0)
  property var bucketsByNode: new Int16Array(0)
  property var hotNodes: new Uint8Array(0)
  property var thoughtByNode: new Float32Array(0)
  property var focusedNodes: new Uint8Array(0)
  property var neighborNodes: new Uint8Array(0)
  property var changedNodes: new Uint8Array(0)
  property var labelWidths: new Float32Array(0)
  property var labelWidthsMeasured: new Uint8Array(0)
  property var labelCandidateIndices: new Int32Array(24)
  property var occupiedLabelBoxes: new Float32Array(96)
  property int groupCount: 0
  readonly property int alphaBands: 6
  readonly property real graphPulse: Cadence.pulse(agentLevel, elapsedSeconds)
  readonly property bool thoughtActive: agentActivity.length > 0 || recentlyChangedIds.length > 0
  property int focusedNodeIndex: -1

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  function rebuildGraphIndices() {
    var nodes = graph && Array.isArray(graph.nodes) ? graph.nodes : []
    var edges = graph && Array.isArray(graph.edges) ? graph.edges : []
    var index = Object.create(null)
    var ids = new Array(nodes.length)
    var labels = new Array(nodes.length)
    var xs = new Float32Array(nodes.length)
    var ys = new Float32Array(nodes.length)
    var zs = new Float32Array(nodes.length)
    var radii = new Float32Array(nodes.length)
    var degrees = new Uint16Array(nodes.length)
    var groups = new Uint16Array(nodes.length)
    var waveSin = new Float32Array(nodes.length)
    var waveCos = new Float32Array(nodes.length)
    var previousWaveSin = new Float32Array(nodes.length)
    var previousWaveCos = new Float32Array(nodes.length)
    var tangentX = new Float32Array(nodes.length), tangentY = new Float32Array(nodes.length), tangentZ = new Float32Array(nodes.length)
    var previousTangentX = new Float32Array(nodes.length), previousTangentY = new Float32Array(nodes.length), previousTangentZ = new Float32Array(nodes.length)
    var modeA = new Float32Array(nodes.length), modeB = new Float32Array(nodes.length), modeC = new Float32Array(nodes.length)
    var maxGroup = -1
    for (var i = 0; i < nodes.length; i++) {
      var sourceNode = nodes[i]
      ids[i] = String(sourceNode.id)
      labels[i] = String(sourceNode.label || "")
      if (labels[i].length > 32) labels[i] = labels[i].slice(0, 31) + "…"
      index[ids[i]] = i
      xs[i] = sourceNode.x || 0
      ys[i] = sourceNode.y || 0
      zs[i] = sourceNode.z || 0
      groups[i] = sourceNode.groupIndex || 0
      degrees[i] = sourceNode.degree || 0
      radii[i] = 2.2 + Math.sqrt(degrees[i]) * 0.55
      maxGroup = Math.max(maxGroup, groups[i])

      // Low-order spherical modes are fixed for this graph. The animation
      // combines them with three frame-level scalars instead of evaluating
      // trigonometry for every node on every paint.
      modeA[i] = xs[i] * xs[i] - ys[i] * ys[i]
      modeB[i] = 0.5 * (2 * zs[i] * zs[i] - xs[i] * xs[i] - ys[i] * ys[i])
      modeC[i] = 2.6 * xs[i] * ys[i] * zs[i]
    }
    var sources = new Int32Array(edges.length)
    var targets = new Int32Array(edges.length)
    var valid = 0
    for (var e = 0; e < edges.length; e++) {
      var a = index[String(edges[e][0])]
      var b = index[String(edges[e][1])]
      if (a === undefined || b === undefined) continue
      sources[valid] = a
      targets[valid] = b
      valid++
    }
    nodeIndex = index
    nodeIds = ids
    nodeLabels = labels
    nodeX = xs; nodeY = ys; nodeZ = zs
    nodeRadius = radii; nodeDegrees = degrees; nodeGroups = groups
    var glowColors = [], coreColors = []
    for (var group = 0; group <= maxGroup; group++) {
      var hue = (group * 67 + 192) % 360
      glowColors[group] = "hsla(" + hue + ", 90%, 64%, 1)"
      coreColors[group] = "hsla(" + hue + ", 82%, 76%, 1)"
    }
    groupGlowColors = glowColors; groupCoreColors = coreColors
    thoughtWaveSin = waveSin; thoughtWaveCos = waveCos
    previousThoughtWaveSin = previousWaveSin; previousThoughtWaveCos = previousWaveCos
    thoughtTangentX = tangentX; thoughtTangentY = tangentY; thoughtTangentZ = tangentZ
    previousThoughtTangentX = previousTangentX; previousThoughtTangentY = previousTangentY; previousThoughtTangentZ = previousTangentZ
    shapeModeA = modeA; shapeModeB = modeB; shapeModeC = modeC
    edgeSources = sources.slice(0, valid)
    edgeTargets = targets.slice(0, valid)
    edgeBands = new Uint8Array(valid)
    edgeWaveHops = new Int8Array(valid)
    edgeBandCounts = new Int32Array(4)
    edgeBandOffsets = new Int32Array(4)
    edgeBandCursors = new Int32Array(4)
    edgeBucketIndices = new Int32Array(valid)
    focusEdgeIndices = new Int32Array(valid)
    focusEdgeCount = 0
    edgeWaveBandCounts = new Int32Array(8)
    edgeWaveBandOffsets = new Int32Array(8)
    edgeWaveBandCursors = new Int32Array(8)
    edgeWaveBucketIndices = new Int32Array(valid)
    var adjacency = new Array(nodes.length)
    for (var a = 0; a < nodes.length; a++) adjacency[a] = []
    for (var linked = 0; linked < valid; linked++) {
      var source = edgeSources[linked], target = edgeTargets[linked]
      adjacency[source].push(target)
      adjacency[target].push(source)
    }
    adjacencyByNode = adjacency
    thoughtDistances = new Int8Array(nodes.length)
    thoughtDistances.fill(-1)
    projectedX = new Float32Array(nodes.length)
    projectedY = new Float32Array(nodes.length)
    groupCount = maxGroup + 1
    projectedZ = new Float32Array(nodes.length)
    bucketCounts = new Int32Array(groupCount * alphaBands)
    bucketOffsets = new Int32Array(groupCount * alphaBands)
    bucketCursors = new Int32Array(groupCount * alphaBands)
    bucketNodes = new Int32Array(nodes.length)
    bucketsByNode = new Int16Array(nodes.length)
    hotNodes = new Uint8Array(nodes.length)
    thoughtByNode = new Float32Array(nodes.length)
    focusedNodes = new Uint8Array(nodes.length)
    neighborNodes = new Uint8Array(nodes.length)
    changedNodes = new Uint8Array(nodes.length)
    labelWidths = new Float32Array(nodes.length)
    labelWidthsMeasured = new Uint8Array(nodes.length)
  }

  function rebuildNodeSignals() {
    focusedNodes.fill(0)
    neighborNodes.fill(0)
    changedNodes.fill(0)
    focusedNodeIndex = -1
    focusEdgeCount = 0

    var title = String(activeNoteTitle || "").toLocaleLowerCase()
    if (title !== "") {
      var match = -1
      var matches = 0
      for (var i = 0; i < nodeIds.length; i++) {
        if (String(graph.nodes[i].label).toLocaleLowerCase() !== title) continue
        match = i
        matches++
        if (matches > 1) break
      }
      if (matches === 1) {
        focusedNodeIndex = match
        focusedNodes[match] = 1
        for (var e = 0; e < edgeSources.length; e++) {
          if (edgeSources[e] === match) {
            neighborNodes[edgeTargets[e]] = 1
            focusEdgeIndices[focusEdgeCount++] = e
          } else if (edgeTargets[e] === match) {
            neighborNodes[edgeSources[e]] = 1
            focusEdgeIndices[focusEdgeCount++] = e
          }
        }
      }
    }

    var changed = Array.isArray(recentlyChangedIds) ? recentlyChangedIds : []
    for (var c = 0; c < changed.length; c++) {
      var changedIndex = nodeIndex[String(changed[c])]
      if (changedIndex !== undefined) changedNodes[changedIndex] = 1
    }
  }

  function rebuildThoughtField(force) {
    var nodes = graph && Array.isArray(graph.nodes) ? graph.nodes : []
    var seeds = []
    var changed = Array.isArray(recentlyChangedIds) ? recentlyChangedIds : []
    for (var c = Math.max(0, changed.length - 3); c < changed.length; c++) {
      var changedIndex = nodeIndex[String(changed[c])]
      if (changedIndex !== undefined && seeds.indexOf(changedIndex) < 0) seeds.push(changedIndex)
    }
    if (seeds.length === 0 && thoughtActive && nodes.length > 0) {
      var hub = 0
      for (var h = 1; h < nodes.length; h++) {
        if ((nodes[h].degree || 0) > (nodes[hub].degree || 0)) hub = h
      }
      seeds.push(hub)
    }

    // Keep the last spatial field while the thought level fades out. Switching
    // only when the seed set changes prevents agent lease updates from
    // restarting the wave or snapping the surface.
    if (seeds.length === 0 && !force) return
    var signature = seeds.join("|")
    if (signature === thoughtSignature && !force) return
    thoughtSignature = signature

    var waveSin = thoughtWaveSin, waveCos = thoughtWaveCos
    var prevWaveSin = previousThoughtWaveSin, prevWaveCos = previousThoughtWaveCos
    var tangentX = thoughtTangentX, tangentY = thoughtTangentY, tangentZ = thoughtTangentZ
    var prevTangentX = previousThoughtTangentX, prevTangentY = previousThoughtTangentY, prevTangentZ = previousThoughtTangentZ
    for (var copy = 0; copy < nodes.length; copy++) {
      prevWaveSin[copy] = waveSin[copy]; prevWaveCos[copy] = waveCos[copy]
      prevTangentX[copy] = tangentX[copy]; prevTangentY[copy] = tangentY[copy]; prevTangentZ[copy] = tangentZ[copy]
    }
    thoughtFieldSwitchTime = elapsedSeconds
    if (thoughtEpochSeconds === 0) thoughtEpochSeconds = elapsedSeconds

    var distances = new Int8Array(nodes.length)
    distances.fill(-1)
    var queue = []
    for (var s = 0; s < seeds.length; s++) {
      distances[seeds[s]] = 0
      queue.push(seeds[s])
    }
    var maxWaveNodes = 24
    var maxWaveHops = 2
    for (var q = 0; q < queue.length && q < maxWaveNodes; q++) {
      var current = queue[q]
      var distance = distances[current]
      if (distance >= maxWaveHops) continue
      var neighbors = adjacencyByNode[current] || []
      for (var n = 0; n < neighbors.length; n++) {
        var neighbor = neighbors[n]
        if (distances[neighbor] >= 0) continue
        if (queue.length >= maxWaveNodes) break
        distances[neighbor] = distance + 1
        queue.push(neighbor)
      }
    }
    thoughtDistances = distances

    // Build the short, static wave-edge list once per seed change. The moving
    // color wave later packs only these edges into depth buckets.
    for (var edge = 0; edge < edgeSources.length; edge++) {
      var sourceDistance = distances[edgeSources[edge]]
      var targetDistance = distances[edgeTargets[edge]]
      var waveHop = -1
      if (sourceDistance >= 0 && targetDistance >= 0 && Math.abs(sourceDistance - targetDistance) <= 1) {
        var hop = Math.max(sourceDistance, targetDistance)
        if (hop > 0 && hop <= maxWaveHops) waveHop = hop
      }
      edgeWaveHops[edge] = waveHop
    }

    if (!nodes.length || !seeds.length) {
      thoughtSeedX = 0; thoughtSeedY = 0; thoughtSeedZ = 0
      return
    }
    var seed = seeds.length ? seeds[0] : 0
    var seedX = nodeX[seed], seedY = nodeY[seed], seedZ = nodeZ[seed]
    thoughtSeedX = seedX; thoughtSeedY = seedY; thoughtSeedZ = seedZ
    for (var point = 0; point < nodes.length; point++) {
      var dot = clamp(nodeX[point] * seedX + nodeY[point] * seedY + nodeZ[point] * seedZ, -1, 1)
      var theta = Math.acos(dot)
      var envelope = 0.45 + 0.55 * Math.exp(-Math.pow(theta / 1.1, 2))
      waveSin[point] = envelope * Math.sin(theta * 3)
      waveCos[point] = envelope * Math.cos(theta * 3)
      var tx = nodeX[point] * dot - seedX
      var ty = nodeY[point] * dot - seedY
      var tz = nodeZ[point] * dot - seedZ
      var tangentLength = Math.sqrt(tx * tx + ty * ty + tz * tz)
      if (tangentLength > 1e-4) {
        var inverseLength = 1 / tangentLength
        tangentX[point] = tx * inverseLength
        tangentY[point] = ty * inverseLength
        tangentZ[point] = tz * inverseLength
      } else {
        tangentX[point] = 0; tangentY[point] = 0; tangentZ[point] = 0
      }
    }
  }

  function thoughtIntensity(distance, offset) {
    if (thoughtLevel <= 0.001 || distance < 0) return 0
    var cycle = (elapsedSeconds - thoughtEpochSeconds) % 5
    var progress = cycle - distance * 0.62 - (offset || 0)
    if (progress < 0 || progress > 1.05) return 0
    return Math.sin(Math.PI * progress / 1.05) * thoughtLevel
  }

  onPaint: {
    root.paintedMotionClock = root.motionClock
    root.rasterPointerYaw = root.pointerYaw
    root.rasterPointerPitch = root.pointerPitch
    var ctx = getContext("2d")
    ctx.globalAlpha = 1
    var px = projectedX, py = projectedY, pz = projectedZ
    var sourceIndices = edgeSources, targetIndices = edgeTargets
    var distanceByNode = thoughtDistances
    var thoughtValues = thoughtByNode, pulse = graphPulse
    var xByNode = nodeX, yByNode = nodeY, zByNode = nodeZ
    var radiusByNode = nodeRadius, degreeByNode = nodeDegrees
    var groupByNode = nodeGroups
    var glowColorByGroup = groupGlowColors, coreColorByGroup = groupCoreColors
    var waveSinByNode = thoughtWaveSin, waveCosByNode = thoughtWaveCos
    var previousWaveSinByNode = previousThoughtWaveSin, previousWaveCosByNode = previousThoughtWaveCos
    var tangentXByNode = thoughtTangentX, tangentYByNode = thoughtTangentY, tangentZByNode = thoughtTangentZ
    var previousTangentXByNode = previousThoughtTangentX, previousTangentYByNode = previousThoughtTangentY, previousTangentZByNode = previousThoughtTangentZ
    var modeAByNode = shapeModeA, modeBByNode = shapeModeB, modeCByNode = shapeModeC
    var waveEnabled = thoughtLevel > 0.001
    var drawWidth = width, drawHeight = height
    var bands = alphaBands, drawScale = view.renderScale
    var renderTime = elapsedSeconds
    var activeLevel = thoughtLevel * thoughtLevel * (3 - 2 * thoughtLevel)
    var waveTime = renderTime * (Math.PI * 2 / 3.2)
    var waveTimeSin = Math.sin(waveTime), waveTimeCos = Math.cos(waveTime)
    var fieldBlend = clamp((renderTime - thoughtFieldSwitchTime) / 1.2, 0, 1)
    var shapeA = 0.010 * activeLevel * Math.sin(renderTime * (Math.PI * 2 / 5.7))
    var shapeB = 0.008 * activeLevel * Math.sin(renderTime * (Math.PI * 2 / 7.3) + 1.3)
    var shapeC = 0.006 * activeLevel * Math.sin(renderTime * (Math.PI * 2 / 9.1) + 2.1)
    ctx.clearRect(0, 0, width, height)

    var nodes = graph && Array.isArray(graph.nodes) ? graph.nodes : []
    if (!nodes.length) {
      firstFramePainted = false
      return
    }

    var cy = Math.cos(yaw + pointerYaw), sy = Math.sin(yaw + pointerYaw)
    var cp = Math.cos(pitch + pointerPitch), sp = Math.sin(pitch + pointerPitch)
    var cr = Math.cos(roll), sr = Math.sin(roll)
    var projectionRadius = Math.min(drawWidth, drawHeight) * 0.34
    var graphScale = 1 + pulse * 0.012
    var centerX = drawWidth * 0.5, centerY = drawHeight * 0.5
    for (var i = 0; i < nodes.length; i++) {
      var waveMotion = 0, radialMotion = 0, tangentMotion = 0
      var distance = distanceByNode[i]
      if (waveEnabled && distance >= 0) {
        var localProgress = (renderTime - thoughtEpochSeconds) % 5 - distance * 0.62
        if (localProgress >= 0 && localProgress <= 1.05) waveMotion = Math.sin(Math.PI * localProgress / 1.05) * thoughtLevel
      }
      var baseX = xByNode[i], baseY = yByNode[i], baseZ = zByNode[i]
      if (waveEnabled) {
        var fieldSin = previousWaveSinByNode[i] + (waveSinByNode[i] - previousWaveSinByNode[i]) * fieldBlend
        var fieldCos = previousWaveCosByNode[i] + (waveCosByNode[i] - previousWaveCosByNode[i]) * fieldBlend
        var tangentX = previousTangentXByNode[i] + (tangentXByNode[i] - previousTangentXByNode[i]) * fieldBlend
        var tangentY = previousTangentYByNode[i] + (tangentYByNode[i] - previousTangentYByNode[i]) * fieldBlend
        var tangentZ = previousTangentZByNode[i] + (tangentZByNode[i] - previousTangentZByNode[i]) * fieldBlend
        // A traveling surface wave carries nodes tangentially and radially;
        // three slow precomputed shape modes make the full sphere wobble like
        // a water-filled bubble instead of merely pulsing its brightness.
        var wave = fieldSin * waveTimeCos - fieldCos * waveTimeSin
        var quadrature = fieldCos * waveTimeCos + fieldSin * waveTimeSin
        radialMotion = activeLevel * 0.030 * wave + shapeA * modeAByNode[i] + shapeB * modeBByNode[i] + shapeC * modeCByNode[i]
        tangentMotion = activeLevel * 0.035 * quadrature
      }
      thoughtValues[i] = waveMotion
      var wx = baseX * (1 + radialMotion) + tangentX * tangentMotion
      var wy = baseY * (1 + radialMotion) + tangentY * tangentMotion
      var wz = baseZ * (1 + radialMotion) + tangentZ * tangentMotion
      var x1 = wx * cy - wz * sy
      var z1 = wx * sy + wz * cy
      var y2 = wy * cp - z1 * sp
      var z2 = wy * sp + z1 * cp
      var x3 = x1 * cr - y2 * sr
      var y3 = x1 * sr + y2 * cr
      var perspective = 3.6 / (3.6 + z2)
      px[i] = centerX + x3 * projectionRadius * perspective * graphScale
      py[i] = centerY + y3 * projectionRadius * perspective * graphScale
      pz[i] = z2
    }

    // Classify endpoints into preallocated depth buckets; avoid rebuilding
    // nested JS path arrays and string lookups for every moving frame.
    var hasFocusedNote = focusedNodeIndex >= 0
    var edgeBandByEdge = edgeBands, edgeCounts = edgeBandCounts
    var edgeOffsets = edgeBandOffsets, edgeCursors = edgeBandCursors, edgeIndices = edgeBucketIndices
    var focusEdges = focusEdgeIndices, focusEdgesCount = focusEdgeCount
    var bucketCountsByNode = bucketCounts, bucketOffsetsByNode = bucketOffsets
    var bucketCursorsByNode = bucketCursors, packedNodes = bucketNodes, nodeBuckets = bucketsByNode
    var hotFlags = hotNodes, focusFlags = focusedNodes, neighborFlags = neighborNodes, changedFlags = changedNodes
    var labelCandidates = labelCandidateIndices, labelWidthCache = labelWidths
    var labelMeasured = labelWidthsMeasured, labelBoxes = occupiedLabelBoxes
    var groupLimit = groupCount
    var waveHopsByEdge = edgeWaveHops
    var waveCounts = edgeWaveBandCounts, waveOffsets = edgeWaveBandOffsets
    var waveCursors = edgeWaveBandCursors, waveIndices = edgeWaveBucketIndices
    edgeCounts.fill(0)
    waveCounts.fill(0)
    for (var e = 0; e < sourceIndices.length; e++) {
      var ai = sourceIndices[e], bi = targetIndices[e]
      var az = pz[ai], bz = pz[bi]
      var depth = (az + bz + 2) / 4
      var depthBand = clamp(Math.floor(depth * 4), 0, 3)
      edgeBandByEdge[e] = depthBand
      edgeCounts[depthBand]++
      var waveHop = waveHopsByEdge[e]
      if (waveHop > 0) waveCounts[(waveHop - 1) * 4 + depthBand]++
    }

    var edgeStart = 0
    for (var bandOffset = 0; bandOffset < 4; bandOffset++) {
      edgeOffsets[bandOffset] = edgeStart
      edgeCursors[bandOffset] = edgeStart
      edgeStart += edgeCounts[bandOffset]
    }
    var waveStartIndex = 0
    for (var waveBucket = 0; waveBucket < 8; waveBucket++) {
      waveOffsets[waveBucket] = waveStartIndex
      waveCursors[waveBucket] = waveStartIndex
      waveStartIndex += waveCounts[waveBucket]
    }
    for (var packEdge = 0; packEdge < sourceIndices.length; packEdge++) {
      var packBand = edgeBandByEdge[packEdge]
      edgeIndices[edgeCursors[packBand]++] = packEdge
      var packedHop = waveHopsByEdge[packEdge]
      if (packedHop > 0) {
        var packedWaveBucket = (packedHop - 1) * 4 + packBand
        waveIndices[waveCursors[packedWaveBucket]++] = packEdge
      }
    }

    for (var band = 0; band < 4; band++) {
      if (edgeCounts[band] === 0) continue
      var bandStart = edgeOffsets[band]
      var bandEnd = bandStart + edgeCounts[band]
      var bandDepth = (band + 0.5) / 4
      ctx.beginPath()
      for (var edgeSlot = bandStart; edgeSlot < bandEnd; edgeSlot++) {
        var baseEdge = edgeIndices[edgeSlot]
        var baseA = sourceIndices[baseEdge], baseB = targetIndices[baseEdge]
        ctx.moveTo(px[baseA], py[baseA])
        ctx.lineTo(px[baseB], py[baseB])
      }
      ctx.lineWidth = (0.55 + (1 - bandDepth) * 0.45) * drawScale * (1 + pulse * 0.14)
      var focusDim = hasFocusedNote ? 0.72 : 1
      ctx.strokeStyle = "rgb(119, 190, 255)"
      ctx.globalAlpha = (0.10 + (1 - bandDepth) * 0.28) * (0.82 + pulse * 0.28) * focusDim
      ctx.stroke()
      ctx.globalAlpha = 1
    }

    if (hasFocusedNote) for (var focusBand = 0; focusBand < 4; focusBand++) {
      if (edgeCounts[focusBand] === 0) continue
      var focusedDepth = (focusBand + 0.5) / 4
      ctx.beginPath()
      for (var focusSlot = 0; focusSlot < focusEdgesCount; focusSlot++) {
        var focusEdge = focusEdges[focusSlot]
        if (edgeBandByEdge[focusEdge] !== focusBand) continue
        var focusA = sourceIndices[focusEdge], focusB = targetIndices[focusEdge]
        ctx.moveTo(px[focusA], py[focusA])
        ctx.lineTo(px[focusB], py[focusB])
      }
      ctx.lineWidth = (0.9 + (1 - focusedDepth) * 0.5) * drawScale * (1 + pulse * 0.12)
      ctx.strokeStyle = "rgb(197, 226, 255)"
      ctx.globalAlpha = 0.52
      ctx.stroke()
      ctx.globalAlpha = 1
    }

    for (var waveHop = 1; waveHop <= 2; waveHop++) {
      var edgeWave = thoughtIntensity(waveHop - 1, 0.27)
      if (edgeWave <= 0) continue
      for (var waveBand = 0; waveBand < 4; waveBand++) {
        var waveBucketIndex = (waveHop - 1) * 4 + waveBand
        if (waveCounts[waveBucketIndex] === 0) continue
        var waveStart = waveOffsets[waveBucketIndex]
        var waveEnd = waveStart + waveCounts[waveBucketIndex]
        var waveDepth = (waveBand + 0.5) / 4
        ctx.beginPath()
        for (var waveSlot = waveStart; waveSlot < waveEnd; waveSlot++) {
          var waveEdge = waveIndices[waveSlot]
          var waveA = sourceIndices[waveEdge], waveB = targetIndices[waveEdge]
          ctx.moveTo(px[waveA], py[waveA])
          ctx.lineTo(px[waveB], py[waveB])
        }
        ctx.lineWidth = (0.9 + (1 - waveDepth) * 0.45) * drawScale * (1 + edgeWave * 0.24)
        ctx.strokeStyle = "rgb(164, 213, 255)"
        ctx.globalAlpha = edgeWave * 0.34
        ctx.stroke()
        ctx.globalAlpha = 1
      }
    }

    // Classify once, then pack ordinary nodes into reusable group/depth buckets.
    // This replaces repeated whole-graph scans and per-frame bucket allocation.
    bucketCountsByNode.fill(0)
    for (var classify = 0; classify < nodes.length; classify++) {
      var classifyThought = thoughtValues[classify]
      var isFocused = focusFlags[classify] === 1
      var isNeighbor = neighborFlags[classify] === 1
      var isChanged = changedFlags[classify] === 1
      // Positional surface motion applies to the whole sphere, but only the
      // bounded BFS trail receives per-node glow passes. This keeps its cost
      // independent of graph size and avoids hot-path work on half the notes.
      var isHot = isFocused || isNeighbor || isChanged || classifyThought > 0
      hotFlags[classify] = isHot ? 1 : 0
      var nodeGroup = clamp(groupByNode[classify], 0, groupLimit - 1)
      var nodeBand = clamp(Math.floor((pz[classify] + 1) * bands / 2), 0, bands - 1)
      var nodeBucket = nodeGroup * bands + nodeBand
      nodeBuckets[classify] = nodeBucket
      bucketCountsByNode[nodeBucket]++
    }

    var bucketStart = 0
    for (var bucket = 0; bucket < bucketCountsByNode.length; bucket++) {
      bucketOffsetsByNode[bucket] = bucketStart
      bucketCursorsByNode[bucket] = bucketStart
      bucketStart += bucketCountsByNode[bucket]
    }
    for (var pack = 0; pack < nodes.length; pack++) {
      var packBucket = nodeBuckets[pack]
      packedNodes[bucketCursorsByNode[packBucket]++] = pack
    }

    var normalFocusOpacity = hasFocusedNote ? 0.70 : 1
    for (var drawBucket = 0; drawBucket < bucketCountsByNode.length; drawBucket++) {
      if (bucketCountsByNode[drawBucket] === 0) continue
      var drawGroup = Math.floor(drawBucket / bands)
      var drawBand = drawBucket % bands
      var bandZ = -1 + (drawBand + 0.5) * 2 / bands
      var start = bucketOffsetsByNode[drawBucket]
      var end = start + bucketCountsByNode[drawBucket]
      ctx.beginPath()
      for (var glowSlot = start; glowSlot < end; glowSlot++) {
        var glowIndex = packedNodes[glowSlot]
        if (hotFlags[glowIndex]) continue
        var glowZ = pz[glowIndex]
        var glowDepth = clamp(1.25 - glowZ * 0.32, 0.55, 1.8)
        var glowRadius = clamp(radiusByNode[glowIndex] * glowDepth * (1 + pulse * 0.10), 1.5, 7)
        var glowX = px[glowIndex], glowY = py[glowIndex]
        ctx.moveTo(glowX + glowRadius * 2.4, glowY)
        ctx.arc(glowX, glowY, glowRadius * 2.4, 0, Math.PI * 2)
      }
      var glowAlpha = clamp((0.035 + (1 - bandZ) * 0.045) * (0.78 + pulse * 0.42) * normalFocusOpacity, 0, 1)
      ctx.fillStyle = glowColorByGroup[drawGroup]
      ctx.globalAlpha = glowAlpha
      ctx.fill()
      ctx.globalAlpha = 1

      ctx.beginPath()
      for (var coreSlot = start; coreSlot < end; coreSlot++) {
        var coreIndex = packedNodes[coreSlot]
        if (hotFlags[coreIndex]) continue
        var coreZ = pz[coreIndex]
        var coreDepth = clamp(1.25 - coreZ * 0.32, 0.55, 1.8)
        var coreRadius = clamp(radiusByNode[coreIndex] * coreDepth * (1 + pulse * 0.10), 1.5, 7)
        var coreX = px[coreIndex], coreY = py[coreIndex]
        ctx.moveTo(coreX + coreRadius, coreY)
        ctx.arc(coreX, coreY, coreRadius, 0, Math.PI * 2)
      }
      var coreAlpha = clamp((0.38 + (1 - bandZ) * 0.38) * (0.84 + pulse * 0.22) * normalFocusOpacity, 0, 1)
      ctx.fillStyle = coreColorByGroup[drawGroup]
      ctx.globalAlpha = coreAlpha
      ctx.fill()
      ctx.globalAlpha = 1
    }

    for (var n = 0; n < nodes.length; n++) {
      var pointX = px[n], pointY = py[n], pointZ = pz[n]
      var depthScale = clamp(1.25 - pointZ * 0.32, 0.55, 1.8)
      var focused = focusFlags[n] === 1
      var focusNeighbor = neighborFlags[n] === 1
      var focusRelated = focused || focusNeighbor
      var focusOpacity = hasFocusedNote ? (focusRelated ? 1.12 : 0.70) : 1
      var thought = thoughtValues[n]
      var pointRadius = clamp(radiusByNode[n] * depthScale * (1 + pulse * 0.10 + thought * 0.10), 1.5, 7)
      var changed = changedFlags[n] === 1
      var thoughtOnly = thought > 0 && !focused && !focusNeighbor && !changed
      var pointBand = nodeBuckets[n] % bands
      var pointBandZ = -1 + (pointBand + 0.5) * 2 / bands
      var pointAlphaDepth = thoughtOnly ? pointBandZ : pointZ
      if (thought > 0 || focused || focusNeighbor || changed) {
        ctx.beginPath()
        ctx.arc(pointX, pointY, pointRadius * (2.4 + thought * 0.9), 0, Math.PI * 2)
        ctx.fillStyle = glowColorByGroup[groupByNode[n]]
        ctx.globalAlpha = clamp((0.035 + (1 - pointAlphaDepth) * 0.045) * (0.78 + pulse * 0.42) * focusOpacity + thought * 0.065, 0, 1)
        ctx.fill()
        ctx.globalAlpha = 1
        ctx.beginPath()
        ctx.arc(pointX, pointY, pointRadius, 0, Math.PI * 2)
        ctx.fillStyle = coreColorByGroup[groupByNode[n]]
        ctx.globalAlpha = clamp((0.38 + (1 - pointAlphaDepth) * 0.38) * (0.84 + pulse * 0.22) * focusOpacity + thought * 0.16, 0, 1)
        ctx.fill()
        ctx.globalAlpha = 1
      }

      if (changed) {
        var editPulse = (Math.sin(elapsedSeconds * Math.PI * 2 / 3.8) + 1) * 0.5
        ctx.beginPath()
        ctx.arc(pointX, pointY, pointRadius + (5 + editPulse * 4) * drawScale, 0, Math.PI * 2)
        ctx.lineWidth = 1.6 * drawScale
        ctx.strokeStyle = "rgb(255, 222, 145)"
        ctx.globalAlpha = 0.35 + editPulse * 0.5
        ctx.stroke()
        ctx.globalAlpha = 1
      }

      if (focused) {
        var focusPulse = userActive ? (Math.sin(elapsedSeconds * Math.PI * 2 / 4.8) + 1) * 0.5 : 0.25
        ctx.beginPath()
        ctx.arc(pointX, pointY, pointRadius + (4 + focusPulse * 2) * drawScale, 0, Math.PI * 2)
        ctx.lineWidth = 1.4 * drawScale
        ctx.strokeStyle = "rgb(227, 242, 255)"
        ctx.globalAlpha = 0.38 + focusPulse * 0.42
        ctx.stroke()
        ctx.globalAlpha = 1
      }

    }

    // Keep only the best 24 label indices in a reusable typed array instead
    // of allocating/sorting a full list of per-frame label objects.
    var labelCount = 0
    for (var candidate = 0; candidate < nodes.length; candidate++) {
      if ((degreeByNode[candidate] < 3 && !focusFlags[candidate] && !neighborFlags[candidate] && !changedFlags[candidate]) || pz[candidate] >= 0.35) continue
      var insertAt = labelCount
      while (insertAt > 0) {
        var previous = labelCandidates[insertAt - 1]
        var comesFirst = false
        if (focusFlags[candidate] !== focusFlags[previous]) comesFirst = focusFlags[candidate] > focusFlags[previous]
        else if (neighborFlags[candidate] !== neighborFlags[previous]) comesFirst = neighborFlags[candidate] > neighborFlags[previous]
        else if (changedFlags[candidate] !== changedFlags[previous]) comesFirst = changedFlags[candidate] > changedFlags[previous]
        else if (degreeByNode[candidate] !== degreeByNode[previous]) comesFirst = degreeByNode[candidate] > degreeByNode[previous]
        else comesFirst = pz[candidate] < pz[previous]
        if (!comesFirst) break
        insertAt--
      }
      if (insertAt >= 24) continue
      var nextCount = Math.min(24, labelCount + 1)
      for (var move = nextCount - 1; move > insertAt; move--) labelCandidates[move] = labelCandidates[move - 1]
      labelCandidates[insertAt] = candidate
      labelCount = nextCount
    }

    ctx.font = "12px sans-serif"
    ctx.textAlign = "left"
    var occupiedCount = 0
    for (var l = 0; l < labelCount; l++) {
      var labelIndex = labelCandidates[l]
      var labelText = nodeLabels[labelIndex]
      if (!labelMeasured[labelIndex]) {
        labelWidthCache[labelIndex] = ctx.measureText(labelText).width
        labelMeasured[labelIndex] = 1
      }
      var labelX = px[labelIndex] + 8
      var labelY = py[labelIndex] - 7
      var labelWidth = labelWidthCache[labelIndex]
      var boxLeft = labelX - 2, boxRight = labelX + labelWidth + 2
      var boxTop = labelY - 13, boxBottom = labelY + 3
      var overlaps = false
      for (var placed = 0; placed < occupiedCount; placed++) {
        var boxOffset = placed * 4
        if (boxLeft < labelBoxes[boxOffset + 2] && boxRight > labelBoxes[boxOffset] && boxTop < labelBoxes[boxOffset + 3] && boxBottom > labelBoxes[boxOffset + 1]) {
          overlaps = true
          break
        }
      }
      if (overlaps) continue
      var storeOffset = occupiedCount++ * 4
      labelBoxes[storeOffset] = boxLeft
      labelBoxes[storeOffset + 1] = boxTop
      labelBoxes[storeOffset + 2] = boxRight
      labelBoxes[storeOffset + 3] = boxBottom
      ctx.fillStyle = "rgb(232, 241, 255)"
      ctx.globalAlpha = clamp(0.25 + (1 - pz[labelIndex]) * 0.35, 0.2, 0.62)
      ctx.fillText(labelText, labelX, labelY)
      ctx.globalAlpha = 1
    }
    firstFramePainted = true

  }

  FrameAnimation {
    running: root.animationEnabled && root.visible
    onTriggered: {
      // Advance uniforms at a fixed vblank-quantized 30/60 Hz. In particular,
      // do not request a Canvas paint here: the graph raster is event-driven.
      root.frameSchedulerState.userActive = root.userActive
      root.frameSchedulerState.pointerOver = root.pointerOver
      root.frameSchedulerState.thoughtActive = root.thoughtActive
      root.frameSchedulerState.agentLevel = root.agentLevel
      root.frameSchedulerState.thoughtLevel = root.thoughtLevel
      root.frameSchedulerState.pointerLevel = root.pointerLevel
      root.frameSchedulerState.keyboardLevel = root.keyboardLevel
      var frameDelta = Cadence.tick(root.frameScheduler, frameTime, root.frameSchedulerState)
      if (frameDelta <= 0) return
      root.elapsedSeconds += frameDelta
      var targetOrbitSpeed = root.userActive ? 1.0 : 0.6
      root.orbitSpeed = Cadence.follow(root.orbitSpeed, targetOrbitSpeed, frameDelta, 0.65)
      root.motionClock += frameDelta * root.orbitSpeed
      var pose = Cadence.pose(root.motionClock)
      root.yaw = pose.yaw
      root.pitch = pose.pitch
      root.roll = pose.roll

      root.agentLevel = Cadence.follow(root.agentLevel, root.agentActivity.length > 0 ? 1 : 0, frameDelta, 1 / 3)
      var thoughtTarget = root.thoughtActive ? 1 : 0
      var thoughtTau = thoughtTarget > 0 ? 0.8 : 1.6
      root.thoughtLevel = Cadence.follow(root.thoughtLevel, thoughtTarget, frameDelta, thoughtTau)

      var pointerFollow = 1 - Math.exp(-frameDelta * 1.4)
      root.pointerYaw += (root.pointerTargetYaw - root.pointerYaw) * pointerFollow
      root.pointerPitch += (root.pointerTargetPitch - root.pointerPitch) * pointerFollow
      var pointerTarget = root.pointerOver ? 1 : 0
      var pointerTau = pointerTarget > 0 ? 0.22 : 0.45
      root.pointerLevel = Cadence.follow(root.pointerLevel, pointerTarget, frameDelta, pointerTau)
      var keyboardTarget = root.userActive ? 1 : 0
      root.keyboardLevel = Cadence.follow(root.keyboardLevel, keyboardTarget, frameDelta, keyboardTarget > 0 ? 0.35 : 0.45)
    }
  }

  HoverHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onPointChanged: {
      root.pointerTargetYaw = ((point.position.x / Math.max(1, root.width)) - 0.5) * 0.42
      root.pointerTargetPitch = ((point.position.y / Math.max(1, root.height)) - 0.5) * 0.24
      root.pointerU = (point.position.x / Math.max(1, root.width)) * 2 - 1
      root.pointerV = (point.position.y / Math.max(1, root.height)) * 2 - 1
    }
    onActiveChanged: {
      root.pointerOver = active
      if (!active) {
        root.pointerTargetYaw = 0
        root.pointerTargetPitch = 0
      }
    }
  }

  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onGraphChanged: { rebuildGraphIndices(); rebuildNodeSignals(); rebuildThoughtField(true); requestPaint() }
  onUserActiveChanged: requestPaint()
  onActiveNoteTitleChanged: {
    rebuildNodeSignals()
    requestPaint()
  }
  onAgentActivityChanged: {
    rebuildThoughtField()
    requestPaint()
  }
  onRecentlyChangedIdsChanged: {
    rebuildNodeSignals()
    rebuildThoughtField()
    requestPaint()
  }
}

  // Canvas remains the low-frequency, native-resolution raster source. The
  // GPU mesh interpolates its camera movement and thought ripple between
  // those paints without requesting another Canvas upload.
  ShaderEffect {
    id: gpuSurface
    anchors.fill: root
    scale: root.scale
    transformOrigin: Item.TopLeft
    visible: view.gpuInterpolationEnabled && status === ShaderEffect.Compiled && root.firstFramePainted
    property var source: root
    property size canvasSize: Qt.size(root.width, root.height)
    property real motionClock: root.motionClock
    property real rasterMotionClock: root.paintedMotionClock
    property real elapsedTime: root.elapsedSeconds
    property real thoughtLevel: root.thoughtLevel
    property real pointerYaw: root.pointerYaw
    property real pointerPitch: root.pointerPitch
    property real rasterPointerYaw: root.rasterPointerYaw
    property real rasterPointerPitch: root.rasterPointerPitch
    property vector2d pointerPosition: Qt.vector2d(root.pointerU, root.pointerV)
    property real pointerLevel: root.pointerLevel
    property real keyboardLevel: root.keyboardLevel
    mesh: GridMesh { resolution: Qt.size(128, 120) }
    vertexShader: Qt.resolvedUrl("shaders/bubble.vert.qsb")
    fragmentShader: Qt.resolvedUrl("shaders/bubble.frag.qsb")
    onStatusChanged: {
      if (status === ShaderEffect.Compiled) console.warn("obsidian-graph: bubble shader compiled")
      if (status === ShaderEffect.Error) console.warn("obsidian-graph: bubble shader failed: " + log)
    }
  }
}
