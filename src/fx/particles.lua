-- Partículas con memoria fija (pensado para la Raspberry Pi): un único bloque de arrays paralelos con tope,
-- sin crear tablas por partícula ni usar table.remove (la que muere se cambia por la última), y dibujo en
-- un SpriteBatch de un píxel blanco: todas las partículas salen en UNA llamada de dibujo.
-- update() es Lua puro (se prueba con luajit, tests/juice_cases.lua); draw() usa love.graphics.
--
-- Tipos (kind): 0 polvo/humo (frena, sube un poco) · 1 chispa (gravedad, rebote breve, color cálido)
--               2 destello (cruz que parpadea) · 3 hoja (cae lenta balanceándose) · 4 confeti (gravedad suave)
local Particles = {}
Particles.__index = Particles

Particles.PRESETS = {
  dust = { kind = 0, color = { 0.84, 0.78, 0.66 }, speed = 12, life = 0.35, size = 2, drag = 0.9 },
  skid = { kind = 0, color = { 0.78, 0.72, 0.60 }, speed = 22, life = 0.45, size = 3, drag = 0.88 },
  smoke = { kind = 0, color = { 0.55, 0.53, 0.56 }, speed = 8, life = 0.6, size = 2, drag = 0.92 },
  spark = { kind = 1, color = { 1.0, 0.86, 0.35 }, speed = 70, life = 0.28, size = 1, drag = 0.97, grav = 260 },
  sparkle = { kind = 2, color = { 1.0, 0.97, 0.75 }, speed = 26, life = 0.8, size = 2, drag = 0.9 },
  leaf = { kind = 3, color = { 0.55, 0.66, 0.30 }, speed = 4, life = 4.5, size = 2, drag = 1, grav = 9 },
  confetti = { kind = 4, color = { 0.95, 0.45, 0.35 }, speed = 60, life = 1.1, size = 2, drag = 0.95, grav = 90 },
  levelup = { kind = 2, color = { 1.0, 0.9, 0.4 }, speed = 40, life = 0.7, size = 2, drag = 0.9 },
}
local CONFETTI = { { 0.95, 0.45, 0.35 }, { 0.33, 0.78, 0.76 }, { 0.98, 0.85, 0.35 }, { 0.55, 0.75, 0.40 }, { 0.75, 0.55, 0.9 } }
local LEAVES = { { 0.55, 0.66, 0.30 }, { 0.72, 0.62, 0.25 }, { 0.80, 0.48, 0.22 }, { 0.45, 0.58, 0.28 } }

function Particles.new(cap, rng)
  local self = setmetatable({ cap = cap or 320, n = 0, rng = rng or math.random, dropped = 0 }, Particles)
  for _, k in ipairs({ 'x', 'y', 'vx', 'vy', 't', 'life', 'r', 'g', 'b', 'size', 'kind', 'grav', 'drag', 'ph' }) do
    self[k] = {}
  end
  self.fields = { self.x, self.y, self.vx, self.vy, self.t, self.life, self.r, self.g, self.b, self.size, self.kind,
                  self.grav, self.drag, self.ph }
  return self
end

-- una partícula; si el bloque está lleno se descarta (nunca crece)
function Particles:add(x, y, vx, vy, life, r, g, b, size, kind, grav, drag)
  if self.n >= self.cap then self.dropped = self.dropped + 1; return false end
  local i = self.n + 1
  self.n = i
  self.x[i], self.y[i], self.vx[i], self.vy[i] = x, y, vx, vy
  self.t[i], self.life[i] = 0, life
  self.r[i], self.g[i], self.b[i] = r, g, b
  self.size[i], self.kind[i] = size, kind or 0
  self.grav[i], self.drag[i] = grav or 0, drag or 0.9
  self.ph[i] = self.rng() * 6.283
  return true
end

-- ráfaga radial (compatible con el antiguo World:puff)
function Particles:burst(x, y, n, col, speed, life, size, kind, grav, drag)
  local rng = self.rng
  speed = speed or 12
  col = col or { 0.86, 0.81, 0.71 }
  for _ = 1, n do
    local a = rng() * 6.283
    local v = speed * (0.4 + rng() * 0.6)
    self:add(x, y, math.cos(a) * v, math.sin(a) * v * 0.5 - speed * 0.3, (life or 0.35) * (0.7 + rng() * 0.6),
      col[1], col[2], col[3], size or 2, kind, grav, drag)
  end
