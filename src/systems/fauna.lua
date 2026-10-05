-- Fauna: perros (a veces paseados por su dueño), gatos callejeros, pájaros y animales salvajes de la montaña.
--
-- Todo es dinámico y local al jugador (el mapa no se toca): cada ~1 s se intenta crear un animal justo fuera de
-- pantalla según el terreno que pisa su casilla (calle, parque/jardín, playa, montaña) y los topes por especie y por
-- zona; los que quedan a más de KEEP px se descargan. Los salvajes son `Enemy` de verdad (src/entities/enemy.lua):
-- van en w.enemies, pegan, dan XP/monedas y pueden soltar comida. Lua puro salvo draw() (se prueba con
-- tests/fauna_cases.lua con un mundo falso).
--
-- Interfaz con la escena (w): w.map, w:tile_name('ground', tx, ty), w.player, w.cam, w.blockers, w.enemies, w.state,
-- w.game.sprites {animals, enemies, chars}, w.fx, w.hud, w:popup().
local Collision = require('src.world.collision')
local Enemy = require('src.entities.enemy')
local Pedestrians = require('src.systems.pedestrians')

local Fauna = {}
Fauna.__index = Fauna

Fauna.CAP = { cat = 4, dog = 3, bird = 9, wild = 4, total = 16 }
Fauna.ZONE_CAP = { street = 6, park = 9, beach = 6, mountain = 5 }
Fauna.KEEP = 300            -- px: más lejos se descarga
local SPAWN_MIN, SPAWN_MAX = 150, 235
local TICK = 0.9

-- ------------------------------------------------------------------ terreno
local ZONES = {}
local function zone_set(zone, list) for _, n in ipairs(list) do ZONES[n] = zone end end
zone_set('street', { 'g_urban', 'g_cobble', 'd_paving' })
zone_set('road', { 'g_asphalt', 'g_parking', 'd_road', 'd_main', 'd_moto' })
zone_set('park', { 'g_park', 'g_flowers', 'g_grass', 'g_yard', 'd_path' })
zone_set('mountain', { 'g_forest', 'g_scrub', 'g_rock', 'g_dry' })
zone_set('beach', { 'g_beach', 'g_sandpit' })

local function base(name) return name and (name:gsub('_%d+$', '')) end
Fauna.base = base

-- 'street' | 'road' | 'park' | 'mountain' | 'beach' | nil según el nombre del tile de suelo
function Fauna.zone(name)
  if not name then return nil end
  local b = base(name)
  local z = ZONES[b]
  if z then return z end
  -- transición de terreno tw_<a>_<b>: monte si toca monte y ninguna punta es calle
  local a, c = b:match('^tw_(%a+)_(%a+)$')
  if not a then return nil end
  local za, zc = ZONES['g_' .. a], ZONES['g_' .. c]
  if za == 'street' or zc == 'street' then return nil end
  if za == 'mountain' or zc == 'mountain' then return 'mountain' end
  if za == zc then return za end
  return nil
end

local function zone_at(w, x, y)
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  if not w.map:in_bounds(tx, ty) then return nil end
  return Fauna.zone(w:tile_name('ground', tx, ty))
end
Fauna.zone_at = zone_at

-- montaña «de verdad»: la casilla y 8 vecinas a 3 casillas son casi todas monte y ninguna calle (no el borde del pueblo)
local RING = { { 0, 0 }, { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 }, { 3, 3 }, { -3, -3 }, { 3, -3 }, { -3, 3 } }
local function deep_mountain(w, x, y)
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  local n = 0
  for _, o in ipairs(RING) do
    local ax, ay = tx + o[1], ty + o[2]
    if not w.map:in_bounds(ax, ay) then return false end
    local z = Fauna.zone(w:tile_name('ground', ax, ay))
    if z == 'mountain' then n = n + 1 elseif z == 'street' or z == 'road' then return false end
  end
  return n >= 7
end

local WALKABLE = { street = true, park = true, beach = true }   -- por donde pasean (road solo al huir)

local function dist2(ax, ay, bx, by) return (ax - bx) ^ 2 + (ay - by) ^ 2 end

function Fauna.new(w, rng)
  return setmetatable({ w = w, list = {}, rng = rng or math.random, t = 0, spawn_t = 0.3, wild_t = 2 }, Fauna)
end

-- ------------------------------------------------------------------ creación
local function new_body(x, y) return { x = x, y = y, w = 8, h = 6, level = 0 } end

