import QtQml
import "../../Cadence.js" as Cadence

// Headless probe for timer policy and animation helpers in Cadence.js.
QtObject {
  Component.onCompleted: {
    var idle = {}
    var agent = { agentLevel: 1, thoughtLevel: 1, thoughtActive: true }
    var out = { intervalMs: {}, easing: {} }
    out.intervalMs.idle = Cadence.intervalMs(idle)
    out.intervalMs.pointer = Cadence.intervalMs({ pointerLevel: 0.5 })
    out.intervalMs.pointerResting = Cadence.intervalMs({ pointerOver: true, pointerLevel: 0 })
    out.intervalMs.keyboard = Cadence.intervalMs({ userActive: true })
    out.intervalMs.agent = Cadence.intervalMs(agent)
    out.intervalMs.tailAgent = Cadence.intervalMs({ agentLevel: 0.02 })
    out.intervalMs.tailThought = Cadence.intervalMs({ thoughtLevel: 0.02 })
    out.intervalMs.tailPointer = Cadence.intervalMs({ pointerLevel: 0.02 })
    out.intervalMs.tailKeyboard = Cadence.intervalMs({ keyboardLevel: 0.02 })
    out.intervalMs.settled = Cadence.intervalMs({ agentLevel: 0.005, thoughtLevel: 0.005 })

    out.easing.rise = Cadence.follow(0, 1, 0.5, 0.8)
    out.easing.fall = Cadence.follow(1, 0, 0.5, 1.6)
    out.easing.holds = Cadence.follow(0.4, 0.4, 3, 1)
    out.easing.rolling = Cadence.follow(Cadence.follow(0, 1, 0.1, 0.8), 1, 0.4, 0.8)
    out.easing.single = Cadence.follow(0, 1, 0.5, 0.8)
    out.rippleRise = Cadence.rippleLevel(0, true, 0.1, 0.08, 0.62)
    out.rippleAfterTwoSeconds = Cadence.rippleLevel(1, false, 2, 0.08, 0.62)
    var flowPhase = Cadence.advancePhase(6.2, 0.1, 3.4)
    var thoughtPhase = Cadence.advancePhase(0, 0.2, 0.5)
    out.integratedPhases = { flow: flowPhase, thought: thoughtPhase,
                             next: Cadence.advancePhase(flowPhase, 0.1, 1.4) }
    out.orbitTargets = [
      Cadence.orbitSpeedTarget(0, 0, 0, 0),
      Cadence.orbitSpeedTarget(0.5, 0, 0, 0),
      Cadence.orbitSpeedTarget(0, 0, 1, 0),
      Cadence.orbitSpeedTarget(0, 0, 0, 1),
      Cadence.orbitSpeedTarget(1, 0, 0, 0)
    ]
    var poseBuffer = { yaw: 0, pitch: 0, roll: 0 }
    var pose = Cadence.poseInto(poseBuffer, 0)
    out.pose0 = { yaw: pose.yaw, pitch: pose.pitch, roll: pose.roll }
    out.poseReusesBuffer = pose === poseBuffer
    out.poseLater = Cadence.poseInto(poseBuffer, 100)
    out.pulse = [Cadence.pulse(0, 3), Cadence.pulse(1, 0)]
    console.log("PROBE " + JSON.stringify(out))
    Qt.quit()
  }
}
