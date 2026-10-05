-- Caja de diálogo con texto progresivo (UTF-8) y páginas. Pausa el combate mientras está abierta.
local utf8 = require('utf8')

local Dialogue = {}
Dialogue.__index = Dialogue

local CPS = 45

function Dialogue.new(font, sfx)
  return setmetatable({ font = font, sfx = sfx, open = false }, Dialogue)
end

local MAX_LINES = 3

function Dialogue:show(name, pages, on_close, voice)
  self.open = true
  self.name = name
  -- las páginas que no caben en 3 líneas se parten (antes la 4.ª línea no se veía nunca)
  local out = {}
  for _, p in ipairs(pages) do
    local _, lines = self.font:getWrap(p, 288)
    if #lines <= MAX_LINES then out[#out + 1] = p
    else
      for i = 1, #lines, MAX_LINES do
        out[#out + 1] = table.concat(lines, ' ', i, math.min(#lines, i + MAX_LINES - 1))
      end
    end
  end
  self.pages = #out > 0 and out or { '...' }
  self.page = 1
  self.t = 0
  self.on_close = on_close
  self.voice = voice   -- (opcional) 'm' | 'f': si no, pel nom (src/tts.lua Tts.gender)
  self:layout()
end

function Dialogue:layout()
  -- veu (src/tts.lua): cada pàgina es llegeix en veu alta en aparèixer (asíncron, no atura el joc)
  local Tts = require('src.tts')
  -- veu: la demanada, la del nom («En Jordi» → home) o la de qui t'està parlant (World posa speaker_voice)
  Tts.say(self.pages[self.page], true, self.voice or Tts.gender(self.name) or self.speaker_voice)
  -- karaoke: la paraula que diu la veu es ressalta (si la veu parla)
  self.read_id = Tts.enabled() and Tts.seq or nil
  self.read_t = 0
  local _, lines = self.font:getWrap(self.pages[self.page], 288)
  self.lines = lines
  self.total = 0
  for _, l in ipairs(lines) do self.total = self.total + utf8.len(l) end
end

function Dialogue:update(dt, pressed)
  if not self.open then return end
  local before = math.floor(self.t * CPS)
  self.t = self.t + dt
  self.read_t = (self.read_t or 0) + dt
  if math.floor(self.t * CPS) > before and before < self.total and before % 3 == 0 and self.sfx then
    self.sfx('talk')
  end
  if pressed.confirm or pressed.cancel then
    if self.t * CPS < self.total then
      self.t = self.total / CPS -- mostrar la página entera
    elseif self.page < #self.pages then
      self.page = self.page + 1
      self.t = 0
      self:layout()
    else
      self.open = false
      if self.on_close then self.on_close() end
    end
  end
end

-- caràcter de la pàgina que s'està dient: el que avisa el navegador (Tts.word) o, si no n'avisa, una estimació
-- pel ritme de la veu (13 caràcters per segon a velocitat normal, després d'un quart de segon)
function Dialogue:reading_char()
  if not self.read_id then return nil end
  local Tts = require('src.tts')
  if Tts.seq ~= self.read_id then return nil end
  local total = (self.total or 0) + math.max(0, #(self.lines or {}) - 1)   -- (amb els espais dels salts de línia)
  local w = Tts.word
  if w and w.id == self.read_id then
    if w.done then return nil end
    return math.floor(w.frac * total)
  end
  local rate = Tts.settings and Tts.settings.tts and Tts.settings.tts.rate or 1
  local c = math.floor(((self.read_t or 0) - 0.25) * 13 * rate)
  if c < 0 or c >= total then return nil end
  return c
end

-- fons suau darrere la paraula de la línia l que conté el caràcter k (0 = primer); visible: caràcters ja escrits
function Dialogue:draw_word(l, k, x, y, visible)
  local chars = {}
  for _, c in utf8.codes(l) do chars[#chars + 1] = utf8.char(c) end
  if k >= #chars then k = #chars - 1 end
  if k < 0 or not chars[k + 1] then return end
  local a, b = k + 1, k + 1
  while a > 1 and chars[a - 1] ~= ' ' do a = a - 1 end
  while b < #chars and chars[b + 1] ~= ' ' do b = b + 1 end
  if chars[a] == ' ' then return end
  if a > visible then return end
  b = math.min(b, visible)
  local pre = table.concat(chars, '', 1, a - 1)
  local word = table.concat(chars, '', a, b)
  local wx = x + self.font:getWidth(pre)
  local ww = self.font:getWidth(word)
  love.graphics.setColor(1, 0.86, 0.45, 0.28)
  love.graphics.rectangle('fill', wx - 1, y + 1, ww + 2, 15, 3, 3)
  love.graphics.setColor(1, 1, 1)
end

function Dialogue:draw()
  if not self.open then return end
  local x, y, w, h = 8, 168, 304, 64
  love.graphics.setColor(0.12, 0.10, 0.14, 0.94)
  love.graphics.rectangle('fill', x, y, w, h)
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.rectangle('line', x + 1.5, y + 1.5, w - 3, h - 3)
  if self.name then
    local nw = self.font:getWidth(self.name) + 12
    love.graphics.setColor(0.84, 0.42, 0.29)
    love.graphics.rectangle('fill', x + 6, y - 14, nw, 16)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(self.name, x + 12, y - 14)
  end
  love.graphics.setColor(1, 1, 1)
  local shown = math.floor(self.t * CPS)
  local ly = y + 6
  local reading = self:reading_char()   -- índex (caràcters de la pàgina) del que diu la veu, o nil
  local base = 0
  for i, l in ipairs(self.lines) do
    if i > 3 then break end
    local n = utf8.len(l)
    local s = l
    if shown < n then
      s = shown > 0 and l:sub(1, (utf8.offset(l, shown + 1) or (#l + 1)) - 1) or ''
    end
    if reading and reading >= base and reading < base + n + 1 then self:draw_word(l, reading - base, x + 8, ly, utf8.len(s)) end
    base = base + n + 1
    love.graphics.print(s, x + 8, ly)
    shown = math.max(0, shown - n)
    ly = ly + 18
  end
  if self.t * CPS >= self.total and math.floor(love.timer.getTime() * 3) % 2 == 0 then
    love.graphics.polygon('fill', x + w - 16, y + h - 12, x + w - 8, y + h - 12, x + w - 12, y + h - 7)
  end
end

return Dialogue
