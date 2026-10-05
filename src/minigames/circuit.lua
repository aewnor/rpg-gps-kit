-- Circuit d'agilitat (Poliesportiu): baixes per una pista amb la bici o el patinet i has de passar entre
-- els parells de cons (portes) amb les fletxes ← →. Tocar un con: frenada i +2 s; saltar-se una porta: +3 s.
-- Es juga contra el rellotge (temps de referència = PAR). Lògica en Lua pur (tests/minigames_cases.lua).
local UI = require('src.minigames.ui')

local Circ = {}
Circ.__index = Circ

Circ.GATES = 14
Circ.SPACING = 72          -- px entre portes
Circ.HALF = 17             -- mitja obertura de la porta (px)
Circ.TRACK = 64            -- mitja amplada de la pista (px)
Circ.STEER = 120           -- px/s de lateral
Circ.SPEED = { bici = 110, patinete = 125 }
Circ.PAR_EXTRA = 1.5       -- segons de marge sobre el temps ideal

function Circ.new(params, rng)
  rng = rng or math.random
  local self = setmetatable({ rng = rng, state = 'ready', t = 0, x = 0, dist = 0, time = 0, penalty = 0, slow = 0,
                              passed = 0, missed = 0, bumps = 0, gates = {}, vehicle = params.vehicle or 'bici',
                              flash = 0 }, Circ)
  -- portes amb un recorregut suau (cada porta com a molt 34 px de la de abans)
  local gx = 0
  for i = 1, Circ.GATES do
    gx = math.max(-Circ.TRACK + Circ.HALF + 4, math.min(Circ.TRACK - Circ.HALF - 4, gx + (rng() * 2 - 1) * 34))
    self.gates[i] = { x = gx, y = 140 + i * Circ.SPACING, state = nil }
  end
  self.finish_y = 140 + (Circ.GATES + 1) * Circ.SPACING
  self.speed = Circ.SPEED[self.vehicle] or Circ.SPEED.bici
  self.par = (self.finish_y) / self.speed + Circ.PAR_EXTRA
  return self
end

local function sfx(self, n) if self.sfx then self.sfx(n) end end

function Circ:update(dt, act)
  local p = act.pressed or {}
  self.t = self.t + dt
  if p.cancel and self.state ~= 'end' then self.done = true; self.result = { finished = false }; return end
  if self.state == 'ready' then
    if p.confirm or self.t > 2.5 then self.state, self.t = 'run', 0; sfx(self, 'whistle') end
    return
  end
  if self.state == 'end' then
    if self.t > 0.5 and p.confirm then
      self.done = true
      self.result = { finished = true, time = self.total, passed = self.passed, missed = self.missed, bumps = self.bumps,
                      perfect = self.missed == 0 and self.bumps == 0, par = self.par, under_par = self.total <= self.par }
    end
    return
  end
  -- en marxa
  self.time = self.time + dt
  self.slow = math.max(0, self.slow - dt)
  self.flash = math.max(0, self.flash - dt)
  local steer = (act.right and 1 or 0) - (act.left and 1 or 0)
  self.x = math.max(-Circ.TRACK, math.min(Circ.TRACK, self.x + steer * Circ.STEER * dt))
  local v = self.speed * (self.slow > 0 and 0.4 or 1)
  local before = self.dist
  self.dist = self.dist + v * dt
  for _, g in ipairs(self.gates) do
    if not g.state and before < g.y and self.dist >= g.y then
      local d = math.abs(self.x - g.x)
      if d < Circ.HALF - 3 then
        g.state = 'ok'; self.passed = self.passed + 1; sfx(self, 'good')
      elseif d < Circ.HALF + 4 then     -- con!
        g.state = 'bump'; self.bumps = self.bumps + 1; self.penalty = self.penalty + 2; self.slow = 0.6
        self.flash = 0.3; sfx(self, 'miss')
      else
        g.state = 'missed'; self.missed = self.missed + 1; self.penalty = self.penalty + 3; sfx(self, 'miss')
      end
    end
  end
  if self.dist >= self.finish_y then
    self.total = self.time + self.penalty
    self.state, self.t = 'end', 0
    sfx(self, self.total <= self.par and 'win' or 'stop')
  end
