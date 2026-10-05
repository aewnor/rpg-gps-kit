-- Tanda de penals (Camp de futbol, Poliesportiu): 5 xuts. Primer Z fixa la direcció (el punt de mira va
-- d'un pal a l'altre), després Z fixa la força (la barra puja i baixa). El porter s'hi tira cap a un costat
-- a l'atzar: si endevina i el xut és fluix, l'atura; a tocar del pal i amb força és gol segur; massa força,
-- per sobre del travesser. Lògica en Lua pur (tests/minigames_cases.lua).
local UI = require('src.minigames.ui')

local Pen = {}
Pen.__index = Pen

Pen.SHOTS = 5
Pen.AIM_HZ = 0.55        -- passades del punt de mira per segon (anada i tornada)
Pen.POWER_HZ = 0.8
Pen.FLIGHT = 0.55        -- segons de vol de la pilota
-- zones que cobreix el porter segons cap on es tira (aim en [-1, 1])
Pen.KEEPER = { left = { -1.0, -0.2 }, center = { -0.45, 0.45 }, right = { 0.2, 1.0 } }

function Pen.new(params, rng)
  return setmetatable({ rng = rng or math.random, state = 'aim', t = 0, shot = 1, goals = 0, aim = 0, power = 0,
                        log = {}, keeper = 'center' }, Pen)
end

local function sfx(self, n) if self.sfx then self.sfx(n) end end

-- ona triangular entre -1 i 1 (punt de mira) o 0 i 1 (força)
local function tri(t, hz) local p = (t * hz) % 1; return 1 - 4 * math.abs(p - 0.5) end

-- resultat d'un xut: 'goal' | 'saved' | 'over' | 'post'
function Pen.outcome(aim, power, keeper)
  if power > 0.93 then return 'over' end
  if math.abs(aim) > 0.97 then return 'post' end
  local z = Pen.KEEPER[keeper]
  local covered = aim >= z[1] and aim <= z[2]
  if covered then
    -- a tocar del pal i fort: no hi arriba
    if math.abs(aim) > 0.75 and power > 0.55 then return 'goal' end
    if power > 0.8 and keeper ~= 'center' and math.abs(aim) > 0.5 then return 'goal' end
    return 'saved'
  end
  if power < 0.18 then return 'saved' end      -- tan fluix que el porter té temps de recuperar-se
  return 'goal'
end