local function pick(rng, list) return list[math.floor(rng() * #list) + 1] end

local function sheet_names(w, prefix)
  local out = {}
  for name in pairs(w.game.sprites.animals or {}) do
    if name:sub(1, #prefix) == prefix then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

function Fauna:count(cls)
  local n = 0
  for _, a in ipairs(self.list) do if a.cls == cls then n = n + 1 end end
  return n
end

function Fauna:count_zone(zone)
  local n = 0
  for _, a in ipairs(self.list) do if a.zone == zone and a.cls ~= 'owner' then n = n + 1 end end
  return n
end

function Fauna:count_wild()
  local n = 0
  for _, e in ipairs(self.w.enemies) do if e.fauna and e.state ~= 'dead' then n = n + 1 end end
  return n
end

local function add(self, a)
  a.body = a.body or new_body(a.x, a.y)
  a.x, a.y = a.body.x, a.body.y
  a.anim, a.z, a.t = a.anim or 0, a.z or 0, a.t or 0
  self.list[#self.list + 1] = a
  return a
end

function Fauna:spawn_cat(x, y, zone)
  local names = sheet_names(self.w, 'cat_')
  if #names == 0 then return end
  local rng = self.rng
  return add(self, { cls = 'cat', coat = pick(rng, names), x = x, y = y, zone = zone, state = 'idle',
                     t = 1 + rng() * 3, tame = rng() < 0.4, left = rng() < 0.5, sleepy = rng() < 0.3 })
end

function Fauna:spawn_dog(x, y, zone, owner)
  local names = sheet_names(self.w, 'dog_')
  if #names == 0 then return end
  local rng = self.rng
  local d = add(self, { cls = 'dog', coat = pick(rng, names), x = x, y = y, zone = zone, state = 'idle',
                        t = 1 + rng() * 3, left = rng() < 0.5, home = { x, y }, owner = owner })
  if owner then owner.dog = d end
  return d
end

function Fauna:spawn_owner(x, y, zone)
  local rng = self.rng
  local o = add(self, { cls = 'owner', sprite = pick(rng, Pedestrians.SPRITES), x = x, y = y, zone = zone,
                        state = 'pause', t = 0.5 + rng(), facing = 'down', moving = false, alpha = 1 })
  o.dir = { 0, 1 }
  local dog = self:spawn_dog(x + 8, y + 2, zone, o)
  if not dog then
    table.remove(self.list)   -- sin perros en las hojas no hay paseador
    return nil
  end
  return o
end

function Fauna:spawn_bird(x, y, zone)
  local names = zone == 'beach' and { 'bird_gull' } or sheet_names(self.w, 'bird_')
  if zone ~= 'beach' then
    local keep = {}
    for _, n in ipairs(names) do if n ~= 'bird_gull' then keep[#keep + 1] = n end end
    names = keep
  end
  if #names == 0 then return end
  local rng = self.rng
  return add(self, { cls = 'bird', coat = pick(rng, names), x = x, y = y,
                     zone = zone, state = 'peck', t = 1 + rng() * 3, left = rng() < 0.5, hop_t = 1 + rng() * 3 })
end

-- salvaje: un Enemy más, marcado .fauna para descargarlo
function Fauna:spawn_wild(x, y, tile)
  local w, rng = self.w, self.rng
  local st = w.state or {}
  local lvl = st.char_level or 1
  local clock = st.clock or 720
  local night = clock >= 19 * 60 or clock < 7 * 60
  local b = base(tile)
  local choices = { { 'boar', 3 }, { 'fox', 3 } }
  if b == 'g_scrub' or b == 'g_dry' or b == 'g_rock' then choices[#choices + 1] = { 'snake', 2 } end
  if night and lvl >= 3 then choices[#choices + 1] = { 'wolf', 3 } end
  local total = 0
  for _, c in ipairs(choices) do total = total + c[2] end
  local r = rng() * total
  local kind = choices[1][1]
  for _, c in ipairs(choices) do
    r = r - c[2]
    if r <= 0 then kind = c[1]; break end
  end
  local k = Enemy.KINDS[kind]
  local sheet = w.game.sprites.enemies[k.sprite:sub(7)]
  local bonus = math.max(0, math.min(3, math.floor((lvl - (k.lvl or 1)) / 3)))
  self.wild_n = (self.wild_n or 0) + 1
  local e = Enemy.new({ x = x, y = y, name = 'fauna_' .. self.wild_n,
                        props = { kind = kind, patrol = rng() < 0.5 and 'h' or 'v', range = 2 + math.floor(rng() * 3),
                                  hp_bonus = bonus } }, sheet)
  e.fauna = true
  w.enemies[#w.enemies + 1] = e
  return e
end

-- intento de creación en un punto al azar fuera de pantalla
function Fauna:try_spawn()
  local w, rng = self.w, self.rng
  local pb = w.player.body
  if pb.level ~= 0 then return end
  local ang, d = rng() * math.pi * 2, SPAWN_MIN + rng() * (SPAWN_MAX - SPAWN_MIN)
  local x, y = pb.x + math.cos(ang) * d, pb.y + math.sin(ang) * d
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  if not w.map:in_bounds(tx, ty) then return end
  if w.cam and w.cam:visible(x - 8, y - 16, 16, 16, 0) then return end
  local tile = w:tile_name('ground', tx, ty)
  local zone = Fauna.zone(tile)
  if not zone or zone == 'road' then return end
  if not Collision.fits(new_body(x, y), x, y, w.map, w.blockers) then return end

  if zone == 'mountain' then
    local clock = w.state and w.state.clock or 720
    if clock >= 6.5 * 60 and clock < 21 * 60 and rng() < .65 and #self.list < Fauna.CAP.total
        and self:count('bird') < Fauna.CAP.bird and self:count_zone(zone) < Fauna.ZONE_CAP.mountain then
      return self:spawn_bird(x, y, zone)
    end
    local st = w.state or {}
    local weak = (st.hp or 99) < math.max(3, (st.max_hp or 24) * 0.5)   -- con poca vida no salen más
    if self:count_wild() >= Fauna.CAP.wild or weak or not deep_mountain(w, x, y) then return end
    return self:spawn_wild(x, y, tile)
  end
  if #self.list >= Fauna.CAP.total or self:count_zone(zone) >= (Fauna.ZONE_CAP[zone] or 4) then return end
  local clock = w.state and w.state.clock or 720
  local day = clock >= 6.5 * 60 and clock < 21 * 60
  local opts = {}
  if day and self:count('bird') < Fauna.CAP.bird then opts[#opts + 1] = { 'bird', zone == 'beach' and 4 or 3 } end
  if zone ~= 'beach' then
    if self:count('cat') < Fauna.CAP.cat then opts[#opts + 1] = { 'cat', zone == 'street' and 3 or 1 } end
    if self:count('dog') < Fauna.CAP.dog - 1 and day and #self.list <= Fauna.CAP.total - 2 then opts[#opts + 1] = { 'owner', zone == 'street' and 2 or 1 } end
    if zone == 'park' and self:count('dog') < Fauna.CAP.dog then opts[#opts + 1] = { 'dog', 1 } end
  end
  local total = 0
  for _, o in ipairs(opts) do total = total + o[2] end
  if total == 0 then return end
  local r = rng() * total
  for _, o in ipairs(opts) do
    r = r - o[2]
    if r <= 0 then
      if o[1] == 'bird' then return self:spawn_bird(x, y, zone)
      elseif o[1] == 'cat' then return self:spawn_cat(x, y, zone)
      elseif o[1] == 'dog' then return self:spawn_dog(x, y, zone)
      else return self:spawn_owner(x, y, zone) end
    end
  end
end

-- ------------------------------------------------------------------ comportamiento
local DIRS = { { 1, 0, 'right' }, { -1, 0, 'left' }, { 0, 1, 'down' }, { 0, -1, 'up' } }

-- mueve al animal; false si lo bloqueó algo en el eje pedido
local function step(self, a, vx, vy, dt)
  local w = self.w
  local mx, my = Collision.move(a.body, vx * dt, vy * dt, w.map, w.blockers)
  a.x, a.y = a.body.x, a.body.y
  if vx ~= 0 then a.left = vx < 0 end
  return not ((vx ~= 0 and not mx) or (vy ~= 0 and not my))
end

-- ¿puede pasear hacia allí? (acera, parque o playa; la calzada solo al huir)
local function can_stroll(self, a, dx, dy)
  local z = zone_at(self.w, a.x + dx * 9, a.y + dy * 9)
  return WALKABLE[z] == true
end

local function pick_dir(self, a)
  local rng = self.rng
  local start = math.floor(rng() * 4)
  for i = 0, 3 do
    local d = DIRS[(start + i) % 4 + 1]
    if can_stroll(self, a, d[1], d[2]) then return d end
  end
  return nil
end

local function update_cat(self, a, dt, d)
  local pb = self.w.player.body
  local rng = self.rng
  a.anim = a.anim + dt
  a.pet_t = math.max(0, (a.pet_t or 0) - dt)
  if not a.tame and d < 40 and a.state ~= 'flee' then
    a.state, a.t, a.rot = 'flee', 1.3, 0
  end
  local vx, vy = 0, 0
  if a.state == 'flee' then
    local dx, dy = a.x - pb.x, a.y - pb.y
    local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
    local ang = math.atan2(dy, dx) + (a.rot or 0)
    vx, vy = math.cos(ang) * 62, math.sin(ang) * 62
    if not step(self, a, vx, vy, dt) then a.rot = ((a.rot or 0) + 0.9) % (math.pi * 2) end
    a.t = a.t - dt
    if a.t <= 0 and len > 70 then a.state, a.t = 'idle', 2 + rng() * 3 end
    return
  end
  a.t = a.t - dt
  if a.state == 'walk' then
    if not (step(self, a, a.dir[1] * 16, a.dir[2] * 16, dt) and can_stroll(self, a, a.dir[1], a.dir[2])) then a.t = 0 end
    if a.t <= 0 then a.state, a.t = 'idle', 1.5 + rng() * 4 end
  elseif a.t <= 0 then
    local dir = rng() < 0.55 and pick_dir(self, a) or nil
    if dir then a.state, a.dir, a.t = 'walk', dir, 0.8 + rng() * 1.8
    else a.state, a.t, a.sleepy = 'idle', 2 + rng() * 5, rng() < 0.35 end
  end
end

local function update_owner(self, o, dt)
  local rng = self.rng
  o.anim = o.anim + dt
  o.t = o.t - dt
  o.moving = false
  if o.state == 'walk' then
    local ok = step(self, o, o.dir[1] * 22, o.dir[2] * 22, dt) and can_stroll(self, o, o.dir[1], o.dir[2])
    o.moving = true
    if not ok or o.t <= 0 then
      o.state, o.t, o.moving = 'pause', 0.8 + rng() * 2.5, false
      o.stuck = (o.stuck or 0) + (ok and 0 or 1)
    end
  elseif o.t <= 0 then
    local dir = pick_dir(self, o)
    if dir then
      o.state, o.dir, o.t = 'walk', dir, 2 + rng() * 4
      o.facing = dir[3]
    else
      o.t = 1
      o.stuck = (o.stuck or 0) + 1
    end
  end
  if o.dir then o.facing = o.state == 'walk' and o.dir[3] or o.facing end
end

local function update_dog(self, a, dt, d)
  local pb = self.w.player.body
  local rng = self.rng
  a.anim = a.anim + dt
  a.pet_t = math.max(0, (a.pet_t or 0) - dt)
  a.bark_t = math.max(0, (a.bark_t or 0) - dt)
  local o = a.owner
  if o then   -- con correa: va un poco por detrás del dueño y se sienta cuando él para
    local tx, ty = o.x, o.y
    if o.dir then tx, ty = o.x - o.dir[1] * 12, o.y - o.dir[2] * 12 + 2 end
    local dx, dy = tx - a.x, ty - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 5 then
      local sp = math.min(46, 14 + len * 3)
      step(self, a, dx / len * sp, dy / len * sp, dt)
      a.state = 'walk'
    else
      a.state = o.state == 'pause' and 'idle' or 'walk'
    end
    if len > 80 then a.body.x, a.body.y = o.x, o.y; a.x, a.y = o.x, o.y end   -- atascado: junto al dueño
    return
  end
  if d < 46 and a.bark_t <= 0 then
    a.state, a.t, a.bark_t = 'bark', 0.6, 5 + rng() * 4
    if d < 34 then self.w:popup('Guau!', 'stat', a.x, a.y - 14) end
  end
  a.t = a.t - dt
  if a.state == 'walk' then
    local hx, hy = a.home[1] - a.x, a.home[2] - a.y
    if hx * hx + hy * hy > 48 * 48 then a.dir = { hx > 0 and 1 or -1, hy > 0 and 1 or -1 } end
    step(self, a, a.dir[1] * 20, a.dir[2] * 20, dt)
    if a.t <= 0 then a.state, a.t = 'idle', 2 + rng() * 4 end
  elseif a.t <= 0 then
    if rng() < 0.5 then a.state, a.t, a.dir = 'walk', 0.8 + rng() * 1.5, { rng() < 0.5 and 1 or -1, rng() < 0.5 and 1 or -1 }
    else a.state, a.t = 'idle', 2 + rng() * 4 end
  end
end

local function update_bird(self, a, dt, d)
  local w = self.w
  local pb = w.player.body
  local rng = self.rng
  a.anim = a.anim + dt
  if a.state == 'fly' then
    a.life = a.life - dt
    a.z = math.min(34, a.z + 42 * dt)
    a.x, a.y = a.x + a.vx * dt, a.y + a.vy * dt
    a.body.x, a.body.y = a.x, a.y
    a.dead = a.life <= 0
    return
  end
  local scared = d < 42 or (w.honk_t and w.honk_t > 0 and d < 90)
  if scared then
    local dx, dy = a.x - pb.x, a.y - pb.y
    local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
    a.state, a.life = 'fly', 3.5
    a.vx, a.vy = dx / len * 46 + (rng() - 0.5) * 20, dy / len * 28 - 12
    a.left = a.vx < 0
    return
  end
  a.hop_t = a.hop_t - dt
  if a.z > 0 then a.z = math.max(0, a.z - 30 * dt) end
  if a.hop_t <= 0 then   -- saltito a otro punto del suelo
    a.hop_t = 1.5 + rng() * 4
    local ang = rng() * math.pi * 2
    local nx, ny = a.x + math.cos(ang) * 7, a.y + math.sin(ang) * 5
    local hop_zone = zone_at(w, nx, ny)
    if (WALKABLE[hop_zone] or hop_zone == 'mountain') and Collision.fits(a.body, nx, ny, w.map, w.blockers) then
      a.body.x, a.body.y = nx, ny
      a.x, a.y, a.z, a.left = nx, ny, 3, math.cos(ang) < 0
    end
  end
end

-- ------------------------------------------------------------------ bucle
function Fauna:update(dt)
  local w = self.w
  local pb = w.player.body
  self.t = self.t + dt
  self.spawn_t = self.spawn_t - dt
  if self.spawn_t <= 0 then
    self.spawn_t = TICK
    self:try_spawn()
  end
  local keep2 = Fauna.KEEP ^ 2
  for i = #self.list, 1, -1 do
    local a = self.list[i]
    local d2 = dist2(a.x, a.y, pb.x, pb.y)
    local drop = d2 > keep2 or a.dead or (a.cls == 'owner' and (a.stuck or 0) > 6)
    if not drop then
      local d = math.sqrt(d2)
      if a.cls == 'cat' then update_cat(self, a, dt, d)
      elseif a.cls == 'owner' then update_owner(self, a, dt)
      elseif a.cls == 'dog' then update_dog(self, a, dt, d)
      else update_bird(self, a, dt, d) end
    end
    if drop or a.dead then
      if a.owner and a.owner.dog == a then a.owner.dog = nil end
      table.remove(self.list, i)
    end
  end
  -- dueños sin perro o perros huérfanos: se van juntos
  for i = #self.list, 1, -1 do
    local a = self.list[i]
    if (a.cls == 'owner' and not a.dog) or (a.cls == 'dog' and a.owner and a.owner.dead) then
      a.dead = true
    end
  end
  -- salvajes: descargar los lejanos y los muertos hace rato
  local en = w.enemies
  for i = #en, 1, -1 do
    local e = en[i]
    if e.fauna and ((e.state == 'dead' and e.t > 2.5) or dist2(e.body.x, e.body.y, pb.x, pb.y) > keep2) then
      table.remove(en, i)
    end
  end
end

-- ------------------------------------------------------------------ interacción: acariciar gatos mansos y perros
local function nearest_pettable(self, fx, fy)
  local best, bd = nil, 15 * 15
  for _, a in ipairs(self.list) do
    if (a.cls == 'dog' or (a.cls == 'cat' and a.tame)) then
      local d = dist2(a.x, a.y - 2, fx, fy)
      if d < bd then best, bd = a, d end
    end
  end
  return best
end

function Fauna:can_interact(fx, fy) return nearest_pettable(self, fx, fy) ~= nil end

function Fauna:interact(fx, fy)
  local a = nearest_pettable(self, fx, fy)
  if not a then return false end
  local w = self.w
  if (a.pet_t or 0) > 0 then
    w.hud:toast(a.cls == 'cat' and 'El gat ja està content.' or 'El gos ja està content.', 1.5)
    return true
  end
  a.pet_t = 30
  local st = w.state
  if st.max_mp and (st.mp or 0) < st.max_mp then st.mp = math.min(st.max_mp, (st.mp or 0) + 1) end
  w.fx:preset('sparkle', a.x, a.y - 10, 6, { color = { 1, 0.45, 0.55 } })
  w:popup('+1 MP', 'stat', a.x, a.y - 14)
  w.hud:toast(a.cls == 'cat' and 'El gat fa ronron.' or 'El gos et llepa la mà!', 2)
  if a.cls == 'dog' then a.state, a.t = 'bark', 0.5 end
  if a.cls == 'cat' then a.state, a.t = 'idle', 4 end
  return true
end

-- botín de los salvajes (la recompensa de XP/monedas ya la da World:enemy_event)
Fauna.DROPS = { boar = { 'carn_senglar', 0.6 }, wolf = { 'botiqui', 0.35 } }

function Fauna.on_kill(w, e)
  local kind
  for name, k in pairs(Enemy.KINDS) do if k == e.kind then kind = name end end
  local d = kind and Fauna.DROPS[kind]
  if d and math.random() < d[2] then
    local st = w.state
    st.inventory[d[1]] = (st.inventory[d[1]] or 0) + 1
    local def = w.game.items and w.game.items[d[1]]
    w.hud:toast('Botí: ' .. (def and def.name or d[1]), 2)
  end
end

-- ------------------------------------------------------------------ dibujo
local function frame_of(a)
  if a.cls == 'cat' then
    if a.state == 'flee' or a.state == 'walk' then return math.floor(a.anim * (a.state == 'flee' and 12 or 6)) % 2 + 1 end
    return a.sleepy and 4 or 3
  elseif a.cls == 'dog' then
    if a.state == 'bark' then return 4 end
    if a.state == 'walk' then return math.floor(a.anim * 8) % 2 + 1 end
    return 3
  else
    if a.state == 'fly' then return math.floor(a.anim * 14) % 2 + 5 end
    return (math.floor(a.anim * 2.5) % 2 == 0) and 1 or 2
  end
end
Fauna.frame_of = frame_of

-- add(y, fn): cola de dibujo ordenada de la escena; shadow y draw_ped son los de world_scene
function Fauna:draw(add_fn, ox, oy, shadow, draw_ped)
  local w = self.w
  local sprites = w.game.sprites
  for _, a in ipairs(self.list) do
    if w.cam:visible(a.x - 8, a.y - 24 - a.z, 16, 32) then
      if a.cls == 'owner' then
        local sh = sprites.chars[a.sprite]
        if sh then
          add_fn(a.y + 4, function()
            shadow(a.x - ox, a.y + 3 - oy, 5, 2)
            draw_ped(sh, a, ox, oy)
          end)
        end
      else
        local sh = sprites.animals[a.coat]
        if sh then
          local flying = a.cls == 'bird' and a.state == 'fly'
          local alpha = (flying and a.life < 1) and math.max(0, a.life) or 1
          add_fn(a.y + 4 + (flying and 20 or 0), function()
            shadow(a.x - ox, a.y + 3 - oy, a.cls == 'bird' and 3 or 5, a.cls == 'bird' and 1.2 or 2, 0.25 * alpha)
            love.graphics.setColor(1, 1, 1, alpha)
            if a.cls == 'dog' and a.owner then   -- correa
              love.graphics.setColor(0.42, 0.28, 0.18, 1)
              love.graphics.line(math.floor(a.owner.x - ox) + 0.5, math.floor(a.owner.y - 8 - oy) + 0.5,
                                 math.floor(a.x - ox) + 0.5, math.floor(a.y - 5 - oy) + 0.5)
              love.graphics.setColor(1, 1, 1, 1)
            end
            local breath=(a.state~='walk' and a.state~='fly' and a.state~='flee') and require('src.motion').bob(a.anim*1.5,.55) or 0
            love.graphics.draw(sh.img, sh.quads[frame_of(a)], math.floor(a.x + 0.5) - ox,
                               math.floor(a.y + 4 - a.z + 0.5) - oy, 0, a.left and 1 or -1, (16-breath)/16, 8, 16)
            love.graphics.setColor(1, 1, 1, 1)
          end)
        end
      end
    end
  end
end

return Fauna
