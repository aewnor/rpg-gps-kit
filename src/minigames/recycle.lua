-- Reciclatge als contenidors (fase 5, missions de civisme): van sortint residus i s'han de llençar al
-- contenidor del color que toca amb ← → i Z. Si t'equivoques, t'explica on va (és per aprendre).
-- Groc: envasos · Blau: paper i cartró · Verd: vidre · Marró: orgànic · Gris: la resta.
-- Lògica en Lua pur (tests/missions_cases.lua).
local UI = require('src.minigames.ui')

local R = {}
R.__index = R

R.BINS = {
  { id = 'groc', name = 'Envasos', c = { 0.98, 0.82, 0.25 } },
  { id = 'blau', name = 'Paper', c = { 0.24, 0.44, 0.77 } },
  { id = 'verd', name = 'Vidre', c = { 0.33, 0.62, 0.30 } },
  { id = 'marro', name = 'Orgànic', c = { 0.55, 0.36, 0.20 } },
  { id = 'gris', name = 'Resta', c = { 0.52, 0.52, 0.54 } },
}
R.ITEMS = {
  { 'Ampolla de plàstic', 'groc' }, { 'Llauna de refresc', 'groc' }, { 'Brik de llet', 'groc' },
  { 'Bossa de plàstic', 'groc' }, { 'Diari vell', 'blau' }, { 'Caixa de cartró', 'blau' }, { 'Revista', 'blau' },
  { 'Pot de vidre', 'verd' }, { 'Ampolla de vidre', 'verd' }, { 'Pela de plàtan', 'marro' },
  { 'Cor de poma', 'marro' }, { 'Closques d\'ou', 'marro' }, { 'Tovalló brut', 'gris' }, { 'Bolígraf gastat', 'gris' },
}
R.ROUNDS = 8
R.PASS = 6

function R.new(params, rng)
  rng = rng or math.random
  local self = setmetatable({ state = 'play', sel = 3, i = 1, right = 0, t = 0, msg = nil, rng = rng }, R)
  -- 8 residus diferents, en ordre aleatori
  local pool = {}
  for k, it in ipairs(R.ITEMS) do pool[k] = it end
  for k = #pool, 2, -1 do local j = math.floor(rng() * k) + 1; pool[k], pool[j] = pool[j], pool[k] end
  self.items = {}
  for k = 1, R.ROUNDS do self.items[k] = pool[k] end
  return self
end

local function sfx(self, n) if self.sfx then self.sfx(n) end end

function R.bin_of(id) for i, b in ipairs(R.BINS) do if b.id == id then return i, b end end end

function R:throw(bin)
  local it = self.items[self.i]
  local ok = R.BINS[bin].id == it[2]
  if ok then
    self.right = self.right + 1
    self.msg = { 'Molt bé! ' .. it[1] .. ': ' .. R.BINS[bin].name, true }
    sfx(self, 'good')
  else
    local _, b = R.bin_of(it[2])
    self.msg = { it[1] .. ' va al contenidor ' .. b.id:gsub('marro', 'marró') .. ' (' .. b.name .. ')', false }
    sfx(self, 'miss')
  end
  self.i = self.i + 1
  self.t = 0
  if self.i > R.ROUNDS then self.state = 'end'; sfx(self, self.right >= R.PASS and 'win' or 'lose') end
  return ok
end

function R:update(dt, act)
  local p = act.pressed or {}
  self.t = self.t + dt
  if self.state == 'end' then
    if self.t > 0.6 and (p.confirm or p.cancel) then
      self.done = true
      self.result = { finished = true, right = self.right, total = R.ROUNDS, passed = self.right >= R.PASS }
    end
    return
  end
  if p.cancel then self.done = true; self.result = { finished = false }; return end
  if p.left then self.sel = (self.sel - 2) % #R.BINS + 1; sfx(self, 'talk') end
  if p.right then self.sel = self.sel % #R.BINS + 1; sfx(self, 'talk') end
  if p.confirm then self:throw(self.sel) end
end

function R:draw(ui)
  local font = ui.font
  UI.frame('Reciclem!', font)
  -- residu actual
  if self.state == 'play' then
    local it = self.items[self.i]
    UI.col({ 0.25, 0.22, 0.28 }); love.graphics.rectangle('fill', 70, 36, 180, 48, 4)
    UI.center(it[1], 44, font, UI.C.text)
    UI.center(string.format('%d / %d', self.i, R.ROUNDS), 62, font, UI.C.dim)
  else
    UI.big(string.format('%d de %d', self.right, R.ROUNDS), 44, font, self.right >= R.PASS and UI.C.gold or UI.C.text, self.t)
  end
  if self.msg then UI.center(self.msg[1], 94, font, self.msg[2] and UI.C.good or UI.C.bad) end
  -- contenidors
  for i, b in ipairs(R.BINS) do
    local x = 22 + (i - 1) * 58
    local y = 124
    if i == self.sel and self.state == 'play' then
      UI.col(UI.C.text); love.graphics.rectangle('line', x - 3.5, y - 9.5, 53, 82)
      UI.arrow('down', x + 23, y - 16, 6, UI.C.text)
    end
    UI.col(b.c); love.graphics.rectangle('fill', x, y, 46, 56, 3)
    UI.col({ b.c[1] * 0.7, b.c[2] * 0.7, b.c[3] * 0.7 }); love.graphics.rectangle('fill', x - 2, y - 4, 50, 8, 2)
    UI.col(UI.C.ink); love.graphics.rectangle('fill', x + 13, y + 10, 20, 3)
    UI.col(UI.C.text)
    love.graphics.print(b.name, math.floor(x + 23 - font:getWidth(b.name) / 2), y + 58)
  end
  if self.state == 'end' then
    UI.center(self.right >= R.PASS and 'Ets un crack del reciclatge!' or 'Torna-ho a provar: tu pots!', 104, font, UI.C.text)
  end
  UI.help(self.state == 'end' and 'Z: continuar' or 'Fletxes: triar · Z: llençar · Esc: sortir', font)
end

return R
