.pragma library

function targetFps(state) {
  if (state.pointerOver || state.userActive || state.thoughtActive
      || Number(state.agentLevel || 0) > 0.01 || Number(state.thoughtLevel || 0) > 0.01
      || Number(state.pointerLevel || 0) > 0.01 || Number(state.keyboardLevel || 0) > 0.01)
    return 60
  return 30
}

function newScheduler() {
  return { accumulator: 0, pending: 0 }
}

function tick(scheduler, frameDelta, state) {
  var elapsed = Math.max(0, Number(frameDelta) || 0)
  scheduler.accumulator += elapsed
  scheduler.pending += elapsed
  var interval = 1 / targetFps(state)
  if (scheduler.accumulator < interval) return 0
  var step = scheduler.pending
  scheduler.pending = 0
  scheduler.accumulator -= interval
  return step
}

function follow(current, target, delta, timeConstant) {
  if (timeConstant <= 0) return target
  return current + (target - current) * (1 - Math.exp(-Math.max(0, delta) / timeConstant))
}

function pose(time) {
  return {
    yaw: time * 0.045,
    pitch: 0.20 + 0.22 * Math.sin(time * (Math.PI * 2 / 47)),
    roll: 0.16 * Math.sin(time * (Math.PI * 2 / 73) + 1.1)
  }
}

function pulse(level, time) {
  // Keep the agent's whole-sphere breath clearly visible at native scale.
  // This is a single uniform scalar; it adds no per-node or per-frame work.
  return level * (0.70 + (Math.sin(time * 1.04) + 1) * 0.35)
}
