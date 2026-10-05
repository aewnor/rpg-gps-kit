-- Acumulador de paso fijo: como máximo `max_steps` pasos por frame; el retraso excesivo se descarta
-- y se cuenta. Al pausar o perder el foco se vacía para no acumular pasos.
local Loop = {}
Loop.__index = Loop

function Loop.new(step, max_steps, max_dt)
  return setmetatable({ step = step, max_steps = max_steps, max_dt = max_dt or 0.1, acc = 0, dropped = 0,
                        paused = false }, Loop)
end

function Loop:advance(dt, fn, forced_steps)
  if self.paused then return 0 end
  self.acc = self.acc + (forced_steps and self.step * forced_steps or math.min(dt, self.max_dt))
  local n, limit = 0, forced_steps or self.max_steps
  while self.acc >= self.step and n < limit do
    fn(self.step)
    self.acc = self.acc - self.step
    n = n + 1
  end
  if self.acc >= self.step then
    self.dropped = self.dropped + 1
    self.acc = 0
  end
  return n
end

function Loop:pause(on)
  self.paused = on
  self.acc = 0
end

return Loop
