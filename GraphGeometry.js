.pragma library

// Builds one static triangle mesh per graph generation. Per-frame motion stays
// in the GPU vertex shader; no per-note/per-link QML objects are created.
var SPHERE_RADIUS = 440
var NODE_FACES = [
  0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2,
  1, 4, 2, 1, 3, 4, 1, 5, 3, 1, 2, 5
]
var OCTA = [
  [1, 0, 0], [-1, 0, 0], [0, 1, 0],
  [0, -1, 0], [0, 0, 1], [0, 0, -1]
]

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function hslToRgb(hue, saturation, lightness) {
  var h = ((hue % 360) + 360) % 360 / 360
  var s = clamp(saturation, 0, 1), l = clamp(lightness, 0, 1)
  if (s === 0) return [l, l, l]
  var q = l < 0.5 ? l * (1 + s) : l + s - l * s
  var p = 2 * l - q
  function channel(t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  return [channel(h + 1 / 3), channel(h), channel(h - 1 / 3)]
}

function nodeColor(groupIndex, highlighted, changed) {
  if (changed) return [1.0, 0.72, 0.38, 1.0]
  if (highlighted) return [0.88, 0.94, 1.0, 1.0]
  var rgb = hslToRgb((groupIndex * 67 + 192) % 360, 0.82, 0.72)
  return [rgb[0], rgb[1], rgb[2], 0.96]
}

function validGraph(graph) {
  return graph && Array.isArray(graph.nodes) && Array.isArray(graph.edges)
      ? graph : { nodes: [], edges: [] }
}

function build(graph, options) {
  options = options || {}
  graph = validGraph(graph)
  var nodes = graph.nodes.slice(0, 1200)
  var edges = graph.edges.slice(0, 4000)
  var nodeStart = clamp(Number(options.nodeStart) || 0, 0, nodes.length)
  var nodeEnd = options.nodeEnd === undefined ? nodes.length : clamp(Number(options.nodeEnd), nodeStart, nodes.length)
  var edgeStart = clamp(Number(options.edgeStart) || 0, 0, edges.length)
  var edgeEnd = options.edgeEnd === undefined ? edges.length : clamp(Number(options.edgeEnd), edgeStart, edges.length)
  var indexById = Object.create(null)
  var i, node
  for (i = 0; i < nodes.length; i++) {
    node = nodes[i]
    indexById[String(node.id)] = i
  }

  var nodePositions = [], nodeUvs = [], nodeColors = [], nodeIndices = []
  for (i = nodeStart; i < nodeEnd; i++) {
    node = nodes[i]
    var center = [Number(node.x) * SPHERE_RADIUS, Number(node.y) * SPHERE_RADIUS, Number(node.z) * SPHERE_RADIUS]
    var radius = clamp(2.2 + Math.sqrt(Number(node.degree) || 0) * 0.7, 2.8, 8.5)
    var tint = nodeColor(Number(node.groupIndex) || 0, false, false)
    var firstVertex = nodePositions.length / 3
    for (var f = 0; f < NODE_FACES.length; f += 3) {
      for (var k = 0; k < 3; k++) {
        var dir = OCTA[NODE_FACES[f + k]]
        nodePositions.push(center[0] + dir[0] * radius, center[1] + dir[1] * radius, center[2] + dir[2] * radius)
        nodeUvs.push((i + 0.5) / Math.max(1, nodes.length), 0)
        nodeColors.push(tint[0], tint[1], tint[2], tint[3])
        nodeIndices.push(firstVertex + f + k)
      }
    }
  }

  var edgePositions = [], edgeUvs = [], edgeColors = [], edgeIndices = []
  var edgeCount = 0
  for (i = edgeStart; i < edgeEnd; i++) {
    var pair = edges[i]
    var sourceIndex = indexById[String(pair[0])], targetIndex = indexById[String(pair[1])]
    if (sourceIndex === undefined || targetIndex === undefined) continue
    var source = nodes[sourceIndex], target = nodes[targetIndex]
    var ax = Number(source.x), ay = Number(source.y), az = Number(source.z)
    var bx = Number(target.x), by = Number(target.y), bz = Number(target.z)
    var alen = Math.sqrt(ax * ax + ay * ay + az * az), blen = Math.sqrt(bx * bx + by * by + bz * bz)
    if (alen < 0.001 || blen < 0.001) continue
    ax /= alen; ay /= alen; az /= alen
    bx /= blen; by /= blen; bz /= blen
    var dot = clamp(ax * bx + ay * by + az * bz, -1, 1)
    var arcAngle = Math.acos(dot)
    var sinAngle = Math.sin(arcAngle)
    var segments = clamp(Math.ceil(arcAngle / (Math.PI / 12)), 1, 12)
    var edgeBase = edgePositions.length / 3
    var targetChannel = targetIndex / Math.max(1, nodes.length)
    // High-degree hub links remain represented but draw more quietly, which
    // prevents a single index note from saturating the center of the sphere.
    var hubWeight = clamp(1 / Math.sqrt(Math.max(1, Number(source.degree) || 0,
                                                   Number(target.degree) || 0)), 0.12, 1)
    for (var stepIndex = 0; stepIndex <= segments; stepIndex++) {
      var t = stepIndex / segments
      var px, py, pz
      if (sinAngle > 0.001) {
        var wa = Math.sin((1 - t) * arcAngle) / sinAngle
        var wb = Math.sin(t * arcAngle) / sinAngle
        px = ax * wa + bx * wb; py = ay * wa + by * wb; pz = az * wa + bz * wb
      } else if (dot < 0) {
        var ox = Math.abs(az) < 0.9 ? 0 : 1
        var oy = 0, oz = Math.abs(az) < 0.9 ? 1 : 0
        var rx = ay * oz - az * oy, ry = az * ox - ax * oz, rz = ax * oy - ay * ox
        var rlen = Math.sqrt(rx * rx + ry * ry + rz * rz)
        rx /= rlen; ry /= rlen; rz /= rlen
        px = ax * Math.cos(Math.PI * t) + rx * Math.sin(Math.PI * t)
        py = ay * Math.cos(Math.PI * t) + ry * Math.sin(Math.PI * t)
        pz = az * Math.cos(Math.PI * t) + rz * Math.sin(Math.PI * t)
      } else {
        px = ax * (1 - t) + bx * t; py = ay * (1 - t) + by * t; pz = az * (1 - t) + bz * t
      }
      var plen = Math.sqrt(px * px + py * py + pz * pz)
      if (plen < 0.001) continue
      var scale = SPHERE_RADIUS / plen
      edgePositions.push(px * scale, py * scale, pz * scale)
      edgeUvs.push(t, sourceIndex / Math.max(1, nodes.length))
      // Keep the seed constant across every segment of an edge. The fragment
      // shader uses it to choose a small, evenly distributed set of neuron
      // paths and to move one bright pulse along each selected path.
      var edgeSeed = (i * 0.618033988749895) % 1
      edgeColors.push(targetChannel, hubWeight, edgeSeed, 0.34)
      if (stepIndex > 0) edgeIndices.push(edgeBase + stepIndex - 1, edgeBase + stepIndex)
    }
    edgeCount++
  }

  var labelIndices = []
  if (options.includeLabels === false) {
    return {
      nodePositions: new Float32Array(nodePositions), nodeUvs: new Float32Array(nodeUvs),
      nodeColors: new Float32Array(nodeColors), nodeIndices: new Uint32Array(nodeIndices),
      edgePositions: new Float32Array(edgePositions), edgeUvs: new Float32Array(edgeUvs),
      edgeColors: new Float32Array(edgeColors), edgeIndices: new Uint32Array(edgeIndices),
      labelIndices: labelIndices, nodeCount: nodes.length,
      edgeCount: edgeCount
    }
  }
  var labelOrder = nodes.map(function(value, idx) { return idx })
  labelOrder.sort(function(a, b) { return (Number(nodes[b].degree) || 0) - (Number(nodes[a].degree) || 0) })
  var seenLabels = Object.create(null)
  for (i = 0; i < labelOrder.length && labelIndices.length < 36; i++) {
    node = nodes[labelOrder[i]]
    var labelKey = String(node.label || "").trim().toLocaleLowerCase()
    if (!labelKey || seenLabels[labelKey]) continue
    seenLabels[labelKey] = true
    labelIndices.push(labelOrder[i])
  }
  return {
    nodePositions: new Float32Array(nodePositions), nodeUvs: new Float32Array(nodeUvs),
    nodeColors: new Float32Array(nodeColors), nodeIndices: new Uint32Array(nodeIndices),
    edgePositions: new Float32Array(edgePositions), edgeUvs: new Float32Array(edgeUvs),
    edgeColors: new Float32Array(edgeColors), edgeIndices: new Uint32Array(edgeIndices),
    labelIndices: labelIndices, nodeCount: nodes.length,
    edgeCount: edgeCount
  }
}

function uniqueTitleIndex(graph, title) {
  graph = validGraph(graph)
  var key = String(title || "").trim().toLocaleLowerCase()
  if (!key) return -1
  var found = -1
  for (var i = 0; i < graph.nodes.length; i++) {
    if (String(graph.nodes[i].label || "").trim().toLocaleLowerCase() !== key) continue
    if (found >= 0) return -1
    found = i
  }
  return found
}

function indexForId(graph, id) {
  graph = validGraph(graph)
  var key = String(id || "")
  for (var i = 0; i < graph.nodes.length; i++)
    if (String(graph.nodes[i].id) === key) return i
  return -1
}

function labelsFor(graph, focusIndex) {
  graph = validGraph(graph)
  var nodes = graph.nodes.slice(0, 1200)
  var result = []
  var seen = Object.create(null)
  var order = nodes.map(function(value, idx) { return idx })
  order.sort(function(a, b) { return (Number(nodes[b].degree) || 0) - (Number(nodes[a].degree) || 0) })
  if (focusIndex >= 0 && focusIndex < nodes.length) order.unshift(focusIndex)
  for (var i = 0; i < order.length && result.length < 36; i++) {
    var idx = order[i]
    var key = String(nodes[idx].label || "").trim().toLocaleLowerCase()
    if (!key || seen[key]) continue
    seen[key] = true
    result.push(idx)
  }
  return result
}
