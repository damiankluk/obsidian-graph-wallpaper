import QtQml
import "../../Cadence.js" as Cadence

// Headless probe: runs the real Cadence.js policy through simulated display
// ticks and prints one JSON line. tests/test_cadence.py asserts on it.
QtObject {
  function simulate(displayHz, seconds, stateAt) {
    var sched = Cadence.newScheduler()
    var tick = 1 / displayHz
    var ticks = Math.round(displayHz * seconds)
    var presents = [], elapsedTotal = 0
    for (var i = 0; i < ticks; i++) {
      var t = i * tick
      var dt = Cadence.tick(sched, tick, stateAt(t))
      if (dt > 0) { presents.push(t); elapsedTotal += dt }
    }
    var gaps = []
    for (var p = 1; p < presents.length; p++) gaps.push(presents[p] - presents[p - 1])
    return { count: presents.length, elapsedTotal: elapsedTotal, simulated: ticks * tick,
             minGap: gaps.length ? Math.min.apply(null, gaps) : 0,
             maxGap: gaps.length ? Math.max.apply(null, gaps) : 0, presents: presents }
  }

  Component.onCompleted: {
    var idle = {}
    var agent = { agentLevel: 1, thoughtLevel: 1, thoughtActive: true }
    var out = { fps: {}, sim: {}, easing: {}, switchOver: null }
    out.fps.idle = Cadence.targetFps(idle)
    out.fps.pointer = Cadence.targetFps({ pointerOver: true })
    out.fps.keyboard = Cadence.targetFps({ userActive: true })
    out.fps.agent = Cadence.targetFps(agent)
    out.fps.tailAgent = Cadence.targetFps({ agentLevel: 0.02 })
    out.fps.tailThought = Cadence.targetFps({ thoughtLevel: 0.02 })
    out.fps.tailPointer = Cadence.targetFps({ pointerLevel: 0.02 })
    out.fps.tailKeyboard = Cadence.targetFps({ keyboardLevel: 0.02 })
    out.fps.settled = Cadence.targetFps({ agentLevel: 0.005, thoughtLevel: 0.005 })

    var hzList = [60, 120, 144, 165, 180, 240]
    for (var h = 0; h < hzList.length; h++) {
      var hz = hzList[h]
      var a = simulate(hz, 10, function () { return idle })
      var b = simulate(hz, 10, function () { return agent })
      out.sim[hz] = { idle: { count: a.count, minGap: a.minGap, maxGap: a.maxGap, elapsed: a.elapsedTotal, simulated: a.simulated },
                      active: { count: b.count, minGap: b.minGap, maxGap: b.maxGap, elapsed: b.elapsedTotal, simulated: b.simulated } }
    }
    var sw = simulate(180, 4, function (t) { return t < 2 ? idle : agent })
    var before = [], after = []
    for (var p = 0; p < sw.presents.length; p++) (sw.presents[p] < 2 ? before : after).push(sw.presents[p])
    out.switchOver = { beforeCount: before.length, afterCount: after.length,
                       firstAfterGap: after[0] - before[before.length - 1], minGapAfter: sw.minGap }

    out.easing.rise = Cadence.follow(0, 1, 0.5, 0.8)
    out.easing.fall = Cadence.follow(1, 0, 0.5, 1.6)
    out.easing.holds = Cadence.follow(0.4, 0.4, 3, 1)
    out.easing.rolling = Cadence.follow(Cadence.follow(0, 1, 0.1, 0.8), 1, 0.4, 0.8)
    out.easing.single = Cadence.follow(0, 1, 0.5, 0.8)
    var pose = Cadence.pose(0)
    out.pose0 = pose
    out.poseLater = Cadence.pose(100)
    out.pulse = [Cadence.pulse(0, 3), Cadence.pulse(1, 0)]
    console.log("PROBE " + JSON.stringify(out))
    Qt.quit()
  }
}
