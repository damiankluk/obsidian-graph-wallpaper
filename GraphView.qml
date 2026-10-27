import QtQuick

Canvas {
  id: root

  property var graph: ({ nodes: [], edges: [] })
  property bool animationEnabled: false
  property bool userActive: false
  property string activeNoteTitle: ""
  property real yaw: 0
  property real pitch: 0.12
  property int frame: 0
  property real pointerYaw: 0
  property real pointerPitch: 0
  property real pointerTargetYaw: 0
  property real pointerTargetPitch: 0

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  function pointFor(node) {
    var cy = Math.cos(yaw + pointerYaw)
    var sy = Math.sin(yaw + pointerYaw)
    var cp = Math.cos(pitch + pointerPitch)
    var sp = Math.sin(pitch + pointerPitch)
    var x1 = node.x * cy - node.z * sy
    var z1 = node.x * sy + node.z * cy
    var y2 = node.y * cp - z1 * sp
    var z2 = node.y * sp + z1 * cp
    var perspective = 3.6 / (3.6 + z2)
    var radius = Math.min(width, height) * 0.34
    return {
      x: width * 0.5 + x1 * radius * perspective,
      y: height * 0.5 + y2 * radius * perspective,
      z: z2,
      scale: perspective
    }
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)

    var nodes = graph && Array.isArray(graph.nodes) ? graph.nodes : []
    var edges = graph && Array.isArray(graph.edges) ? graph.edges : []
    if (!nodes.length) return

    var projected = new Array(nodes.length)
    var lookup = Object.create(null)
    for (var i = 0; i < nodes.length; i++) {
      var p = pointFor(nodes[i])
      projected[i] = p
      lookup[nodes[i].id] = i
    }

    // Draw far connections first so nearby notes stay crisp.
    for (var e = 0; e < edges.length; e++) {
      var ai = lookup[edges[e][0]]
      var bi = lookup[edges[e][1]]
      if (ai === undefined || bi === undefined) continue
      var a = projected[ai]
      var b = projected[bi]
      var depth = (a.z + b.z + 2) / 4
      ctx.beginPath()
      ctx.moveTo(a.x, a.y)
      ctx.lineTo(b.x, b.y)
      ctx.lineWidth = 0.55 + (1 - depth) * 0.45
      ctx.strokeStyle = "rgba(119, 190, 255, " + (0.10 + (1 - depth) * 0.28) + ")"
      ctx.stroke()
    }

    var labelCandidates = []
    for (var n = 0; n < nodes.length; n++) {
      var item = nodes[n]
      var point = projected[n]
      var depthScale = clamp(1.25 - point.z * 0.32, 0.55, 1.8)
      var nodeRadius = clamp((2.2 + Math.sqrt(item.degree || 0) * 0.55) * depthScale, 1.5, 7)
      var hue = (item.groupIndex * 67 + 192) % 360
      ctx.beginPath()
      ctx.arc(point.x, point.y, nodeRadius * 2.4, 0, Math.PI * 2)
      ctx.fillStyle = "hsla(" + hue + ", 90%, 64%, " + (0.035 + (1 - point.z) * 0.045) + ")"
      ctx.fill()
      ctx.beginPath()
      ctx.arc(point.x, point.y, nodeRadius, 0, Math.PI * 2)
      ctx.fillStyle = "hsla(" + hue + ", 82%, 76%, " + (0.38 + (1 - point.z) * 0.38) + ")"
      ctx.fill()

      var focused = activeNoteTitle !== "" && String(item.label).toLocaleLowerCase() === activeNoteTitle.toLocaleLowerCase()
      if (focused) {
        var focusPulse = userActive ? (Math.sin(frame * 0.12) + 1) * 0.5 : 0.25
        ctx.beginPath()
        ctx.arc(point.x, point.y, nodeRadius + 4 + focusPulse * 2, 0, Math.PI * 2)
        ctx.lineWidth = 1.4
        ctx.strokeStyle = "rgba(227, 242, 255, " + (0.38 + focusPulse * 0.42) + ")"
        ctx.stroke()
      }

      if ((item.degree || 0) >= 3 || focused) labelCandidates.push({ node: item, point: point, depth: point.z, focused: focused })
    }

    labelCandidates.sort(function(a, b) {
      if (a.focused !== b.focused) return a.focused ? -1 : 1
      if ((b.node.degree || 0) !== (a.node.degree || 0)) return (b.node.degree || 0) - (a.node.degree || 0)
      return a.depth - b.depth
    })
    var labelCount = Math.min(24, labelCandidates.length)
    ctx.font = "12px sans-serif"
    ctx.textAlign = "left"
    for (var l = 0; l < labelCount; l++) {
      var label = labelCandidates[l]
      ctx.fillStyle = "rgba(232, 241, 255, " + clamp(0.25 + (1 - label.depth) * 0.35, 0.2, 0.62) + ")"
      ctx.fillText(label.node.label, label.point.x + 8, label.point.y - 7)
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: root.animationEnabled && root.visible
    onTriggered: {
      root.yaw += root.userActive ? 0.009 : 0.0025
      root.pitch = 0.12 + Math.sin(root.yaw * 0.37) * 0.09
      root.pointerYaw += (root.pointerTargetYaw - root.pointerYaw) * 0.035
      root.pointerPitch += (root.pointerTargetPitch - root.pointerPitch) * 0.035
      root.frame += 1
      root.requestPaint()
    }
  }

  HoverHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onPointChanged: {
      root.pointerTargetYaw = ((point.position.x / Math.max(1, root.width)) - 0.5) * 0.42
      root.pointerTargetPitch = ((point.position.y / Math.max(1, root.height)) - 0.5) * 0.24
    }
    onActiveChanged: {
      if (!active) {
        root.pointerTargetYaw = 0
        root.pointerTargetPitch = 0
      }
    }
  }

  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onGraphChanged: requestPaint()
  onUserActiveChanged: requestPaint()
  onActiveNoteTitleChanged: requestPaint()
}
