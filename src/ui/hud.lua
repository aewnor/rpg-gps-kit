-- HUD: vida, energía, avisos breves y cartel de lugar.
local Hud = {}
Hud.__index = Hud

function Hud.new(font, icons)
  return setmetatable({ font = font, icons = icons, toasts = {}, banner = nil }, Hud)
end

-- avisos: el mismo texto no se apila (se renueva) y como mucho 3 a la vez; los largos se parten en líneas
-- speak = true: també en veu alta (avisos de missió)
function Hud:toast(text, dur, speak)
  -- veu: tots els avisos (qui encara no llegeix també se n'assabenta), menys si l'opció «llegir-ho tot» és apagada;
  -- el mateix avís no es repeteix en 6 s
  local Tts = require('src.tts')
  local all = Tts.settings and Tts.settings.tts and Tts.settings.tts.all ~= false
  if speak or all then
    self.said = self.said or {}
    local now = love.timer and love.timer.getTime() or 0
    if not self.said[text] or now - self.said[text] > 6 then self.said[text] = now; Tts.say(text, false) end
  end
  for _, t in ipairs(self.toasts) do
    if t.text == text then t.t = math.max(t.t, dur or 2.5); return end
  end
  local _, lines = self.font:getWrap(text, 288)
  table.insert(self.toasts, { text = text, lines = lines, t = dur or 2.5, age = 0 })
  while #self.toasts > 3 do table.remove(self.toasts, 1) end
end

-- cartell del carrer o del lloc on entres: només es mostra (la veu llegeix els noms quan llegeixes un cartell)
function Hud:place(label)
  self.banner = { text = label, t = 2.2 }
end

function Hud:update(dt)
  for i = #self.toasts, 1, -1 do
    self.toasts[i].age = (self.toasts[i].age or 0) + dt
    self.toasts[i].t = self.toasts[i].t - dt
    if self.toasts[i].t <= 0 then table.remove(self.toasts, i) end
  end
  if self.banner then
    self.banner.t = self.banner.t - dt
    if self.banner.t <= 0 then self.banner = nil end
  end
end

-- rellotge: just sota el panell de dalt a l'esquerra (Hud:draw en desa la posició)
function Hud:clock(text)
  local w = self.font:getWidth(text) + 6
  local y = self.clock_y or 20
  love.graphics.setColor(0.12, 0.10, 0.14, 0.7)
  love.graphics.rectangle('fill', 3, y, w, 15)
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.print(text, 6, y - 1)
  love.graphics.setColor(1, 1, 1)
end

-- barra amb text a la dreta («5/6»): x, y, amplada, fracció, color
local function bar(self, x, y, w, f, col, text)
  love.graphics.setColor(0.25, 0.22, 0.28)
  love.graphics.rectangle('fill', x, y + 5, w, 6)
  love.graphics.setColor(col[1], col[2], col[3])
  love.graphics.rectangle('fill', x, y + 5, math.floor(w * math.max(0, math.min(1, f)) + 0.5), 6)
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.rectangle('fill', x, y + 5, math.floor(w * math.max(0, math.min(1, f)) + 0.5), 1)
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.print(text, x + w + 4, y - 1)
  return x + w + 4 + self.font:getWidth(text)
end

-- icona d'objecte dins d'un quadret de 14 px (null: quadret buit)
local function slot(x, y, im)
  love.graphics.setColor(0.25, 0.22, 0.28, 0.9)
  love.graphics.rectangle('fill', x, y, 14, 14, 2)
  love.graphics.setColor(1, 1, 1)
  if im then
    local iw, ih = im:getDimensions()
    local k = math.min(12 / iw, 12 / ih, 1)
    love.graphics.draw(im, math.floor(x + 7 - iw * k / 2), math.floor(y + 7 - ih * k / 2), 0, k, k)
  end
end

-- panell de dalt a l'esquerra (2026-10-05): vida (cors + «5/6»), màgia (barra + «12/20»), nivell amb XP i monedes,
-- i què portes: arma, mà esquerra (escut o bastó) i l'encanteri triat. L'amplada s'ajusta al text (lletra
-- majúscula inclosa) i res surt del recuadre. equip = { weapon = imatge, left = imatge, spell = nom } o nil.
function Hud:draw(state, player, show_stamina, show_mp, equip)
  local font = self.font
  local rows = {}
  local x0, y = 4, 3
  -- amplada: la fila més llarga
  local hearts = math.ceil(state.max_hp / 2)
  local hp_text = math.max(0, state.hp) .. '/' .. state.max_hp
  local w1 = hearts * 9 + 4 + font:getWidth(hp_text)
  local mp_text = show_mp and state.max_mp and (math.floor(state.mp or 0) .. '/' .. state.max_mp) or nil
  local w2 = mp_text and (10 + 40 + 4 + font:getWidth(mp_text)) or 0
  local lv = state.char_level and ('Nv' .. state.char_level) or nil
  local w3 = lv and (font:getWidth(lv) + 3 + 26 + 6 + 8 + font:getWidth(tostring(state.coins or 0))) or 0
  local spell = equip and equip.spell
  local w4 = equip and (16 + 16 + (spell and (4 + font:getWidth(spell)) or 0)) or 0
  local W = math.max(w1, w2, w3, w4) + 6
  local H = 15 + (show_stamina and 4 or 0) + (mp_text and 15 or 0) + (lv and 15 or 0) + (equip and 17 or 0) + 2
  self.panel_w = x0 + W
  love.graphics.setColor(0.12, 0.10, 0.14, 0.72)
  love.graphics.rectangle('fill', x0 - 2, y - 1, W + 2, H, 3)
  love.graphics.setColor(1, 1, 1)
  -- vida: cors (2 punts per cor; amb poca vida l'últim batega) i el número
  local low = state.hp > 0 and state.hp <= 2
  for i = 1, hearts do
    local hp = state.hp - (i - 1) * 2
    local icon = hp >= 1 and self.icons.heart_full or self.icons.heart_empty
    local beat = not require('src.motion').reduced and low and hp >= 1 and hp <= 2 and math.floor(love.timer.getTime() * 4) % 2 == 0
    love.graphics.draw(icon, x0 + (i - 1) * 9, y + (beat and 3 or 4))
    if hp == 1 then -- mig cor: la meitat dreta buida
      love.graphics.setColor(0.7, 0.65, 0.56)
      love.graphics.rectangle('fill', x0 + (i - 1) * 9 + 4, y + (beat and 4 or 5), 3, 5)
      love.graphics.setColor(1, 1, 1)
    end
  end
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.print(hp_text, x0 + hearts * 9 + 3, y - 1)
  y = y + 15
  if show_stamina then   -- energia de l'escut: barreta fina sota els cors
    local f = player.stamina / player.max_stamina
    love.graphics.setColor(0.25, 0.22, 0.28)
    love.graphics.rectangle('fill', x0, y - 1, 42, 3)
    if player.block_exhausted then love.graphics.setColor(0.79, 0.25, 0.23) else love.graphics.setColor(0.33, 0.78, 0.76) end
    love.graphics.rectangle('fill', x0, y - 1, 42 * f, 3)
    y = y + 4
  end
  if mp_text then        -- màgia: estrella blava, barra i número
    love.graphics.setColor(0.42, 0.55, 0.95)
    love.graphics.circle('fill', x0 + 4, y + 8, 4)
    love.graphics.setColor(0.8, 0.88, 1)
    love.graphics.circle('fill', x0 + 3, y + 7, 1.5)
    bar(self, x0 + 10, y, 40, (state.mp or 0) / math.max(1, state.max_mp), { 0.42, 0.55, 0.95 }, mp_text)
    y = y + 15
  end
  if lv then             -- nivell, barra d'experiència i monedes
    love.graphics.setColor(0.96, 0.94, 0.89)
    love.graphics.print(lv, x0, y - 1)
    local bx = x0 + font:getWidth(lv) + 3
    love.graphics.setColor(0.25, 0.22, 0.28)
    love.graphics.rectangle('fill', bx, y + 6, 26, 4)
    love.graphics.setColor(0.89, 0.72, 0.40)
    love.graphics.rectangle('fill', bx, y + 6, 26 * math.min(1, (state.xp or 0) / math.max(1, state.next_xp or 1)), 4)
    local cx = bx + 32
    love.graphics.setColor(0.89, 0.72, 0.40); love.graphics.circle('fill', cx + 3, y + 8, 3)
    love.graphics.setColor(0.75, 0.55, 0.29); love.graphics.circle('line', cx + 3, y + 8, 3)
    love.graphics.setColor(0.96, 0.94, 0.89)
    love.graphics.print(tostring(state.coins or 0), cx + 8, y - 1)
    y = y + 15
  end
  if equip then          -- què portes a cada mà i l'encanteri
    slot(x0, y + 1, equip.weapon)
    slot(x0 + 16, y + 1, equip.left)
    if spell then
      love.graphics.setColor(0.75, 0.82, 1)
      love.graphics.print(spell, x0 + 34, y)
    end
    y = y + 17
  end
  love.graphics.setColor(1, 1, 1)
  self.clock_y = y + 2
  if self.banner then
    local a = math.min(1, self.banner.t * 2)
    local w = self.font:getWidth(self.banner.text) + 16
    love.graphics.setColor(0.12, 0.10, 0.14, 0.85 * a)
    love.graphics.rectangle('fill', 320 - w - 4, 4, w, 20)
    love.graphics.setColor(0.96, 0.94, 0.89, a)
    love.graphics.print(self.banner.text, 320 - w + 4, 6)
    love.graphics.setColor(1, 1, 1)
  end
  -- avisos: a la dreta del panell (no el tapen), partits a l'amplada que queda
  local left = (self.panel_w or 0) + 4
  local avail = 318 - left
  local mid = left + avail / 2
  local y = 26
  for _, t in ipairs(self.toasts) do
    local a = math.min(1, t.t / .18, (t.age or 1) / .12)
    local _, lines = self.font:getWrap(t.text, avail - 12)
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, self.font:getWidth(l)) end
    w = math.min(avail, w + 12)
    local h = #lines * 16 + 4
    love.graphics.setColor(0.33, 0.24, 0.13, 0.9 * a)
    love.graphics.rectangle('fill', math.floor(mid - w / 2), y, w, h)
    love.graphics.setColor(1, 0.96, 0.85, a)
    for i, l in ipairs(lines) do
      love.graphics.print(l, math.floor(mid - self.font:getWidth(l) / 2), y + 2 + (i - 1) * 16)
    end
    love.graphics.setColor(1, 1, 1)
    y = y + h + 2
  end
end

-- barra de vida de l'enemic final (a baix de tot)
function Hud:boss_bar(boss)
  local w = 180
  local x, y = 24, 222   -- a l'esquerra: la brúixola de la missió és a baix a la dreta
  love.graphics.setColor(0.12, 0.10, 0.14, 0.85)
  love.graphics.rectangle('fill', x - 2, y - 14, w + 4, 20)
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.print(boss.kind.name, x + 2, y - 15)
  love.graphics.setColor(0.3, 0.12, 0.12)
  love.graphics.rectangle('fill', x, y + 1, w, 4)
  love.graphics.setColor(boss:enraged() and 0.95 or 0.79, boss:enraged() and 0.45 or 0.25, 0.2)
  love.graphics.rectangle('fill', x, y + 1, w * boss.hp / boss.max_hp, 4)
  love.graphics.setColor(1, 1, 1)
end

return Hud