function Pen:update(dt, act)
  local p = act.pressed or {}
  self.t = self.t + dt
  if p.cancel and self.state ~= 'flight' then self:finish(); return end
  if self.state == 'aim' then
    self.aim = tri(self.t + 0.25 / Pen.AIM_HZ, Pen.AIM_HZ)
    if p.confirm then self.state, self.t, self.power = 'power', 0, 0 end
  elseif self.state == 'power' then
    self.power = (tri(self.t, Pen.POWER_HZ) + 1) / 2      -- comença buida i puja
    if p.confirm then
      local r = self.rng()
      self.keeper = r < 0.36 and 'left' or (r < 0.72 and 'right' or 'center')
      self.res = Pen.outcome(self.aim, self.power, self.keeper)
      self.state, self.t = 'flight', 0
      sfx(self, 'kick')
    end
  elseif self.state == 'flight' then
    if self.t >= Pen.FLIGHT then
      self.log[#self.log + 1] = self.res
      if self.res == 'goal' then self.goals = self.goals + 1; sfx(self, 'cheer') else sfx(self, 'miss') end
      self.state, self.t = 'result', 0
    end
  elseif self.state == 'result' then
    if self.t > 1.1 or (self.t > 0.3 and p.confirm) then
      if self.shot >= Pen.SHOTS then self.state, self.t = 'end', 0; sfx(self, 'whistle')
      else self.shot = self.shot + 1; self.state, self.t = 'aim', 0 end
    end
  elseif self.state == 'end' then
    if self.t > 0.5 and p.confirm then self:finish() end
  end
end

function Pen:finish()
  self.done = true
  self.result = { goals = self.goals, shots = #self.log, perfect = self.goals == Pen.SHOTS }
end

-- ---------------------------------------------------------------- dibujo
local GX0, GX1, GY = 92, 228, 54        -- porteria (pals i travesser)

function Pen:ball_pos(k)
  local tx = (GX0 + GX1) / 2 + self.aim * (GX1 - GX0) / 2 * 0.95
  local ty = GY + 34 - self.power * 26
  if self.res == 'over' then ty = GY - 22 end
  local sx, sy = 160, 196
  return sx + (tx - sx) * k, sy + (ty - sy) * k - math.sin(k * math.pi) * 18, 5 - 2.5 * k
end

function Pen:draw(ui)
  local font = ui.font
  UI.frame('Tanda de penals', font)
  for i = 0, 7 do   -- gespa a franges
    UI.col(i % 2 == 0 and { 0.42, 0.62, 0.30 } or { 0.38, 0.57, 0.27 })
    love.graphics.rectangle('fill', 8, 28 + i * 24, 304, 24)
  end
  UI.col(UI.C.text, 0.8)
  love.graphics.rectangle('line', 60.5, 90.5, 200, 120)            -- àrea
  love.graphics.circle('fill', 160, 196, 2)                         -- punt de penal
  -- xarxa i pals
  UI.col({ 0.9, 0.9, 0.86, 0.35 })
  for x = GX0, GX1, 6 do love.graphics.line(x, GY - 16, x, GY + 36) end
  for y = GY - 16, GY + 36, 6 do love.graphics.line(GX0, y, GX1, y) end
  UI.col(UI.C.text)
  love.graphics.rectangle('fill', GX0 - 3, GY - 18, 3, 56); love.graphics.rectangle('fill', GX1, GY - 18, 3, 56)
  love.graphics.rectangle('fill', GX0 - 3, GY - 18, GX1 - GX0 + 6, 3)
  -- porter (samarreta groga), es tira al costat triat durant el vol
  local kx, ky, lean = 160, GY + 22, 0
  if self.state == 'flight' or self.state == 'result' then
    local k = math.min(1, (self.state == 'result' and 1 or self.t / Pen.FLIGHT) * 1.6)
    local dir = self.keeper == 'left' and -1 or (self.keeper == 'right' and 1 or 0)
    kx = kx + dir * 44 * k; ky = ky - (dir == 0 and 8 * k or 4 * k); lean = dir * k
  end
  UI.col({ 0.98, 0.85, 0.35 }); love.graphics.rectangle('fill', kx - 6 + lean * 4, ky - 14, 12, 12)
  UI.col({ 0.24, 0.24, 0.30 }); love.graphics.rectangle('fill', kx - 5, ky - 2, 4, 8); love.graphics.rectangle('fill', kx + 1, ky - 2, 4, 8)
  UI.col({ 0.95, 0.76, 0.63 }); love.graphics.rectangle('fill', kx - 3 + lean * 6, ky - 21, 6, 6)
  UI.col({ 0.98, 0.85, 0.35 })
  love.graphics.rectangle('fill', kx - 13 + lean * 8, ky - 16 - math.abs(lean) * 4, 7, 3)
  love.graphics.rectangle('fill', kx + 6 + lean * 8, ky - 16 - math.abs(lean) * 4, 7, 3)
  -- pilota
  local bx, by, br = 160, 196, 5
  if self.state == 'flight' then bx, by, br = self:ball_pos(math.min(1, self.t / Pen.FLIGHT))
  elseif self.state == 'result' then bx, by, br = self:ball_pos(1) end
  UI.col(UI.C.ink, 0.3); love.graphics.ellipse('fill', bx, by + br + 1, br, br * 0.4)
  UI.col(UI.C.text); love.graphics.circle('fill', bx, by, br)
  UI.col(UI.C.ink); love.graphics.rectangle('fill', math.floor(bx) - 1, math.floor(by) - 1, 2, 2)
  -- punt de mira i barra de força
  if self.state == 'aim' or self.state == 'power' then
    local ax = (GX0 + GX1) / 2 + self.aim * (GX1 - GX0) / 2 * 0.95
    UI.col(UI.C.red); love.graphics.circle('line', ax, GY + 18, 6); love.graphics.line(ax - 9, GY + 18, ax + 9, GY + 18)
    love.graphics.line(ax, GY + 9, ax, GY + 27)
  end
  if self.state == 'power' then
    UI.col(UI.C.ink); love.graphics.rectangle('fill', 276, 96, 14, 104)
    local h = 100 * self.power
    UI.col(self.power > 0.93 and UI.C.bad or (self.power > 0.55 and UI.C.gold or UI.C.good))
    love.graphics.rectangle('fill', 278, 198 - h, 10, h)
    UI.col(UI.C.text); love.graphics.line(274, 198 - 93, 292, 198 - 93)
  end
  -- marcador: un cercle per xut
  for i = 1, Pen.SHOTS do
    local r = self.log[i]
    UI.col(r == 'goal' and UI.C.good or (r and UI.C.bad or UI.C.dim))
    love.graphics.circle(r and 'fill' or 'line', 120 + i * 13, 214 - 6, 4)
  end
  if self.state == 'result' then
    local txt = ({ goal = 'GOL!', saved = 'ATURADA!', over = 'FORA!', post = 'AL PAL!' })[self.res]
    UI.big(txt, 120, font, self.res == 'goal' and UI.C.gold or UI.C.bad, self.t)
  elseif self.state == 'end' then
    UI.big(self.goals .. ' de ' .. Pen.SHOTS, 112, font, UI.C.gold, self.t)
    UI.center('Z: continuar', 150, font, UI.C.text)
  elseif self.state == 'aim' then UI.center('Z: tria cap on xutes', 160, font, UI.C.text)
  elseif self.state == 'power' then UI.center('Z: tria la força', 160, font, UI.C.text) end
  UI.help('Xut ' .. math.min(self.shot, Pen.SHOTS) .. '/' .. Pen.SHOTS .. ' · Esc: sortir', font)
end

return Pen
