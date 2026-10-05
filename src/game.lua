-- Coordina escena, entrada, guardado, render a 320×240 con escala entera y métricas.
local Input = require('src.input')
local Data = require('src.data')
local Map = require('src.world.map')
local Renderer = require('src.world.renderer')
local World = require('src.scenes.world_scene')
local State = require('src.state')
local Save = require('src.save')
local Home = require('src.home')
local Audio = require('src.audio')
local Hud = require('src.ui.hud')
local Menu = require('src.ui.menu')
local Collision = require('src.world.collision')
local Loop = require('src.loop')

local Game = {}
Game.__index = Game

local STEP = 1 / 60
local MAX_STEPS = 6
local VW, VH = 320, 240

local function img(path)
  local i = love.graphics.newImage(path)
  i:setFilter('nearest', 'nearest')
  return i
end

local function grid_quads(image, w, h)
  local out = {}
  local cols, rows = image:getWidth() / w, image:getHeight() / h
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      out[#out + 1] = love.graphics.newQuad(c * w, r * h, w, h, image:getDimensions())
    end
  end
  return out
end

local function char_sheet(path)
  local data, diag = require('src.paperdoll.diag').extend_data(love.image.newImageData(path))   -- + files en diagonal
  local sheet = love.graphics.newImage(data)
  sheet:setFilter('nearest', 'nearest')
  local quads = grid_quads(sheet, 16, 24)
  return { sheet = sheet, diag = diag, quad = function(row, col) return quads[row * 6 + col + 1] end }
end

function Game.new(args)
  local self = setmetatable({}, Game)
  self.args = args or {}
  love.graphics.setDefaultFilter('nearest', 'nearest')
  self.canvas = love.graphics.newCanvas(VW, VH)
  self.canvas:setFilter('nearest', 'nearest')
  local glyphs = love.filesystem.read('assets/runtime/font.txt')
  self.font = love.graphics.newImageFont('assets/runtime/font.png', glyphs, 0)
  love.graphics.setFont(self.font)

  self.world = Data.read_json('data/world.json')
  self.scenes = Data.read_json('data/scenes.json')
  -- interiores generados por el editor de zonas
  if love.filesystem.getInfo('maps/runtime/scenes_extra.json') then
    for k, v in pairs(Data.read_json('maps/runtime/scenes_extra.json')) do self.scenes[k] = v end
  end
  self.dialogue = Data.read_json('data/dialogue.json')
  self.items = Data.read_json('data/items.json')
  self.loot = Data.read_json('data/loot.json')
  self.renderer = Renderer.new('assets/runtime/tiles.png')
  local Daylight = require('src.systems.daylight')
  self.tile_defs = Data.read_json('data/tiles.json').tiles
  self.renderer.light_kind = Daylight.light_kinds(self.tile_defs)
  self.daylight = Daylight.new()
  self.themes, self.skins = require('src.themes').load()
  require('src.motion').set('user',require('src.settings').get().reduced_motion)
  self:load_sprites()
  self.hud = Hud.new(self.font, { heart_full = self.sprites.heart_full, heart_empty = self.sprites.heart_empty })
  self.audio = Audio
  if not self.args.mute then Audio.init() else Audio.enabled = false end
  -- opcions globals i veu (Web Speech API al navegador, espeak-ng a l'escriptori)
  self.settings = require('src.settings').load()
  local Upper = require('src.ui.upper')
  Upper.install(self.font)
  Upper.on = self.settings.upper and true or false
  Audio.configure(self.settings)
  if not self.args.mute then require('src.tts').init(self.settings) else require('src.tts').settings = self.settings end
  self.maps = {}
  self.loop = Loop.new(STEP, MAX_STEPS, 0.1)
  self.frame_times = {}
  self.frame_i = 0
  self.debug = false
  self.scene_manager = self
  self:load_home()
  self:load_house()
  -- versión web: la casa no está en el paquete; la da el servidor local (tools/web_server.py)
  if love.system.getOS() == 'Web' and not self.home then
    require('src.net').post('/api/private_home', {}, function(v)
      if type(v) ~= 'table' or type(v.home) ~= 'table' then return end
      self:load_home(v.home)
      if v.house then self:load_house(v.house) end
    end, 10)
  end
  self:load_config()
  -- perfils entre aparells (src/sync.lua): mai a les proves; en arrencar es baixa el que hi hagi al servidor
  local Sync = require('src.sync')
  Sync.off = (self.args.test or self.args.bench or self.args.shot) and true or false
  Sync.pull()
  self.menu = Menu.new(self, 'title')
  return self
end

-- configuració del servidor (config/joc.json, /api/config): s'edita des del PC i la llegeix el joc en
-- arrencar, també al mòbil. Sense servidor, els valors per defecte.
Game.CONFIG_DEFAULT = { veu = nil, volum = 0.6, volum_musica = 0.45, temps = 'auto', mostrar_tots_els_locals = false,
                        locals_verificats = {} }
function Game:load_config()
  self.config = {}
  for k, v in pairs(Game.CONFIG_DEFAULT) do self.config[k] = v end
  local a = self.args or {}
  if self.dev or a.test or a.bench or a.shot then return end   -- proves: sense dependre del servidor
  local Net = require('src.net')
  if not Net.available() then return end
  Net.post('/api/config', {}, function(v)
    if type(v) == 'table' and not v.error then self:apply_config(v) end
  end, 8)
end

function Game:apply_config(v)
  local c = self.config
  if v.veu == true or v.veu == false then c.veu = v.veu end
  if type(v.volum) == 'number' then c.volum = math.max(0, math.min(1, v.volum)) end
  if type(v.volum_musica) == 'number' then c.volum_musica = math.max(0, math.min(1, v.volum_musica)) end
  if type(v.temps) == 'string' then c.temps = v.temps end
  c.mostrar_tots_els_locals = v.mostrar_tots_els_locals == true
  c.locals_set = {}
  for _, id in ipairs(type(v.locals_verificats) == 'table' and v.locals_verificats or {}) do c.locals_set[id] = true end
  local Audio = self.audio
  Audio.configure(self.settings, c)
  local Tts = require('src.tts')
  if c.veu ~= nil and Tts.settings and Tts.settings.tts then Tts.settings.tts.on = c.veu end
  if self.scene and self.scene.refresh_locals then self.scene:refresh_locals() end
end

-- ¿es mostra aquest local real? (verificat el 2026 a data/locals.json o marcat a la configuració)
function Game:local_visible(id)
  local loc = self:local_info(id)
  if not loc then return true end
  local c = self.config or {}
  return loc.verified or c.mostrar_tots_els_locals or (c.locals_set and c.locals_set[id]) or false
end

function Game:load_sprites()
  local S = 'assets/runtime/sprites/'
  local s = {}
  s.player = char_sheet(S .. 'player.png')
  s.chars = {}
  for _, n in ipairs({ 'npc_baker', 'npc_fisher', 'npc_elder', 'npc_girl', 'npc_ranger', 'npc_postie', 'npc_tourist',
                       'npc_kid', 'npc_lady', 'npc_police', 'npc_doctor', 'npc_clerk', 'npc_coach', 'npc_teacher', 'npc_builder', 'npc_builder2',
                       'npc_cat_orange', 'npc_cat_grey' }) do
    s.chars[n] = char_sheet(S .. n .. '.png')
  end
  -- El gos domèstic reutilitza els fotogrames de fauna (16×16, mirant a l'esquerra).
  local dog = img(S .. 'animal_dog_brown.png')
  local dog_quads = grid_quads(dog, 16, 16)
  s.chars.npc_dog = { sheet = dog, height = 16, side_facing = true,
    quad = function(_, col) return dog_quads[col < 4 and (col % 2 + 1) or (col == 4 and 3 or 4)] end }
  local variety = Data.read_json('data/variety.json')
  for name in pairs(variety.characters) do s.chars[name] = char_sheet(S .. name .. '.png') end
  s.chest_anims = {}
  for _, tier in ipairs({'wood','iron','silver','legend','sea','forest','roman','crystal'}) do
    local image = img(S .. 'chest_anim_' .. tier .. '.png')
    s.chest_anims[tier] = {img=image, quads=grid_quads(image,16,16)}
  end
  s.enemy_sheets = {}
  s.enemies = {}
  for _, k in ipairs({ 'boar', 'bat', 'fox', 'wolf', 'snake' }) do
    local i = img(S .. 'enemy_' .. k .. '.png')
    s.enemy_sheets['enemy_' .. k] = { img = i, quads = grid_quads(i, 16, 16) }
    s.enemies[k] = s.enemy_sheets['enemy_' .. k]
  end
  s.slash = img(S .. 'slash.png'); s.slash_quads = grid_quads(s.slash, 16, 16)
  -- fase 6: el drac (64 × 48) i els projectils
  local dimg = img(S .. 'dragon.png')
  s.enemy_sheets.dragon = { img = dimg, quads = grid_quads(dimg, 64, 48) }
  s.fireball = img(S .. 'fireball.png'); s.fireball_quads = grid_quads(s.fireball, 12, 12)
  s.gust = img(S .. 'gust.png'); s.gust_quads = grid_quads(s.gust, 16, 16)
  s.player_action = img(S .. 'player_action.png'); s.player_action_quads = grid_quads(s.player_action, 32, 32)
  s.player_bike = img(S .. 'player_bike.png'); s.player_bike_quads = grid_quads(s.player_bike, 32, 32)
  for _, n in ipairs({ 'sword', 'shield', 'heart_full', 'heart_empty', 'postcard', 'notebook', 'chest_closed',
                       'chest_open', 'lever_off', 'lever_on', 'sign', 'bubble', 'cave_exit', 'home_mailbox',
                       'barrier', 'lamp_off', 'lamp_on', 'chest_iron_closed', 'chest_iron_open',
                       'chest_silver_closed', 'chest_silver_open', 'chest_legend_closed', 'chest_legend_open' }) do
    s[n] = img(S .. n .. '.png')
  end
  s.torch = img(S .. 'torch.png'); s.torch_quads = grid_quads(s.torch, 8, 16)
  s.car_h = img(S .. 'car_h.png'); s.car_hq = grid_quads(s.car_h, 32, 16)
  s.car_v = img(S .. 'car_v.png'); s.car_vq = grid_quads(s.car_v, 16, 32)
  s.car_d = img(S .. 'car_d.png'); s.car_dq = grid_quads(s.car_d, 24, 24)
  -- modelos de coche 5-12 (car2_*) y furgonetas de reparto (van2_*): ver tools/make_sprites.py
  s.car2_h = img(S .. 'car2_h.png'); s.car2_hq = grid_quads(s.car2_h, 32, 16)
  s.car2_v = img(S .. 'car2_v.png'); s.car2_vq = grid_quads(s.car2_v, 16, 32)
  s.car2_d = img(S .. 'car2_d.png'); s.car2_dq = grid_quads(s.car2_d, 24, 24)
  s.van2_h = img(S .. 'van2_h.png'); s.van2_hq = grid_quads(s.van2_h, 32, 16)
  s.van2_v = img(S .. 'van2_v.png'); s.van2_vq = grid_quads(s.van2_v, 16, 32)
  s.van2_d = img(S .. 'van2_d.png'); s.van2_dq = grid_quads(s.van2_d, 24, 24)
  -- coche de la Policia Local (15) y ambulancia (16), aparcados delante de su edificio
  s.svc_h = img(S .. 'svc_h.png'); s.svc_hq = grid_quads(s.svc_h, 32, 16)
  s.svc_v = img(S .. 'svc_v.png'); s.svc_vq = grid_quads(s.svc_v, 16, 32)
  s.svc_d = img(S .. 'svc_d.png'); s.svc_dq = grid_quads(s.svc_d, 24, 24)
  -- fauna de calle (perros, gatos, pájaros): 6 fotogramas 16 × 16 por pelaje
  s.animals = {}
  for _, f in ipairs(love.filesystem.getDirectoryItems(S)) do
    local name = f:match('^animal_(.+)%.png$')
    if name then
      local i = img(S .. f)
      s.animals[name] = { img = i, quads = grid_quads(i, 16, 16) }
    end
  end
  s.train_h = img(S .. 'train_h.png'); s.train_hq = grid_quads(s.train_h, 48, 16)
  s.train_v = img(S .. 'train_v.png'); s.train_vq = grid_quads(s.train_v, 16, 48)
  s.train_d = img(S .. 'train_d.png'); s.train_dq = grid_quads(s.train_d, 40, 40)
  do local i = img(S .. 'sailboat.png'); s.sailboat = { img = i, quads = grid_quads(i, 24, 24) } end   -- velers
  s.helmet_overlay = img(S .. 'helmet_overlay.png'); s.helmet_overlay_quads = grid_quads(s.helmet_overlay, 16, 24)
  do local i = img(S .. 'puzzle.png'); s.puzzle = { img = i, quads = grid_quads(i, 16, 16) } end   -- puzles de masmorra
  do local i = img(S .. 'errands.png'); s.errands = { img = i, quads = grid_quads(i, 16, 16) } end   -- encàrrecs dels veïns
  for _, k in ipairs({ 'ruc', 'cavall', 'porc', 'ovella', 'gallina' }) do   -- animals de les granges (src/systems/farm.lua)
    local i = img(S .. 'farm_' .. k .. '.png')
    s['farm_' .. k] = { img = i, quads = k == 'gallina' and grid_quads(i, 16, 16) or grid_quads(i, 24, 20) }
  end
  -- motos y patinetes del tráfico (32×32: 2 frames × abajo, arriba, izquierda, derecha)
  s.traffic = {}
  for _, k in ipairs({ 'moto_1', 'moto_2', 'police_1', 'patinete_1', 'patinete_2' }) do
    local i = img(S .. 'traffic_' .. k .. '.png')
    s.traffic[k] = { img = i, quads = grid_quads(i, 32, 32) }
  end
  s.landmarks = {}
  for _, f in ipairs(love.filesystem.getDirectoryItems(S)) do
    local name = f:match('^(landmark_.+)%.png$')
    if name then s.landmarks[name] = img(S .. f) end
  end
  if love.filesystem.getInfo('assets/runtime/minimap.png') then s.minimap = img('assets/runtime/minimap.png') end
  self.sprites = s
end

-- aspecto del protagonista (data/skins.json); vuelve al clásico si falta alguna hoja
-- sprites dels edificis especials (rètols, llums, bústies…): es carreguen la primera vegada que es veuen
function Game:special_sprite(name)
  local s = self.sprites
  s.special = s.special or {}
  if s.special[name] == nil then
    local p = 'assets/runtime/sprites/' .. name .. '.png'
    s.special[name] = love.filesystem.getInfo(p) and img(p) or false
  end
  return s.special[name] or nil
end

-- avatar del perfil (src/paperdoll/): hojas de caminar, ataque, bici y vehículos generadas por capas
function Game:apply_avatar(look)
  local Looks = require('src.paperdoll.looks')
  local b = Looks.build(look, true)
  self.avatar_key = Looks.key(look)
  local s = self.sprites
  s.player = { sheet = b.sheet, quad = b.quad, diag = b.diag }
  s.player_action, s.player_action_quads = b.action, b.action_quads
  s.player_bike, s.player_bike_quads = b.bike, b.bike_quads
  s.player_bike_diag = b.bike_diag
  s.player_vehicles = b.vehicles
  if self.state then self.state.skin = 'avatar' end
end

function Game:apply_skin(id)
  if id == 'avatar' then
    if self.profile then self:apply_avatar(self.profile.avatar); return end
    id = 'nena'
  end
  local S = 'assets/runtime/sprites/'
  local base = (id and id ~= 'default') and ('player_' .. id) or 'player'
  if not love.filesystem.getInfo(S .. base .. '.png') then base, id = 'player', 'default' end
  local s = self.sprites
  s.player = char_sheet(S .. base .. '.png')
  s.player_action = img(S .. (base == 'player' and 'player_action' or base .. '_action') .. '.png')
  s.player_action_quads = grid_quads(s.player_action, 32, 32)
  s.player_bike = img(S .. (base == 'player' and 'player_bike' or base .. '_bike') .. '.png')
  s.player_bike_quads = grid_quads(s.player_bike, 32, 32)
  s.player_bike_diag = nil   -- (les fulles PNG no en tenen: es veu en 4 direccions)
  -- vehículos (tools/make_sprites.py): <base>_<vehículo>.png, mismas 2 × 4 casillas de 32 px que la bici
  s.player_vehicles = {}
  for _, v in ipairs({ 'patinete', 'scooter', 'motocross' }) do
    local p = S .. base .. '_' .. v .. '.png'
    if love.filesystem.getInfo(p) then
      local i = img(p)
      s.player_vehicles[v] = { img = i, quads = grid_quads(i, 32, 32) }
    end
  end
  if self.state then self.state.skin = id end
end

-- temporada: 'auto' (por fecha), 'none' o el id de un tema; reconstruye los adornos del mapa
function Game:apply_theme(setting)
  local Themes = require('src.themes')
  if self.state then self.state.theme = setting end
  self.theme = Themes.active(self.themes, setting)
  self.renderer.theme = Themes.render_spec(self.theme, self.tile_defs)
  for _, m in pairs(self.maps) do m.chunks:clear() end
end

-- interiores generados en memoria (procgen.lua o la casa privada): id → { spec, back }
function Game:register_generated(id, spec, back, music)
  self.generated = self.generated or {}
  self.generated[id] = { spec = spec, back = back }
  self.scenes[id] = { map = 'proc/' .. id, music = music or 'overworld', outdoor = false, interior = true,
                      name = spec.name or id, generated = true }
  if self.maps[id] then self.maps[id] = nil end
end

-- interior procedural de la fachada (tx, ty) del exterior: mismo edificio → mismo interior
-- floors: plantes de l'edifici (files de façana al mapa): casa de 2 plantes amb escala o bloc de pisos amb
-- portal, replans, ascensor i pisos (procgen.building). Totes les plantes es registren alhora (només taules de
-- noms; el mapa de cada planta es construeix quan s'hi entra).
-- locals reals del poble (data/locals.json, tools/make_locals.py): id → { name, kind, sign, ... }
function Game:local_info(id)
  if not self.locals_by_id then
    self.locals_by_id = {}
    local raw = love.filesystem.read('data/locals.json')
    local ok, doc = pcall(function() return raw and require('src.lib.json').decode(raw) end)
    for _, l in ipairs(ok and doc and doc.locals or {}) do self.locals_by_id[l.id] = l end
  end
  return id and self.locals_by_id[id]
end

function Game:proc_interior(tx, ty, kind, back, floors, local_id, size, solar)
  local id = string.format('proc_%d_%d', tx, ty)
  if not (self.generated and self.generated[id]) then
    local Procgen = require('src.world.procgen')
    local seed = tx * 7919 + ty * 104729
    if kind == 'shop' then
      local loc = self:local_info(local_id)   -- el local real d'aquesta porta: mobles, nom i qui t'atén
      self:register_generated(id, Procgen.generate({ kind = kind, seed = seed, theme = loc and loc.kind,
                                                     name = loc and loc.name, w = size and size.w, h = size and size.h }), back)
    else
      local b = Procgen.building({ kind = kind, seed = seed, base = id, floors = floors or 1 })
      if solar and b.specs[id] then Procgen.solarize(b.specs[id], seed) end   -- casa amb placas al teulat
      for sid, spec in pairs(b.specs) do self:register_generated(sid, spec, back) end
    end
  end
  if self.state then self.state.proc = { id = id, tx = tx, ty = ty, kind = kind, back = back, floors = floors,
                                        local_id = local_id, size = size, solar = solar } end
  return id
end

-- interior de un servei amb minijocs (Casino, Gimnàs, Poliesportiu, Camp de futbol): procgen.poi
-- npc: { sprite, name, service, service_id, label } (el mateix personatge que fa de servei a fora)
function Game:poi_interior(service_id, kind, back, npc, size)
  local id = 'poi_' .. service_id
  if not (self.generated and self.generated[id]) then
    local seed = 0
    for i = 1, #service_id do seed = seed + service_id:byte(i) * 31 * i end
    local spec = require('src.world.procgen').poi({ kind = kind, npc = npc, name = npc and npc.label, size = size,
                                                    seed = seed })
    self:register_generated(id, spec, back)
  end
  if self.state then
    self.state.proc = { id = id, poi = service_id, kind = kind, back = back, npc = npc }
  end
  return id
end

-- casa d'un amic o dels avis del perfil: interior procedural (mateixa porta → mateixa distribució) amb el
-- terra triat a l'editor, el gat si en té i el personatge a dins si el seu horari diu que és a casa
local FLOOR_SET = { wood = { 'i_floor_wood_0', 'i_floor_wood_1' }, tile = { 'i_floor_tile_0', 'i_floor_tile_1' },
                    carpet = { 'i_floor_carpet_0', 'i_floor_carpet_1' } }
function Game:friend_interior(f, back)
  local id = 'friend_' .. f.id
  local Procgen = require('src.world.procgen')
  local Schedule = require('src.systems.schedule')
  -- llavor estable: la porta + l'id de l'amic (dos amics a la mateixa porta tenen cases diferents)
  local seed = f.home.door_x * 7919 + f.home.door_y * 104729
  for i = 1, #tostring(f.id) do seed = seed + tostring(f.id):byte(i) * 31 * i end
  local spec, entry = nil, id
  if f.interior.kind == 'block' then
    -- bloc de pisos: portal, replà i ascensor; el personatge viu al 1r 1a
    local b = Procgen.building({ kind = 'block', seed = seed, base = id, floors = 3, flats = 2, name = 'Portal de ' .. f.name })
    local home_id = Procgen.flat_id(id, 1, 1)
    for sid, sp in pairs(b.specs) do if sid ~= home_id then self:register_generated(sid, sp, back) end end
    spec, id = b.specs[home_id], home_id
    spec.name = 'Pis de ' .. f.name .. ' (' .. Procgen.flat_label(1, 1) .. ')'
  else
    spec = Procgen.generate({ kind = 'house', seed = seed, name = 'Casa de ' .. f.name })
  end
  Procgen.enrich(spec, { seed = seed, age = Schedule.kind_of_friend(f) })
  -- el terra triat a l'editor substitueix només la fusta del saló i el dormitori (cuina i bany segueixen amb rajola)
  local set = FLOOR_SET[f.interior.floor] or FLOOR_SET.wood
  for i, nm in ipairs(spec.ground) do
    if nm:match('^i_floor_wood_') then spec.ground[i] = set[(i % 2) + 1] end
  end
  -- fora els veïns inventats: aquí hi viu el personatge del perfil
  local objs = {}
  for _, o in ipairs(spec.objects) do if o.type ~= 'npc' then objs[#objs + 1] = o end end
  spec.objects = objs
  -- els pares ocupen el seu racó; el personatge i el gat busquen una cel·la lliure que no sigui seva
  local taken = {}
  for _, o in ipairs(require('src.systems.family').friend_parents(self, spec, f, self.state)) do
    objs[#objs + 1] = o; taken[o.y * spec.w + o.x] = true
  end
  local function free_spot(dx, dy)
    local cx, cy = math.floor(spec.w / 2) + dx, math.floor(spec.h / 2) + dy
    for r = 0, 6 do
      for yy = cy - r, cy + r do
        for xx = cx - r, cx + r do
          if xx > 0 and yy > 1 and xx < spec.w - 1 and yy < spec.h - 2 and spec.structures[yy * spec.w + xx + 1] == ''
              and not taken[yy * spec.w + xx] then
            return xx, yy
          end
        end
      end
    end
  end
  local place = self.state and Schedule.place(Schedule.kind_of_friend(f), self.state.clock, self.state.day) or 'home'
  if place == 'home' then
    local x, y = free_spot(0, -1)
    if x then
      objs[#objs + 1] = { type = 'npc', x = x, y = y, sprite = 'friend_' .. f.id, name = f.name, say = { 'Hola!' },
                          facing = 'down', wander = 1, friend = f.id }
      taken[y * spec.w + x] = true
    end
  end
  if f.interior.cat then
    local x, y = free_spot(2, 1)
    if x then
      objs[#objs + 1] = { type = 'npc', x = x, y = y, sprite = 'npc_cat_orange', name = 'El gat', say = { 'Miau!', 'Prrr...' },
                          facing = 'down', wander = 2 }
      taken[y * spec.w + x] = true
    end
  end
  if f.interior.dog then
    local x, y = free_spot(-2, 1)
    if x then
      objs[#objs + 1] = { type = 'npc', x = x, y = y, sprite = 'npc_dog', name = 'El gos',
                          say = { 'Bup, bup!', 'El gos mou la cua, content de veure’t.' }, facing = 'left', wander = 2 }
      taken[y * spec.w + x] = true
    end
  end
  self:register_generated(id, spec, back)
  if self.state then self.state.proc = { id = entry, friend = f.id, back = back } end
  return entry
end

-- casa privada (casa_privada.json, generada por tools/casa_privada.py): fuera del paquete y del repositorio.
-- Escritorio: directorio de datos de LÖVE; web: el servidor local la sirve por /api/private_home.
function Game:load_house(data)
  -- web: la casa arriba per /api/private_home en arrencar i no hi ha fitxer local; es reaprofita en començar
  -- una partida amb perfil (si no, la casa del perfil era un interior genèric sense pare ni mare)
  if data then self.house_data = data end
  data = data or self.house_data
  if not data then
    if not love.filesystem.getInfo('casa_privada.json') then return end
    local ok, v = pcall(Data.read_json, 'casa_privada.json')
    if not ok or type(v) ~= 'table' then self.warning = 'casa_privada.json no és vàlid'; return end
    data = v
  end
  if type(data.floors) ~= 'table' or not data.entry then return end
  local back = self.home and { scene = self.home.scene, x = self.home.x, y = self.home.y + 4, level = 0 } or
      { scene = 'overworld', x = 0, y = 0 }
  require('src.systems.crafting').ensure_bench(data.floors[data.entry])   -- banc de taller a la planta d'entrada
  for id, spec in pairs(data.floors) do self:register_generated(id, spec, back) end
  local order = type(data.order) == 'table' and data.order or nil   -- plantas de abajo arriba (pare i mare)
  self.house = { entry = data.entry, name = data.name or 'Casa', spawn = data.entry_spawn,
                 entrance = data.entrance,   -- 'este': se entra por la pared este (tools/casa_privada.py)
                 floors = order }
end

function Game:get_map(scene)
  if not self.maps[scene] then
    local def = self.scenes[scene]
    if not def then error('escena desconocida: ' .. tostring(scene)) end
    if def.generated then
      local g = self.generated[scene]
      local anim = self.scenes.overworld and self:get_map('overworld').anim
      local m, warns = require('src.world.procmap').build(scene, g.spec, self.tile_defs, g.back, anim)
      for _, w in ipairs(warns) do print('[' .. scene .. '] ' .. w) end
      m.chunks.on_unload = Renderer.release
      self.maps[scene] = m
      return m
    end
    local Codec = require('src.world.chunkcodec')
    local m = Map.load(def.map, function(p) return love.filesystem.load(p)() end,
      function(p) return Codec.decode(assert(love.filesystem.read(p), p)) end)
    m.chunks.on_unload = Renderer.release
    self.maps[scene] = m
  end
  return self.maps[scene]
end

function Game:load_home(cfg)
  cfg = cfg or Home.read()
  if cfg.configured and not cfg.profile then self.real_home_cfg = cfg end   -- home.json (o /api/private_home)
  local home, why = Home.resolve(cfg, function(s) return self:get_map(s) end, self.world.start_spawn)
  self.home = home
  self.home_warning = (cfg.configured or cfg.error) and not home and ('Casa no vàlida: ' .. tostring(why)) or nil
  if self.home_warning then self.warning = self.home_warning end
end

-- la casa del perfil és la de veritat (la del plànol, casa_privada.json) si cau a tocar de home.json
function Game:is_real_home(h)
  local r = self.real_home_cfg
  if not (r and h) or not (self.house_data or love.filesystem.getInfo('casa_privada.json')) then return false end
  return math.abs((tonumber(r.tile_x) or -99) - (h.tile_x or 0)) <= 6 and math.abs((tonumber(r.tile_y) or -99) - (h.tile_y or 0)) <= 6
end

-- casa d'un perfil fora de la casa de veritat: planta baixa i planta de dalt procedurals (mateixa adreça → mateixa
-- casa), amb el banc de taller i la família (src/systems/family.lua) com a la casa de sempre
function Game:profile_house(profile)
  local Procgen = require('src.world.procgen')
  local h = profile.home
  local seed = (h.tile_x or 0) * 7919 + (h.tile_y or 0) * 104729 + 77
  local b = Procgen.building({ kind = 'house', seed = seed, base = 'casa_perfil', floors = 2,
                               name = 'Casa de ' .. tostring(profile.name or 'la protagonista') })
  local back = self.home and { scene = self.home.scene, x = self.home.x, y = self.home.y + 4, level = 0 } or
      { scene = 'overworld', x = 0, y = 0 }
  for id, spec in pairs(b.specs) do
    -- fora els veïns inventats: és casa teva (els pares hi posa src/systems/family.lua)
    local objs = {}
    for _, o in ipairs(spec.objects) do if o.type ~= 'npc' or (o.name or ''):match('gat') then objs[#objs + 1] = o end end
    spec.objects = objs
    self:register_generated(id, spec, back)
  end
  require('src.systems.crafting').ensure_bench(b.specs.casa_perfil)
  self.house = { entry = 'casa_perfil', name = 'Casa de ' .. tostring(profile.name or ''), spawn = 'spawn_in',
                 floors = { 'casa_perfil', 'casa_perfil_p1' }, layout = b.specs.casa_perfil.layout }
end

-- ------------------------------------------------------------- escenas y spawns
function Game:spawn_point(scene, name)
  local map = self:get_map(scene)
  local function ok(o)
    return o and Collision.walk_at(map:cell(math.floor(o.x / 16), math.floor(o.y / 16)), o.props.level or 0)
  end
  local o = map:object('spawn', name)
  if ok(o) then return { x = o.x, y = o.y, level = o.props.level or 0, facing = o.props.facing } end
  for _, s in ipairs(map:objects_of('spawn')) do
    if s.props.public and ok(s) then
      self.hud:toast('Punt d\'aparició no vàlid: s\'usa ' .. s.name)
      return { x = s.x, y = s.y, level = 0 }
    end
  end
  error('escena ' .. scene .. ' sin spawn válido')
end

-- carga la nueva escena, valida el spawn y solo después libera la anterior
function Game:change(scene, spawn_name, spawn)
  self.transition = { t = 0, phase = 'out', scene = scene, spawn_name = spawn_name, spawn = spawn }
end

-- celda transitable más cercana a (x, y) a nivel `level` (radio en tiles) o nil
function Game:nearest_walkable(scene, x, y, level, radius)
  local map = self:get_map(scene)
  local tx0, ty0 = math.floor(x / 16), math.floor(y / 16)
  for r = 0, radius or 6 do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local tx, ty = tx0 + dx, ty0 + dy
          if map:in_bounds(tx, ty) and Collision.walk_at(map:cell(tx, ty), level or 0) then
            if r == 0 then return x, y end
            return tx * 16 + 8, ty * 16 + 8
          end
        end
      end
    end
  end
end

function Game:do_change(tr)
  local sp = tr.spawn
  if sp then  -- punto explícito (bus, salida de interiores): nunca dentro de un muro
    local x, y = self:nearest_walkable(tr.scene, sp.x, sp.y, sp.level or 0)
    if x then sp.x, sp.y = x, y else sp = nil end
  end
  sp = sp or self:spawn_point(tr.scene, tr.spawn_name)
  local new = World.new(self, tr.scene, sp)
  local old = self.scene
  self.scene = new
  if old and old.map ~= new.map then old:release() end
  self.state.scene = tr.scene
  self.state.x, self.state.y, self.state.level = sp.x, sp.y, sp.level or 0
  Audio.music_play(self.scenes[tr.scene].music)
  Input.clear()
  if old then self:save_game(false) end -- autoguardado al cambiar de escena
end

-- ---------------------------------------------------------------- perfiles (src/profile.lua)
-- slot: 1..5; mode: 'new' (partida nueva con este perfil) o 'continue'
function Game:start_profile(slot, profile, mode)
  local Profile = require('src.profile')
  self.slot, self.profile = slot, profile
  Save.use(Profile.dir(slot))
  -- casa: la del perfil; sin casa en el perfil, la configuración local de siempre (home.json)
  if profile.home then
    self.house = nil
    self:load_home(Profile.home_cfg(profile))
    -- la casa del protagonista és sempre la del plànol (casa_privada.json, de casa-plano del hub) on sigui que la
    -- posi el perfil; només si no hi ha plànol (un altre equip), una de les 10 distribucions procedurals
    self:load_house()
    if not self.house then self:profile_house(profile) end
  else
    self:load_home()
    self:load_house()
  end
  require('src.paperdoll.looks').clear_cache()
  self:build_friends()
  if mode == 'continue' and Save.exists() then self:continue_game() else self:new_game() end
end

-- personajes del perfil (amigos y abuelos): hoja paperdoll, casa e interior
function Game:build_friends()
  local Looks = require('src.paperdoll.looks')
  self.friends = {}
  for _, f in ipairs(self.profile and self.profile.friends or {}) do
    local key = 'friend_' .. f.id
    self.sprites.chars[key] = Looks.build(f.look)
    self.friends[#self.friends + 1] = { def = f, sprite = key }
  end
end

function Game:new_game()
  self.state = State.new(self.world)
  if self.profile then
    self.state.skin = 'avatar'
    self.state.player_name = self.profile.name
  end
  self.menu = nil
  local sp
  if self.home then sp = { x = self.home.x, y = self.home.y, level = 0 } end
  self:apply_skin(self.state.skin)
  self:apply_theme(self.state.theme or 'auto')
  self:do_change({ scene = self.home and self.home.scene or 'overworld', spawn_name = self.world.start_spawn,
                   spawn = sp })
  if self.home_warning then self.hud:toast(self.home_warning, 4)
  elseif self.theme and self.theme.welcome then self.hud:toast(self.theme.welcome, 4) end
end

function Game:has_save() return Save.exists() end

function Game:continue_game()
  local st, src, warn = Save.read()
  if not st then
    self.warning = warn or 'No hi ha cap partida desada.'
    return
  end
  self.state = st
  self.menu = nil
  require('src.systems.rpg').ensure(st)   -- partidas de versiones anteriores
  st.clock = st.clock or 540
  st.stops = st.stops or {}
  self:apply_skin(st.skin)
  self:apply_theme(st.theme or 'auto')
  -- interior procedural: se regenera igual a partir de la fachada; si no se puede, de vuelta al exterior
  if not self.scenes[st.scene] then
    local p = st.proc
    local fr = p and p.friend and self.profile and require('src.systems.town').friend(self, p.friend)
    if p and p.id == st.scene and p.poi then
      self:poi_interior(p.poi, p.kind, p.back, p.npc, require('src.systems.services').STORE_SIZE[p.poi])
    elseif fr and fr.home and (p.id == st.scene or st.scene:sub(1, #p.id + 2) == p.id .. '_p') then
      self:friend_interior(fr, p.back)
    elseif p and p.tx and (p.id == st.scene or st.scene:sub(1, #p.id + 2) == p.id .. '_p') then
      self:proc_interior(p.tx, p.ty, p.kind, p.back, p.floors, p.local_id, p.size, p.solar)   -- també una altra planta o un pis del bloc
    end
    if not self.scenes[st.scene] then st.scene, st.x, st.y, st.level = 'overworld', -1, -1, 0 end
  end
  -- validar la posición guardada; si no es transitable, usar un spawn público
  local map = self:get_map(st.scene)
  local tx, ty = math.floor(st.x / 16), math.floor(st.y / 16)
  local sp
  if map:in_bounds(tx, ty) and Collision.walk_at(map:cell(tx, ty), st.level or 0) then
    sp = { x = st.x, y = st.y, level = st.level or 0, facing = st.facing }
  end
  self:do_change({ scene = st.scene, spawn_name = st.scene == 'overworld' and self.world.start_spawn or 'spawn_entrance',
                   spawn = sp })
  if warn then self.hud:toast(warn, 4)
  elseif self.theme and self.theme.welcome then self.hud:toast(self.theme.welcome, 4) end
end

function Game:save_game(announce)
  if not self.state then return end
  local ok, why = Save.write(self.state)
  self.save_error = not ok and why or nil
  if announce or not ok then
    self.hud:toast(ok and 'Partida desada' or ('Error en desar: ' .. tostring(why)))
    if ok and announce then self:close_menu() end
  end
  return ok, why
end

function Game:to_title()
  require('src.net').cancel_all()
  if self.scene then self.scene:release() end
  self.scene = nil
  self.state = nil
  if self.profile then   -- tornar a la configuració sense perfil (guardat i casa de sempre)
    self.profile, self.slot, self.friends = nil, nil, nil
    Save.use(require('src.profile').quick_dir())
    self:load_home(); self:load_house()
  end
  self.menu = Menu.new(self, 'title')
  Audio.set_context({ scene = 'overworld' })
end

function Game:open_menu(screen)
  self.menu = Menu.new(self, 'pause')
  if screen then self.menu.screen = screen end
  Audio.pause(true)
end

-- lista de opciones a pantalla (viaje en bus, aspecto…): items = { {texto, función}, … }
function Game:open_list(title, items)
  self.menu = Menu.new(self, 'list')
  self.menu.title, self.menu.list = title, items
  Input.clear()
end

function Game:close_menu()
  self.menu = nil
  Audio.pause(false)
  Input.clear()
end

-- ------------------------------------------------------------- bucle
function Game:update(dt)
  self.t_frame0 = love.timer.getTime()
  local turbo = self.dev and self.dev.turbo   -- tests: varios pasos fijos por frame
  self.loop:advance(dt, function(step)
    local act = Input.step()                -- acciones de un solo uso: se consumen aquí
    if self.dev and self.dev.step then self.dev:step(act, step) end
    self:sim(step, act)
  end, turbo)
  self.dropped = self.loop.dropped
  self.renderer:update(dt)
  Audio.update(dt)                -- música adaptativa, fundidos y síntesis pendiente (por trozos)
  require('src.sync').update(dt)  -- perfils i partides pendents de pujar al servidor
  require('src.webui').update(self)
  require('src.ui.speech').update(self)   -- menús en veu alta
  require('src.net').update(dt)   -- respuestas pendientes (IA de los personajes)
end

function Game:sim(dt, act)
  if self.transition then
    local tr = self.transition
    tr.t = tr.t + dt
    if tr.phase == 'out' and tr.t >= 0.18 then
      self:do_change(tr)
      tr.phase, tr.t = 'in', 0
    elseif tr.phase == 'in' and tr.t >= 0.18 then
      self.transition = nil
    end
    return
  end
  if self.minigame then   -- minijoc a pantalla completa (src/minigames/init.lua)
    require('src.minigames.init').update(self, dt, act)
    return
  end
  if self.menu then
    self.menu:update(dt, act.pressed, act)
    return
  end
  if self.scene then
    self.scene:update(dt, act)
    -- autoguardat cada minut de joc (abans només en canviar d'escena: tancar la pestanya al carrer feia
    -- perdre les missions fetes); mai a mig diàleg ni en les proves
    if not self.dev or self.dev.autosave then
      self.autosave_t = (self.autosave_t or 0) + dt
      if self.autosave_t >= (self.autosave_every or 60) and not (self.scene.dialogue and self.scene.dialogue.open) then
        self.autosave_t = 0
        self:save_game(false)
      end
    end
  end
end

-- texto y teclas para los menús que escriben (src/ui/profiles.lua)
function Game:textinput(t)
  if self.menu and self.menu.textinput then self.menu:textinput(t) end
end

-- clic o toque (coordenadas de ventana → pantalla virtual 320×240)
function Game:pointer(x, y)
  local v = self.view
  if not (v and self.menu and self.menu.pointer) then return end
  self.menu:pointer((x - v.ox) / v.s, (y - v.oy) / v.s)
end

function Game:keypressed(key)
  return self.menu and self.menu.keypressed and self.menu:keypressed(key) or false
end

-- diari de missions (src/ui/journal.lua); back = tornar al menú de pausa
function Game:open_journal(back)
  self.menu = require('src.ui.journal').new(self, back)
  Audio.pause(true)
  Input.clear()
end

-- opcions: veu (activar, volum, velocitat, idioma) — des del títol o des de la pausa
function Game:open_options(from_title, sel)
  local S = require('src.settings')
  local Tts = require('src.tts')
  local t = self.settings.tts
  local function again(i) S.save(); self:open_options(from_title, i) end
  local RATES = { { 0.8, 'lenta' }, { 1.0, 'normal' }, { 1.25, 'ràpida' } }
  local rate_name = 'normal'
  for _, r in ipairs(RATES) do if math.abs(r[1] - t.rate) < 0.01 then rate_name = r[2] end end
  local items = {
    { 'Veu dels diàlegs: ' .. (t.on and 'Sí' or 'No'), function() t.on = not t.on; again(1) end },
    { string.format('Volum de la veu: %d%%', math.floor(t.volume * 100 + 0.5)), function()
      t.volume = t.volume >= 0.99 and 0.2 or math.min(1, t.volume + 0.2); again(2) end },
    { 'Velocitat: ' .. rate_name, function()
      local i = 1
      for k, r in ipairs(RATES) do if r[2] == rate_name then i = k end end
      t.rate = RATES[i % #RATES + 1][1]; again(3) end },
    { 'Idioma de la veu: ' .. (t.lang == 'ca' and 'Català' or 'Castellà'), function()
      t.lang = t.lang == 'ca' and 'es' or 'ca'; again(4) end },
    { 'Provar la veu', function()
      Tts.say(t.lang == 'ca' and 'Hola! Sóc la veu del joc. Els teus amics et saluden.' or
        'Hola. Soy la voz del juego. Tus amigos te saludan.', true)
      if Tts.backend == 'none' then self.hud:toast('No hi ha veu en aquest equip (cal un navegador o espeak-ng)', 3) end
      self:open_options(from_title, 5)
    end },
  }
  local all_i = #items + 1
  items[all_i] = { 'Llegir-ho tot (menús, avisos): ' .. (t.all ~= false and 'Sí' or 'No'), function()
    t.all = t.all == false; again(all_i) end }
  local up_i = #items + 1
  items[up_i] = { 'TEXT EN MAJÚSCULES: ' .. (S.get().upper and 'SÍ' or 'NO'), function()
    local Upper = require('src.ui.upper')
    S.get().upper = not S.get().upper; Upper.on = S.get().upper; again(up_i) end }
  items[#items+1] = { 'Volum i música', function() self:open_audio_options(from_title) end }
  if from_title then items[#items + 1] = { 'Tornar al títol', function() self:to_title() end } end
  items[#items+1] = { 'Moviment reduït: ' .. (S.get().reduced_motion and 'sí' or 'no'), function()
    local value=not S.get().reduced_motion;S.get().reduced_motion=value
    require('src.motion').set('user',value);again(#items)
  end }
  self:open_list('Opcions · veu: ' .. (Tts.backend == 'web' and 'navegador' or (Tts.backend == 'espeak' and 'espeak-ng' or 'no disponible')), items)
  if sel then self.menu.sel = sel end
  self.menu.from_title = from_title
end

function Game:open_audio_options(from_title, sel)
  local S=require('src.settings')
  local a=self.settings.audio
  local rows={}
  for i,def in ipairs({{'master','General'},{'music','Música'},{'effects','Efectes i ambient'}}) do
    local key,label,index=def[1],def[2],i
    local actual=key=='master' and self.audio.volume or (key=='music' and self.audio.music_volume or self.audio.effects_volume)
    local function adjust(delta)
      if not a.custom then a.master=self.audio.volume;a.music=self.audio.music_volume end
      a.custom=true;a[key]=math.max(0,math.min(1,math.floor((a[key]+delta)*100+.5)/100))
      self.audio.configure(self.settings,self.config);S.save()
      if self.audio.volume==0 then require('src.tts').stop() end
      self:open_audio_options(from_title,index)
    end
    rows[#rows+1]={string.format('%s: < %d%% >',label,math.floor(actual*100+.5)),function() adjust(actual>=.999 and -1 or .1) end,
      adjust=adjust}
  end
  rows[#rows+1]={'Silenciar tot',function()
    if not a.custom then a.music=self.audio.music_volume end
    a.custom=true;a.master=0;self.audio.configure(self.settings,self.config);require('src.tts').stop();S.save();self:open_audio_options(from_title,1)
  end}
  rows[#rows+1]={'Veu i altres opcions',function() self:open_options(from_title) end}
  if not from_title then rows[#rows+1]={'Ràdio de butxaca',function() require('src.systems.radio').open(self) end} end
  self:open_list('Volum · esquerra / dreta',rows)
  self.menu.from_title=from_title;self.menu.sel=sel or 1
end

function Game:open_profiles()
  self.menu = require('src.ui.profiles').new(self)
  Input.clear()
end

function Game:focus(f)
  if self.dev then return end
  self.loop:pause(not f)
  Input.clear()
  -- canviar de pestanya o d'aplicació (o tancar-la al mòbil) desa la partida
  if not f and self.scene and self.state and not self.transition then self:save_game(false) end
  if not f and self.scene and not self.menu and not self.minigame and not self.dev then self:open_menu() end
end

-- view: estado de zoom (src/ui/mapzoom.lua); sin él se dibuja el mapa entero
function Game:draw_minimap(view)
  local Z = require('src.ui.mapzoom')
  local mm = self.sprites.minimap
  love.graphics.setColor(0.12, 0.10, 0.14); love.graphics.rectangle('fill', 0, 0, 320, 240)
  love.graphics.setColor(1, 1, 1)
  if not mm then love.graphics.print('Sense mapa', 120, 110); return end
  view = view or Z.new()
  local rect = { x = 0, y = 0, w = 320, h = 240 }
  local base = 232 * mm:getWidth() / mm:getHeight()
  Z.clamp(view, rect, base)
  local S = Z.size(view, base)
  local x0, y0 = Z.pos(view, rect, base, 0, 0)
  local pic = mm
  if view.i > 1 then   -- amb zoom, la versió detallada (tools/make_minimap.py), carregada la primera vegada
    if self.sprites.minimap_hd == nil then
      local p = 'assets/runtime/minimap_hd.jpg'
      self.sprites.minimap_hd = love.filesystem.getInfo(p) and img(p) or false
      if self.sprites.minimap_hd then self.sprites.minimap_hd:setFilter('linear', 'nearest') end
    end
    pic = self.sprites.minimap_hd or mm
  end
  love.graphics.draw(pic, x0, y0, 0, S / pic:getWidth(), S / pic:getHeight())
  local map = self:get_map('overworld')
  local k = S / (map.width * 16)
  local function at(px, py) return x0 + px * k, y0 + py * k end
  for _, p in ipairs(self.world.pois) do
    local o = map:object('poi', p)
    if o then
      local x, y = at(o.x, o.y)
      love.graphics.setColor(self.state.visited[p] and { 0.84, 0.42, 0.29 } or { 0.12, 0.10, 0.14 })
      love.graphics.rectangle('fill', x - 2, y - 2, 4, 4)
    end
  end
  -- serveis (colors per tipus) i, amb el Mapa antic, els cofres sense obrir
  local SC = { shop = { 0.24, 0.44, 0.77 }, super = { 0.24, 0.44, 0.77 }, station = { 0.79, 0.25, 0.23 },
               doctor = { 0.96, 0.94, 0.89 }, police = { 0.2, 0.3, 0.6 } }
  for _, o in ipairs(map.objects) do
    if o.type == 'service' then
      local x, y = at(o.x, o.y)
      love.graphics.setColor(SC[o.props.service] or { 0.89, 0.72, 0.40 })
      love.graphics.circle('fill', x, y, 1.6)
    end
  end
  if self.state and (self.state.inventory.mapa_antic or 0) > 0 then
    local opened = (self.state.scene_state.overworld or {}).chests or {}
    love.graphics.setColor(0.55, 0.34, 0.16)
    for _, o in ipairs(map.objects) do
      if o.type == 'chest' and not opened[o.props.flag] then
        local x, y = at(o.x, o.y)
        love.graphics.rectangle('fill', x - 1.5, y - 1.5, 3, 3)
      end
    end
  end
  -- cases dels amics i avis del perfil i objectiu de la missió activa
  for _, fr in ipairs(self.friends or {}) do
    local h = fr.def.home
    if h then
      local x, y = at(h.tile_x * 16, h.tile_y * 16)
      love.graphics.setColor(0.93, 0.52, 0.72)
      love.graphics.rectangle('fill', x - 2, y - 2, 5, 5)
      love.graphics.print(fr.def.name, x + 4, y - 9)
    end
  end
  local tgt = self.scene and self.scene.town and self.scene.town.target
  if tgt and math.floor(love.timer.getTime() * 4) % 2 == 0 then
    local c = require('src.systems.missions').CAT_COLOR[self.scene.town.cat or 'nav']
    local x, y = at(tgt.x, tgt.y)
    love.graphics.setColor(c); love.graphics.circle('fill', x, y, 3.5)
  end
  require('src.systems.marker').draw_map(self.state, at)
  if self.scene and self.scene.id == 'overworld' and math.floor(love.timer.getTime() * 3) % 2 == 0 then
    local b = self.scene.player.body
    local x, y = at(b.x, b.y)
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle('fill', x, y, 2.5)
  end
  love.graphics.setColor(1, 1, 1)
  Z.draw_buttons(view, view.btns or Z.buttons(292, 6), self.font)
end

function Game:draw()
  love.graphics.setCanvas({ self.canvas, stencil = true })
  love.graphics.clear(0.07, 0.06, 0.08)
  if self.scene then self.scene:draw() end
  if self.minigame then require('src.minigames.init').draw(self) end
  if self.menu then self.menu:draw() end
  if self.transition then
    local k=require('src.motion').ease(self.transition.t/.18)
    local a = self.transition.phase == 'out' and k or 1-k
    love.graphics.setColor(0, 0, 0, math.max(0, math.min(1, a)))
    love.graphics.rectangle('fill', 0, 0, VW, VH)
    love.graphics.setColor(1, 1, 1)
  end
  if self.debug then self:draw_debug() end
  love.graphics.setCanvas()
  -- escala entera con bandas negras
  local ww, wh = love.graphics.getDimensions()
  local s = math.min(ww / VW, wh / VH)
  -- escala entera en escritorio; en el navegador se ajusta a la pantalla (filtro nearest)
  if love.system.getOS() ~= 'Web' or s >= 3 then s = math.max(1, math.floor(s)) end
  love.graphics.clear(0, 0, 0)
  self.view = { s = s, ox = math.floor((ww - VW * s) / 2), oy = math.floor((wh - VH * s) / 2) }
  love.graphics.draw(self.canvas, self.view.ox, self.view.oy, 0, s, s)
  self:record_frame()
end

function Game:record_frame()
  if not self.t_frame0 then return end
  local ft = love.timer.getTime() - self.t_frame0
  self.frame_i = self.frame_i % 600 + 1
  self.frame_times[self.frame_i] = ft
  if self.dev and self.dev.record then self.dev:record(ft) end
end

function Game:p95()
  local t = {}
  for _, v in ipairs(self.frame_times) do t[#t + 1] = v end
  if #t == 0 then return 0 end
  table.sort(t)
  return t[math.max(1, math.floor(#t * 0.95))]
end

function Game:draw_debug()
  local lines = {
    string.format('FPS %d  P95 %.1f ms  descartes %d', love.timer.getFPS(), self:p95() * 1000, self.dropped),
    string.format('Lua %.1f MiB  tex %.1f MiB', collectgarbage('count') / 1024,
      love.graphics.getStats().texturememory / 1048576),
  }
  if self.scene then
    local b = self.scene.player.body
    local m = self.scene.map
    lines[#lines + 1] = string.format('%s (%d,%d) nivell %d', self.scene.id, math.floor(b.x / 16),
      math.floor(b.y / 16), b.level)
    lines[#lines + 1] = string.format('chunks %d  cel·la %d', m.chunks.count, m:cell(math.floor(b.x / 16), math.floor(b.y / 16)))
  end
  if self.home_warning then lines[#lines + 1] = self.home_warning end
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle('fill', 0, 240 - #lines * 16 - 4, 320, #lines * 16 + 4)
  love.graphics.setColor(1, 1, 0.6)
  for i, l in ipairs(lines) do love.graphics.print(l, 4, 240 - (#lines - i + 1) * 16 - 2) end
  love.graphics.setColor(1, 1, 1)
end

return Game
