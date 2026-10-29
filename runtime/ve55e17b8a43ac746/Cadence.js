.pragma library

function intervalMs(state) {
  if (state.userActive || state.thoughtActive
      || Number(state.agentLevel || 0) > 0.01 || Number(state.thoughtLevel || 0) > 0.01
      || Number(state.pointerLevel || 0) > 0.01 || Number(state.keyboardLevel || 0) > 0.01)
    return 17
  return 33
}

function follow(current, target, delta, timeConstant) {
  if (timeConstant <= 0) return target
  return current + (target - current) * (1 - Math.exp(-Math.max(0, delta) / timeConstant))
}

function rippleLevel(current, active, delta, riseSeconds, decaySeconds) {
  return follow(current, active ? 1 : 0, delta, active ? riseSeconds : decaySeconds)
}

function activityLevel(agentLevel, thoughtLevel, pointerLevel, keyboardLevel) {
  return Math.max(0, Math.min(1, Math.max(
    Number(agentLevel || 0),
    Number(thoughtLevel || 0),
    Number(pointerLevel || 0),
    Number(keyboardLevel || 0)
  )))
}

function orbitSpeedTarget(agentLevel, thoughtLevel, pointerLevel, keyboardLevel) {
  // Agent work drives a clearly stronger orbit. Pointer and keyboard activity
  // only nudge it, so ordinary input never makes the whole sphere snap faster.
  return Math.min(1, 0.55
    + 0.45 * Math.max(0, Math.min(1, Number(agentLevel || 0)))
    + 0.03 * Math.max(0, Math.min(1, Number(thoughtLevel || 0)))
    + 0.06 * Math.max(0, Math.min(1, Number(pointerLevel || 0)))
    + 0.06 * Math.max(0, Math.min(1, Number(keyboardLevel || 0))) )
}

function advancePhase(phase, delta, angularSpeed) {
  var tau = Math.PI * 2
  var next = (phase + Math.max(0, delta) * angularSpeed) % tau
  return next < 0 ? next + tau : next
}

function poseInto(out, time) {
  var tau = Math.PI * 2
  // A bounded, non-repeating drift keeps the image-space sphere round for
  // the whole session without periodically repainting the expensive Canvas.
  // Mutate the caller's object so the hot frame path creates no pose objects.
  out.yaw = 0.18 * Math.sin(time * tau / 47) + 0.06 * Math.sin(time * tau / 83 + 0.7)
  out.pitch = 0.12 + 0.12 * Math.sin(time * tau / 53)
  out.roll = 0.10 * Math.sin(time * tau / 73 + 1.1)
  return out
}

function pose(time) {
  return poseInto({ yaw: 0, pitch: 0, roll: 0 }, time)
}

function pulse(level, time) {
  return level * (0.55 + (Math.sin(time * 1.04) + 1) * 0.075)
}