end

-- efecto con nombre (PRESETS); opts: { color, speed, life, size, dir = ángulo, spread = rad }
function Particles:preset(name, x, y, n, opts)
  if require('src.motion').reduced then n=math.min(n or 1,3) end
  local p = Particles.PRESETS[name]
  opts = opts or {}
  local rng = self.rng
  local speed, life, size = opts.speed or p.speed, opts.life or p.life, opts.size or p.size
  for _ = 1, n or 1 do
    local col = opts.color or p.color
    if name == 'confetti' then col = CONFETTI[math.floor(rng() * #CONFETTI) + 1]
    elseif name == 'leaf' then col = LEAVES[math.floor(rng() * #LEAVES) + 1] end
    local a = opts.dir and (opts.dir + (rng() - 0.5) * (opts.spread or 1)) or rng() * 6.283
    local v = speed * (0.4 + rng() * 0.6)
    local vy = math.sin(a) * v
    if p.kind == 0 then vy = vy * 0.5 - speed * 0.3 end
    if name == 'confetti' and not opts.dir then vy = -math.abs(vy) - speed * 0.4 end
    self:add(x, y, math.cos(a) * v, vy, life * (0.7 + rng() * 0.6), col[1], col[2], col[3], size, p.kind, p.grav, p.drag)
  end
end

function Particles:update(dt)
  local x, y, vx, vy, t, life = self.x, self.y, self.vx, self.vy, self.t, self.life
  local kind, grav, drag, ph = self.kind, self.grav, self.drag, self.ph
  local fields = self.fields
  local i = 1
  local k60 = dt * 60
  while i <= self.n do
    t[i] = t[i] + dt
    if t[i] >= life[i] then
      local j = self.n          -- cambiar por la última y acortar
      if i ~= j then for _, f in ipairs(fields) do f[i] = f[j] end end
      self.n = j - 1
    else
      local d = drag[i] ^ k60
      if kind[i] == 3 then      -- hoja: cae despacio y se balancea
        vx[i] = math.sin(t[i] * 2.2 + ph[i]) * 10
        vy[i] = grav[i]
      else
        vx[i] = vx[i] * d
        vy[i] = vy[i] * d + grav[i] * dt
      end
      x[i] = x[i] + vx[i] * dt
      y[i] = y[i] + vy[i] * dt
      i = i + 1
    end
  end
end

function Particles:clear() self.n = 0 end

local pixel
function Particles:draw(ox, oy)
  if self.n == 0 then return end
  if not self.batch then
    if not pixel then
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 1, 1, 1, 1)
      pixel = love.graphics.newImage(d)
    end
    self.batch = love.graphics.newSpriteBatch(pixel, self.cap * 2, 'stream')
  end
  local sb = self.batch
  sb:clear()
  local floor = math.floor
  for i = 1, self.n do
    local k = 1 - self.t[i] / self.life[i]
    local kind = self.kind[i]
    local a = kind == 3 and math.min(1, k * 3) or 0.9 * k
    local sz = self.size[i]
    local px, py = floor(self.x[i] - ox + 0.5), floor(self.y[i] - oy + 0.5)
    if kind == 2 then          -- destello: cruz que late
      local on = true -- smooth fade, no rapid sparkle flicker
      if on then
        sb:setColor(self.r[i], self.g[i], self.b[i], math.min(1, k * 1.5))
        local s = k > 0.5 and sz or 1
        sb:add(px - s, py, 0, 2 * s + 1, 1)
        sb:add(px, py - s, 0, 1, 2 * s + 1)
      end
    else
      if kind == 0 then sz = math.max(1, floor(sz * (0.5 + k * 0.5) + 0.5)) end
      sb:setColor(self.r[i], self.g[i], self.b[i], a)
      if kind == 3 then sb:add(px, py, 0, (floor(self.t[i] * 3 + self.ph[i]) % 2 == 0) and 2 or 1, 1)
      else sb:add(px - floor(sz / 2), py - floor(sz / 2), 0, sz, sz) end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(sb)
end

return Particles