end

function Circ:draw(ui)
  local font = ui.font
  UI.frame('Circuit d\'agilitat', font)
  local cx = 160
  local py = 176              -- el jugador, fix a la pantalla; la pista baixa
  -- pista
  UI.col({ 0.42, 0.62, 0.30 }); love.graphics.rectangle('fill', 8, 28, 304, 186)
  UI.col({ 0.62, 0.42, 0.30 }); love.graphics.rectangle('fill', cx - Circ.TRACK - 10, 28, (Circ.TRACK + 10) * 2, 186)
  UI.col(UI.C.text, 0.9)
  love.graphics.rectangle('fill', cx - Circ.TRACK - 12, 28, 2, 186); love.graphics.rectangle('fill', cx + Circ.TRACK + 10, 28, 2, 186)
  love.graphics.setScissor(8, 28, 304, 186)
  -- línia de meta
  local fy = py - (self.finish_y - self.dist)
  if fy > 20 and fy < 220 then
    for i = 0, 15 do
      UI.col(i % 2 == 0 and UI.C.ink or UI.C.text)
      love.graphics.rectangle('fill', cx - Circ.TRACK - 10 + i * 9.25, fy - 3, 9.25, 6)
    end
  end
  -- portes (cons)
  for _, g in ipairs(self.gates) do
    local gy = py - (g.y - self.dist)
    if gy > 10 and gy < 240 then
      for _, side in ipairs({ -1, 1 }) do
        local x = cx + g.x + side * Circ.HALF
        UI.col(g.state == 'bump' and { 0.6, 0.6, 0.6 } or { 0.96, 0.45, 0.2 })
        love.graphics.polygon('fill', x - 4, gy + 3, x + 4, gy + 3, x, gy - 7)
        UI.col(UI.C.text); love.graphics.rectangle('fill', x - 2, gy - 3, 4, 2)
      end
      if g.state == 'ok' then UI.col(UI.C.good, 0.5); love.graphics.rectangle('fill', cx + g.x - Circ.HALF + 5, gy - 1, Circ.HALF * 2 - 10, 2) end
    end
  end
  love.graphics.setScissor()
  -- jugador d'esquena (fila «amunt» de la fulla del vehicle)
  local sp = ui.sprites
  local sh = self.vehicle == 'patinete' and sp.player_vehicles and sp.player_vehicles.patinete or
      { img = sp.player_bike, quads = sp.player_bike_quads }
  if sh and sh.img then
    local f = self.state == 'run' and math.floor(self.dist / 10) % 2 or 0
    if self.flash > 0 and math.floor(self.flash * 20) % 2 == 0 then love.graphics.setColor(1, 0.6, 0.6) else love.graphics.setColor(1, 1, 1) end
    love.graphics.draw(sh.img, sh.quads[1 * 2 + f + 1], math.floor(cx + self.x - 16), py - 28)
  end
  -- marcador
  UI.col(UI.C.ink, 0.8); love.graphics.rectangle('fill', 12, 30, 96, 34)
  UI.col(UI.C.text); love.graphics.print(string.format('%.1f s', self.time + self.penalty), 18, 30)
  UI.col(UI.C.dim); love.graphics.print(string.format('Rècord: %.1f', self.par), 18, 46)
  if self.state == 'ready' then UI.big('Preparats...', 100, font, UI.C.gold, self.t)
  elseif self.state == 'end' then
    UI.big(string.format('%.1f s', self.total), 92, font, self.total <= self.par and UI.C.gold or UI.C.text, self.t)
    UI.center(string.format('Portes: %d/%d · Cons tocats: %d', self.passed, Circ.GATES, self.bumps), 128, font, UI.C.text)
    UI.center('Z: continuar', 146, font, UI.C.text)
  end
  UI.help('Fletxes: girar · Esc: sortir', font)
end

return Circ
