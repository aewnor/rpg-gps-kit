-- Entrenament al ritme (Gimnàs): les fletxes baixen per quatre carrils i s'han de prémer quan toquen la
-- línia. Perfecte (±0,07 s) = 2 punts, bé (±0,16 s) = 1. Amb un 70 % o més, la sessió compta: puja
-- l'estadística de l'aparell (força, resistència o agilitat) un cop al dia. Finestres generoses: per a
-- infants de 6 a 10 anys. Lògica en Lua pur (tests/minigames_cases.lua).
local UI = require('src.minigames.ui')

local Rhy = {}
Rhy.__index = Rhy

Rhy.LANES = { 'left', 'down', 'up', 'right' }
Rhy.COLORS = { { 0.95, 0.45, 0.35 }, { 0.33, 0.78, 0.76 }, { 0.55, 0.85, 0.40 }, { 0.98, 0.80, 0.30 } }
Rhy.PERFECT, Rhy.GOOD = 0.07, 0.16
Rhy.LEAD = 1.6             -- segons que es veu una fletxa abans d'arribar
Rhy.PASS = 0.7             -- percentatge per aprovar
Rhy.HIT_Y, Rhy.TOP_Y = 186, 40
-- patrons per aparell (beats de 0,5 negra): 0 = silenci, 1..4 = carril
local PATTERNS = {
  strength = { 1, 0, 4, 0, 1, 0, 4, 0, 2, 0, 3, 0, 2, 3, 0, 0, 1, 0, 4, 0, 1, 4, 0, 0, 2, 0, 3, 0, 1, 2, 3, 4 },
  resistance = { 2, 3, 2, 3, 1, 0, 4, 0, 2, 3, 2, 3, 4, 0, 1, 0, 1, 2, 3, 4, 0, 0, 4, 3, 2, 1, 0, 0, 2, 3, 2, 3 },
  agility = { 1, 2, 1, 2, 3, 4, 3, 4, 1, 0, 2, 0, 3, 0, 4, 0, 4, 3, 2, 1, 0, 1, 0, 4, 1, 4, 1, 4, 2, 3, 2, 3 },
}
Rhy.BPM = { strength = 96, resistance = 104, agility = 112 }

