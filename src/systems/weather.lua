-- Temps (exteriors): sol, núvols, pluja, tempesta, neu, boira i vent.
-- config/joc.json (camp «temps», editable a /editor/config.html) el fixa per a totes les partides; amb «auto»
-- canvia sol cada 6 hores de joc, de forma determinista pel dia (tothom veu el mateix temps el mateix dia de
-- joc). La neu només surt a l'hivern (desembre-febrer, data real). Tot és visual i sonor: no canvia el joc,
-- excepte el xubasquer, que el protagonista es posa sol quan plou. Deixa rastre: neu a terra i a les teulades
-- (`snow`, renderer) i bassals (`puddles`, src/systems/puddles.lua), que van marxant quan para.
local Weather = {}
Weather.__index = Weather

Weather.KINDS = { 'sol', 'nuvol', 'pluja', 'tempesta', 'neu', 'boira', 'vent' }
Weather.NAMES = { sol = 'Sol', nuvol = 'Ennuvolat', pluja = 'Pluja', tempesta = 'Tempesta', neu = 'Neu',
                  boira = 'Boira', vent = 'Vent' }
Weather.WET = { pluja = true, tempesta = true }
Weather.BLOCK = 360   -- minuts de joc que dura un temps en mode automàtic

local W, H = 320, 240

local function winter(month) return month == 12 or month <= 2 end

-- pes de cada temps en mode automàtic (sol el més habitual: és la Costa Daurada)
function Weather.weights(month)
  return { { 'sol', 46 }, { 'nuvol', 18 }, { 'vent', 10 }, { 'pluja', 12 }, { 'boira', 6 }, { 'tempesta', 4 },
           { 'neu', winter(month) and 10 or 0 } }
end

-- hash enter petit i estable (mateix resultat a LuaJIT i a love.js)
local function hash(n)
  n = (n * 1664525 + 1013904223) % 4294967296   -- < 2^53: exacte amb doubles
  n = (n * 1664525 + 1013904223) % 4294967296
  n = (n * 1664525 + 1013904223) % 4294967296
  return n / 4294967296
end

-- temps del tram (dia, bloc de 6 h): determinista
function Weather.auto(day, clock, month)
  local block = math.floor(((clock or 600) % 1440) / Weather.BLOCK)
  local r = hash((day or 1) * 4 + block + 7)
  local ws, total = Weather.weights(month or 6), 0
  for _, w in ipairs(ws) do total = total + w[2] end
  local acc = 0
  for _, w in ipairs(ws) do
    acc = acc + w[2] / total
    if r < acc then return w[1] end
  end
  return 'sol'
end

function Weather.valid(kind)
  for _, k in ipairs(Weather.KINDS) do if k == kind then return true end end
  return false
end

-- temps que toca ara: el de la configuració si és fix, si no el del tram
function Weather.pick(state, cfg_temps, month)
  if cfg_temps and cfg_temps ~= 'auto' and Weather.valid(cfg_temps) then return cfg_temps end
  return Weather.auto(state.day, state.clock, month or tonumber(os.date('%m')))
end

function Weather.new()
  local self = setmetatable({ kind = 'sol', level = 0, drops = {}, flakes = {}, leaves = {}, flash = 0,
                              bolt_t = 8, t = 0 }, Weather)
  local rng = love.math.newRandomGenerator(11)
  for i = 1, 200 do self.drops[i] = { x = rng:random() * W, y = rng:random() * H, s = 0.7 + rng:random() * 0.6 } end
  for i = 1, 110 do
    self.flakes[i] = { x = rng:random() * W, y = rng:random() * H, s = 0.5 + rng:random(), ph = rng:random() * 6.28,
                       big = rng:random() < 0.3 }
  end
  for i = 1, 28 do
    self.leaves[i] = { x = rng:random() * W, y = rng:random() * H, s = 0.6 + rng:random() * 0.8, ph = rng:random() * 6.28,
                       c = rng:random(1, 3) }
  end
  return self
