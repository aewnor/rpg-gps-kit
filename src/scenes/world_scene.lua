-- Escena de mundo (exterior o cueva): coordina mapa, entidades, interacción, triggers y dibujo.
local Player = require('src.entities.player')
local NPC = require('src.entities.npc')
local Enemy = require('src.entities.enemy')
local Traffic = require('src.systems.traffic')
local Trains = require('src.systems.trains')
local Pedestrians = require('src.systems.pedestrians')
local Quests = require('src.systems.quests')
local State = require('src.state')
local Camera = require('src.camera')
local Dialogue = require('src.ui.dialogue')
local Hud = require('src.ui.hud')
local Collision = require('src.world.collision')
local Particles = require('src.fx.particles')
local Popups = require('src.fx.popups')
local Shake = require('src.fx.shake')
local Town = require('src.systems.town')
local Dragon = require('src.entities.dragon')
local Projectiles = require('src.systems.projectiles')
local Magic = require('src.systems.magic')

local World = {}
World.__index = World

local function overlap(a, b)
  return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

local function point_in(px, py, r) return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h end

-- game: contexto global (assets, datos, estado, audio); spawn = {x, y, level, facing}
function World.new(game, scene_id, spawn)
  local self = setmetatable({}, World)
  self.game = game
  self.id = scene_id
  self.def = game.scenes[scene_id]
  self.map = game:get_map(scene_id)
  self.state = game.state
  self.sstate = State.scene(self.state, scene_id)
  self.cam = Camera.new(320, 240)
  self.player = Player.new(spawn.x, spawn.y, spawn.level or 0, game.world.player, game.sprites.player)
  self.player.facing = spawn.facing or 'down'
  self.dialogue = Dialogue.new(game.font, function(n) game.audio.play(n) end)
  self.hud = game.hud
  self.blockers = {}
  self.npcs, self.enemies, self.chests, self.levers, self.gates, self.doors = {}, {}, {}, {}, {}, {}
  self.triggers, self.landmarks, self.signs = {}, {}, {}
  self.parked, self.stops = {}, {}
  self.torches, self.pickups = {}, {}
  self.arcades = {}      -- màquines i aparells dels minijocs (interiors dels POIs)
  self.signboards, self.props = {}, {}   -- rètols dels edificis especials i bústies, carros (fase 6)
  self.shots = Projectiles.new()         -- encanteris del jugador i foc del drac (fase 6)
  self.spots = {}                        -- llocs amb nom (Cova de Roda, Cau del Drac): missions
  self.inside = {}       -- triggers en los que está el jugador (exigir salida antes de reactivar)
  self.fx = Particles.new(320, love.math.random)   -- partículas con tope fijo (src/fx/particles.lua)
  self.popups = Popups.new()                        -- números flotantes (+20 XP, +4 HP…)
  self.shaker = Shake.new(love.math.random)         -- sacudida de cámara (golpes, tren al lado)
  self.look_x, self.look_y = 0, 0
  require('src.systems.puzzles').init(self)          -- blocs, plaques, runes, brasers i parets secretes
  local seed = 1
  for _, o in ipairs(self.map.objects) do
    local t = o.type
    if t == 'npc' or t == 'service' then   -- 'service': personaje de un servicio (data/services.json)
      seed = seed + 1
      local spr = game.sprites.chars[o.props.sprite] or game.sprites.player
      self.npcs[#self.npcs + 1] = NPC.new(o, spr, seed)
      if t=='service' then
        local names={'barrel','crate','flowers','amphora','lantern','mushrooms'}
        local px,py=o.x+20,o.y
        if Collision.walk_at(self.map:cell(math.floor(px/16),math.floor(py/16)),0) then
          self.props[#self.props+1]={x=px,y=py,props={sprite='prop_'..names[seed%#names+1]}}
        end
      end
    elseif t == 'enemy' then
      if not (o.props.room and self.sstate.defeated[o.name]) then
        local k = o.props.kind or 'boar'
        self.enemies[#self.enemies + 1] = Enemy.new(o, game.sprites.enemies[k])
      end
    elseif t == 'chest' then
      if not o.props.item then o.props.tier=require('src.motion').chest_tier(o.props.tier or 'wood',o.props.flag or o.name) end
      self.chests[#self.chests + 1] = { obj = o, rect = { x = o.x, y = o.y, w = 16, h = 16 } }
    elseif t == 'lever' then
      self.levers[#self.levers + 1] = { obj = o, rect = { x = o.x, y = o.y + 6, w = 16, h = 10 } }
    elseif t == 'gate' then
      self.gates[#self.gates + 1] = { obj = o, rect = { x = o.x, y = o.y, w = o.w, h = o.h } }
    elseif t == 'door' then
      self.doors[#self.doors + 1] = { obj = o, rect = { x = o.x, y = o.y, w = o.w, h = o.h } }
    elseif t == 'trigger' or t == 'room' then
      self.triggers[#self.triggers + 1] = { obj = o, rect = { x = o.x, y = o.y, w = o.w, h = o.h } }
    elseif t == 'landmark' then
      self.landmarks[#self.landmarks + 1] = { obj = o, img = game.sprites.landmarks[o.props.sprite] }
    elseif t == 'sign' then
      self.signs[#self.signs + 1] = o
    elseif t == 'pickup' then
      self.pickups[#self.pickups + 1] = { name = o.name, x = o.x, y = o.y, item = o.props.item }
    elseif t == 'signboard' then
      self.signboards[#self.signboards + 1] = o
    elseif t == 'boss' then
      if not State.flag(self.state, o.props.flag or 'drac_vencut') then
        self.boss = Dragon.new(o, love.math.random)
        self.enemies[#self.enemies + 1] = self.boss
      end
    elseif t == 'spot' then
      self.spots[o.name] = o
    elseif t == 'prop' then
      self.props[#self.props + 1] = o
    elseif t == 'arcade' then
      self.arcades[#self.arcades + 1] = { obj = o, rect = { x = o.x, y = o.y, w = o.w or 16, h = o.h or 16 } }
    elseif t == 'torch' then
      self.torches[#self.torches + 1] = { x = o.x, y = o.y }
    elseif t == 'parked_car' then
      self.parked[#self.parked + 1] = { x = o.x, y = o.y, color = o.props.color or 1, rev = (o.id or 0) % 2 == 0,
                                        orient = o.props.orient == 'h' and 'h' or 'v' }
    elseif t == 'bus_stop' then
      self.stops[#self.stops + 1] = { x = o.x, y = o.y, name = o.name, label = o.props.label or o.name }
    elseif require('src.systems.puzzles').load(self, o) then   -- puzles de les masmorres
    end
  end
  require('src.systems.rest').attach(self)   -- botiquines de pared, camas y neveras de objetos del mapa
  self:refresh_locals()                        -- locals reals sense verificar: amagats (config del servidor)
  -- la casa (solo si está configurada y es válida)
  if game.home and game.home.scene == scene_id then
    self.home = game.home
    if game.house then self:find_house_door() end
  end
  if self.def.traffic then
    self.traffic = Traffic.new(self.map, game.world.cars, love.math.newRandomGenerator(7))
    self.traffic:spawn(spawn.x, spawn.y)
    self.trains = Trains.new(self.map, game.world.trains)
    if #self.map:objects_of('sailboat') > 0 then self.sailboats = require('src.systems.sailboats').new(self.map) end
    self.peds = Pedestrians.new(self.traffic, love.math.random)
    self.fauna = require('src.systems.fauna').new(self, love.math.random)   -- perros, gatos, pájaros y salvajes
    -- dirección de la calle en cada paso a nivel (para dibujar las barreras atravesándola)
    for _, cr in ipairs(self.trains.crossings) do
      local best = 40
      for _, r in ipairs(self.traffic.routes) do
        local s, d = r:project(cr.x, cr.y)
        if d < best then best = d; local _, _, ang = r:at(s); cr.road_ang = ang end
      end
      if not cr.road_ang then   -- calle sin tráfico: perpendicular a la vía
        for l, s in pairs(cr.lines) do local _, _, ang = l.route:at(s); cr.road_ang = ang + math.pi / 2; break end
      end
    end
  end
  -- los triggers donde aparece el jugador no se disparan hasta que salga
  for _, d in ipairs(self.doors) do
    if point_in(spawn.x, spawn.y, d.rect) then self.inside[d] = true end
  end
  for _, tr in ipairs(self.triggers) do
    if point_in(spawn.x, spawn.y, tr.rect) then self.inside[tr] = true end
  end
  -- Olaf, el gato acompañante (src/entities/follower.lua): aparece detrás del jugador en cada escena
  local olaf_away = self.state.quests and self.state.quests.olaf_away   -- missió: l'Olaf t'espera al parc
  if self.state.olaf ~= false and not olaf_away and game.sprites.chars.npc_cat_grey then
    self.olaf = require('src.entities.follower').new('Olaf', game.sprites.chars.npc_cat_grey, spawn.x, spawn.y, 20)
    local map = self.map
    self.olaf.walkable = function(x, y)
      local tx, ty = math.floor(x / 16), math.floor(y / 16)
      return map:in_bounds(tx, ty) and Collision.walk_at(map:cell(tx, ty), 0)
    end
    self.olaf:place(spawn.x, spawn.y, self.player.facing)
  end
  self.cam:follow(self.player.body.x, self.player.body.y - 8, self.map.width * 16, self.map.height * 16)
  -- vida del poble: amics i avis del perfil, horaris, semàfors, reciclatge, missions (src/systems/town.lua)
  Town.attach(self)
  require('src.systems.companion').attach(self)   -- l'amic que t'acompanya en una missió
  require('src.systems.crafting').attach(self)    -- arbres tallats i roques trencades (fins que tornen a créixer)
  require('src.systems.farm').attach(self)        -- granges: animals i pagesos
  require('src.systems.perles').setup(self)     -- les 7 Perles del Drac (data/perles.json)
  return self
end

local OLAF_SAYS = { 'Miau!', 'Prrrr... (l\'Olaf es frega contra la teva cama)', 'Miau? (sembla que té gana)',
                    '(L\'Olaf mira una papallona i fa uns ulls com taronges)', 'Mrrrau! (vol que continueu l\'aventura)' }

-- ---------------------------------------------------------------- efectos (polvo, chispas, sacudida)
-- ráfaga radial de partículas en coordenadas de mundo (ver src/fx/particles.lua)
function World:puff(x, y, n, col, speed, life, size)
  self.fx:burst(x, y, n, col, speed, life, size)
end

function World:popup(text, kind, x, y)
  local b = self.player.body
  self.popups:add(x or b.x, y or b.y, text, kind)
end

function World:update_particles(dt)
  for _,c in ipairs(self.chests) do if c.open_t then c.open_t=math.min(1,c.open_t+dt) end end
  self.fx:update(dt)
  self.popups:update(dt)
  self.shaker:update(dt)
end

function World:draw_particles(ox, oy)
  self.fx:draw(ox, oy)
end

-- nombre del tile de una capa (data/tiles.json) en la casilla (tx, ty)
function World:tile_name(layer, tx, ty)
  local g = self.game
  if not g.tile_names then
    g.tile_names = {}
    for name, t in pairs(g.tile_defs) do g.tile_names[t.id + 1] = name end
  end
  return g.tile_names[self.map:tile_at(layer, tx, ty)]
end

-- efectos de ambiente: hojas que caen en parques y jardines visibles; derrapes con vehículo
local LEAFY = { g_park_0 = true, g_park_1 = true, g_park_2 = true, g_flowers_0 = true, g_flowers_1 = true,
                g_flowers_2 = true }
-- temps (src/systems/weather.lua): el fixa config/joc.json o canvia sol cada 6 h de joc; quan plou el
-- protagonista es posa el xubasquer (només amb l'avatar del perfil) i se'l treu a dins; l'Armadura del Drac
-- (src/systems/perles.lua) també es veu al personatge
local WEATHER_TOAST = {
  pluja = 'Comença a ploure: et poses el xubasquer', tempesta = 'Tempesta! Llamps i trons: xubasquer posat',
  neu = 'Neva! Tot es posa blanc', boira = 'Hi ha boira: no es veu gaire lluny', vent = 'Bufa molt de vent',
  nuvol = 'S\'ha ennuvolat', sol = 'Torna a sortir el sol',
}
function World:update_weather(dt)
  local g = self.game
  local Weather = require('src.systems.weather')
  g.weather = g.weather or Weather.new()
  local wx = g.weather
  if self.def.outdoor then
    local was = wx.kind
    if wx:update(dt, Weather.pick(self.state, g.config and g.config.temps), true) and wx.kind ~= was
        and not (was == 'sol' and wx.kind == 'nuvol') then
      self.hud:toast(WEATHER_TOAST[wx.kind] or Weather.NAMES[wx.kind], 2.5)
    end
    if wx.thunder then wx.thunder = nil; g.audio.play('thunder') end
  end
  if g.renderer then   -- neu a terra i a les teulades, i arbres que es mouen més de pressa amb vent
    g.renderer.snow = self.def.outdoor and (wx.snow or 0) or 0
    g.renderer.wind_fps = (wx.kind == 'vent' or wx.kind == 'tempesta') and wx.level > 0.3 and 7 or 3
  end
  self:update_raincoat(self.def.outdoor and wx:is_wet())
end

function World:update_raincoat(wet)
  local g = self.game
  if self.state.skin ~= 'avatar' or not g.profile or not g.profile.avatar then return end
  local Looks = require('src.paperdoll.looks')
  local look = g.profile.avatar
  if self.state.equipment and self.state.equipment.armor == 'armadura_drac' then look = Looks.dragon(look) end
  if wet then look = Looks.raincoat(look) end
  local v = self.player.vehicle   -- casc sempre que va en vehicle (el cotxe no: va tancat)
  if v and v.id ~= 'cotxe' then look = Looks.helmet(look, v.id == 'cavall') end
  if Looks.key(look) ~= g.avatar_key then g:apply_avatar(look) end
end

function World:ambient_fx(dt)
  if not self.def.outdoor then return end
  self.leaf_t = (self.leaf_t or 0) + dt
  if self.leaf_t >= 0.16 then
    self.leaf_t = 0
    local cx, cy = self.cam:draw_offset()
    local rng = love.math.random
    for _ = 1, 3 do   -- probar unas pocas casillas al azar (barato) y soltar una hoja si es parque
      local tx, ty = math.floor((cx + rng() * 320) / 16), math.floor((cy + rng() * 240) / 16)
      if self.map:in_bounds(tx, ty) and LEAFY[self:tile_name('ground', tx, ty)] then
        self.fx:preset('leaf', tx * 16 + rng() * 16, ty * 16 - 14 - rng() * 10, 1)
        break
      end
    end
  end
  local v = self.player.vehicle
  if v and v.skid and v.speed > 40 then
    self.skid_t = (self.skid_t or 0) - dt
    if self.skid_t <= 0 then
      self.skid_t = 0.04
      local b = self.player.body
      local bx, by = b.x - math.cos(v.angle) * 8, b.y + 3 - math.sin(v.angle) * 4
      self.fx:preset(v.id == 'motocross' and 'skid' or 'dust', bx, by, 2, { dir = v.angle + math.pi, spread = 1.4 })
      if not self.skid_sound then self.skid_sound = true; self.game.audio.play('skid') end
    end
  else
    self.skid_sound = nil
  end
end

-- sombra suave bajo los pies (personajes, enemigos)
local function shadow(x, y, rx, ry, a)
  love.graphics.setColor(0.10, 0.08, 0.12, a or 0.28)
  love.graphics.ellipse('fill', math.floor(x + 0.5), math.floor(y + 0.5), rx, ry)
end

-- piscina municipal (decorate_map la deja transitable): se nada más lento, medio sumergido; en bici o
-- patinete no se entra (vuelve al último sitio seco)
function World:update_swim()
  local pl = self.player
  local b = pl.body
  local tx, ty = math.floor(b.x / 16), math.floor(b.y / 16)
  local gname = self:tile_name('ground', tx, ty) or ''
  local sea = gname:sub(1, 4) == 'sea_'           -- l'aigua de vora la platja (decorate_map.sea_swim)
  local wet = self.def.outdoor and b.level == 0 and not pl.in_boat and (gname:sub(1, 5) == 'pool_' or sea)
  if wet and pl.vehicle and not pl.in_boat then
    if self.dry_pos then b.x, b.y = self.dry_pos[1], self.dry_pos[2] end
    self.hud:toast(sea and 'Amb vehicle no es pot entrar al mar!' or 'Amb vehicle no es pot entrar a la piscina!', 1.5)
    wet = false
  end
  if wet and sea then   -- banderes de la platja (src/systems/beach.lua)
    local flag = require('src.systems.beach').flag(self.game.weather)
    if flag == 'red' then
      if self.dry_pos then b.x, b.y = self.dry_pos[1], self.dry_pos[2] end
      local now = love.timer.getTime()
      if not self.red_told or now - self.red_told > 3 then
        self.red_told = now
        self.hud:toast('Bandera vermella! Avui no es pot banyar al mar.', 2.5, true)
        self.game.audio.play('miss')
      end
      wet = false
    elseif flag == 'yellow' and not pl.swimming and not self.yellow_told then
      self.yellow_told = true
      self.hud:toast('Bandera groga: banya\'t amb compte, a prop de la sorra.', 2.5)
    end
  end
  if not wet then self.dry_pos = { b.x, b.y } end
  if wet and not pl.swimming then
    self.game.audio.play('splash')
    self:puff(b.x, b.y + 2, 6, { 0.8, 0.93, 1 }, 18, 0.5, 3)
    if sea and not self.sea_told then
      self.sea_told = true
      self.hud:toast('A l\'aigua! Bandera verda: nedes al mar', 2.5)
    elseif not sea and not self.swim_told then
      self.swim_told = true
      self.hud:toast('A l\'aigua! Nedes a la piscina municipal', 2.5)
    end
  end
  pl.swimming = wet or nil
end

-- polvo al pisar (exteriores y cuevas, no en el agua ni en los puentes)
function World:footsteps()
  local pl = self.player
  if pl.swimming then
    local col = pl:step_frame()
    if col ~= self.last_step and col == 0 then self.game.audio.play('swim') end
    self.last_step = col
    return
  end
  local col = pl:step_frame()
  if col ~= self.last_step and (col == 0 or col == 2) and pl.body.level == 0 then
    local b = pl.body
    local dust = self.def.outdoor and { 0.84, 0.78, 0.66 } or { 0.55, 0.48, 0.40 }
    self:puff(b.x + (col == 0 and -3 or 3), b.y + 3, pl.bike and 3 or 2, dust, pl.bike and 16 or 9, 0.3, 2)
    if not pl.vehicle then self.game.audio.step(self:step_surface()) end
  end
  self.last_step = col
end

-- números de vida: cualquier cambio de HP (golpe, comida, médico, subir de nivel) sale sobre el jugador
function World:hp_popups()
  local hp = self.state.hp
  if self.hp_seen and hp ~= self.hp_seen and hp > 0 then
    local d = hp - self.hp_seen
    self:popup((d > 0 and '+' or '') .. d .. ' HP', d > 0 and 'hp' or 'hurt')
    if d > 0 then self.fx:preset('sparkle', self.player.body.x, self.player.body.y - 12, 4, { color = { 0.6, 1, 0.6 } }) end
  end
  self.hp_seen = hp
end

-- tren en marcha cerca: chispas en las ruedas, retumbo (sacudida continua) y ruido de rodadura
function World:train_fx(dt)
  local b = self.player.body
  local near = math.huge
  local cx, cy = self.cam:draw_offset()
  cx, cy = cx + 160, cy + 120
  self.spark_t = (self.spark_t or 0) - dt
  local spark = self.spark_t <= 0
  if spark then self.spark_t = 0.05 end
  for _, tr in ipairs(self.trains.current or {}) do
    local l = tr.line
    local fast = l.consist.kind == 'hs'
    for k = 0, 4 do    -- cabeza, cola y puntos intermedios del tren
      local s = tr.head - tr.dir * l.len * k / 4
      if s >= 0 and s <= l.route.length then
        local x, y, _, level = l.route:at(s)
        local d = math.sqrt((x - b.x) ^ 2 + (y - b.y) ^ 2)
        if (level or 0) >= (b.level or 0) - 1 then near = math.min(near, fast and d * 0.7 or d) end
        if spark and not tr.dwell and (x - cx) ^ 2 + (y - cy) ^ 2 < 200 ^ 2 and love.math.random() < (fast and 0.6 or 0.25) then
          self.fx:preset('spark', x + love.math.random(-6, 6), y + 5, fast and 3 or 2)
        end
      end
    end
  end
  local r = near < 120 and (1 - near / 120) or 0
  if r > 0 then self.shaker:set_rumble(r * 0.55) end
  self.game.audio.rumble(r)
end

-- superficie bajo los pies para el sonido de los pasos: asfalto, hierba, tierra, arena, madera (interiores)
function World:step_surface()
  if not self.def.outdoor then return self.def.dark and 'dirt' or 'wood' end
  local b = self.player.body
  local tx, ty = math.floor(b.x / 16), math.floor(b.y / 16)
  local name = self:tile_name('ground', tx, ty) or ''
  if name:find('sand') or name:find('beach') then return 'sand' end
  local _, surf = self.map:height_at(tx, ty)
  if surf == 1 or surf == 3 then return 'asphalt' end
  if surf == 2 then return 'dirt' end
  return 'grass'
end

-- recompensa: experiencia y monedas; anuncia la subida de nivel (vida llena, +ataque, +defensa)
function World:reward(xp, coins, why)
  local Rpg = require('src.systems.rpg')
  local st = self.state
  if coins and coins > 0 then Rpg.earn(st, coins) end
  local ups = Rpg.add_xp(st, xp or 0)
  if xp and xp > 0 then self:popup('+' .. xp .. ' XP', 'xp') end
  if coins and coins > 0 then self:popup('+' .. coins .. ' mon.', 'coins'); self.game.audio.play('coin') end
  if why then
    self.hud:toast(string.format('%s  +%d XP%s', why, xp or 0, (coins and coins > 0) and ('  +' .. coins .. ' monedes') or ''), 2)
  end
  if ups > 0 then
    self.hud:toast('Nivell ' .. st.char_level .. '! Més força, defensa i màgia', 3)
    local Magic = require('src.systems.magic')
    for _, sp in ipairs(Magic.SPELLS) do   -- encanteri nou a l'arbre
      if sp.level == st.char_level and Magic.unlocked(st, sp.id) then self.hud:toast('Nou encanteri: ' .. sp.name, 3) end
    end
    self.game.audio.play('levelup')
    local b = self.player.body
    self.fx:preset('levelup', b.x, b.y - 10, 16)
    self.fx:preset('confetti', b.x, b.y - 14, 18)
    self:popup('NIVELL ' .. st.char_level .. '!', 'stat')
    self.hp_seen = st.hp   -- la vida llena del nivell no fa un segon número
    Town.level_up(self)
  end
  return ups
end

-- efecto con volumen según la distancia al jugador (x, y opcionales: sin posición suena a tope)
-- resultat d'un cop a un enemic (espasa, encanteri o projectil): efectes, recompensa i, si és el drac, el final
function World:enemy_event(e, ev)
  if ev == 'dead' then
    require('src.systems.crafting').drop(self, e)   -- pell, cuir... (data/crafting.json)
    if e.room then self.sstate.defeated[e.name] = true end
    self:puff(e.body.x, e.body.y - 4, e.kind.boss and 30 or 10, { 0.93, 0.90, 0.82 }, 30, 0.5, 3)
    self.shaker:add(e.kind.boss and 0.8 or 0.25)
    if e.kind.boss then self:boss_defeated(e) else self:reward(e.kind.xp or 10, e.kind.coins or 0) end
    if e.fauna then require('src.systems.fauna').on_kill(self, e) end
  elseif ev == 'hit' then
    self.fx:preset('spark', e.body.x, e.body.y - (e.kind.boss and 20 or 6), 5, { color = { 1, 0.95, 0.7 } })
    self.shaker:add(0.15)
  end
  if ev then self:popup('-' .. (e.last_dmg or 1), 'dmg', e.body.x, e.body.y - (e.kind.boss and 24 or 0)) end
end

function World:boss_defeated(e)
  local st = self.state
  st.flags[e.flag or 'drac_vencut'] = true
  st.gems = (st.gems or 0) + (e.kind.gems or 0)
  State.give(st, 'corona_drac')
  self.shots:clear()
  self.boss = nil
  self.fx:preset('confetti', e.body.x, e.body.y - 20, 30)
  self:reward(e.kind.xp, e.kind.coins, 'Has vençut el Drac del cim!')
  Town.event(self, 'defeat', { target = 'boss:dragon' })
  self.dialogue:show('El Drac', { 'Grrr... D\'acord, d\'acord! Em rendeixo.',
    'Només volia un lloc tranquil per dormir... i el soroll del poble em despertava.',
    'Et prometo que no faré més llums estranyes a la muntanya. Té, la meva corona!' })
end

-- encanteri (tecla V): el que hi ha triat (Q/E per canviar-lo)
function World:cast_spell()
  local st, pl = self.state, self.player
  local MQ = require('src.systems.magic_quest')
  if Magic.has_staff(st, self.game.items) then     -- (el bastó sol no fa màgia: cal aprendre'n, src/systems/magic_quest.lua)
    local ok, why0 = MQ.can_cast(self)
    if not ok then self.hud:toast(why0, 3, true); return end
  end
  local out, why = Magic.cast(st, self.game.items, st.spell, pl.body.x, pl.body.y - 8, pl.facing)
  if not out then self.hud:toast(why, 1.5); return end
  MQ.on_cast(self)
  if out.heal then
    self.game.audio.play('heal')
    self.fx:preset('levelup', pl.body.x, pl.body.y - 10, 10)
    self:popup('+' .. out.heal, 'hp', pl.body.x, pl.body.y)
    self.hp_seen = st.hp
    return
  end
  if out.teleport then   -- Retorn a la plaça: només a l'aire lliure del poble
    local sp = self.id == 'overworld' and self.map:object('spawn', 'spawn_public_centre')
    if not sp then
      st.mp = st.mp + out.spell.mp
      self.hud:toast("Només funciona a l'aire lliure, al poble", 2); return
    end
    self.game.audio.play('spell')
    self.fx:preset('sparkle', pl.body.x, pl.body.y - 12, 10)
    if pl.vehicle then pl:dismount() end
    pl.body.x, pl.body.y, pl.body.level = sp.x, sp.y, 0
    if self.olaf then self.olaf.x, self.olaf.y = sp.x + 14, sp.y + 4 end
    self.fx:preset('sparkle', sp.x, sp.y - 12, 10)
    self.hud:toast("Pluf! Ets a la Plaça de l'Església", 2)
    return
  end
  if out.ward then
    self.game.audio.play('heal')
    self.fx:preset('levelup', pl.body.x, pl.body.y - 10, 8)
    self.hud:toast('Escut màgic: ' .. out.ward .. ' s sense mal', 2)
    return
  end
  if out.bolt then       -- Llamp: l'enemic viu més proper dins l'abast
    local best, bd
    for _, e in ipairs(self.enemies) do
      if e.state ~= 'dead' and e.damage then
        local d = math.sqrt((e.body.x - pl.body.x) ^ 2 + (e.body.y - pl.body.y) ^ 2)
        if d <= out.bolt.range and (not bd or d < bd) then best, bd = e, d end
      end
    end
    if not best then
      st.mp = st.mp + out.spell.mp
      self.hud:toast('Cap enemic a prop per al llamp', 1.5); return
    end
    local res = best:damage(out.bolt.dmg, pl.body.x, pl.body.y)
    self.bolts = self.bolts or {}
    self.bolts[#self.bolts + 1] = { x = best.body.x, y = best.body.y - 8, t0 = love.timer.getTime() }
    self.game.audio.play('spell')
    self.fx:preset('sparkle', best.body.x, best.body.y - 8, 8)
    self:enemy_event(best, res == 'dead' and 'dead' or 'hit')
    return
  end
  self.game.audio.play('spell')
  for _, sh in ipairs(out.shots) do self.shots:spawn(sh) end
  self.fx:preset('sparkle', pl.body.x, pl.body.y - 12, 6)
end

function World:sfx_at(name, x, y, range)
  local vol = 1
  if x then
    local b = self.player.body
    local d = math.sqrt((x - b.x) ^ 2 + (y - b.y) ^ 2)
    vol = 1 - d / (range or 260)
    if vol <= 0.05 then return end
  end
  self.game.audio.play(name, { vol = vol })
end

function World:ctx()
  local g = self.game
  self.sfx_fn = self.sfx_fn or function(n, x, y) self:sfx_at(n, x, y) end
  self.shoot_fn = self.shoot_fn or function(o) self.shots:spawn(o) end
  return { map = self.map, blockers = self.blockers, state = self.state, items = g.items,
           sfx = self.sfx_fn, player = self.player, outdoor = self.def.outdoor,
           toast = function(t) self.hud:toast(t, 2) end, shoot = self.shoot_fn }
end

function World:gate_open(g)
  local p = g.obj.props
  if p.key_flag and State.flag(self.state, p.key_flag) then return true end   -- oberta amb la clau
  if State.flag(self.state, 'solved_' .. tostring(self.id) .. '_' .. (g.obj.name or '')) then return true end   -- puzle de plaques resolt
  if p.open_key and not p.open_flag then return false end
  if p.open_flag then   -- un flag o diversos separats per comes (totes les plaques premudes)
    for f in tostring(p.open_flag):gmatch('[^,]+') do if not State.flag(self.state, f) then return false end end
    return true
  end
  if p.open_room_clear then
    for _, e in ipairs(self.enemies) do
      if e.room == p.open_room_clear and e.state ~= 'dead' then return false end
    end
    return true
  end
  return false
end

-- conducció guiada (src/systems/vehicles.lua Vehicles.assist): cotxes, peatons i personatges a menys de 120 px
function World:vehicle_obstacles(v)
  local b = self.player.body
  local out = v.obs or {}
  for i = #out, 1, -1 do out[i] = nil end
  local R2 = 120 * 120
  local level = b.level or 0
  if self.traffic then
    local Traffic = require('src.systems.traffic')
    for _, c in ipairs(self.traffic.cars) do
      if not c.decorative then
        local x, y, ang, lv = Traffic.pos(c)
        if lv == level and (x - b.x) ^ 2 + (y - b.y) ^ 2 < R2 then
          local k = Traffic.kind_of(c)
          out[#out + 1] = { x = x, y = y, r = math.min(k.w, k.h) / 2, kind = 'car', ang = ang, v = c.v or 0 }
        end
      end
    end
  end
  if self.peds then
    for _, p in ipairs(self.peds.list) do
      if (p.x - b.x) ^ 2 + (p.y - b.y) ^ 2 < R2 then out[#out + 1] = { x = p.x, y = p.y, r = 6, kind = 'ped' } end
    end
  end
  for _, n in ipairs(self.npcs) do
    local nb = n.body
    if nb and not n.hidden and (nb.x - b.x) ^ 2 + (nb.y - b.y) ^ 2 < R2 then
      out[#out + 1] = { x = nb.x, y = nb.y, r = 6, kind = 'ped' }
    end
  end
  v.obs = out
  -- eixos de les vies a prop (src/systems/roads.lua): la guia segueix la carretera, no la superfície
  v.lines = require('src.systems.roads').near(b.x, b.y, 40, v.lines)
end

function World:rebuild_blockers()
  local b = self.blockers
  for i = #b, 1, -1 do b[i] = nil end
  for _, n in ipairs(self.npcs) do if not n.hidden then b[#b + 1] = n.blocker end end
  for _, c in ipairs(self.chests) do b[#b + 1] = c.rect end
  for _, o in ipairs(self.props) do   -- xiringuitos i para-sols dels locals visibles (no són al mapa de col·lisions)
    if o.props.local_id and not o.hidden then
      o.rect = o.rect or (o.props.sprite == 'chiringuito' and { x = o.x - 24, y = o.y - 8, w = 48, h = 14 }
                          or { x = o.x - 3, y = o.y - 2, w = 6, h = 6 })
      b[#b + 1] = o.rect
    end
  end
  for _, l in ipairs(self.levers) do b[#b + 1] = l.rect end
  for _, g in ipairs(self.gates) do if not self:gate_open(g) then b[#b + 1] = g.rect end end
  require('src.systems.puzzles').blockers(self, b)
  if self.traffic then self.traffic:blockers(b) end
  if self.trains then self.trains:blockers(b) end
end

function World:say(key, after)
  local res = Quests.run(self.state, self.game.dialogue, self.game.items, key, self.game.world.pois)
  self.dialogue:show(res.name, res.pages, function()
    if res.toast then self.hud:toast(res.toast); self.game.audio.play('chest') end
    if res.xp or res.coins then self:reward(res.xp or 0, res.coins or 0) end
    self:check_notebook()
    if after then after() end
  end)
end

-- texto literal de zonas del editor: páginas separadas por '|'
function World:say_text(name, text, after)
  local pages = {}
  for p in (text .. '|'):gmatch('(.-)|') do if p ~= '' then pages[#pages + 1] = p end end
  if #pages == 0 then pages = { '...' } end
  self.dialogue:show(name ~= '' and name or nil, pages, after)
end

function World:check_notebook()
  local st = self.state
  if State.flag(st, 'has_notebook') and not State.flag(st, 'notebook_done') and
     Quests.remaining(st, self.game.world.pois) == 0 then
    State.set(st, 'notebook_done')
    self.hud:toast('Quadern complet!')
    self.game.audio.play('stamp')
  end
end

-- punto delante del jugador para interactuar
function World:front_point(d)
  local f = Player.DIRS[self.player.facing]
  return self.player.body.x + f[1] * (d or 12), self.player.body.y - 2 + f[2] * (d or 12)
end

function World:mount_horse(o)
  local pl = self.player
  pl.vehicle = require('src.systems.vehicles').new_state('cavall', pl.facing)
  pl.vehicle.skin = 'cavall_' .. o.props.sprite:sub(7)
  pl.bike, pl.body.no_stairs = true, true
  o.hidden = true
  self.horse_prop = o
  self.game.audio.play('neigh')
  if not self.horse_told then
    self.horse_told = true
    self.hud:toast('Puges al cavall! B per baixar-ne, H per fer-lo renillar', 3)
  end
end

-- en baixar del cavall (o entrar a un lloc tancat) el cavall es queda al costat
function World:update_horse()
  local o = self.horse_prop
  local pl = self.player
  if not o or (pl.vehicle and pl.vehicle.id == 'cavall') then return end
  o.x, o.y = math.floor(pl.body.x + 14), math.floor(pl.body.y)
  o.hidden = nil
  self.horse_prop = nil
end

function World:interact()
  local fx, fy = self:front_point()
  local near = function(x, y, r) return (x - fx) ^ 2 + (y - fy) ^ 2 < r * r end
  for _, n in ipairs(self.npcs) do
    if n.hidden and n.props.service and near(n.body.x, n.body.y - 2, 16) then
      local ci = n.props.service_id and Town.closed_info(self.game, n.props.service_id)   -- de nit els serveis tanquen
      self.hud:toast('Tancat. ' .. (ci and ci.when or 'Obre cada dia a les 7:30') .. '. Al menú pots triar «Esperar».', 3)
      return true
    end
    if not n.hidden and near(n.body.x, n.body.y - 2, 16) then
      n:face(self.player.body.x, self.player.body.y)
      self.talking = n
      self.dialogue.speaker_voice = require('src.systems.town').sprite_voice(n.props.sprite)
      local after = function() self.talking = nil; self.dialogue.speaker_voice = nil; n.facing = n.base_facing end
      if Town.on_talk(self, n) then   -- missions (parlar, lliurar) i amics del perfil
        self.talking = nil
        return true
      end
      if n.props.service then
        self.talking = nil
        require('src.systems.services').open(self, n)
      elseif n.name == 'npc_toni_patro' and require('src.systems.boat').talk(self, n, after) then
        return true   -- la barca: 3 petxines i et porta al Roc de Sant Gaietà
      elseif n.props.ai then
        self:ai_talk(n, 'Hola!')
      elseif n.props.say then
        local Chat = require('src.systems.chat')
        -- veïns de les cases: després de la seva frase, preguntes per triar (src/systems/chat.lua)
        self:say_text(n.props.say_name, n.props.say, Chat.applies(self, n) and function() Chat.open(self, n, after) end or after)
      else
        self:say(n.props.dialogue, after)
      end
      return true
    end
  end
  -- cavalls de la hípica: s'hi puja i, en baixar (B), es queda on el deixes
  if not self.player.vehicle and self.def.outdoor then
    for _, o in ipairs(self.props) do
      local spr = o.props.sprite or ''
      if not o.hidden and spr:sub(1, 6) == 'horse_' and near(o.x, o.y - 4, 18) then
        self:mount_horse(o)
        return true
      end
    end
  end
  for _, s in ipairs(self.signs) do
    if near(s.x, s.y, 12) then
      if s.props.display then require('src.systems.services').display(self, s.props)
      elseif s.props.book and require('src.systems.magic_quest').on_book(self, s) then   -- buscant el Llibre de Màgia
      elseif s.props.say then self:say_text(nil, s.props.say) else self:say(s.props.text) end
      return true
    end
  end
  for _, c in ipairs(self.chests) do
    if near(c.rect.x + 8, c.rect.y + 8, 13) then
      local key = c.obj.props.flag
      if self.sstate.chests[key] then self:say('chest_empty'); return true end
      self.sstate.chests[key] = true
      require('src.systems.companion').on_chest(self, key)
      c.open_t=0
      State.set(self.state, key)
      local item = c.obj.props.item
      if not item then   -- cofre por categoría (data/loot.json): madera, hierro, plata, legendario
        local Loot = require('src.systems.loot')
        local res = Loot.roll(self.game.loot, c.obj.props.tier or 'wood', key)
        local names = Loot.apply(self.state, self.game.items, res)
        c.reward_icon=self.game.items[res.items[1]] and self.game.items[res.items[1]].sprite
        self.game.audio.play('chest')
        local cx, cy = c.rect.x + 8, c.rect.y + 4
        local legend = c.obj.props.tier == 'legend'
        self.fx:preset('sparkle', cx, cy, legend and 22 or 12, legend and { color = { 1, 0.85, 0.3 }, speed = 40 } or nil)
        if legend then self.fx:preset('confetti', cx, cy - 4, 24); self.shaker:add(0.35) end
        local pages = { res.label .. ': ' .. table.concat(names, ', ') .. '!' }
        for _, id in ipairs(res.items) do
          local d = self.game.items[id]
          if d and d.kind == 'blueprint' then
            local v = require('src.systems.vehicles').CATALOG[d.vehicle]
            pages[#pages + 1] = 'Amb aquest plànol ja pots fer servir: ' .. v.name .. ' (nivell ' .. (v.min_level or 1) .. ').'
          end
        end
        self.dialogue:show(nil, pages, function() self:reward(res.xp, res.coins, res.label) end)
        return true
      end
      c.reward_icon=self.game.items[item] and self.game.items[item].sprite
      State.give(self.state, item)
      State.equip(self.state, self.game.items, item)
      self.game.audio.play('chest')
      self.fx:preset('sparkle', c.rect.x + 8, c.rect.y + 4, 12)
      if item == 'radio' then
        self.dialogue:show('Ràdio de butxaca',{'Has trobat una ràdio! Té quatre emissores musicals.','Obre Personatge i equip > Ràdio de butxaca per sintonitzar-la.','El volum es pot canviar a Opcions (so i veu).'})
      elseif item == 'sword_bera' then self:say('chest_sword')
      else
        local def = self.game.items[item]
        self.dialogue:show(nil, { 'Has trobat: ' .. (def and def.name or tostring(item)) .. '!' })
      end
      return true
    end
  end
  if require('src.systems.farm').interact(self, fx, fy) then return true end   -- donar menjar als animals de granja
  if self.fauna and self.fauna:interact(fx, fy) then return true end   -- acariciar gatos mansos y perros
  if Town.interact(self, fx, fy) then return true end   -- contenidors de reciclatge
  for _, a in ipairs(self.arcades) do
    if near(a.rect.x + 8, a.rect.y + 10, 14) then
      if a.obj.props.game == 'lift' then self:lift_menu(a.obj.props)
      elseif a.obj.props.game == 'taller' then require('src.systems.crafting').open(self)
      else require('src.minigames.init').launch(self, a.obj.props) end
      return true
    end
  end
  if require('src.systems.puzzles').interact(self, fx, fy) then return true end
  for _, l in ipairs(self.levers) do
    if near(l.rect.x + 8, l.rect.y + 5, 13) then
      local f = l.obj.props.flag
      local on = not State.flag(self.state, f)
      self.state.flags[f] = on or nil   -- (State.set con nil guardaba true: la reja no se cerraba nunca)
      self.sstate.levers[f] = on
      self.game.audio.play('door')
      self.hud:toast(on and 'La reixa s\'ha obert' or 'La reixa s\'ha tancat')
      return true
    end
  end
  for _, st in ipairs(self.stops) do
    if near(st.x, st.y - 12, 18) then self:bus_menu(st); return true end
  end
  if self.home and self.game.house and near(self.home.x + 8, self.home.y - 6, 16) then
    if self.house_east then   -- la casa se entra por el este: el buzón solo lo recuerda
      self.hud:toast('La porta de casa és a l\'est', 2)
      return true
    end
    self.game.audio.play('door')
    self.game.scene_manager:change(self.game.house.entry, self.game.house.spawn or 'spawn_in')
    return true
  end
  if require('src.systems.fishing').try_start(self) then return true end   -- amb la canya, mirant el mar
  if require('src.systems.rest').interact(self, fx, fy) then return true end
  local ftx, fty, fkind = self:facade_ahead()
  if ftx then self:enter_facade(ftx, fty, fkind); return true end
  for _, g in ipairs(self.gates) do
    if overlap({ x = fx - 4, y = fy - 4, w = 8, h = 8 }, g.rect) and not self:gate_open(g) then
      self:say('gate_closed'); return true
    end
  end
  if require('src.systems.companion').near(self, fx, fy, 12) then
    require('src.systems.companion').talk(self)
    return true
  end
  if self.olaf and near(self.olaf.x, self.olaf.y - 2, 12) then
    self.game.audio.play(love.math.random() < 0.7 and 'meow' or 'purr')
    self.fx:preset('sparkle', self.olaf.x, self.olaf.y - 14, 3, { color = { 1, 0.7, 0.75 }, speed = 12 })
    self.dialogue:show('Olaf', { OLAF_SAYS[love.math.random(#OLAF_SAYS)] })
    return true
  end
  return false
end

-- lugar con nombre más cercano (contexto para la IA)
function World:place_near(x, y)
  local best, label = 600 * 600, self.def.name or require('src.place').name()
  if self.map.props.interior then return self.map.props.name or label end
  for _, o in ipairs(self.map.objects) do
    if o.type == 'poi' then
      local d = (o.x - x) ^ 2 + (o.y - y) ^ 2
      if d < best then best, label = d, o.props.label or o.name end
    end
  end
  return label
end

-- conversación con IA (personajes con props.ai, creados en el editor). Si la IA no responde a tiempo,
-- el personaje dice una de sus frases fijas: el juego nunca se queda esperando.
function World:ai_talk(n, ask)
  local Net = require('src.net')
  local name = (n.props.say_name and n.props.say_name ~= '') and n.props.say_name or 'Veí'
  local say = {}
  for line in tostring(n.props.say or ''):gmatch('[^|]+') do say[#say + 1] = line end
  n.ai_hist = n.ai_hist or {}
  self.talking = n
  self.dialogue.speaker_voice = require('src.systems.town').sprite_voice(n.props.sprite)
  local token = {}
  self.ai_token = token
  local function finish() self.talking = nil; n.facing = n.base_facing end
  self.dialogue:show(name, { '...' }, function()
    if self.ai_token == token then self.ai_token = nil; Net.cancel(self.ai_req); finish() end
  end)
  local doing = Town.errand_key(self, n)              -- encàrrec del veí (pa, platja, jardí...)
  if doing then table.insert(say, 1, Town.errand_line(self, n)) end
  self.ai_req = Net.post('/api/npc_chat', {
    npc = { id = (n.name or ''):gsub('^npc_', ''), say = say, doing = doing },
    history = n.ai_hist, ask = ask,
  }, function(res)
    if self.ai_token ~= token then return end
    self.ai_token = nil
    local reply = (res and res.ai ~= false and res.reply) or (doing and say[1]) or (res and res.reply)
        or say[love.math.random(math.max(1, #say))] or 'Hola!'   -- sense IA: el que està fent
    local options = res and res.options or nil
    local h = n.ai_hist
    h[#h + 1] = { role = 'user', text = ask }
    h[#h + 1] = { role = 'npc', text = reply }
    while #h > 8 do table.remove(h, 1) end
    self.dialogue:show(name, { reply }, function()
      if not options or #options == 0 then finish(); return end
      local items = {}
      for _, o in ipairs(options) do
        local bye = o:lower():find('ad[eé]u') or o:lower():find('adéu')
        items[#items + 1] = { o, function()
          self.game:close_menu()
          if bye then finish() else self:ai_talk(n, o) end
        end }
      end
      self.game:open_list(name, items)
    end)
  end, 15)
end

-- ---------------------------------------------------------------- serveis: tren, cursa, cartera
function World:service_npcs(kind)
  local out = {}
  for _, n in ipairs(self.npcs) do if n.props.service == kind then out[#out + 1] = n end end
  return out
end

-- una parada de bus a 15–60 casillas (para la cartera perdida o la meta de una cursa)
function World:random_stop(near, min_d, max_d)
  local b = near or self.player.body
  local cands = {}
  for _, s in ipairs(self.stops) do
    local d = math.sqrt((s.x - b.x) ^ 2 + (s.y - b.y) ^ 2) / 16
    if d >= (min_d or 15) and d <= (max_d or 60) then cands[#cands + 1] = s end
  end
  if #cands == 0 then cands = self.stops end
  if #cands == 0 then return nil end
  return cands[love.math.random(#cands)]
end

-- tren: entre estaciones conocidas (se conocen al pasar cerca, como las paradas de bus)
function World:station_menu(here)
  local st = self.state
  st.stations = st.stations or {}
  st.stations[here.props.service_id] = true
  local items = {}
  for _, n in ipairs(self:service_npcs('station')) do
    if n ~= here and st.stations[n.props.service_id] then
      items[#items + 1] = { n.props.label, function()
        self.game:close_menu()
        self.game.audio.play('horn')
        self.game:change(self.id, nil, { x = n.home[1], y = n.home[2] + 16, level = 0, facing = 'down' })
        self.hud:toast('Tren: has arribat a ' .. n.props.label, 2.5)
      end }
    end
  end
  if #items == 0 then
    self.dialogue:show(here.props.say_name, { here.props.label .. '.', 'Quan coneguis una altra estació, hi podràs anar en tren!' })
    return
  end
  self.game:open_list('Tren des de ' .. here.props.label, items)
end

-- cursa contra rellotge: córrer fins a una parada de bus abans que s'acabi el temps
function World:start_race(n)
  local goal = self:random_stop(n.body, 18, 45)
  if not goal then self.hud:toast('Avui no hi ha cap cursa', 2); return end
  local d = math.sqrt((goal.x - n.body.x) ^ 2 + (goal.y - n.body.y) ^ 2)
  local limit = math.floor(d / 48 * 1.5 + 10)
  self.race = { x = goal.x, y = goal.y + 8, label = goal.label, t = limit, limit = limit }
  self.dialogue:show(n.props.say_name, { string.format('Corre fins a la parada %s! Tens %d segons. A la una, a les dues i a les tres... ja!',
    goal.label, limit) })
end

function World:update_race(dt)
  local r = self.race
  if not r then return end
  r.t = r.t - dt
  local b = self.player.body
  if (b.x - r.x) ^ 2 + (b.y - r.y) ^ 2 < 28 ^ 2 then
    self.race = nil
    local bonus = math.floor(r.t)
    self:reward(25 + bonus, 5 + math.floor(bonus / 3), 'Cursa guanyada!')
  elseif r.t <= 0 then
    self.race = nil
    self.hud:toast('S\'ha acabat el temps! Torna-ho a provar.', 2.5)
  end
end

-- col·leccionables (petxines, pinyes): es recullen en passar-hi per sobre
function World:update_pickups()
  if #self.pickups == 0 then return end
  local got = self.sstate.pickups or {}
  self.sstate.pickups = got
  local b = self.player.body
  for _, p in ipairs(self.pickups) do
    if not got[p.name] and math.abs(p.x - b.x) < 10 and math.abs(p.y - b.y) < 10 then
      got[p.name] = true
      State.give(self.state, p.item)
      local d = self.game.items[p.item]
      self.hud:toast('+1 ' .. (d and d.name or p.item), 1.5)
      self.game.audio.play('talk')
      self:puff(p.x, p.y, 4, { 1, 1, 0.85 }, 20, 0.3, 1)
    end
  end
end

function World:update_wallet()
  local w = self.state.missions and self.state.missions.wallet
  if type(w) ~= 'table' or self.id ~= 'overworld' then return end
  local b = self.player.body
  if (b.x - w.x) ^ 2 + (b.y - w.y) ^ 2 < 14 ^ 2 then
    self.state.missions.wallet = 'found'
    State.give(self.state, 'cartera')
    self.hud:toast('Has trobat la cartera! Porta-la a la Policia Local.', 3)
    self.game.audio.play('chest')
  end
end

-- viaje rápido: lista de paradas descubiertas (se descubren al pasar cerca)
function World:bus_menu(here)
  local st = self.state
  st.stops = st.stops or {}
  st.stops[here.name] = true
  local items = {}
  for _, s in ipairs(self.stops) do
    if s ~= here and st.stops[s.name] then
      items[#items + 1] = { s.label, function()
        self.game:close_menu()
        self.game.audio.play('door')
        self.game:change(self.id, nil, { x = s.x, y = s.y + 6, level = 0, facing = 'down' })
        self.hud:toast('Bus: has arribat a ' .. s.label, 2.5)
        Town.event(self, 'bus', {})
      end }
    end
  end
  table.sort(items, function(a, b) return a[1] < b[1] end)
  if #items == 0 then
    self.dialogue:show('Parada de bus', { here.label, 'Encara no coneixes cap altra parada. Quan en trobis més, podràs viatjar-hi en bus!' })
    return
  end
  self.game:open_list('Bus des de ' .. here.label, items)
end

-- ¿hay algo con lo que interactuar delante? (para el indicador)
function World:can_interact()
  local fx, fy = self:front_point()
  for _, n in ipairs(self.npcs) do
    if not n.hidden and (n.body.x - fx) ^ 2 + (n.body.y - 2 - fy) ^ 2 < 256 then return true end
  end
  if Town.can_interact(self, fx, fy) then return true end
  if require('src.systems.farm').can_interact(self, fx, fy) then return true end
  if self.fauna and self.fauna:can_interact(fx, fy) then return true end
  for _, s in ipairs(self.signs) do if (s.x - fx) ^ 2 + (s.y - fy) ^ 2 < 144 then return true end end
  for _, c in ipairs(self.chests) do if (c.rect.x + 8 - fx) ^ 2 + (c.rect.y + 8 - fy) ^ 2 < 169 then return true end end
  for _, l in ipairs(self.levers) do if (l.rect.x + 8 - fx) ^ 2 + (l.rect.y + 5 - fy) ^ 2 < 169 then return true end end
  for _, a in ipairs(self.arcades) do if (a.rect.x + 8 - fx) ^ 2 + (a.rect.y + 10 - fy) ^ 2 < 196 then return true end end
  for _, s in ipairs(self.stops) do if (s.x - fx) ^ 2 + (s.y - 12 - fy) ^ 2 < 324 then return true end end
  if self:facade_ahead() then return true end
  if require('src.systems.rest').can_interact(self, fx, fy) then return true end
  return false
end

-- puerta o escaparate de una fachada justo delante (mirando hacia arriba): kind del interior o nil
function World:facade_ahead()
  if self.def.outdoor and self:house_east_ahead() then return self.house_east.wx, self.house_east.ty, 'house' end
  if not self.def.outdoor or self.player.body.level ~= 0 or self.player.facing ~= 'up' then return end
  local px, py = self.player.body.x, self.player.body.y
  local tx, ty = math.floor(px / 16), math.floor((py - 10) / 16)
  if ty == math.floor(py / 16) then return end
  local lk = self.game.renderer.light_kind
  for dx = 0, 1 do  -- la celda de delante y, si el jugador va entre dos, la vecina
    local x = dx == 0 and tx or (px % 16 < 8 and tx - 1 or tx + 1)
    local kind = lk[self.map:tile_at('structures', x, ty)]
    if (kind == 'door' or kind == 'shop') and not Collision.walk_at(self.map:cell(x, ty), 0) and
        not self:door_object_at(x, ty) then
      return x, ty, kind
    end
  end
end

-- ascensor d'un bloc de pisos: triar la planta (la planta on som surt marcada)
function World:lift_menu(p)
  local g = self.game
  local items = {}
  for k, f in ipairs(p.floors or {}) do
    local here = (k - 1) == p.current
    items[#items + 1] = { (here and '· ' or '') .. f.label .. (here and ' (ets aquí)' or ''), function()
      g:close_menu()
      if here then return end
      g.audio.play('coin')
      self.hud:toast('Ascensor: ' .. f.label, 1.5, true)
      g:change(f.scene, 'lift')
    end }
  end
  g:open_list('Ascensor · a quina planta vas?', items)
end

function World:door_object_at(tx, ty)
  for _, d in ipairs(self.doors) do
    if point_in(tx * 16 + 8, ty * 16 + 8, d.rect) or point_in(tx * 16 + 8, ty * 16 + 24, d.rect) then return true end
  end
  return false
end

-- entrar empujando la puerta: la casa privada si es la de casa; si no, un interior procedural
function World:check_facade_door()
  local tx, ty, kind = self:facade_ahead()
  if not tx then self.facade_push = nil; return false end
  local key = tx .. ',' .. ty
  local b = self.player.body
  if self.facade_push ~= key then self.facade_push, self.facade_t = key, 0 end
  -- solo cuenta empujar parado contra la puerta (no pasar rozando ni deslizarse por la fachada)
  local still = self.facade_pos and math.abs(b.x - self.facade_pos[1]) < 0.3 and math.abs(b.y - self.facade_pos[2]) < 0.3
  self.facade_pos = { b.x, b.y }
  if not self.player.move_intent or not still then self.facade_t = 0; return false end
  self.facade_t = self.facade_t + 1
  if self.facade_t < 14 then return false end  -- ~0,25 s empujando
  self.facade_push = nil
  self:enter_facade(tx, ty, kind)
  return true
end

-- la puerta de fachada más cercana al buzón de casa es la de la casa privada; al salir se vuelve delante
function World:find_house_door()
  local h, lk = self.home, self.game.renderer.light_kind
  local best, bd = nil, 13 * 13
  for y = h.ty - 12, h.ty + 12 do
    for x = h.tx - 12, h.tx + 12 do
      if lk[self.map:tile_at('structures', x, y)] == 'door' and Collision.walk_at(self.map:cell(x, y + 1), 0) then
        local d = (x - h.tx) ^ 2 + (y - h.ty) ^ 2
        if d < bd then best, bd = { x, y }, d end
      end
    end
  end
  self.house_door = best
  local g = self.game
  -- casa con entrada por el este (tools/casa_privada.py --entrada este): se entra empujando hacia el oeste
  -- contra la pared este del edificio, y al salir se vuelve a ese lado
  self.house_east = best and g.house.entrance == 'este' and self:find_east_entry(best[1], best[2]) or nil
  local gen = g.generated and g.generated[g.house.entry]
  if best and gen and not gen.back_door then
    local e = self.house_east
    if e then
      gen.back = { scene = self.id, x = (e.wx + 1) * 16 + 10, y = e.ty * 16 + 8, level = 0, facing = 'right' }
    else
      gen.back = { scene = self.id, x = best[1] * 16 + 8, y = (best[2] + 1) * 16 + 10, level = 0 }
    end
    gen.back_door = true
    g.maps[g.house.entry] = nil
  end
end

-- edificio de la puerta (tx, ty): casillas de tejado/fachada conectadas; la entrada este es la casilla libre
-- junto a su columna más oriental, en la fila más baja posible (la de la fachada si se puede)
function World:find_east_entry(tx, ty)
  local g = self.game
  if not g.tile_names then
    g.tile_names = {}
    for name, t in pairs(g.tile_defs) do g.tile_names[t.id + 1] = name end
  end
  local names, map = g.tile_names, self.map
  local function part(x, y)
    local n = names[map:tile_at('structures', x, y)]
    return n and (n:sub(1, 2) == 'r_' or n:sub(1, 2) == 'f_')
  end
  local seen, q, cells = { [tx .. ',' .. ty] = true }, { { tx, ty } }, {}
  while #q > 0 and #cells < 600 do
    local c = table.remove(q)
    cells[#cells + 1] = c
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local x, y = c[1] + d[1], c[2] + d[2]
      local k = x .. ',' .. y
      if not seen[k] and part(x, y) then seen[k] = true; q[#q + 1] = { x, y } end
    end
  end
  local east = {}   -- fila → columna más oriental del edificio
  for _, c in ipairs(cells) do east[c[2]] = math.max(east[c[2]] or -1, c[1]) end
  local rows = {}
  for y in pairs(east) do rows[#rows + 1] = y end
  table.sort(rows, function(a, b) return a > b end)   -- de abajo (fachada) arriba
  for _, y in ipairs(rows) do
    local wx = east[y]
    if Collision.walk_at(map:cell(wx + 1, y), 0) then return { wx = wx, ty = y } end
  end
end

-- ¿el jugador está delante de la entrada este de la casa, mirando al oeste?
function World:house_east_ahead()
  local e = self.house_east
  local pl = self.player
  if not e or pl.facing ~= 'left' or pl.body.level ~= 0 then return false end
  return math.floor((pl.body.x - 10) / 16) == e.wx and math.floor(pl.body.y / 16) == e.ty
end

function World:enter_facade(tx, ty, kind)
  local g = self.game
  local hd = self.house_door
  if kind ~= 'house' and self.house_east and hd and hd[1] == tx and hd[2] == ty then
    self.hud:toast('La porta de casa és a l\'est', 2)   -- la casa se entra por el este
    return
  end
  -- casa d'un amic o dels avis del perfil: el seu interior (src/game.lua friend_interior)
  for _, fr in ipairs(g.friends or {}) do
    local h = fr.def.home
    if h and h.door_x == tx and h.door_y == ty then
      g.audio.play('door')
      local back = { scene = self.id, x = tx * 16 + 8, y = (ty + 1) * 16 + 10, level = 0 }
      g.scene_manager:change(g:friend_interior(fr.def, back), 'spawn_in')
      return
    end
  end
  g.audio.play('door')
  if g.house and (kind == 'house' or (hd and hd[1] == tx and hd[2] == ty)) then
    g.scene_manager:change(g.house.entry, g.house.spawn or 'spawn_in')
    return
  end
  local back = { scene = self.id, x = tx * 16 + 8, y = (ty + 1) * 16 + 10, level = 0 }
  -- porta d'un edifici important (CAP, Policia, Correus, estació...): el seu interior propi
  local Services = require('src.systems.services')
  local sid = self:poi_doors()[tx .. ',' .. ty]
  if sid then Services.enter_poi(self, sid, Services.POI_KIND[sid], back); return end
  local floors = self:facade_floors(tx, ty)
  local pkind = kind == 'shop' and 'shop' or
      ((floors >= 3 or require('src.themes').cell_rand(tx, ty, 5) < 0.3) and 'block' or 'house')
  -- porta amb el rètol d'un local real (decorate_map.locals_): interior de botiga amb els mobles del local
  local local_id
  for _, o in ipairs(self.signboards) do
    local spr = o.props.sprite or ''
    if spr:sub(1, 11) == 'sign_local_' and not o.hidden and math.floor(o.x / 16) == tx and math.floor(o.y / 16) == ty then
      local_id = spr:sub(12); pkind = 'shop'; break
    end
  end
  -- botigues i locals: l'interior fa la mida de l'edifici de fora (el Bonpreu, gran; una botiga petita, petita)
  local size
  if pkind == 'shop' then size = self:facade_size(tx, ty) end
  -- casa amb placas solars reals al teulat (tools/decorate_map.py solar_roofs): interior amb aparells
  if not self.solar_doors then
    self.solar_doors = {}
    for _, o in ipairs(self.map.objects or {}) do
      if o.type == 'solar_house' then self.solar_doors[math.floor(o.x / 16) .. ',' .. math.floor(o.y / 16)] = true end
    end
  end
  local solar = pkind ~= 'shop' and self.solar_doors[tx .. ',' .. ty] or nil
  g.scene_manager:change(g:proc_interior(tx, ty, pkind, back, floors, local_id, size, solar), 'spawn_in')
end

-- la porta de façana de cada edifici important: la més propera al punt del servei (a menys de 14 caselles), un
-- cop per escena. Retorna { ["x,y"] = service_id }
function World:poi_doors()
  if self._poi_doors then return self._poi_doors end
  local out = {}
  self._poi_doors = out
  if self.id ~= 'overworld' then return out end
  local Services = require('src.systems.services')
  local lk = self.game.renderer.light_kind
  for _, o in ipairs(self.map.objects or {}) do
    local k = o.type == 'service' and Services.POI_KIND[o.props.service_id]
    if k and k ~= 'super' and k ~= 'diy' then
      local sx, sy = math.floor(o.x / 16), math.floor(o.y / 16)
      local best, bd
      for dy = -14, 14 do
        for dx = -14, 14 do
          local kind = lk[self.map:tile_at('structures', sx + dx, sy + dy)]
          if (kind == 'door' or kind == 'shop') and (not bd or math.abs(dx) + math.abs(dy) < bd) then
            best, bd = (sx + dx) .. ',' .. (sy + dy), math.abs(dx) + math.abs(dy)
          end
        end
      end
      if best and not out[best] then out[best] = o.props.service_id end
    end
  end
  return out
end

-- mida en casselles de l'edifici d'una porta: amplada de la façana i fondària (teulat + façana) → interior
function World:facade_size(tx, ty)
  local function part(x, y) local n = self:tile_name('structures', x, y) or ''; return n:sub(1, 2) == 'f_' or n:sub(1, 2) == 'r_' end
  local x0, x1 = tx, tx
  while x0 > tx - 40 and (self:tile_name('structures', x0 - 1, ty) or ''):sub(1, 2) == 'f_' do x0 = x0 - 1 end
  while x1 < tx + 40 and (self:tile_name('structures', x1 + 1, ty) or ''):sub(1, 2) == 'f_' do x1 = x1 + 1 end
  local y0 = ty
  while y0 > ty - 40 and part(tx, y0 - 1) do y0 = y0 - 1 end
  local fw, fd = x1 - x0 + 1, ty - y0 + 1
  return { w = math.max(10, math.min(40, fw * 2 + 2)), h = math.max(8, math.min(30, fd * 2 + 2)) }
end

-- locals reals no verificats (Game:local_visible): sense rètol, sense xiringuito i la porta és una casa
function World:refresh_locals()
  local g = self.game
  local function vis(id) return not id or g:local_visible(id) end
  for _, o in ipairs(self.signboards) do
    local spr = o.props.sprite or ''
    o.hidden = spr:sub(1, 11) == 'sign_local_' and not vis(spr:sub(12)) or nil
  end
  for _, o in ipairs(self.props) do o.hidden = not vis(o.props.local_id) or nil end
  for _, n in ipairs(self.npcs) do
    if n.props and n.props.local_id then n.hidden = not vis(n.props.local_id) or nil end
  end
end

-- plantes d'un edifici del mapa: files de façana (tiles f_*) des de la porta cap amunt
local FACADE
function World:facade_floors(tx, ty)
  if not FACADE then
    FACADE = {}
    for name, t in pairs(self.game.tile_defs) do
      if type(t) == 'table' and t.id and name:sub(1, 2) == 'f_' then FACADE[t.id + 1] = true end
    end
  end
  local n = 0
  while n < 8 and ty - n >= 0 and FACADE[self.map:tile_at('structures', tx, ty - n)] do n = n + 1 end
  return math.max(1, n)
end

function World:update_triggers()
  local px, py = self.player.body.x, self.player.body.y
  self.state.stops = self.state.stops or {}
  self.state.stations = self.state.stations or {}
  for _, n in ipairs(self.npcs) do
    if n.props.service == 'station' and not self.state.stations[n.props.service_id] and
        (n.body.x - px) ^ 2 + (n.body.y - py) ^ 2 < 40 ^ 2 then
      self.state.stations[n.props.service_id] = true
      self.hud:toast('Estació descoberta: ' .. n.props.label, 2.5)
    end
  end
  for _, s in ipairs(self.stops) do
    if not self.state.stops[s.name] and (s.x - px) ^ 2 + (s.y - py) ^ 2 < 40 ^ 2 then
      self.state.stops[s.name] = true
      self.hud:toast('Parada de bus descoberta: ' .. s.label, 2.5)
    end
  end
  for _, d in ipairs(self.doors) do
    local inside = point_in(px, py, d.rect)
    if d.obj.props.secret_flag and not State.flag(self.state, d.obj.props.secret_flag) then inside = false end
    if inside and not self.inside[d] then
      self.inside[d] = true
      local p = d.obj.props
      if p.requires_item and (self.state.inventory[p.requires_item] or 0) <= 0 then
        self.hud:toast(p.locked_text or 'Està tancat.', 3, true)
      elseif p.requires_item and p.min_level and (self.state.char_level or 1) < p.min_level then
        self.hud:toast('Encara no ets prou fort: torna quan siguis de nivell ' .. p.min_level .. '.', 3, true)
      elseif p.requires and not State.flag(self.state, p.requires) then
        self:say('cave_locked')
      elseif p.min_level and (self.state.char_level or 1) < p.min_level then
        self:say('dungeon_locked')
      elseif p.poi then   -- edifici important (decorate_map.landmark_doors): el seu interior propi
        local back = { scene = self.id, x = d.rect.x + 8, y = d.rect.y + d.rect.h + 10, level = 0, facing = 'down' }
        require('src.systems.services').enter_poi(self, p.poi_id, p.poi, back)
        return
      else
        self.game.audio.play('door')
        if p.target_x then  -- salida de un interior generado: vuelve delante de la fachada
          self.game.scene_manager:change(p.target_scene, nil, { x = p.target_x, y = p.target_y,
            level = p.target_level or 0, facing = p.target_facing or 'down' })
        else
          self.game.scene_manager:change(p.target_scene, p.target_spawn)
        end
        return
      end
    elseif not inside then
      self.inside[d] = nil
    end
  end
  if self:check_facade_door() then return end
  for _, tr in ipairs(self.triggers) do
    local inside = point_in(px, py, tr.rect)
    if inside and not self.inside[tr] then
      self.inside[tr] = true
      local p = tr.obj.props
      if p.kind == 'poi' then
        local label = (self.map:object('poi', p.poi) or { props = {} }).props.label or p.poi
        self.hud:place(label)
        local in_notebook = false
        for _, id in ipairs(self.game.world.pois) do if id == p.poi then in_notebook = true end end
        -- els edificis nous (Ajuntament, Biblioteca, Castell) només mostren el cartell: no tenen segell
        local first = not self.state.visited[p.poi] and not (self.state.seen or {})[p.poi]
        local msg = in_notebook and Quests.visit(self.state, p.poi, label, self.game.world.pois)
        if first then   -- descubrir un lugar da experiencia
          self.state.seen = self.state.seen or {}
          self.state.seen[p.poi] = true
          self:reward(15, 0)
        end
        if msg and State.flag(self.state, 'has_notebook') then
          self.hud:toast(msg)
          self.game.audio.play('stamp')
        end
      end
    elseif not inside then
      self.inside[tr] = nil
    end
  end
end

function World:update(dt, act)
  local g = self.game
  self.hud:update(dt)
  self:update_particles(dt) -- visual feedback keeps running during reward dialogue
  local pressed = act.pressed
  if self.rest_fx and require('src.systems.rest').update(self, dt) then return end
  if self.dialogue.open then
    self.dialogue:update(dt, pressed)
    for _, n in ipairs(self.npcs) do n:update(dt, self:ctx(), true) end
    return
  end
  if self.dead_t then
    self.dead_t = self.dead_t - dt
    if self.dead_t <= 0 then self:respawn() end
    return
  end
  if pressed.pause then g:open_menu(); return end
  if pressed.heal then require('src.systems.rest').use_medkit(self) end
  if pressed.map then g:open_menu('map'); return end
  if pressed.view and self.def.outdoor then
    self.zoom_out = not self.zoom_out
    self.cam.w, self.cam.h = self.zoom_out and 640 or 320, self.zoom_out and 480 or 240
    self.hud:toast(self.zoom_out and 'Vista allunyada (N per tornar)' or 'Vista normal', 1.2)
  end
  if pressed.journal then g:open_journal(); return end
  if pressed.inventory then g:open_menu(); if g.menu then g.menu:open_inventory() end; return end
  if pressed.swap then
    local msg = require('src.systems.rpg').swap(self.state, g.items)
    self.hud:toast(msg or 'No tens cap altra arma per canviar', 2)
    if msg then g.audio.play('confirm') end
  end
  if pressed.debug then g.debug = not g.debug end

  self.state.sim_time = self.state.sim_time + dt
  if self.def.outdoor then require('src.systems.daylight').advance(self.state, dt) end
  self:update_weather(dt)
  self.state.play_time = self.state.play_time + dt
  self:rebuild_blockers()
  local ctx = self:ctx()
  if self.fishing then require('src.systems.fishing').update(self, dt, pressed)   -- pescant: el jugador no es mou
  elseif pressed.confirm and self.player.state ~= 'attack' and not self.boat_ride then
    if self:interact() then return end
  end
  local hp_before = self.state.hp
  if self.player.vehicle then self:vehicle_obstacles(self.player.vehicle) end   -- conducció guiada: qui hi ha davant
  if not self.fishing and not self.player.jump then self.player:update(dt, act, ctx) end
  -- encallat: salt fins a la casella lliure més propera (src/systems/unstuck.lua)
  require('src.systems.unstuck').update(self, dt, (act.right and 1 or 0) - (act.left and 1 or 0),
    (act.down and 1 or 0) - (act.up and 1 or 0))
  require('src.systems.puzzles').update(self, dt, act)
  if self.boat_ride then require('src.systems.boat').update(self, dt) end
  self:update_horse()
  if (pressed.spell_next or pressed.spell_prev) and Magic.has_staff(self.state, g.items) then
    local id = Magic.next(self.state, pressed.spell_prev and -1 or 1)
    self.hud:toast(id and ('Encanteri: ' .. Magic.BY_ID[id].name .. ' (' .. Magic.BY_ID[id].mp .. ' MP)')
                   or 'Encara no saps cap encanteri (nivell 2)', 1.5)
  end
  if pressed.spell and self.player.state ~= 'dead' and not self.player.vehicle and not self.player.in_boat then self:cast_spell() end
  self:update_swim()
  self:footsteps()
  self:ambient_fx(dt)
  if self.olaf then
    local v = self.player.vehicle
    self.olaf:update(dt, self.player.body.x, self.player.body.y, v and 14 or 0)
  end
  require('src.systems.companion').update(self, dt)
  require('src.systems.crafting').update(self)   -- cops d'espasa a arbres, matolls i roques: materials
  require('src.systems.farm').update(self, dt)
  if self.player.state == 'dead' then
    self.dead_t = 1.2
    self.hud:toast('Has caigut! Tornes a començar...', 1.5)
    return
  end
  for _, n in ipairs(self.npcs) do if not (n.hidden or (n.routine and n.walk)) then n:update(dt, ctx, false) end end
  for _, e in ipairs(self.enemies) do
    local cam = self.cam
    if cam:visible(e.body.x - 8, e.body.y - 16, 16, 16, 96) then
      self:enemy_event(e, e:update(dt, ctx))
    end
  end
  -- encanteris i foc del drac
  if #self.shots.list > 0 then
    local map = self.map
    self.solid_fn = self.solid_fn or function(x, y)
      local tx, ty = math.floor(x / 16), math.floor(y / 16)
      return not map:in_bounds(tx, ty) or not Collision.walk_at(map:cell(tx, ty), 0)
    end
    self.shots:update(dt, self.solid_fn, self.enemies, self.player, ctx)
    for _, ev in ipairs(self.shots:take_events()) do
      local fire = ev.p_kind ~= 'gust'
      self.fx:preset('spark', ev.x, ev.y, fire and 7 or 4, { color = fire and { 1, 0.6, 0.2 } or { 0.8, 0.95, 1 } })
      if ev.kind == 'hit' or ev.kind == 'kill' then self:enemy_event(ev.target, ev.kind == 'kill' and 'dead' or 'hit') end
      if ev.kind == 'blocked' then self.hud:toast('Bé! L\'escut para el foc', 1) end
    end
  end
  Magic.regen(self.state, dt)
  if self.fauna then self.fauna:update(dt) end
  if self.traffic then
    local b = self.player.body
    self.peds:update(dt, b.x, b.y, self.honk_t)
    self.ped_obs = self.ped_obs or {}
    for i = #self.ped_obs, 1, -1 do self.ped_obs[i] = nil end
    self.traffic:update(dt, self.player, self.peds:obstacles(self.ped_obs))
    for _, ev in ipairs(self.traffic:take_events()) do
      if ev.type == 'horn' then self:sfx_at((Traffic.KINDS[ev.kind or 'car'] or {}).car and 'horn_car' or 'horn_moto', ev.x, ev.y, 200) end
    end
    local car, cx, cy = self.traffic:hit_test(self.player)
    if car and self.player:hit(2, cx, cy, ctx, true) then
      self.hud:toast('Compte amb els cotxes! Creua pels passos de vianants.', 2)
      if not self.player.vehicle then   -- la Policia Local posa una multa educativa (es paga a l'Ajuntament)
        self.state.fines = (self.state.fines or 0) + 5
        self.hud:toast('Multa de 5 monedes per creuar malament (Ajuntament)', 3)
      end
      if self.player.state == 'dead' then self.dead_t = 1.2 end
    end
  end
  if self.sailboats then self.sailboats:update(dt) end
  if self.trains then
    self.trains:update(dt, self.state.sim_time, self.player, ctx.sfx)
    self:train_fx(dt)
  end
  if self.state.hp < hp_before then self.shaker:add(0.5) end
  self:hp_popups()
  Town.update(self, dt)
  self:update_race(dt)
  self:update_wallet()
  self:update_pickups()
  require('src.systems.perles').update(self)
  require('src.systems.marker').update(self)
  self:update_triggers()
  local b = self.player.body
  local v = Player.DIRS[self.player.facing]
  self.map.chunks:update(b.x, b.y, self.player.moving and v[1] or 0, self.player.moving and v[2] or 0, 2)
  -- cámara con anticipación: se adelanta hasta 24 px hacia donde se camina (en píxeles enteros, para que el
  -- jugador no tiemble respecto al fondo) y vuelve suavemente al centro al pararse
  local f = Player.DIRS[self.player.facing]
  local reach = self.player.moving and (self.player.bike and 40 or 24) or 0
  local k = math.min(1, dt * 2.5)
  self.look_x = self.look_x + (f[1] * reach - self.look_x) * k
  self.look_y = self.look_y + (f[2] * reach * 0.6 - self.look_y) * k
  self.cam:follow(b.x + math.floor(self.look_x + 0.5), b.y - 8 + math.floor(self.look_y + 0.5),
    self.map.width * 16, self.map.height * 16)
  self:update_audio(pressed)
  -- estado guardable
  self.state.scene = self.id
  self.state.x, self.state.y, self.state.level, self.state.facing = b.x, b.y, b.level, self.player.facing
end

-- sonido adaptativo (src/audio.lua): zona, hora y altura; motor del vehículo y claxon
local ENGINE = { patinete = 'e', scooter = 'moto', motocross = 'moto', cotxe = 'car' }
local HORN = { bici = 'horn_bell', patinete = 'horn_bell', scooter = 'horn_moto', motocross = 'horn_moto', cotxe = 'horn_car',
               cavall = 'neigh' }
function World:update_audio(pressed)
  local a = self.game.audio
  local b = self.player.body
  local h = 0
  if self.def.outdoor then h = self.map:height_at(math.floor(b.x / 16), math.floor(b.y / 16)) end
  a.set_context({ scene = self.def.music, outdoor = self.def.outdoor, clock = self.state.clock, height = h,
                  weather = self.game.weather and self.game.weather:ambient(),
                  vehicle = self.player.vehicle and self.player.vehicle.id, swimming = self.player.swimming,
                  radio = require('src.systems.radio').track(self.state) })
  local v = self.player.vehicle
  if v then
    local def = require('src.systems.vehicles').CATALOG[v.id]
    a.engine(ENGINE[v.id], v.speed / def.max)
    if pressed.horn then
      a.play(HORN[v.id] or 'horn_bell')
      self.honk_t = 1.5           -- los peatones cercanos se apartan / miran (src/systems/pedestrians.lua)
    end
  end
  self.honk_t = math.max(0, (self.honk_t or 0) - 1 / 60)
end

function World:respawn()
  self.dead_t = nil
  self.state.hp = self.state.max_hp
  local sp = self.map:object('spawn', self.id == 'overworld' and 'spawn_public_centre' or 'spawn_entrance')
  if self.id == 'overworld' and self.home then sp = { x = self.home.x, y = self.home.y } end
  self.player.body.x, self.player.body.y, self.player.body.level = sp.x, sp.y, 0
  self.player.state = 'idle'
  self.player.invuln = 1.0
  for _, e in ipairs(self.enemies) do
    if e.state ~= 'dead' then e.body.x, e.body.y = e.home[1], e.home[2] end
  end
end

-- ---------------------------------------------------------------- dibujo
-- color 1-4: car_*; 5-12: modelos car2_*; 13-14: furgonetas van2_* (ver tools/make_sprites.py)
local CAR_SHEETS = { { 'car', 0, 4 }, { 'car2', 4, 8 }, { 'van2', 12, 2 }, { 'svc', 14, 5 } }   -- svc: policia, ambulància, bombers, camió, excavadora
local function draw_car(game, car, x, y, orient, reverse, ox, oy)
  local s = game.sprites
  local c = car.color or 1
  local sheet = CAR_SHEETS[c > 14 and 4 or c > 12 and 3 or c > 4 and 2 or 1]
  local p, i, n = sheet[1], c - sheet[2], sheet[3]
  local q, img, w, h
  if orient == 'h' then img, q, w, h = s[p .. '_h'], s[p .. '_hq'][i], 32, 16
  elseif orient == 'v' then img, q, w, h = s[p .. '_v'], s[p .. '_vq'][i], 16, 32
  else img, q, w, h = s[p .. '_d'], s[p .. '_dq'][(orient == 'd2' and n or 0) + i], 24, 24 end
  local sx, sy = 1, 1
  if reverse then if orient == 'h' then sx = -1 elseif orient == 'v' then sy = -1 else sx, sy = -1, -1 end end
  love.graphics.draw(img, q, math.floor(x - ox + 0.5), math.floor(y - oy + 0.5), 0, sx, sy, w / 2, h / 2 + 2)
end

local DIR_INDEX = { down = 0, up = 1, left = 2, right = 3 }

-- barrera de paso a nivel: poste y brazo a franjas rojas y blancas que gira de vertical (b = 0) a cruzar la
-- calle (b = 1). (px, py): pie del poste; (dx, dy): dirección del brazo bajado
local function draw_barrier_arm(px, py, dx, dy, b, blink)
  local down = math.atan2(dy, dx)
  local up = -math.pi / 2
  local d = (down - up) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  local a = up + d * b
  love.graphics.setColor(0.25, 0.24, 0.27)
  love.graphics.rectangle('fill', math.floor(px) - 1, math.floor(py) - 10, 3, 10)
  love.graphics.push()
  love.graphics.translate(math.floor(px) + 0.5, math.floor(py) - 9)
  love.graphics.rotate(a)
  for i = 0, 5 do
    if i % 2 == 0 then love.graphics.setColor(0.84, 0.22, 0.2) else love.graphics.setColor(0.96, 0.94, 0.89) end
    love.graphics.rectangle('fill', i * 4, -1, 4, 2)
  end
  if blink then love.graphics.setColor(1, 0.3, 0.2); love.graphics.rectangle('fill', 22, -2, 2, 2) end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

-- peatón (src/systems/pedestrians.lua): hoja de personaje 16×24, se desvanece al aparecer y al irse
local function draw_ped(sheet, p, ox, oy)
  local row = DIR_INDEX[p.facing or 'down']
  local col = p.moving and math.floor(p.anim * 7) % 4 or 4
  love.graphics.setColor(1, 1, 1, math.max(0, math.min(1, p.alpha)))
  love.graphics.draw(sheet.sheet, sheet.quad(row, col), math.floor(p.x - 8 - ox + 0.5), math.floor(p.y - 20 - oy + 0.5))
  if p.startle then   -- ¡claxon!: signo de exclamación
    love.graphics.setColor(1, 0.95, 0.5, 1)
    love.graphics.rectangle('fill', math.floor(p.x - ox), math.floor(p.y - 30 - oy), 2, 5)
    love.graphics.rectangle('fill', math.floor(p.x - ox), math.floor(p.y - 24 - oy), 2, 2)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local TRAIN_ROW = { rodalies = 0, hs = 2, freight = 4 }
local function draw_train_car(game, c, ox, oy)
  local s = game.sprites
  local idx = TRAIN_ROW[c.kind] + (c.loco and 0 or 1) + 1
  local img, q, w, h
  if c.orient == 'h' then img, q, w, h = s.train_h, s.train_hq[idx], 48, 16
  elseif c.orient == 'v' then img, q, w, h = s.train_v, s.train_vq[idx], 16, 48
  else img, q, w, h = s.train_d, s.train_dq[(c.orient == 'd2' and 6 or 0) + idx], 40, 40 end
  local sx, sy = 1, 1
  if c.reverse then if c.orient == 'h' then sx = -1 elseif c.orient == 'v' then sy = -1 else sx, sy = -1, -1 end end
  love.graphics.draw(img, q, math.floor(c.x - ox + 0.5), math.floor(c.y - oy + 0.5), 0, sx, sy, w / 2, h / 2 + 2)
end

function World:draw()
  local g = self.game
  local r = g.renderer
  local ox, oy = self.cam:draw_offset()
  do  -- sacudida (golpes, impactos, tren que pasa al lado): src/fx/shake.lua
    local sx, sy = self.shaker:offset()
    ox, oy = ox + sx, oy + sy
  end
  -- vista allunyada (tecla N / botó 🔭): el món es dibuixa a 640 × 480 en un llenç a part i es redueix a la meitat
  local zoomed = self.def.outdoor and self.zoom_out
  local VW, VH = zoomed and 640 or 320, zoomed and 480 or 240
  if zoomed then
    if not self.zcanvas then
      self.zcanvas = love.graphics.newCanvas(640, 480)
      self.zcanvas:setFilter('linear', 'linear')
    end
    love.graphics.setCanvas({ self.zcanvas, stencil = true })
    love.graphics.clear(0.07, 0.06, 0.08)
  end
  local chunks = r:visible(self.map, { x = ox, y = oy, w = VW, h = VH })
  love.graphics.push()
  love.graphics.translate(-ox, -oy)
  local pl = self.player
  local sprites = g.sprites
  local draw_player = function() pl:draw({ sheet = sprites.player.sheet, quad = sprites.player.quad, diag = sprites.player.diag,
    weapon = g.items[self.state.equipment.weapon] and g:special_sprite(g.items[self.state.equipment.weapon].sprite or 'sword'),
    shield = g.items[self.state.equipment.shield] and g.items[self.state.equipment.shield].kind == 'shield'
             and g:special_sprite(g.items[self.state.equipment.shield].sprite or 'shield') or nil,
    action = sprites.player_action, action_quads = sprites.player_action_quads,
    bike = sprites.player_bike, bike_quads = sprites.player_bike_quads, bike_diag = sprites.player_bike_diag, vehicles = sprites.player_vehicles,
    car = function(x, y, ang)
      local o, rev = require('src.systems.route').orient(ang)
      draw_car(g, { color = 2 }, x, y - 2, o, rev, ox, oy)
    end,
    horse = function(skin) return g:special_sprite('horse_' .. ((skin or ''):match('^cavall_(%w+)$') or 'brown')) end,
    -- casc superposat: l'avatar del perfil ja el porta a la fulla (update_raincoat); les altres aparences, no
    helmet = not (self.state.skin == 'avatar' and g.profile and g.profile.avatar) and sprites.helmet_overlay or nil,
    helmet_quads = sprites.helmet_overlay_quads,
    slash = sprites.slash, slash_quads = sprites.slash_quads }, ox, oy) end

  r:draw_layer(chunks, 'ground')
  r:draw_vectors(chunks, -1)
  love.graphics.pop()
  -- nivel -1 (túneles): el jugador va debajo de la calle o la vía que lo cubre
  if pl.body.level == -1 then draw_player() end
  love.graphics.push(); love.graphics.translate(-ox, -oy)
  r:draw_vectors(chunks, 0)
  r:draw_layer(chunks, 'ground_detail')
  require('src.systems.puddles').draw(self)          -- bassals quan plou
  r:draw_relief(chunks)
  r:draw_layer(chunks, 'structures')
  r:draw_layer(chunks, 'theme')
  love.graphics.pop()

  love.graphics.push(); love.graphics.translate(-ox, -oy)
  r:draw_layer(chunks, 'cover_low')
  love.graphics.pop()

  -- felpudo delante de la entrada este de casa
  if self.house_east then
    local mat = g.tile_defs.i_exit
    if mat then
      love.graphics.draw(r.atlas, r.quads[mat.id + 1], (self.house_east.wx + 1) * 16 - ox, self.house_east.ty * 16 - oy)
    end
  end
  -- sombras de personajes y enemigos (antes que cualquier sprite: no tapan a nadie)
  if pl.body.level == 0 and not (pl.invuln > 0 and math.floor(pl.invuln * 20) % 2 == 0) and pl.state ~= 'dead'
      and not (pl.vehicle and pl.vehicle.id == 'cotxe') then
    shadow(pl.body.x - ox, pl.body.y + 3 - oy, pl.bike and 9 or 6, 2.5)
  end
  for _, n in ipairs(self.npcs) do
    if not n.hidden and self.cam:visible(n.body.x - 8, n.body.y - 20, 16, 24) then shadow(n.body.x - ox, n.body.y + 3 - oy, 5.5, 2.2) end
  end
  local olaf_shown = self.olaf and not (pl.vehicle and pl.vehicle.id == 'cotxe')   -- en coche va dentro
  if olaf_shown then shadow(self.olaf.x - ox, self.olaf.y + 3 - oy, 5, 2) end
  for _, e in ipairs(self.enemies) do
    if e.state ~= 'dead' and self.cam:visible(e.body.x - 8, e.body.y - 16, 16, 16) then
      local fly = e.kind.flying
      shadow(e.body.x - ox, e.body.y + (fly and 8 or 3) - oy, fly and 4 or 7, fly and 1.5 or 2.5, fly and 0.18 or 0.28)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)

  -- nivel 0: entidades ordenadas por la Y de sus pies
  local list = {}
  local function add(y, fn) list[#list + 1] = { y = y, fn = fn } end
  local pcell = self.map:cell(math.floor(pl.body.x / 16), math.floor(pl.body.y / 16))
  local on_deck_ramp = pcell % 32 >= 16 and (math.floor(pcell / 4) % 2 == 1)
  if pl.body.level == 0 and not on_deck_ramp then add(pl.body.y + 4, draw_player) end
  for _, n in ipairs(self.npcs) do
    if not n.hidden and self.cam:visible(n.body.x - 8, n.body.y - 20, 16, 24) then
      add(n.body.y + 4, function() n:draw(n.sprite, ox, oy + (n.hop and 3 or 0)) end)   -- hop: s'aparta d'un salt
    end
  end
  Town.draw_world(self, add, ox, oy)
  require('src.systems.beach').draw(self, add, ox, oy)   -- banderes de la platja
  require('src.systems.farm').draw(self, add, ox, oy, shadow)   -- animals de les granges
  require('src.systems.rest').draw_kits(self, add, ox, oy)
  self:draw_signs(add, ox, oy)
  if olaf_shown then add(self.olaf.y + 3.9, function() self.olaf:draw(ox, oy) end) end
  require('src.systems.companion').draw(self, add, ox, oy, shadow)
  for _, e in ipairs(self.enemies) do
    if self.cam:visible(e.body.x - 8, e.body.y - 16, 16, 16) then
      local es = sprites.enemy_sheets[e.kind.sprite]
      add(e.body.y + 4, function() e:draw(es.img, es.quads, ox, oy) end)
    end
  end
  for _, sh in ipairs(self.shots.list) do
    add(sh.y + 6, function()
      local reduced=require('src.motion').reduced
      local f = reduced and 1 or math.floor(sh.t * 8) % 2 + 1
      if not reduced then
        for k=3,1,-1 do
          love.graphics.setColor(sh.kind=='gust' and .65 or 1,.72,.38,(1-k/4)*.35)
          love.graphics.circle('fill',sh.x-ox-sh.vx*.018*k,sh.y-oy-sh.vy*.018*k,math.max(1,3-k*.6))
        end
        love.graphics.setColor(1,1,1,1)
      end
      if sh.kind == 'gust' then love.graphics.draw(sprites.gust, sprites.gust_quads[f], math.floor(sh.x - 8 - ox), math.floor(sh.y - 8 - oy))
      else
        local k = sh.kind == 'dragonfire' and 1.3 or 1
        if sh.kind == 'ice' then love.graphics.setColor(0.55, 0.85, 1, 1) end   -- raig de gel
        love.graphics.draw(sprites.fireball, sprites.fireball_quads[f], math.floor(sh.x - ox), math.floor(sh.y - oy), 0, k, k, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end)
  end
  -- llamps (encanteri Llamp): ziga-zaga del cel fins a l'enemic, 0,3 s
  if self.bolts then
    local now = love.timer.getTime()
    for i = #self.bolts, 1, -1 do
      local bo = self.bolts[i]
      local a = 1 - (now - bo.t0) / 0.3
      if a <= 0 then table.remove(self.bolts, i)
      else
        add(bo.y + 12, function()
          local x, y = math.floor(bo.x - ox), math.floor(bo.y - oy)
          local pts, yy = {}, y - 90
          while yy < y do
            pts[#pts + 1] = x + ((#pts % 2 == 0) and -5 or 5) + love.math.random(-2, 2); pts[#pts + 1] = yy
            yy = yy + 12
          end
          pts[#pts + 1] = x; pts[#pts + 1] = y
          love.graphics.setLineWidth(3); love.graphics.setColor(1, 0.95, 0.4, a); love.graphics.line(pts)
          love.graphics.setLineWidth(1); love.graphics.setColor(1, 1, 1, a); love.graphics.line(pts)
          love.graphics.setColor(1, 1, 1, 1)
        end)
      end
    end
  end
  if self.fishing then add(pl.body.y + 7, function() require('src.systems.fishing').draw(self, ox, oy) end) end
  -- escut màgic: bombolla al voltant del jugador (parpelleja quan s'acaba)
  if (self.state.ward_t or 0) > 0 then
    local wt = self.state.ward_t
    add(pl.body.y + 6, function()
      if wt < 2 and math.floor(wt * 8) % 2 == 0 then return end
      local x, y = math.floor(pl.body.x - ox), math.floor(pl.body.y - 10 - oy)
      love.graphics.setColor(0.55, 0.85, 1, 0.22); love.graphics.circle('fill', x, y, 13)
      love.graphics.setColor(0.75, 0.95, 1, 0.8); love.graphics.circle('line', x, y, 13)
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end
  for _, lm in ipairs(self.landmarks) do
    local o = lm.obj
    if self.cam:visible(o.x, o.y, o.w, o.h) then
      add(o.y + o.h, function() love.graphics.draw(lm.img, o.x - ox, o.y - oy) end)
    end
  end
  for i, tc in ipairs(self.torches) do   -- antorchas (2 frames)
    if self.cam:visible(tc.x - 8, tc.y - 16, 16, 16) then
      local f = require('src.motion').reduced and 1 or (math.floor(love.timer.getTime() * 5) + i) % 2 + 1
      add(tc.y - 8, function() love.graphics.draw(sprites.torch, sprites.torch_quads[f], tc.x - 4 - ox, tc.y - 16 - oy) end)
    end
  end
  for _, s in ipairs(self.signs) do
    if not s.props.display and not s.props.book and self.cam:visible(s.x - 8, s.y - 8, 16, 16) then   -- (llibres: sense rètol)
      add(s.y + 8, function() love.graphics.draw(sprites.sign, s.x - 8 - ox, s.y - 8 - oy) end)
    end
  end
  for _, c in ipairs(self.chests) do
    if self.cam:visible(c.rect.x, c.rect.y, 16, 16) then
      local open = self.sstate.chests[c.obj.props.flag]
      local tier = c.obj.props.tier
      local img = (tier and tier ~= 'wood') and sprites['chest_' .. tier .. (open and '_open' or '_closed')]
          or (open and sprites.chest_open or sprites.chest_closed)
      local sh=sprites.chest_anims[tier or 'wood']
      add(c.rect.y + 16, function()
        local x,y=c.rect.x-ox,c.rect.y-oy
        if sh then
          local frame=open and (c.open_t and require('src.motion').chest_frame(c.open_t) or 5) or 1
          love.graphics.draw(sh.img,sh.quads[frame],x,y)
        else love.graphics.draw(img,x,y) end
        if c.open_t and c.open_t<.9 and c.reward_icon then
          local icon=g:special_sprite(c.reward_icon)
          if icon then
            local motion=require('src.motion')
            local rise=motion.reduced and 0 or 10*motion.ease(c.open_t/.4)
            love.graphics.setColor(1,1,1,math.min(1,(.9-c.open_t)/.2))
            love.graphics.draw(icon,x,y-12-rise)
            love.graphics.setColor(1,1,1,1)
          end
        end
      end)
    end
  end
  require('src.systems.puzzles').draw(self, add, sprites.puzzle, ox, oy)
  for _, l in ipairs(self.levers) do
    local on = State.flag(self.state, l.obj.props.flag)
    add(l.rect.y + 10, function() love.graphics.draw(on and sprites.lever_on or sprites.lever_off, l.rect.x - ox, l.rect.y - 6 - oy) end)
  end
  for _, gt in ipairs(self.gates) do
    if not self:gate_open(gt) then
      add(gt.rect.y + gt.rect.h, function()
        love.graphics.setColor(0.25, 0.24, 0.27)
        for x = gt.rect.x + 2, gt.rect.x + gt.rect.w - 2, 4 do
          love.graphics.rectangle('fill', x - ox, gt.rect.y - 6 - oy, 2, gt.rect.h + 4)
        end
        love.graphics.rectangle('fill', gt.rect.x - ox, gt.rect.y - 6 - oy, gt.rect.w, 2)
        love.graphics.setColor(1, 1, 1)
      end)
    end
  end
  if self.home then
    add(self.home.y + 2, function() love.graphics.draw(sprites.home_mailbox, self.home.x + 8 - ox, self.home.y - 14 - oy) end)
  end
  for _, pc in ipairs(self.parked) do
    if self.cam:visible(pc.x - 18, pc.y - 18, 36, 36) then
      add(pc.y + (pc.orient == 'h' and 6 or 14), function() draw_car(g, pc, pc.x, pc.y, pc.orient, pc.rev, ox, oy) end)
    end
  end
  if self.peds then
    for _, p in ipairs(self.peds.list) do
      local sh = sprites.chars[p.sprite]
      if sh and self.cam:visible(p.x - 8, p.y - 20, 16, 24) then
        add(p.y + 4, function()
          shadow(p.x - ox, p.y + 3 - oy, 5, 2, 0.28 * math.max(0, math.min(1, p.alpha)))
          draw_ped(sh, p, ox, oy)
        end)
      end
    end
  end
  if self.fauna then self.fauna:draw(add, ox, oy, shadow, draw_ped) end
  local high = {}
  if self.traffic then
    for _, car in ipairs(self.traffic.cars) do
      local x, y, ang, level = Traffic.pos(car)
      if self.cam:visible(x - 16, y - 16, 32, 32) and level >= 0 then
        local fn
        local kd = Traffic.KINDS[car.kind or 'car']
        if kd and not kd.car then   -- moto o patinete: hoja de 32×32 con conductor
          local sh = sprites.traffic[car.kind .. '_' .. (car.kind == 'police' and 1 or car.variant)]
          local di = DIR_INDEX[require('src.systems.vehicles').facing(ang)]
          local f = car.v > 5 and math.floor(car.s / 6) % 2 or 0
          fn = function() love.graphics.draw(sh.img, sh.quads[di * 2 + f + 1], math.floor(x - 16 - ox + 0.5),
                                             math.floor(y - 24 - oy + 0.5)) end
        else
          local o, rev = require('src.systems.route').orient(ang)
          fn = function()
            draw_car(g, car, x, y, o, rev, ox, oy)
            if kd and kd.siren then   -- llums d'emergència: alternen cada quart de segon
              local on = math.floor(love.timer.getTime() * 4 + (car.variant or 0)) % 2 == 0
              local c1 = kd.siren == 'fire' and { 1, 0.3, 0.2 } or { 0.3, 0.55, 1 }
              local c2 = kd.siren == 'police' and { 1, 1, 1 } or { 1, 0.3, 0.2 }
              local sx, sy = math.floor(x - ox + 0.5), math.floor(y - oy - 3 + 0.5)
              love.graphics.setColor(on and c1 or c2); love.graphics.rectangle('fill', sx - 3, sy - 1, 2, 2)
              love.graphics.setColor(on and c2 or c1); love.graphics.rectangle('fill', sx + 1, sy - 1, 2, 2)
              love.graphics.setColor(1, 1, 1, 1)
            end
          end
        end
        if level == 1 then high[#high + 1] = fn else add(y + 6, fn) end
      end
    end
  end
  if self.sailboats then self.sailboats:draw(add, self.cam, sprites.sailboat, ox, oy) end
  if self.trains then
    for _, c in ipairs(self.trains:cars(self.cam)) do
      local fn = function() draw_train_car(g, c, ox, oy) end
      if c.level == 1 then high[#high + 1] = fn elseif c.level == 0 then add(c.y + 6, fn) end
    end
    for _, cr in ipairs(self.trains.crossings) do
      if self.cam:visible(cr.area.x, cr.area.y, cr.area.w, cr.area.h) then
        add(cr.y, function()
          local blink = cr.state ~= 'open' and math.floor(love.timer.getTime() * 3) % 2 == 0
          love.graphics.draw(blink and sprites.lamp_on or sprites.lamp_off, cr.area.x - 8 - ox, cr.y - 24 - oy)
          if cr.road_ang then   -- barreras animadas a ambos lados de la vía, atravesando la calle
            local ux, uy = math.cos(cr.road_ang), math.sin(cr.road_ang)
            local nx, ny = -uy, ux
            local cx, cy = cr.x - ox, cr.y - oy
            draw_barrier_arm(cx - ux * 22 + nx * 12, cy - uy * 22 + ny * 12, -nx, -ny, cr.bar, blink)
            draw_barrier_arm(cx + ux * 22 - nx * 12, cy + uy * 22 - ny * 12, nx, ny, cr.bar, blink)
          elseif cr.bar > 0.5 then
            love.graphics.draw(sprites.barrier, cr.area.x - ox, cr.area.y - 4 - oy)
            love.graphics.draw(sprites.barrier, cr.area.x + cr.area.w - 16 - ox, cr.area.y + cr.area.h - 12 - oy)
          end
        end)
      end
    end
  end
  table.sort(list, function(a, b) return a.y < b.y end)
  for _, it in ipairs(list) do it.fn() end
  self:draw_particles(ox, oy)
  self:draw_missions(ox, oy)
  require('src.systems.perles').draw(self, ox, oy)
  require('src.systems.marker').draw_world(self, ox, oy)
  require('src.systems.boat').draw(self, ox, oy)
  Town.draw_homes(self, ox, oy)

  love.graphics.push(); love.graphics.translate(-ox, -oy)
  r:draw_layer(chunks, 'bridge')
  r:draw_vectors(chunks, 1)
  love.graphics.pop()
  for _, fn in ipairs(high) do fn() end
  if pl.body.level == 1 or (pl.body.level == 0 and on_deck_ramp) then draw_player() end
  love.graphics.push(); love.graphics.translate(-ox, -oy)
  r:draw_layer(chunks, 'overhead')
  love.graphics.pop()
  if pl.body.level == -1 then -- silueta visible dentro del túnel
    love.graphics.setColor(1, 1, 1, 0.22); draw_player(); love.graphics.setColor(1, 1, 1)
  end

  if self.def.outdoor then
    local cars = {}
    if self.traffic then
      for _, car in ipairs(self.traffic.cars) do
        local x, y, ang, level = Traffic.pos(car)
        if level >= 0 and self.cam:visible(x - 40, y - 40, 80, 80) then cars[#cars + 1] = { x = x, y = y, ang = ang } end
      end
    end
    g.daylight:draw(self.state.clock, chunks, cars, { x = pl.body.x, y = pl.body.y, light = self:player_light(),
                                                      cone = self:flashlight_angle() }, ox, oy,
      g.theme and g.theme.night_tint, VW, VH)
    if g.weather and pl.body.level >= 0 and not zoomed then g.weather:draw(ox, oy) end
  end
  if self.def.dark then self:draw_darkness(ox, oy) end
  self.popups:draw(g.font, ox, oy)
  Town.draw_bubbles(self, ox, oy)
  -- indicador de interacción
  if not self.dialogue.open and self:can_interact() then
    local bob = require('src.motion').bob(love.timer.getTime()*3,1)
    love.graphics.draw(sprites.bubble, math.floor(pl.body.x - ox) + 4, math.floor(pl.body.y - oy) - 32 - bob)
  end
  if zoomed then   -- el món reduït a la pantalla; el temps i el HUD, a mida normal
    love.graphics.setCanvas({ g.canvas, stencil = true })
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.zcanvas, 0, 0, 0, 0.5, 0.5)
    if g.weather and pl.body.level >= 0 then g.weather:draw(ox, oy) end
  end
  local eq = self.state.equipment or {}
  local wi, li = g.items[eq.weapon or ''], g.items[eq.shield or '']
  local staff = Magic.has_staff(self.state, self.game.items)
  local sp = staff and Magic.BY_ID[self.state.spell or '']
  self.hud:draw(self.state, pl, (li or {}).kind == 'shield', staff, {
    weapon = wi and g:special_sprite(wi.sprite or 'sword') or nil,
    left = li and g:special_sprite(li.sprite or (li.kind == 'shield' and 'shield' or 'staff')) or nil,
    spell = sp and sp.name or nil })
  if self.boss and self.boss.state == 'fight' then self.hud:boss_bar(self.boss) end
  Town.draw_hud(self)   -- brúixola de la missió activa
  require('src.systems.marker').draw_hud(self)   -- brúixola de la marca del mapa
  if self.def.outdoor then self.hud:clock(require('src.systems.daylight').label(self.state.clock)) end
  self:draw_race_hud()
  require('src.systems.rest').draw(self)
  self.dialogue:draw()
end

function World:draw_missions(ox, oy)
  local r = self.race
  if r then   -- bandera de meta
    local x, y = math.floor(r.x - ox), math.floor(r.y - oy)
    love.graphics.setColor(0.25, 0.22, 0.27); love.graphics.rectangle('fill', x, y - 22, 2, 22)
    local wave = require('src.motion').bob(love.timer.getTime()*4,1)
    for i = 0, 3 do
      for j = 0, 2 do
        love.graphics.setColor((i + j) % 2 == 0 and { 0.12, 0.10, 0.14 } or { 0.96, 0.94, 0.89 })
        love.graphics.rectangle('fill', x + 2 + i * 3, y - 22 + j * 3 + (i % 2) * wave, 3, 3)
      end
    end
    love.graphics.setColor(1, 1, 1)
  end
  local got = self.sstate.pickups or {}
  for _, p in ipairs(self.pickups) do
    if not got[p.name] and self.cam:visible(p.x - 4, p.y - 4, 8, 8, 0) then
      local x, y = math.floor(p.x - ox), math.floor(p.y - oy)
      if p.item == 'petxina' then   -- petxina en ventall
        love.graphics.setColor(0.96, 0.82, 0.78); love.graphics.polygon('fill', x - 3, y + 2, x, y - 3, x + 3, y + 2)
        love.graphics.setColor(0.82, 0.6, 0.55); love.graphics.line(x, y - 2, x, y + 2); love.graphics.line(x - 2, y + 1, x, y - 2)
      else                           -- pinya
        love.graphics.setColor(0.55, 0.35, 0.2); love.graphics.ellipse('fill', x, y, 2.5, 3.5)
        love.graphics.setColor(0.38, 0.22, 0.12); love.graphics.line(x - 2, y - 1, x + 2, y - 1); love.graphics.line(x - 2, y + 1, x + 2, y + 1)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
  local w = self.state.missions and self.state.missions.wallet
  if type(w) == 'table' and self.id == 'overworld' then
    local x, y = math.floor(w.x - ox), math.floor(w.y - oy)
    love.graphics.setColor(0.42, 0.26, 0.15); love.graphics.rectangle('fill', x - 4, y - 3, 8, 6)
    love.graphics.setColor(0.6, 0.4, 0.22); love.graphics.rectangle('fill', x - 4, y - 3, 8, 2)
    if require('src.motion').reduced or math.floor(love.timer.getTime() * 2) % 2 == 0 then
      love.graphics.setColor(1, 1, 0.7); love.graphics.rectangle('fill', x + 3, y - 6, 1, 1)
    end
    love.graphics.setColor(1, 1, 1)
  end
end

function World:draw_race_hud()
  local r = self.race
  if not r then return end
  local txt = string.format('Cursa: %d s', math.max(0, math.ceil(r.t)))
  local w = self.game.font:getWidth(txt) + 10
  love.graphics.setColor(0.12, 0.10, 0.14, 0.8); love.graphics.rectangle('fill', 160 - w / 2, 220, w, 16)
  love.graphics.setColor(r.t < 6 and { 1, 0.5, 0.4 } or { 1, 0.95, 0.8 })
  love.graphics.print(txt, 160 - w / 2 + 5, 219)
  -- flecha hacia la meta
  local b = self.player.body
  local a = math.atan2(r.y - b.y, r.x - b.x)
  local cx, cy = 160 + math.cos(a) * 70, 120 + math.sin(a) * 50
  love.graphics.polygon('fill', cx + math.cos(a) * 6, cy + math.sin(a) * 6, cx + math.cos(a + 2.5) * 5, cy + math.sin(a + 2.5) * 5,
    cx + math.cos(a - 2.5) * 5, cy + math.sin(a - 2.5) * 5)
  love.graphics.setColor(1, 1, 1)
end

-- rètols dels edificis especials: Policia (llum blava i vermella), CAP (creu verda que brilla), Ajuntament
-- (escut i senyera que oneja), súpers, Correus i escoles; bústies i carros
local SIGN_Q
function World:draw_signs(add, ox, oy)
  local g = self.game
  if not SIGN_Q then   -- quads dels fotogrames (un sol cop)
    SIGN_Q = { siren = { love.graphics.newQuad(0, 0, 16, 6, 32, 6), love.graphics.newQuad(16, 0, 16, 6, 32, 6) },
               cross = { love.graphics.newQuad(0, 0, 14, 14, 28, 14), love.graphics.newQuad(14, 0, 14, 14, 28, 14) },
               flag = { love.graphics.newQuad(0, 0, 16, 24, 32, 24), love.graphics.newQuad(16, 0, 16, 24, 32, 24) } }
  end
  local t = love.timer.getTime()
  for _, o in ipairs(self.signboards) do
    if self.cam:visible(o.x - 40, o.y - 30, 80, 50) and not o.hidden then
      local p = o.props
      local im = g:special_sprite(p.sprite)
      add(o.y + 14, function()
        local x, y = math.floor(o.x - ox), math.floor(o.y - oy)
        if im then love.graphics.draw(im, x - math.floor(im:getWidth() / 2), y - 6) end
        local ex = p.extra ~= '' and g:special_sprite(p.extra)
        if p.extra == 'siren' and ex then
          local f = math.floor(t * 3) % 2
          love.graphics.draw(ex, SIGN_Q.siren[f + 1], x - 8, y - 13)
        elseif p.extra == 'cross_cap' and ex then
          local f = (math.sin(t * 3) > 0.2) and 1 or 0
          love.graphics.draw(ex, SIGN_Q.cross[f + 1], im and x - math.floor(im:getWidth() / 2) + im:getWidth() + 1 or x - 7, y - 8)
        elseif p.extra == 'shield_roda' and ex then
          love.graphics.draw(ex, x - 6, y - 22)
        end
        if p.flag then
          local fl = g:special_sprite('flag_senyera')
          if fl then
            local f = math.floor(t * 4) % 2
            love.graphics.draw(fl, SIGN_Q.flag[f + 1], x + (im and math.floor(im:getWidth() / 2) or 8) + 2, y - 26)
          end
        end
      end)
    end
  end
  for _, o in ipairs(self.props) do
    if self.cam:visible(o.x - 10, o.y - 22, 20, 30) and not o.hidden then
      local im = g:special_sprite(o.props.sprite)
      if im then
        add(o.y + 6, function()
          love.graphics.draw(im, math.floor(o.x - im:getWidth() / 2 - ox), math.floor(o.y + 6 - im:getHeight() - oy))
        end)
      end
    end
  end
end

-- con de la llanterna: rumb cap a on mira el jugador (o el vehicle), si la porta; nil si no
local FACE_ANG = { right = 0, down = math.pi / 2, left = math.pi, up = -math.pi / 2 }
function World:flashlight_angle()
  if (self.state.inventory.llanterna or 0) <= 0 then return nil end
  local pl = self.player
  if pl.vehicle and pl.vehicle.angle then return pl.vehicle.angle end
  return FACE_ANG[pl.facing] or math.pi / 2
end

-- luz del jugador: más amplia con la llanterna (data/items.json light)
function World:player_light()
  local l = self.game.items.llanterna
  return ((self.state.inventory.llanterna or 0) > 0 and l and l.light) or 1
end

-- Cuevas y mazmorras: oscuridad con luz dinámica. Un lienzo de luz (ambiente casi negro + focos aditivos:
-- el jugador y las antorchas, que parpadean) se multiplica sobre la escena, como el ciclo de noche.
function World:draw_darkness(ox, oy)
  local dl = self.game.daylight
  self.dark_canvas = self.dark_canvas or love.graphics.newCanvas(320, 240)
  local prev = love.graphics.getCanvas()
  love.graphics.push('all')
  love.graphics.setCanvas(self.dark_canvas)
  love.graphics.origin()
  love.graphics.clear(0.06, 0.05, 0.09, 1)
  love.graphics.setBlendMode('add')
  local t = love.timer.getTime()
  local function glow(x, y, r, cr, cg, cb)
    love.graphics.setColor(cr, cg, cb, 1)
    love.graphics.draw(dl.glow, x - r, y - r, 0, 2 * r / 64, 2 * r / 64)
  end
  local pr = 70 * self:player_light()
  glow(self.player.body.x - ox, self.player.body.y - 8 - oy, pr, 0.95, 0.9, 0.8)
  glow(self.player.body.x - ox, self.player.body.y - 8 - oy, pr * 0.55, 0.35, 0.33, 0.3)
  local ca = self:flashlight_angle()
  if ca then require('src.systems.daylight').cone(self.player.body.x - ox, self.player.body.y - 8 - oy, ca, 150, 1, 0.92, 0.72) end
  for _, sh in ipairs(self.shots.list) do
    if sh.kind == 'gust' then glow(sh.x - ox, sh.y - oy, 22, 0.35, 0.45, 0.5)
    else glow(sh.x - ox, sh.y - oy, 34, 1.0, 0.55, 0.2) end
  end
  if self.boss and self.boss.state ~= 'dead' then   -- el drac brilla una mica (escates) i molt quan treu foc
    local bx, by = self.boss.body.x - ox, self.boss.body.y - 22 - oy
    glow(bx, by, 64, 0.55, 0.62, 0.5)
    if self.boss.breath > 0 then glow(bx, by - 8, 70, 1, 0.5, 0.2) end
  end
  for i, tc in ipairs(self.torches) do
    local x, y = tc.x - ox, tc.y - 6 - oy
    if x > -80 and x < 400 and y > -80 and y < 320 then
      local f = 1 + 0.07 * math.sin(t * 11 + i * 1.7) + 0.05 * math.sin(t * 23 + i)
      glow(x, y, 58 * f, 1.0, 0.62, 0.28)
    end
  end
  love.graphics.pop()
  love.graphics.setCanvas(prev)
  love.graphics.setBlendMode('multiply', 'premultiplied')
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.dark_canvas, 0, 0)
  love.graphics.setBlendMode('alpha')
end

function World:release()
  self.ai_token=nil
  require('src.net').cancel(self.ai_req)
  self.map.chunks:clear()
end

return World
