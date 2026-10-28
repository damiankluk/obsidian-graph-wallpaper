import QtQuick
import "../../GraphGeometry.js" as GraphGeometry

QtObject {
  Component.onCompleted: {
    var graph = {
      nodes: [
        { id: "Real/One.md", label: "One", groupIndex: 0, degree: 1, x: 1, y: 0, z: 0 },
        { id: "Real/Two.md", label: "Two", groupIndex: 1, degree: 1, x: -1, y: 0, z: 0 }
      ],
      edges: [["Real/One.md", "Real/Two.md"], ["missing.md", "Real/One.md"]]
    }
    var mesh = GraphGeometry.build(graph)
    var nodeChunk = GraphGeometry.build(graph, {
      nodeStart: 1, nodeEnd: 2, edgeStart: 0, edgeEnd: 0, includeLabels: false
    })
    var edgeChunk = GraphGeometry.build(graph, {
      nodeStart: 0, nodeEnd: 0, edgeStart: 0, edgeEnd: 1, includeLabels: false
    })
    var chunkMesh = {
      nodePositions: [], nodeUvs: [], nodeColors: [], nodeIndices: [],
      edgePositions: [], edgeUvs: [], edgeColors: [], edgeIndices: []
    }
    for (var ni = 0; ni < graph.nodes.length; ni++) {
      var nodePart = GraphGeometry.build(graph, {
        nodeStart: ni, nodeEnd: ni + 1, edgeStart: 0, edgeEnd: 0, includeLabels: false
      })
      var nodeOffset = chunkMesh.nodePositions.length / 3
      append(chunkMesh.nodePositions, nodePart.nodePositions)
      append(chunkMesh.nodeUvs, nodePart.nodeUvs)
      append(chunkMesh.nodeColors, nodePart.nodeColors)
      append(chunkMesh.nodeIndices, nodePart.nodeIndices, nodeOffset)
    }
    for (var ei = 0; ei < graph.edges.length; ei++) {
      var edgePart = GraphGeometry.build(graph, {
        nodeStart: 0, nodeEnd: 0, edgeStart: ei, edgeEnd: ei + 1, includeLabels: false
      })
      var edgeOffset = chunkMesh.edgePositions.length / 3
      append(chunkMesh.edgePositions, edgePart.edgePositions)
      append(chunkMesh.edgeUvs, edgePart.edgeUvs)
      append(chunkMesh.edgeColors, edgePart.edgeColors)
      append(chunkMesh.edgeIndices, edgePart.edgeIndices, edgeOffset)
    }
    var chunkReconstructionMatches = true
    var compareKeys = ["nodePositions", "nodeUvs", "nodeColors", "nodeIndices",
                       "edgePositions", "edgeUvs", "edgeColors", "edgeIndices"]
    for (var ck = 0; ck < compareKeys.length; ck++) {
      var key = compareKeys[ck], expected = mesh[key], actual = chunkMesh[key]
      if (actual.length !== expected.length) { chunkReconstructionMatches = false; break }
      for (var ci = 0; ci < expected.length; ci++) {
        if (actual[ci] !== expected[ci]) { chunkReconstructionMatches = false; break }
      }
    }
    var radiusMin = Infinity, radiusMax = 0
    for (var i = 0; i < mesh.edgePositions.length; i += 3) {
      var x = mesh.edgePositions[i], y = mesh.edgePositions[i + 1], z = mesh.edgePositions[i + 2]
      var radius = Math.sqrt(x * x + y * y + z * z)
      radiusMin = Math.min(radiusMin, radius)
      radiusMax = Math.max(radiusMax, radius)
    }
    console.log("GEOMETRY " + JSON.stringify({
      nodeVertices: mesh.nodePositions.length / 3,
      nodeIndices: mesh.nodeIndices.length,
      edgeVertices: mesh.edgePositions.length / 3,
      edgeIndices: mesh.edgeIndices.length,
      edgeRadiusMin: radiusMin,
      edgeRadiusMax: radiusMax,
      endpoints: [mesh.edgePositions[0], mesh.edgePositions[1], mesh.edgePositions[2],
                  mesh.edgePositions[mesh.edgePositions.length - 3], mesh.edgePositions[mesh.edgePositions.length - 2],
                  mesh.edgePositions[mesh.edgePositions.length - 1]],
      nodeCount: mesh.nodeCount,
      edgeCount: mesh.edgeCount,
      chunkNodeVertices: nodeChunk.nodePositions.length / 3,
      chunkNodeUv: nodeChunk.nodeUvs[0],
      chunkEdgeVertices: edgeChunk.edgePositions.length / 3,
      chunkEdgeIndices: edgeChunk.edgeIndices.length,
      chunkReconstructionMatches: chunkReconstructionMatches,
      labels: mesh.labelIndices,
      uniqueTitle: GraphGeometry.uniqueTitleIndex(graph, "one"),
      duplicateTitle: GraphGeometry.uniqueTitleIndex({ nodes: [graph.nodes[0], graph.nodes[0]], edges: [] }, "one")
    }))
    Qt.quit()
  }

  function append(target, source, offset) {
    for (var i = 0; i < source.length; i++) target.push(source[i] + (offset || 0))
  }
}