end

-- intensitat 0..1 per fondre els canvis de temps; torna true quan acaba de canviar (per avisar)
function Weather:update(dt, kind, outdoor)
  self.t = self.t + dt
  local changed = false
  if kind ~= self.kind then
    self.level = math.max(0, self.level - dt * 0.6)
    if self.level <= 0 then self.kind = kind; changed = true end
  else
    self.level = math.min(1, self.level + dt * 0.4)
  end
  -- el que queda a terra: neu acumulada (es fon a poc a poc) i bassals (s'assequen encara més a poc a poc)
  if self.kind == 'neu' and self.level > 0.3 then self.snow = math.min(1, (self.snow or 0) + dt / 45)
  else self.snow = math.max(0, (self.snow or 0) - dt / 150) end
  if self:is_wet() then self.puddles = math.min(1, (self.puddles or 0) + dt / (self.kind == 'tempesta' and 15 or 30))
  else self.puddles = math.max(0, (self.puddles or 0) - dt / 200) end
  self.flash = math.max(0, self.flash - dt * 2.5)
  if self.kind == 'tempesta' and outdoor and self.level > 0.6 then
    self.bolt_t = self.bolt_t - dt
    if self.bolt_t <= 0 then
      self.flash = 1
      self.bolt_t = 7 + love.math.random() * 9
      self.thunder_in = 0.4 + love.math.random() * 1.2   -- el tro arriba després del llamp
    end
  end
  if self.thunder_in then
    self.thunder_in = self.thunder_in - dt
    if self.thunder_in <= 0 then self.thunder_in = nil; self.thunder = true end
  end
  return changed
end

function Weather:is_wet() return Weather.WET[self.kind] and self.level > 0.3 end

-- capes de so d'ambient (src/audio.lua)
function Weather:ambient()
  local k, l = self.kind, self.level
  if k == 'pluja' then return { rain = 0.45 * l } end
  if k == 'tempesta' then return { rain = 0.7 * l, wind = 0.35 * l } end
  if k == 'vent' then return { wind = 0.55 * l } end
  if k == 'neu' then return { wind = 0.15 * l } end
  return {}
end

-- es dibuixa en coordenades de pantalla, damunt de la llum del dia; ox/oy (càmera) fan que la pluja i la neu
-- es moguin amb el món i no amb el jugador
function Weather:draw(ox, oy)
  local k, l = self.kind, self.level
  if l <= 0.01 or k == 'sol' then return end
  local lg = love.graphics
  local t = self.t
  local function wrap(v, m) return v % m end
  if k == 'nuvol' or k == 'pluja' or k == 'tempesta' then
    local dark = (k == 'nuvol' and 0.10) or (k == 'pluja' and 0.18) or 0.30
    lg.setColor(0.22, 0.25, 0.32, dark * l); lg.rectangle('fill', 0, 0, W, H)
    -- ombres de núvols que passen
    lg.setColor(0.1, 0.12, 0.18, 0.08 * l)
    for i = 0, 2 do
      local cx = wrap(i * 150 + t * 6 - ox * 0.6, W + 240) - 120
      local cy = wrap(i * 97 - oy * 0.6, H + 160) - 80
      lg.ellipse('fill', cx, cy, 90, 50)
    end
  end
  if k == 'pluja' or k == 'tempesta' then
    local n = k == 'tempesta' and 200 or 120
    local slant = k == 'tempesta' and 5 or 2
    lg.setLineWidth(1)
    lg.setColor(0.72, 0.8, 0.95, 0.55 * l)
    for i = 1, n do
      local d = self.drops[i]
      local y = wrap(d.y + t * 260 * d.s - oy, H + 20) - 10
      local x = wrap(d.x + t * 30 * slant * d.s - ox + y * slant * 0.02, W + 20) - 10
      lg.line(x, y, x - slant, y - 7 * d.s)
    end
    -- esquitxos a terra
    lg.setColor(0.8, 0.86, 1, 0.45 * l)
    for i = 1, 24 do
      local d = self.drops[i]
      local ph = (t * 2.2 + d.s * 5) % 1
      local x, y = wrap(d.x * 1.7 - ox, W), wrap(d.y * 1.3 - oy, H)
      lg.ellipse('line', x, y, 1 + ph * 3, 0.5 + ph * 1.2)
    end
  end
  if k == 'neu' then   -- tot una mica blanc i flocs grossos amb vora blava (es veuen sobre la sorra clara)
    lg.setColor(0.92, 0.95, 1, 0.24 * l); lg.rectangle('fill', 0, 0, W, H)
    for i = 1, 110 do
      local f = self.flakes[i]
      local y = math.floor(wrap(f.y + t * 22 * f.s - oy, H + 10) - 5)
      local x = math.floor(wrap(f.x + math.sin(t * 1.3 + f.ph) * 6 - ox + t * 4, W + 10) - 5)
      if f.big then
        lg.setColor(0.55, 0.65, 0.85, 0.7 * l); lg.rectangle('fill', x - 1, y, 4, 2); lg.rectangle('fill', x, y - 1, 2, 4)
        lg.setColor(1, 1, 1, l); lg.rectangle('fill', x, y, 2, 2)
      else
        lg.setColor(0.6, 0.7, 0.9, 0.6 * l); lg.rectangle('fill', x, y + 1, 1, 1)
        lg.setColor(1, 1, 1, l); lg.rectangle('fill', x, y, 1, 1)
      end
    end
  end
  if k == 'boira' then
    lg.setColor(0.86, 0.88, 0.9, 0.30 * l); lg.rectangle('fill', 0, 0, W, H)
    for i = 0, 4 do   -- bancs de boira que s'arrosseguen
      local cx = wrap(i * 83 + t * (4 + i) - ox * 0.8, W + 260) - 130
      local cy = wrap(i * 61 - oy * 0.8, H + 140) - 70
      lg.setColor(0.92, 0.93, 0.95, 0.16 * l)
      lg.ellipse('fill', cx, cy, 120, 40)
    end
  end
  if k == 'vent' or k == 'tempesta' then
    -- fulles i ratlles de vent
    local cols = { { 0.45, 0.62, 0.25 }, { 0.72, 0.5, 0.22 }, { 0.58, 0.4, 0.2 } }
    for i = 1, 28 do
      local f = self.leaves[i]
      local x = math.floor(wrap(f.x + t * 110 * f.s - ox, W + 20) - 10)
      local y = math.floor(wrap(f.y + math.sin(t * 3 + f.ph) * 8 + t * 10 - oy, H + 20) - 10)
      local c = cols[f.c]
      local flip = math.floor(t * 8 + f.ph) % 2
      lg.setColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.9 * l); lg.rectangle('fill', x, y + 1, 4 - flip, 2)
      lg.setColor(c[1], c[2], c[3], l); lg.rectangle('fill', x, y, 3 - flip, 2)
    end
    lg.setLineWidth(1)
    for i = 1, 16 do   -- ratlles de vent: més llargues i amb un deix de corba
      local f = self.leaves[i]
      local x = wrap(f.x * 1.9 + t * 240 * (0.8 + f.s * 0.3) - ox, W + 120) - 60
      local y = wrap(f.y * 1.4 - oy, H)
      local len = 26 + f.s * 18
      lg.setColor(1, 1, 1, 0.38 * l); lg.line(x, y, x + len, y)
      lg.setColor(1, 1, 1, 0.2 * l); lg.line(x + len, y, x + len + 6, y - 2)
    end
  end
  if self.flash > 0 then
    lg.setColor(1, 1, 0.95, 0.75 * self.flash); lg.rectangle('fill', 0, 0, W, H)
  end
  lg.setColor(1, 1, 1)
end

return Weather