function Rhy.new(params, rng)
  local stat = params.stat or 'strength'
  local self = setmetatable({ stat = stat, label = params.label or 'Entrenament', state = 'ready', t = 0, song_t = -1.5,
                              notes = {}, points = 0, combo = 0, best_combo = 0, judge = nil, judge_t = 0,
                              lane_flash = { 0, 0, 0, 0 }, rep = 0, already = params.already }, Rhy)
  local beat = 60 / Rhy.BPM[stat] / 2      -- corxeres
  for i, lane in ipairs(PATTERNS[stat]) do
    if lane > 0 then self.notes[#self.notes + 1] = { lane = lane, time = 1.0 + (i - 1) * beat } end
  end
  self.beat = beat
  self.length = 1.0 + #PATTERNS[stat] * beat + 1.0
  self.max_points = #self.notes * 2
  return self
end

local function sfx(self, n) if self.sfx then self.sfx(n) end end

-- prémer el carril `lane` en l'instant `now` (segons de cançó): retorna 'perfect' | 'good' | nil
function Rhy:hit(lane, now)
  local best, bd
  for _, n in ipairs(self.notes) do
    if n.lane == lane and not n.done then
      local d = math.abs(n.time - now)
      if d <= Rhy.GOOD and (not bd or d < bd) then best, bd = n, d end
    end
  end
  if not best then return nil end
  best.done = true
  local q = bd <= Rhy.PERFECT and 'perfect' or 'good'
  best.result = q
  self.points = self.points + (q == 'perfect' and 2 or 1)
  self.combo = self.combo + 1
  self.best_combo = math.max(self.best_combo, self.combo)
  self.rep = self.rep + 1
  return q
end

function Rhy:update(dt, act)
  local p = act.pressed or {}
  self.t = self.t + dt
  if p.cancel and self.state ~= 'end' then self.done = true; self.result = { finished = false }; return end
  if self.state == 'ready' then
    if p.confirm or self.t > 2 then self.state = 'play'; self.song_t = -0.5 end
    return
  end
  if self.state == 'end' then
    if self.t > 0.5 and p.confirm then
      self.done = true
      self.result = { finished = true, pct = self:pct(), stat = self.stat, passed = self:pct() >= Rhy.PASS,
                      best_combo = self.best_combo }
    end
    return
  end
  local prev = self.song_t
  self.song_t = self.song_t + dt
  -- metrònom a cada negra
  if self.song_t >= 0 and math.floor(prev / (self.beat * 2)) ~= math.floor(self.song_t / (self.beat * 2)) then
    sfx(self, 'beat')
  end
  for i, lane in ipairs(Rhy.LANES) do
    if p[lane] then
      self.lane_flash[i] = 0.12
      local q = self:hit(i, self.song_t)
      if q then self.judge, self.judge_t = q, 0.5; sfx(self, q) end
    end
    self.lane_flash[i] = math.max(0, self.lane_flash[i] - dt)
  end
  -- les que han passat de llarg: fallades
  for _, n in ipairs(self.notes) do
    if not n.done and self.song_t - n.time > Rhy.GOOD then
      n.done, n.result = true, 'miss'
      self.combo = 0
      self.judge, self.judge_t = 'miss', 0.5
      sfx(self, 'miss')
    end
  end
  self.judge_t = math.max(0, self.judge_t - dt)
  if self.song_t >= self.length then
    self.state, self.t = 'end', 0
    sfx(self, self:pct() >= Rhy.PASS and 'win' or 'lose')
  end
end

function Rhy:pct() return self.max_points > 0 and self.points / self.max_points or 0 end

-- ---------------------------------------------------------------- dibujo
local LX0, LW = 112, 30

function Rhy:draw(ui)
  local font = ui.font
  UI.frame(self.label, font)
  -- carrils
  for i, lane in ipairs(Rhy.LANES) do
    local x = LX0 + (i - 1) * LW
    UI.col(UI.C.ink, 0.6); love.graphics.rectangle('fill', x + 1, Rhy.TOP_Y - 12, LW - 2, Rhy.HIT_Y - Rhy.TOP_Y + 26)
    local fl = self.lane_flash[i] > 0
    UI.arrow(lane, x + LW / 2, Rhy.HIT_Y, 8, fl and UI.C.text or { 0.45, 0.42, 0.48 })
  end
  UI.col(UI.C.text, 0.5); love.graphics.rectangle('fill', LX0, Rhy.HIT_Y - 1, LW * 4, 2)
  -- notes
  for _, n in ipairs(self.notes) do
    if not n.done or (n.result ~= 'miss' and self.song_t - n.time < 0.15) then
      local k = (n.time - self.song_t) / Rhy.LEAD
      if k <= 1.05 and k >= -0.2 then
        local y = Rhy.HIT_Y - k * (Rhy.HIT_Y - Rhy.TOP_Y)
        local c = Rhy.COLORS[n.lane]
        if n.done then c = UI.C.text end
        UI.arrow(Rhy.LANES[n.lane], LX0 + (n.lane - 1) * LW + LW / 2, y, n.done and 10 or 7, c)
      end
    end
  end
  -- personatge que fa l'exercici: a cada encert, una repetició
  local up = self.rep % 2 == 1
  local ax, ay = 56, 150
  UI.col({ 0.36, 0.30, 0.40 }); love.graphics.rectangle('fill', ax - 22, ay + 20, 44, 4)
  UI.col({ 0.24, 0.44, 0.77 }); love.graphics.rectangle('fill', ax - 6, ay - 4, 12, 14)
  UI.col({ 0.95, 0.76, 0.63 }); love.graphics.rectangle('fill', ax - 4, ay - 13, 8, 8)
  UI.col({ 0.24, 0.24, 0.30 }); love.graphics.rectangle('fill', ax - 5, ay + 10, 4, 10); love.graphics.rectangle('fill', ax + 1, ay + 10, 4, 10)
  if self.stat == 'strength' then
    local by = up and ay - 22 or ay - 8
    UI.col({ 0.95, 0.76, 0.63 }); love.graphics.rectangle('fill', ax - 10, by + 2, 3, ay - by); love.graphics.rectangle('fill', ax + 7, by + 2, 3, ay - by)
    UI.col({ 0.65, 0.63, 0.60 }); love.graphics.rectangle('fill', ax - 20, by, 40, 2)
    UI.col(UI.C.ink); love.graphics.rectangle('fill', ax - 22, by - 4, 5, 10); love.graphics.rectangle('fill', ax + 17, by - 4, 5, 10)
  else
    UI.col({ 0.95, 0.76, 0.63 })
    local sw = up and 3 or -3
    love.graphics.rectangle('fill', ax - 9, ay - 2 + sw, 3, 9); love.graphics.rectangle('fill', ax + 6, ay - 2 - sw, 3, 9)
  end
  -- puntuació
  UI.col(UI.C.text); love.graphics.print(string.format('%d%%', math.floor(self:pct() * 100 + 0.5)), 246, 40)
  UI.col(UI.C.dim); love.graphics.print('Combo ' .. self.combo, 246, 58)
  UI.col(UI.C.ink); love.graphics.rectangle('fill', 246, 80, 60, 6)
  UI.col(self:pct() >= Rhy.PASS and UI.C.good or UI.C.gold); love.graphics.rectangle('fill', 246, 80, 60 * self:pct(), 6)
  UI.col(UI.C.text); love.graphics.rectangle('fill', 246 + 60 * Rhy.PASS, 78, 1, 10)
  if self.judge_t > 0 then
    local txt = ({ perfect = 'Perfecte!', good = 'Bé!', miss = 'Ui!' })[self.judge]
    UI.col(self.judge == 'miss' and UI.C.bad or (self.judge == 'perfect' and UI.C.gold or UI.C.good))
    love.graphics.print(txt, 246, 98)
  end
  if self.state == 'ready' then
    UI.big('Preparats?', 92, font, UI.C.gold, self.t)
    if self.already then UI.center('Avui ja has pujat aquesta estadística', 124, font, UI.C.dim) end
  elseif self.state == 'end' then
    local ok = self:pct() >= Rhy.PASS
    UI.big(string.format('%d%%', math.floor(self:pct() * 100 + 0.5)), 92, font, ok and UI.C.gold or UI.C.text, self.t)
    UI.center(ok and 'Molt bé! Sessió completada' or 'Cal un 70%. Torna-ho a provar!', 126, font, UI.C.text)
    UI.center('Z: continuar', 144, font, UI.C.text)
  end
  UI.help('Fletxes al ritme · Esc: sortir', font)
end

return Rhy
