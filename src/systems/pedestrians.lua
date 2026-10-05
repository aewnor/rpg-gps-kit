-- Peatones que cruzan por los pasos de cebra (fase 4). Lua puro: se prueba con luajit (tests/traffic_cases.lua).
--
-- Ciclo de vida: aparecen por la acera junto a un paso de cebra cercano al jugador (approach), esperan en
-- el bordillo (wait) hasta que ningún vehículo cercano se acerque en marcha, cruzan perpendicularmente a la
-- calle (cross) y se alejan por la otra acera (leave) hasta desaparecer. Mientras esperan o cruzan marcan el
-- paso (cw.waiting / cw.crossing) y el tráfico (src/systems/traffic.lua) frena. Como mucho MAX a la vez.
local Pedestrians = {}
Pedestrians.__index = Pedestrians

Pedestrians.MAX = 8
Pedestrians.SPEED = 26        -- px/s (el jugador anda a 64)
Pedestrians.SPRITES = { 'npc_archaeologist', 'npc_gardener', 'npc_sailor', 'npc_musician', 'npc_lady', 'npc_kid', 'npc_elder', 'npc_tourist', 'npc_girl', 'npc_baker', 'npc_fisher',
                        'npc_postie' }
local SIDE = 36               -- recorrido por la acera antes y después de cruzar
local SPAWN_EVERY = 0.8
local PER_CROSSWALK = 2

function Pedestrians.new(traffic, rng)
  return setmetatable({ list = {}, traffic = traffic, rng = rng or math.random, t = 0 }, Pedestrians)
end

-- geometría de un paso: centro, dirección de la calle u y normal n (dirección de cruce)
local function geometry(cw)
  local a = cw.ang or 0
  local ux, uy = math.cos(a), math.sin(a)
  return ux, uy, -uy, ux
end

-- ¿se puede cruzar? ningún vehículo en marcha a menos de 64 px que se acerque al paso
function Pedestrians.safe(cw, cars, pos)
  for _, c in ipairs(cars) do
    if not c.decorative and c.v > 12 then
      local x, y, ang = pos(c)
      local dx, dy = cw.x - x, cw.y - y
      local d2 = dx * dx + dy * dy
      if d2 < 64 ^ 2 then
        local toward = dx * math.cos(ang) + dy * math.sin(ang) > -6
        if toward then return false end
      end
    end
  end
  return true
end

