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

function Hud:place(label)
  self.banner = { text = label, t = 2.2 }
  local Tts = require('src.tts')
  if Tts.settings and Tts.settings.tts and Tts.settings.tts.all ~= false then Tts.say(label, false) end
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

-- reloj del ciclo día/noche (arriba a la izquierda, bajo los corazones)
function Hud:clock(text)
  local w = self.font:getWidth(text) + 6
  love.graphics.setColor(0.12, 0.10, 0.14, 0.7)
  love.graphics.rectangle('fill', 3, 20, w, 15)
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.print(text, 6, 19)
  love.graphics.setColor(1, 1, 1)
end

function Hud:draw(state, player, show_stamina, show_mp)
  -- corazones: 2 puntos de vida por corazón; con poca vida el último late
  local low = state.hp > 0 and state.hp <= 2
  for i = 1, math.ceil(state.max_hp / 2) do
    local hp = state.hp - (i - 1) * 2
    local icon = hp >= 1 and self.icons.heart_full or self.icons.heart_empty
    local beat = not require('src.motion').reduced and low and hp >= 1 and hp <= 2 and math.floor(love.timer.getTime() * 4) % 2 == 0
    love.graphics.draw(icon, 4 + (i - 1) * 9, beat and 3 or 4)
    if hp == 1 then -- medio corazón: la mitad derecha vacía
      love.graphics.setColor(0.7, 0.65, 0.56)
      love.graphics.rectangle('fill', 4 + (i - 1) * 9 + 4, beat and 4 or 5, 3, 5)
      love.graphics.setColor(1, 1, 1)
    end
  end
  if show_stamina then
    local w = 40
    love.graphics.setColor(0.12, 0.10, 0.14)
    love.graphics.rectangle('fill', 4, 14, w + 2, 4)
    local f = player.stamina / player.max_stamina
    if player.block_exhausted then love.graphics.setColor(0.79, 0.25, 0.23)
    else love.graphics.setColor(0.33, 0.78, 0.76) end
    love.graphics.rectangle('fill', 5, 15, w * f, 2)
    love.graphics.setColor(1, 1, 1)
  end
  if show_mp and state.max_mp then   -- punts de màgia (fase 6): barra blava sota l'energia
    local w = 40
    love.graphics.setColor(0.12, 0.10, 0.14)
    love.graphics.rectangle('fill', 46, 14, w + 2, 4)
    love.graphics.setColor(0.42, 0.55, 0.95)
    love.graphics.rectangle('fill', 47, 15, w * math.min(1, (state.mp or 0) / math.max(1, state.max_mp)), 2)
    love.graphics.setColor(1, 1, 1)
  end
  -- nivel, barra de experiencia y monedas (src/systems/rpg.lua)
  if state.char_level then
    local y = 38
    love.graphics.setColor(0.12, 0.10, 0.14, 0.7)
    love.graphics.rectangle('fill', 3, y, 84, 15)
    love.graphics.setColor(0.96, 0.94, 0.89)
    love.graphics.print('Nv' .. state.char_level, 6, y - 1)
    local bx = 6 + self.font:getWidth('Nv' .. state.char_level) + 3
    love.graphics.setColor(0.25, 0.22, 0.28)
    love.graphics.rectangle('fill', bx, y + 6, 26, 4)
    love.graphics.setColor(0.89, 0.72, 0.40)
    love.graphics.rectangle('fill', bx, y + 6, 26 * math.min(1, state.xp / math.max(1, state.next_xp)), 4)
    local cx = bx + 32
    love.graphics.setColor(0.89, 0.72, 0.40); love.graphics.circle('fill', cx + 3, y + 8, 3)
    love.graphics.setColor(0.75, 0.55, 0.29); love.graphics.circle('line', cx + 3, y + 8, 3)
    love.graphics.setColor(0.96, 0.94, 0.89)
    love.graphics.print(tostring(state.coins or 0), cx + 8, y - 1)
    love.graphics.setColor(1, 1, 1)
  end
  if self.banner then
    local a = math.min(1, self.banner.t * 2)
    local w = self.font:getWidth(self.banner.text) + 16
    love.graphics.setColor(0.12, 0.10, 0.14, 0.85 * a)
    love.graphics.rectangle('fill', 320 - w - 4, 4, w, 20)
    love.graphics.setColor(0.96, 0.94, 0.89, a)
    love.graphics.print(self.banner.text, 320 - w + 4, 6)
    love.graphics.setColor(1, 1, 1)
  end
  local y = 26
  for _, t in ipairs(self.toasts) do
    local a = math.min(1, t.t / .18, (t.age or 1) / .12)
    local lines = t.lines or { t.text }
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, self.font:getWidth(l)) end
    w = math.min(312, w + 16)
    local h = #lines * 16 + 4
    love.graphics.setColor(0.33, 0.24, 0.13, 0.9 * a)
    love.graphics.rectangle('fill', math.floor(160 - w / 2), y, w, h)
    love.graphics.setColor(1, 0.96, 0.85, a)
    for i, l in ipairs(lines) do
      love.graphics.print(l, math.floor(160 - self.font:getWidth(l) / 2), y + 2 + (i - 1) * 16)
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