function Pedestrians:spawn_near(px, py)
  local cands = {}
  for _, cw in ipairs(self.traffic.crosswalks) do
    if cw.ang and (cw.level or 0) == 0 then
      local d2 = (cw.x - px) ^ 2 + (cw.y - py) ^ 2
      if d2 < 260 ^ 2 and d2 > 24 ^ 2 and (cw.peds or 0) < PER_CROSSWALK then cands[#cands + 1] = cw end
    end
  end
  if #cands == 0 then return nil end
  local rng = self.rng
  local cw = cands[math.floor(rng() * #cands) + 1]
  local ux, uy, nx, ny = geometry(cw)
  local side = rng() < 0.5 and 1 or -1           -- de qué acera sale
  local along = rng() < 0.5 and 1 or -1          -- por qué lado de la acera llega
  local off = cw.r + 4
  local p = {
    cw = cw, state = 'approach', t = 0, anim = 0, alpha = 0, wait = 0,
    sprite = Pedestrians.SPRITES[math.floor(rng() * #Pedestrians.SPRITES) + 1],
    speed = Pedestrians.SPEED * (0.8 + rng() * 0.4),
    -- puntos: inicio en la acera, bordillo, bordillo opuesto, salida
    a = { cw.x + nx * off * side + ux * SIDE * along, cw.y + ny * off * side + uy * SIDE * along },
    b = { cw.x + nx * off * side, cw.y + ny * off * side },
    c = { cw.x - nx * off * side, cw.y - ny * off * side },
    d = { cw.x - nx * off * side - ux * SIDE * along, cw.y - ny * off * side - uy * SIDE * along },
  }
  p.x, p.y = p.a[1], p.a[2]
  cw.peds = (cw.peds or 0) + 1
  self.list[#self.list + 1] = p
  return p
end

local function walk_to(p, tx, ty, dt)
  local dx, dy = tx - p.x, ty - p.y
  local d = math.sqrt(dx * dx + dy * dy)
  local step = p.speed * dt
  if math.abs(dx) > math.abs(dy) then p.facing = dx > 0 and 'right' or 'left'
  else p.facing = dy > 0 and 'down' or 'up' end
  if d <= step then p.x, p.y = tx, ty; return true end
  p.x, p.y = p.x + dx / d * step, p.y + dy / d * step
  p.anim = p.anim + math.min(d,step)/56
  return false
end

-- px, py: jugador; honk: claxon reciente del jugador (los cercanos se sobresaltan)
function Pedestrians:update(dt, px, py, honk)
  local tr = self.traffic
  for _, cw in ipairs(tr.crosswalks) do cw.waiting, cw.crossing = 0, 0 end
  self.t = self.t + dt
  if self.t >= SPAWN_EVERY then
    self.t = 0
    if #self.list < Pedestrians.MAX then self:spawn_near(px, py) end
  end
  local list = self.list
  for i = #list, 1, -1 do
    local p = list[i]
    p.t = p.t + dt
    p.moving = false
    if p.state == 'approach' then
      p.alpha = math.min(1, p.alpha + dt * 2.5)
      p.moving = true
      if walk_to(p, p.b[1], p.b[2], dt) then p.state = 'wait'; p.wait = 0 end
    elseif p.state == 'wait' then
      p.wait = p.wait + dt
      p.cw.waiting = p.cw.waiting + 1
      -- mira a la calzada
      local dx, dy = p.c[1] - p.x, p.c[2] - p.y
      if math.abs(dx) > math.abs(dy) then p.facing = dx > 0 and 'right' or 'left' else p.facing = dy > 0 and 'down' or 'up' end
      local walk_light = true
      if p.cw.light then walk_light = select(2, require('src.systems.traffic').light_state(p.cw, tr.clock)) end
      if p.wait > 0.6 and walk_light and Pedestrians.safe(p.cw, tr.cars, tr.pos) then p.state = 'cross'
      elseif p.wait > 40 then p.state = 'leave'; p.d = p.a end      -- se cansa de esperar y se va
    elseif p.state == 'cross' then
      p.cw.crossing = p.cw.crossing + 1
      p.moving = true
      if walk_to(p, p.c[1], p.c[2], dt) then p.state = 'leave' end
    elseif p.state == 'leave' then
      p.moving = true
      if walk_to(p, p.d[1], p.d[2], dt) then p.state = 'gone' end
    elseif p.state == 'gone' then
      p.alpha = p.alpha - dt * 2.5
      if p.alpha <= 0 then
        p.cw.peds = p.cw.peds - 1
        table.remove(list, i)
      end
    end
    if honk and honk > 0 and (p.x - px) ^ 2 + (p.y - py) ^ 2 < 70 ^ 2 then p.startle = 0.8 end
    if p.startle then p.startle = p.startle - dt; if p.startle <= 0 then p.startle = nil end end
    -- muy lejos del jugador (tren, bus): desaparece
    if list[i] == p and (p.x - px) ^ 2 + (p.y - py) ^ 2 > 420 ^ 2 then
      p.cw.peds = p.cw.peds - 1
      table.remove(list, i)
    end
  end
end

-- obstáculos para el tráfico: solo quien pisa la calzada (cruzando)
function Pedestrians:obstacles(out)
  for _, p in ipairs(self.list) do
    if p.state == 'cross' then out[#out + 1] = { x = p.x, y = p.y, who = 'ped', level = 0 } end
  end
  return out
end

return Pedestrians
