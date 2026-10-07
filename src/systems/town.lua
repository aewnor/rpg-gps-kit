-- Vida del poble (fase 5): connecta el món (src/scenes/world_scene.lua) amb
--   · els personatges del perfil (amics, avis…): apareixen al carrer segons el seu horari, caminen amb A*,
--     viuen a la casa triada (porta → interior personalitzat) i saluden pel teu nom
--   · els veïns i els serveis amb horari (de nit, a casa / tancat)
--   · salutacions i reaccions si passes massa de pressa amb un vehicle
--   · semàfors i punts de reciclatge (dibuix i interacció)
--   · el motor de missions (src/systems/missions.lua): objectius, brúixola, arribades, encàrrecs, l'Olaf al parc
--   · els cartells amb el nom oficial del carrer o la plaça
local State = require('src.state')
local Missions = require('src.systems.missions')
local Schedule = require('src.systems.schedule')
local Streets = require('src.systems.streets')
local AStar = require('src.world.astar')
local Collision = require('src.world.collision')
local NPC = require('src.entities.npc')
local Family = require('src.systems.family')
local Errands = require('src.systems.errands')

local Town = {}

local WALK_SPEED = 30          -- px/s dels personatges amb horari
local GREET_EVERY = 45         -- s entre salutacions del mateix personatge
local FAST = 105               -- px/s: «massa de pressa» amb vehicle a prop de la gent

-- ---------------------------------------------------------------- missions: definicions i ganxos
function Town.defs(g)
  g.missions_data = g.missions_data or require('src.data').read_json('data/missions.json')
  local friends = g.profile and g.profile.friends or {}
  local key = #friends .. (g.home and 'H' or '-')
  for _, f in ipairs(friends) do key = key .. '|' .. f.id .. (f.home and '+' or '-') .. f.name .. f.role .. Missions.parents_text(f) end
  if not g.mission_defs or g.mission_defs_key ~= key then
    g.mission_defs = Missions.build(g.missions_data, friends, { home = g.home ~= nil })
    g.mission_defs_key = key
  end
  return g.mission_defs
end

function Town.friend(g, id)
  for _, f in ipairs(g.profile and g.profile.friends or {}) do if f.id == id then return f end end
end

-- accions del món que demana el motor de missions
function Town.hooks(w)
  local g, st = w.game, w.state
  return function(kind, a, b, c)
    if kind == 'give' then
      State.give(st, a)
      w.hud:toast('Has rebut: ' .. ((g.items[a] or {}).name or a), 2.5)
    elseif kind == 'coins' then
      require('src.systems.rpg').earn(st, a)
      w:popup('+' .. a .. ' mon.', 'coins')
    elseif kind == 'intro' then
      if a.intro and #a.intro > 0 then w.pending_intro = { title = a.title, pages = a.intro } end
    elseif kind == 'step' then
      w.hud:toast('Objectiu: ' .. b.text, 3, true)
      if b.type == 'meet_olaf' then Town.send_olaf(w, b) end
    elseif kind == 'progress' then
      w.hud:toast(string.format('%s (%d/%d)', b.text, c, b.count or 1), 2, true)
      g.audio.play('good')
    elseif kind == 'done' then
      g.audio.play('levelup')
      local p = w.player.body
      w.fx:preset('confetti', p.x, p.y - 14, 24)
      w:reward(a.xp or 0, a.coins or 0, 'Missió feta: ' .. a.title)
      if a.reward_item then
        State.give(st, a.reward_item)
        w.hud:toast('Has rebut: ' .. ((g.items[a.reward_item] or {}).name or a.reward_item), 2.5)
      end
    elseif kind == 'has' then return (st.inventory[a] or 0) >= (b or 1)
    elseif kind == 'take' then for _ = 1, (b or 1) do State.take(st, a) end
    elseif kind == 'say' then w.pending_say = { who = b or 'Missió', pages = a }
    elseif kind == 'warn' then w.hud:toast(a, 3, true); g.audio.play('miss')
    elseif kind == 'join' then require('src.systems.companion').join(w, a, b)
    elseif kind == 'family' then st.family_out = (a == 'out') or nil   -- (src/systems/family.lua)
    elseif kind == 'leave' then require('src.systems.companion').leave(w)
    end
    if kind == 'done' and st.companion and st.companion.mission == a.id then   -- missió acabada: l'amic se'n va
      require('src.systems.companion').leave(w)
    end
  end
end

function Town.event(w, kind, data)
  local res = Missions.event(Town.defs(w.game), w.state, kind, data, Town.hooks(w))
  return res
end

-- primera missió en començar (sense presses: la introducció surt quan no hi ha cap diàleg)
function Town.start(w)
  local defs = Town.defs(w.game)
  local q = Missions.state(w.state)
  if not q.active and not q.offered then
    q.offered = true
    local m = Missions.next_open(defs, w.state)
    if m then
      -- sense diàleg d'entrada (no trepitja l'inici de la història): només un avís
      local h = Town.hooks(w)
      Missions.activate(defs, w.state, m.id, function(kind, ...)
        if kind == 'intro' or kind == 'step' then return end
        return h(kind, ...)
      end)
      w.hud:toast('Missió: ' .. m.title .. '  (J: diari)', 4, true)
    end
  end
end

-- ---------------------------------------------------------------- llocs: on és cada objectiu
local function overworld(g) return g:get_map('overworld') end

-- el chunk de (x, y) ja és a la memòria? (calcular llocs no ha de llegir el disc enmig de la partida)
local function loaded(g, x, y)
  local map = overworld(g)
  local C = map.chunk or 32
  return not map.chunks.has or map.chunks:has(math.floor(x / 16 / C), math.floor(y / 16 / C))
end

local function walkable_near(g, x, y, r)
  local nx, ny = g:nearest_walkable('overworld', x, y, 0, r or 8)
  return nx, ny
end

local function service_pos(g, id)
  g.service_pos = g.service_pos or {}
  if g.service_pos[id] == nil then
    g.service_pos[id] = false
    for _, o in ipairs(overworld(g).objects) do
      if o.type == 'service' and o.props.service_id == id then g.service_pos[id] = { o.x, o.y + 16 } end
    end
  end
  return g.service_pos[id] or nil
end

-- llocs dels encàrrecs (objectes 'errand' de tools/decorate_map.py errand_spots), per tipus
local function errand_spots(g)
  if not g.errand_spots then
    g.errand_spots = {}
    for _, o in ipairs(overworld(g).objects) do
      if o.type == 'errand' then
        local k = o.props.kind
        g.errand_spots[k] = g.errand_spots[k] or {}
        table.insert(g.errand_spots[k], { x = o.x, y = o.y, swim = o.props.swim, shop = o.props.shop })
      end
    end
  end
  return g.errand_spots
end

-- el lloc de tipus `kind` més proper a (x, y) (a menys de `maxd` px); `pick` tria entre els 3 més propers
function Town.errand_spot(g, kind, x, y, maxd, pick)
  local list = errand_spots(g)[kind]
  if not list then return nil end
  local near = {}
  for _, s in ipairs(list) do
    local d = (s.x - x) ^ 2 + (s.y - y) ^ 2
    if not maxd or d < maxd * maxd then near[#near + 1] = { s, d } end
  end
  if #near == 0 then return nil end
  table.sort(near, function(a, b) return a[2] < b[2] end)
  return near[((pick or 0) % math.min(3, #near)) + 1][1]
end

local SHOPS = { 'bonpreu', 'lidl', 'lidl_platja', 'mercadona', 'spar', 'aldi', 'supercor' }

-- àrea (parc, plaça, escola) → punt transitable més proper al centre (memòria)
local function area_pos(g, a)
  if not a then return nil end
  if not a.walk and not loaded(g, a.cx, a.cy) then
    return { a.cx, a.cy, raw = true }            -- aproximat fins que el jugador s'hi acosti
  end
  if not a.walk then
    -- la casella transitable de DINS del recinte més propera al centre (si no n'hi ha, la més propera de fora)
    local map = overworld(g)
    local best, bd
    for ty = math.floor(a.box[2] / 16), math.floor(a.box[4] / 16) do
      for tx = math.floor(a.box[1] / 16), math.floor(a.box[3] / 16) do
        local x, y = tx * 16 + 8, ty * 16 + 8
        if Streets.contains(a, x, y) and map:in_bounds(tx, ty) and Collision.walk_at(map:cell(tx, ty), 0) then
          local d = (x - a.cx) ^ 2 + (y - a.cy) ^ 2
          if not bd or d < bd then best, bd = { x, y }, d end
        end
      end
    end
    a.walk = best or { walkable_near(g, a.cx, a.cy, 12) }
  end
  if not a.walk[1] then return { a.cx, a.cy } end
  return a.walk
end

-- l'àrea de cert tipus més propera a (x, y)
function Town.nearest_area(kind, x, y, maxd)
  Streets.name_at(0, 0)    -- carrega les dades
  local best, bd = nil, (maxd or math.huge) ^ 2
  local d = Streets._data and Streets._data() or nil
  for _, a in ipairs(d and d.areas or {}) do
    if a.k == kind then
      local dd = (a.cx - x) ^ 2 + (a.cy - y) ^ 2
      if dd < bd then best, bd = a, dd end
    end
  end
  return best
end

local function friend_home_pos(f)
  if not f.home then return nil end
  return { f.home.tile_x * 16 + 8, f.home.tile_y * 16 + 8 }
end

-- objecte amb nom de l'exterior (llocs 'spot', cofres…) encara que siguem a dins d'una cova
local function named_object(g, kind, name)
  g._named = g._named or {}
  local key = kind .. ':' .. name
  if g._named[key] == nil then
    g._named[key] = false
    for _, o in ipairs(overworld(g).objects or {}) do
      if o.type == kind and o.name == name then g._named[key] = o; break end
    end
  end
  return g._named[key] or nil
end

-- objectiu → { x, y, label, scene } (o nil si encara no se sap)
function Town.resolve(w, target)
  local g = w.game
  if not target then return nil end
  local kind, arg = target:match('^(%w+):?(.*)$')
  if kind == 'area' then
    local a = Streets.area(arg)
    local p = area_pos(g, a)
    return p and { x = p[1], y = p[2], label = arg, area = a }
  elseif kind == 'street' then
    local s = Streets.street(arg)
    return s and { x = s.cx, y = s.cy, label = arg }
  elseif kind == 'service' then
    local p = service_pos(g, arg)
    local spec = require('src.systems.services').spec(g, arg)
    -- serveis que col·loca el joc (la mestra a l'escola): no són al mapa, sinó a la seva àrea
    if not p and spec and spec.runtime and spec.pos then p = { spec.pos[1] * 16 + 8, spec.pos[2] * 16 + 8 } end
    if not p and spec and spec.runtime and spec.area then p = area_pos(g, Streets.area(spec.area)) end
    return p and { x = p[1], y = p[2], label = spec and spec.label or arg }
  elseif kind == 'friend' then
    local f = Town.friend(g, arg)
    if not f then return nil end
    -- si és al carrer, on és ara; si no, a casa seva
    for _, n in ipairs(w.id == 'overworld' and w.npcs or {}) do
      if n.props.friend == arg and not n.hidden then return { x = n.body.x, y = n.body.y, label = f.name } end
    end
    local p = friend_home_pos(f)
    return p and { x = p[1], y = p[2], label = 'Casa de ' .. f.name }
  elseif kind == 'friendhome' then      -- la porta de casa d'un personatge del perfil (encara que sigui al carrer)
    local f = Town.friend(g, arg)
    local p = f and friend_home_pos(f)
    return p and { x = p[1], y = p[2], label = 'Casa de ' .. f.name }
  elseif kind == 'home' then
    return g.home and { x = g.home.x, y = g.home.y, label = 'Casa' }
  elseif kind == 'spot' or kind == 'chest' or kind == 'door' then   -- Cova de Roda, Cau del Drac, porta d'una cova
    local o = named_object(g, kind, arg)
    local box = kind ~= 'spot'
    return o and { x = o.x + (box and 8 or 0), y = o.y + (box and 16 or 0),
                   label = o.props and o.props.label or arg }
  elseif kind == 'wallet' then
    local wl = w.state.missions and w.state.missions.wallet
    return type(wl) == 'table' and { x = wl.x, y = wl.y, label = 'La cartera' } or nil
  elseif kind == 'nearest' then
    local b = w.player.body
    local best, bd
    local function consider(x, y)
      local d = (x - b.x) ^ 2 + (y - b.y) ^ 2
      if not bd or d < bd then best, bd = { x = x, y = y }, d end
    end
    if arg == 'crosswalk' or arg == 'light' then
      for _, cw in ipairs(w.traffic and w.traffic.crosswalks or {}) do
        if cw.ang and (arg == 'crosswalk' or cw.light) then consider(cw.x, cw.y) end
      end
    elseif arg == 'recycling' then
      for _, r in ipairs(Town.recycling(w)) do consider(r.x, r.y) end
    elseif arg == 'bus_stop' then
      for _, s in ipairs(w.stops) do consider(s.x, s.y + 8) end
    end
    if best then
      best.label = ({ crosswalk = 'Pas de vianants', light = 'Semàfor', recycling = 'Contenidors',
                      bus_stop = 'Parada de bus' })[arg]
    end
    return best
  end
end

-- objectiu actiu per a la brúixola (es recalcula cada 0,5 s)
function Town.target(w)
  return w.town and w.town.target
end

-- ---------------------------------------------------------------- muntatge a l'escena
function Town.attach(w)
  local g = w.game
  Streets.name_at(0, 0)       -- carrega data/streets.json ara (canvi d'escena), no enmig d'un pas
  w.town = { t = 0, path_budget = 0, target = nil, cross = nil, last_scare = 0 }
  if w.id == 'overworld' then
    Town.spawn_friends(w)
    Town.spawn_key_npcs(w)
    Town.setup_routines(w)
    w.town.streets = Streets.tracker(function(name) w.hud:place(name) end)
    if w.state.quests and w.state.quests.olaf_away then Town.place_olaf_npc(w) end
  end
  Town.start(w)
  Town.event(w, 'enter', { scene = w.id })
  -- a dins de la casa d'un personatge del perfil (src/game.lua friend_interior desa state.proc.friend)
  local pr = w.state.proc
  if w.id ~= 'overworld' and pr and pr.friend then Town.event(w, 'event', { name = 'home_' .. pr.friend }) end
  if w.id ~= 'overworld' then Family.attach(w) end   -- pare i mare a la casa del jugador
end

-- en pujar de nivell: els passos de nivell i, si no hi ha cap missió activa, la següent que s'hagi obert
function Town.level_up(w)
  local defs = Town.defs(w.game)
  Town.event(w, 'level', {})
  local q = Missions.state(w.state)
  if not q.active then
    local m = Missions.next_open(defs, w.state)
    if m then
      Missions.activate(defs, w.state, m.id, Town.hooks(w))
      w.hud:toast('Nova missió: ' .. m.title .. '  (J: diari)', 3, true)
    end
  end
end


-- personatges del perfil al carrer (si tenen casa)
function Town.spawn_friends(w)
  local g = w.game
  for _, fr in ipairs(g.friends or {}) do
    local f = fr.def
    if f.home then
      local p = friend_home_pos(f)
      local obj = { name = 'friend_' .. f.id, x = p[1], y = p[2],
                    props = { sprite = fr.sprite, say_name = f.name, friend = f.id, facing = 'down', wander = 0 } }
      local n = NPC.new(obj, g.sprites.chars[fr.sprite], #w.npcs + 100)
      n.routine = { kind = Schedule.kind_of_friend(f), home = p, friend = f }
      w.npcs[#w.npcs + 1] = n
    end
  end
end

-- NPCs clau (fase 6): noms dels serveis segons data/services.json (la metgessa al CAP), la mestra a
-- l'Escola Salvador Espriu (la col·loca el joc: «runtime» a services.json) i dos agents de la Policia
-- Local que patrullen pels voltants de la comissaria
function Town.spawn_key_npcs(w)
  local g = w.game
  local Services = require('src.systems.services')
  local police
  for _, n in ipairs(w.npcs) do
    local id = n.props.service_id
    if id then
      local spec = Services.spec(g, id)
      if spec and spec.name then n.props.say_name = spec.name end
      if n.props.service == 'police' then police = n end
    end
  end
  Services.spec(g, 'escola')
  for id, spec in pairs(g.services_spec or {}) do
    if spec.runtime and spec.area then
      local a = Streets.area(spec.area)
      local p = spec.pos and { spec.pos[1] * 16 + 8, spec.pos[2] * 16 + 8 } or area_pos(g, a)
      if p then
        local obj = { name = 'service_' .. id, x = p[1], y = p[2],
                      props = { sprite = spec.sprite, say_name = spec.name, service = spec.kind, service_id = id,
                                label = spec.label, facing = 'down', wander = 0 } }
        local n = NPC.new(obj, g.sprites.chars[spec.sprite] or g.sprites.player, #w.npcs + 300)
        n.routine = { kind = 'teacher', home = { p[1], p[2] } }
        w.npcs[#w.npcs + 1] = n
      end
    end
  end
  if police then
    local hx, hy = police.body.x, police.body.y
    for k = 1, 2 do
      local pts = {}
      for i = 1, 4 do   -- quatre punts de ronda (fixos per agent) a uns 8–12 m de la comissaria
        local a = (i + k * 2) * math.pi / 2 + k
        local x, y = walkable_near(g, hx + math.cos(a) * 10 * 16, hy + math.sin(a) * 8 * 16, 4)
        if x then pts[#pts + 1] = { x, y } end
      end
      if #pts >= 2 then
        local obj = { name = 'agent_' .. k, x = pts[1][1], y = pts[1][2],
                      props = { sprite = 'npc_police', say_name = 'Agent de la Policia Local', facing = 'down', wander = 0,
                                say = 'Bon dia! Patrullem perquè el poble sigui segur.|Si veus alguna cosa estranya, avisa a la comissaria.' } }
        local n = NPC.new(obj, g.sprites.chars.npc_police, #w.npcs + 400)
        n.routine = { kind = 'patrol', home = pts[1], points = pts, pi = 1 }
        w.npcs[#w.npcs + 1] = n
      end
    end
  end
end

-- rutines dels veïns (els de les missions de la història es queden quiets: no es poden perdre)
function Town.setup_routines(w)
  for _, n in ipairs(w.npcs) do
    if not n.routine then
      local p = n.props
      if p.service then
        n.routine = { kind = 'service', home = { n.body.x, n.body.y } }
      elseif (p.say or p.ai) and not p.dialogue then
        n.routine = { kind = 'townsfolk', home = { n.body.x, n.body.y } }
      end
    end
  end
end

-- posició del lloc `place` per a un personatge
function Town.place_pos(w, n, place)
  local g = w.game
  local r = n.routine
  r.cache = r.cache or {}
  if r.cache[place] ~= nil then return r.cache[place] or nil end
  local pos
  local hx, hy = r.home[1], r.home[2]
  if place == 'home' or place == 'post' or place == 'closed' then pos = { hx, hy }
  elseif place == 'school' then pos = area_pos(g, Town.nearest_area('school', hx, hy))
  elseif place == 'park' then
    local a = Town.nearest_area('park', hx, hy, r.kind == 'townsfolk' and 800 or nil)
    pos = area_pos(g, a)
    if not pos and r.kind == 'townsfolk' then pos = { hx, hy } end
  elseif place == 'plaza' then pos = area_pos(g, Streets.area('Plaça de l\'Església'))
  elseif place == 'shop' then                     -- el súper més proper de casa
    local bd
    for _, id in ipairs(SHOPS) do
      local p = service_pos(g, id)
      if p and (not bd or (p[1] - hx) ^ 2 + (p[2] - hy) ^ 2 < bd) then pos, bd = p, (p[1] - hx) ^ 2 + (p[2] - hy) ^ 2 end
    end
  elseif Errands.PLACE_NAMES[place] then          -- encàrrecs: el lloc exacte (dins la piscina, al jardí...)
    local maxd = ({ garden = 14 * 16, pool = 90 * 16, bakery = 160 * 16, hair = 160 * 16 })[place]
    local s = Town.errand_spot(g, place, hx, hy, maxd, (place == 'beach' or place == 'pool') and r.seed or 0)
    if not s and place == 'pool' then s = Town.errand_spot(g, 'pool_home', hx, hy, 8 * 16) end   -- la seva piscina
    r.cache[place] = s and { s.x, s.y, swim = s.swim } or false
    return r.cache[place] or nil
  end
  if pos and (pos.raw or not loaded(g, pos[1], pos[2])) then
    return { pos[1], pos[2], raw = true }         -- lluny: aproximat, sense guardar-lo
  end
  if pos then
    -- cadascú al seu racó (no tots al mateix punt)
    local k = (#(n.name or '') * 7 + math.floor(hx) % 13) % 5 - 2
    local x, y = walkable_near(g, pos[1] + k * 16, pos[2] + ((k * 3) % 5 - 2) * 16, 3)
    pos = { x or pos[1], y or pos[2] }
  end
  r.cache[place] = pos or false
  return pos
end

local function walker(w)
  w.town.walk = w.town.walk or AStar.walker(w.map)
  return w.town.walk
end

-- ---------------------------------------------------------------- actualització
function Town.update(w, dt)
  local T = w.town
  if not T then return end
  local g, st = w.game, w.state
  T.t = T.t + dt
  -- A*: com a molt una cerca cada 0,2 s entre tots els personatges (Raspberry Pi: sense pics de temps)
  T.path_t = (T.path_t or 0) + dt
  if T.path_t >= 0.2 then T.path_t = 0; T.path_budget = 1 else T.path_budget = 0 end
  local b = w.player.body
  -- campanes de Sant Bartomeu: a cada hora en punt (de 8 a 21 h) si ets a prop del nucli antic
  if w.id == 'overworld' then
    local hour = math.floor((st.clock or 600) / 60) % 24
    if T.last_hour and hour ~= T.last_hour and hour >= 8 and hour <= 21 then
      T.bell = T.bell or (w.map.object and w.map:object('landmark', 'sant_bartomeu')) or false
      local o = T.bell
      if o then
        local d = math.sqrt((o.x + 16 - b.x) ^ 2 + (o.y - b.y) ^ 2) / 16
        if d < 45 then
          T.bell_t = 0
          require('src.audio').play('campana', { vol = math.max(0.25, 1 - d / 45) })
        end
      end
    end
    T.last_hour = hour
    if T.bell_t then T.bell_t = T.bell_t + dt; if T.bell_t > 4 then T.bell_t = nil end end
    for _, n in ipairs(w.npcs) do
      if n.routine then Town.update_routine(w, n, dt) end
      Town.reactions(w, n, dt)
    end
    if T.streets then Streets.track(T.streets, dt, b.x, b.y) end
    Town.crossings(w)
    Town.update_olaf_meet(w)
  else
    for _, n in ipairs(w.npcs) do Town.reactions(w, n, dt) end
    Family.update(w, dt)
  end
  w.town.last_speed = w.player.vehicle and w.player.vehicle.speed or 0
  -- missions: objectiu de la brúixola i arribades
  T.check = (T.check or 0) + dt
  if T.check >= 0.25 then
    T.check = 0
    local defs = Town.defs(g)
    local m, s = Missions.current(defs, st)
    T.target = nil
    if s then
      local tgt = Town.resolve(w, s.target)
      if s.alt and tgt then          -- objectius alternatius (Bonpreu o Lidl): el més proper
        for _, a in ipairs(s.alt) do
          local o = Town.resolve(w, a)
          if o and (o.x - b.x) ^ 2 + (o.y - b.y) ^ 2 < (tgt.x - b.x) ^ 2 + (tgt.y - b.y) ^ 2 then tgt = o end
        end
      end
      T.target = tgt
      T.cat = m.cat
      T.text = s.text
      T.step_type, T.radius = s.type, s.radius
      -- amic objectiu de la missió («Parla amb el Nil»): mentre dura, no canvia de lloc (abans anava i venia de
      -- casa al carrer i la fletxa i el personatge saltaven)
      T.friend_lock = s.target and s.target:match('^friend:(.+)$') or nil
      T.inside = s.inside
      -- parlar amb un servei tancat (de nit, o l'escola el cap de setmana): avís i hora d'obrir
      local sid = (s.type == 'talk' or s.type == 'deliver' or s.type == 'event') and s.target
                  and s.target:match('^service:(.+)$')
      T.closed = sid and Town.closed_info(g, sid) or nil
      if T.closed then
        local near = (tgt and w.id == 'overworld' and (tgt.x - b.x) ^ 2 + (tgt.y - b.y) ^ 2 < 140 * 140)
                     or (w.id ~= 'overworld' and w.id:find(sid, 1, true) ~= nil)
        local key = sid .. ':' .. (st.day or 1) .. ':' .. (T.closed.at or 0)
        if near and T.closed_told ~= key then
          T.closed_told = key
          w.hud:toast(T.closed.label .. ' és tancat ara. ' .. T.closed.when ..
                      '. Al menú de pausa pots triar «Esperar».', 6, true)
        end
      end
      Missions.tick(defs, st, Town.hooks(w))   -- tenir un objecte, arribar a un nivell
      if tgt and w.id == 'overworld' and s.type == 'goto' then
        local r = s.radius or 32
        local inside = tgt.area and Streets.area_at(b.x, b.y) == tgt.area
        if inside or (tgt.x - b.x) ^ 2 + (tgt.y - b.y) ^ 2 < r * r then
          Town.event(w, 'arrive', {})
        end
      end
    end
  end
  -- introducció pendent d'una missió (quan no hi ha cap diàleg obert)
  if w.pending_intro and not w.dialogue.open and not g.menu then
    local p = w.pending_intro
    w.pending_intro = nil
    w.dialogue:show('Missió: ' .. p.title, p.pages)
  elseif w.pending_say and not w.dialogue.open and not g.menu then
    local p = w.pending_say
    w.pending_say = nil
    w.dialogue:show(p.who, p.pages)
  end
end

-- servei tancat ara? → { label, wait (minuts), at (rellotge), when ("Obre a les 8:00", "Obre demà a les 8:00") }
function Town.closed_info(g, id)
  local spec = require('src.systems.services').spec(g, id)
  local st = g.state
  if not (spec and st) then return nil end
  local kind = spec.runtime and 'teacher' or 'service'   -- (la mestra: horari d'escola; la resta, 7:30–21:30)
  if not Schedule.hidden(Schedule.place(kind, st.clock, st.day)) then return nil end
  local wait = Schedule.next_open(kind, st.clock, st.day)
  local info = { label = spec.label or id, wait = wait }
  if not wait then info.when = 'Avui no obre'; return info end
  local total = math.floor((st.clock or 0) + wait + 0.5)
  info.at = total % 1440
  local hhmm = string.format('%d:%02d', math.floor(info.at / 60), info.at % 60)
  local days = math.floor(total / 1440)
  info.when = days == 0 and ('Obre a les ' .. hhmm) or days == 1 and ('Obre demà a les ' .. hhmm)
              or ('Obre d\'aquí a ' .. days .. ' dies, a les ' .. hhmm)
  return info
end

-- on ha de ser ara: un encàrrec (src/systems/errands.lua) si en té i hi ha el lloc, si no l'horari
function Town.routine_place(w, n)
  local r, st = n.routine, w.state
  local base = Schedule.place(r.kind, st.clock, st.day)
  if not Errands.KINDS[r.kind] or base == 'school' then return base end
  if tostring(n.props.sprite or ''):find('builder') then return base end   -- els obrers, a l'obra
  r.seed = r.seed or Errands.seed(n.name, r.home[1], r.home[2])
  if r.garden == nil then r.garden = Town.place_pos(w, n, 'garden') ~= nil end
  local wx = w.game.weather
  local e = Errands.pick(r.kind, r.seed, st.clock, st.day,
    { sunny = wx ~= nil and wx.kind == 'sol', month = tonumber(os.date('%m')), garden = r.garden,
      wet = wx ~= nil and (wx.kind == 'pluja' or wx.kind == 'tempesta') })
  if e and Town.place_pos(w, n, e) then return e end
  return base
end

-- horari: lloc on ha de ser, camí amb A* si és a la vista, salt si és lluny del jugador
function Town.update_routine(w, n, dt)
  local r = n.routine
  local st = w.state
  if n.props.friend and st.companion and st.companion.id == n.props.friend then   -- és amb tu, d'aventura
    n.hidden = true
    r.place, r.goal, r.path = nil, nil, nil
    return
  end
  if n.props.friend and w.town and w.town.friend_lock == n.props.friend and r.place then
    r.tick = 1                 -- missió activa amb aquest amic: es queda on és fins que hi parles
    if r.goal and not n.hidden then
      local dx, dy = r.goal[1] - n.body.x, r.goal[2] - n.body.y
      if dx * dx + dy * dy > 4 then return end
    end
    return
  end
  r.tick = (r.tick or 0) - dt
  if r.kind == 'patrol' and r.tick <= 0 then
    -- ronda: un punt nou cada 15 s
    r.tick = 15
    r.pi = r.pi % #r.points + 1
    r.place, r.goal, r.path = 'patrol', r.points[r.pi], nil
  elseif r.tick <= 0 then
    r.tick = 1
    local place = Town.routine_place(w, n)
    if place ~= r.place then
      if r.place and r.visited == r.place then   -- surt de la botiga amb el pa o la bossa
        r.carry = Errands.carry_after(r.place) or r.carry
        if r.place == 'hair' then r.haircut = (st.clock or 0) + 120; n.sparkle_t = 0 end
      end
      r.visited = nil
      r.place = place
      r.goal = Town.place_pos(w, n, place)
      r.path = nil
    end
  end
  if not r.goal then return end
  local b = w.player.body
  local far = (n.body.x - b.x) ^ 2 + (n.body.y - b.y) ^ 2 > 360 ^ 2
  if r.goal.raw and not far then r.goal = Town.place_pos(w, n, r.place) or r.goal end   -- ara ja es pot precisar
  local hide = Schedule.hidden(r.place) or Errands.INDOOR[r.place] or false
  local gx, gy = r.goal[1], r.goal[2]
  local at_goal = (n.body.x - gx) ^ 2 + (n.body.y - gy) ^ 2 < 6 ^ 2
  if far then
    -- fora de la vista: ja hi és
    n.body.x, n.body.y = gx, gy
    n.hidden = hide
    n.walk, r.path = nil, nil
    Town.arrived(n, r)
    n:sync_blocker()
    return
  end
  if at_goal then
    n.hidden = hide
    n.walk = nil
    r.path = nil
    Town.arrived(n, r)
    return
  end
  n.activity = nil
  if w.talking == n then return end
  if n.hidden then n.hidden = false end           -- surt de casa
  -- camí: A* (com a molt un per pas entre tots els personatges)
  if not r.path or r.wp > #r.path then
    if w.town.path_budget <= 0 then return end
    w.town.path_budget = w.town.path_budget - 1
    local path = AStar.find(walker(w), math.floor(n.body.x / 16), math.floor(n.body.y / 16),
      math.floor(gx / 16), math.floor(gy / 16), 1200)
    r.path = AStar.waypoints(path)
    if #r.path == 0 or (path[#path][1] == math.floor(n.body.x / 16) and path[#path][2] == math.floor(n.body.y / 16)) then
      r.path = { { gx, gy } }
    end
    r.wp = 1
  end
  local p = r.path[r.wp]
  local dx, dy = p[1] - n.body.x, p[2] - n.body.y
  local d = math.sqrt(dx * dx + dy * dy)
  local stepd = WALK_SPEED * dt
  if d <= stepd then
    n.body.x, n.body.y = p[1], p[2]
    r.wp = r.wp + 1
  else
    n.body.x, n.body.y = n.body.x + dx / d * stepd, n.body.y + dy / d * stepd
  end
  if math.abs(dx) > math.abs(dy) then n.facing = dx > 0 and 'right' or 'left' else n.facing = dy > 0 and 'down' or 'up' end
  local ax, ay = math.abs(dx), math.abs(dy)   -- en diagonal (src/paperdoll/diag.lua)
  n.diag = (ax > 0.4 * ay and ay > 0.4 * ax) and ((dy > 0 and 'd' or 'u') .. (dx < 0 and 'l' or 'r')) or nil
  n.walk = n.facing
  n.anim = (n.anim or 0) + dt
  n:sync_blocker()
end

-- ja és al lloc: què hi fa (tovallola, nedar, regar) i, a casa, deixa el que portava
function Town.arrived(n, r)
  r.visited = r.place
  if r.place == 'home' or r.place == 'post' then r.carry = nil end
  local a = ({ beach = 'towel', garden = 'water' })[r.place]
  if (r.place == 'pool' or r.place == 'beach') and r.goal and r.goal.swim then a = 'swim'   -- dins l'aigua
  elseif r.place == 'pool' then a = 'towel' end
  if a and n.activity ~= a then
    n.activity = a
    n.facing = a == 'towel' and 'down' or n.facing
  end
end

-- el que fan els veïns: tovallola a sota, nedant (l'aigua els tapa fins a la cintura), regadora amb gotes,
-- la barra de pa o la bossa a la mà i espurnes de tall de cabell nou (sprites/errands.png)
function Town.draw_errands(w, add, ox, oy)
  local sh = w.game.sprites.errands
  if not sh then return end
  local q, t = sh.quads, love.timer.getTime()
  for _, n in ipairs(w.npcs) do
    local r = n.routine
    if r and not n.hidden and (n.activity or r.carry or n.sparkle_t) and w.cam:visible(n.body.x - 16, n.body.y - 24, 32, 32) then
      local x, y = math.floor(n.body.x + 0.5) - ox, math.floor(n.body.y + 0.5) - oy
      if n.activity == 'towel' then
        add(n.body.y - 12, function() love.graphics.draw(sh.img, q[4], x + 5, y - 13) end)   -- al costat: la seva tovallola
      elseif n.activity == 'swim' then
        add(n.body.y + 4.2, function()
          love.graphics.setColor(0.35, 0.72, 0.86, 0.92)
          love.graphics.rectangle('fill', x - 9, y - 6, 18, 10)
          love.graphics.setColor(0.9, 0.97, 1, 0.9)
          local k = math.floor(t * 4) % 3
          love.graphics.rectangle('fill', x - 8 + k, y - 6, 5, 1); love.graphics.rectangle('fill', x + 2 - k, y - 6, 5, 1)
          love.graphics.setColor(1, 1, 1, 1)
        end)
      elseif n.activity == 'water' then
        add(n.body.y + 4.2, function()
          local side = (n.facing == 'left') and -1 or 1
          love.graphics.draw(sh.img, q[3], x + side * 6 - 8, y - 14)
          if math.floor(t * 3) % 2 == 0 then love.graphics.draw(sh.img, q[5], x + side * 14 - 8, y - 8) end
        end)
      end
      local item = r.carry == 'bread' and 1 or (r.carry == 'bag' and 2 or nil)
      if item and n.activity ~= 'swim' then
        add(n.body.y + 4.3, function() love.graphics.draw(sh.img, q[item], x - 2, y - 14) end)
      end
      if n.sparkle_t then
        n.sparkle_t = n.sparkle_t + 1 / 60
        if n.sparkle_t > 3 then n.sparkle_t = nil
        else
          add(n.body.y + 4.4, function() love.graphics.draw(sh.img, q[6], x - 8, y - 30 - math.floor(n.sparkle_t * 3)) end)
        end
      end
    end
  end
end

-- salutacions i reaccions als vehicles massa ràpids
-- salutacions de la gent pel carrer: segons l'hora, i de tant en tant una frase (per a una nena de 5 anys:
-- curtes, amables i que es puguin entendre en veu alta)
local GREET = {
  morning = { 'Bon dia!', 'Bon dia! Quin sol més bonic!', 'Hola! Vas a l\'escola?', 'Bon dia! Has esmorzat bé?',
              'Ei, bon dia! Fa un dia preciós.', 'Hola, hola!', 'Bon dia! Els ocells ja canten.' },
  afternoon = { 'Bona tarda!', 'Hola! Com va la tarda?', 'Bona tarda! Anem a berenar?', 'Ei, hola! Que vas a la platja?',
                'Bona tarda! Quina calor que fa.', 'Hola! M\'agrada el teu casc.', 'Bona tarda! Has vist els gats?' },
  night = { 'Bona nit!', 'Bona nit! Ja surt la lluna.', 'Hola! Ja és fosc, ves amb compte.', 'Bona nit! Mira quantes estrelles!',
            'Bona nit! Que somiïs coses boniques.' },
  any = { 'Hola! Com estàs?', 'Ei! Bona sort a l\'aventura!', 'Hola! Saps que a la platja hi ha banderes de colors?',
          'Hola! Si tens gana, a la fleca fan coca.', 'Hola! A les granges hi ha rucs i gallines.',
          'Ei! Has trobat algun tresor?', 'Hola! Quin nom més bonic tens.', 'Hola! M\'encanta el nostre poble.',
          'Hola! Recorda: per creuar, el ninotet verd.', 'Hola! Avui he vist un dofí al mar!',
          'Ei! Saps fer la croqueta a la sorra?', 'Hola! Els arbres fan ombra i oxigen.' },
}
Town.GREET = GREET
local function greeting(st)
  local c = (st.clock or 540) % 1440
  local pool = (c >= 6 * 60 and c < 14 * 60) and GREET.morning or ((c >= 14 * 60 and c < 21 * 60) and GREET.afternoon
    or GREET.night)
  if math.random() < 0.35 then pool = GREET.any end
  return pool[math.random(#pool)]
end

function Town.bubble(n, text, t)
  n.bubble = { text = text, t = t or 2.2 }
  -- la bafarada també es diu (amb veu d'home o de dona segons qui parla)
  local Tts = require('src.tts')
  if Tts.settings and Tts.settings.tts and Tts.settings.tts.all ~= false then
    local p = n.props or {}
    Tts.say(text, false, Tts.gender(p.say_name or p.name) or (p.sprite and Town.sprite_voice(p.sprite)))
  end
end

-- veu per l'aspecte quan el nom no ho diu
local SPRITE_VOICE = { npc_girl = 'f', npc_lady = 'f', npc_kid = 'm', npc_elder = 'm', npc_fisher = 'm', npc_baker = 'f',
                       npc_postie = 'm', npc_ranger = 'm', npc_gardener = 'm' }
function Town.sprite_voice(sprite) return SPRITE_VOICE[sprite] end

function Town.reactions(w, n, dt)
  if n.bubble then
    n.bubble.t = n.bubble.t - dt
    if n.bubble.t <= 0 then n.bubble = nil end
  end
  if n.hop then n.hop = n.hop - dt; if n.hop <= 0 then n.hop = nil end end
  if n.hidden or w.talking == n then return end
  local pl = w.player
  local b = pl.body
  local d2 = (n.body.x - b.x) ^ 2 + (n.body.y - b.y) ^ 2
  local now = w.state.play_time or 0
  local v = pl.vehicle
  -- velocitat del pas anterior: si xoca contra la persona, la frenada no amaga que anava massa de pressa
  local speed = v and math.max(v.speed, w.town.last_speed or 0) or 0
  if v and speed > FAST and d2 < 30 ^ 2 then
    if now - (n.scared_t or -99) > 3 then
      n.scared_t = now
      n.hop = 0.25
      n:face(b.x, b.y)
      local name = n.props.friend and (w.state.player_name or '') or nil
      Town.bubble(n, (name and name ~= '' and (name .. ', ') or 'Ep! ') .. 'vés a poc a poc!', 2)
      w.game.audio.play('block', { vol = 0.6 })
      w.state.scares = (w.state.scares or 0) + 1
    end
    return
  end
  if d2 < 44 ^ 2 and not v and now - (n.greet_t or -99) > GREET_EVERY and not n.props.service then
    n.greet_t = now
    n:face(b.x, b.y)
    local name = w.state.player_name
    if n.props.friend and name then Town.bubble(n, 'Hola, ' .. name .. '!')
    else Town.bubble(n, greeting(w.state)) end
  end
end

-- ---------------------------------------------------------------- passos de vianants i semàfors (missions)
function Town.crossings(w)
  local tr = w.traffic
  if not tr then return end
  local T = w.town
  local b = w.player.body
  if (b.level or 0) ~= 0 then T.cross = nil; return end
  local c = T.cross
  if c then
    local cw = c.cw
    local d2 = (cw.x - b.x) ^ 2 + (cw.y - b.y) ^ 2
    if d2 > (cw.r + 4) ^ 2 then
      -- ha sortit: ha creuat si s'ha desplaçat d'una vorera a l'altra (en la direcció de creuar)
      local nx, ny = -math.sin(cw.ang), math.cos(cw.ang)
      local across = math.abs((b.x - c.x) * nx + (b.y - c.y) * ny)
      T.cross = nil
      if across >= cw.r * 1.3 then
        if cw.light then
          if c.green then Town.event(w, 'light', {}); Town.event(w, 'crosswalk', {})
          else
            w.hud:toast('Has creuat amb el ninotet en vermell! Espera el verd.', 3)
            Town.event(w, 'light_red', {})
          end
        else
          Town.event(w, 'crosswalk', {})
        end
      end
    elseif cw.light and not select(2, require('src.systems.traffic').light_state(cw, tr.clock)) then
      c.green = false        -- s'ha posat vermell mentre creuaves: no compta com a ben fet
    end
    return
  end
  for _, cw in ipairs(tr.crosswalks) do
    if cw.ang and (cw.x - b.x) ^ 2 + (cw.y - b.y) ^ 2 < cw.r ^ 2 then
      local green = true
      if cw.light then green = select(2, require('src.systems.traffic').light_state(cw, tr.clock)) end
      T.cross = { cw = cw, x = b.x, y = b.y, green = green }
      return
    end
  end
end

-- ---------------------------------------------------------------- l'Olaf t'espera al parc
function Town.send_olaf(w, s)
  local tgt = Town.resolve(w, s.target)
  if not tgt then return end
  local q = Missions.state(w.state)
  q.olaf_away = { x = tgt.x, y = tgt.y }
  w.olaf = nil
  if w.id == 'overworld' then Town.place_olaf_npc(w) end
  w.hud:toast('L\'Olaf ha marxat cap al parc...', 2.5)
end

function Town.place_olaf_npc(w)
  local q = Missions.state(w.state)
  -- partides velles: si la missió ara apunta a un altre parc (abans la Masieta, de Creixell), l'Olaf hi va
  local _, s = Missions.current(Town.defs(w.game), w.state)
  if s and s.type == 'meet_olaf' then
    local tgt = Town.resolve(w, s.target)
    if tgt then q.olaf_away = { x = tgt.x, y = tgt.y } end
  end
  w.olaf = nil
  w.town.olaf_wait = { x = q.olaf_away.x, y = q.olaf_away.y }
end

function Town.update_olaf_meet(w)
  local o = w.town.olaf_wait
  if not o then return end
  local b = w.player.body
  if (o.x - b.x) ^ 2 + (o.y - b.y) ^ 2 < 26 ^ 2 then
    local q = Missions.state(w.state)
    q.olaf_away = nil
    w.town.olaf_wait = nil
    local g = w.game
    w.olaf = require('src.entities.follower').new('Olaf', g.sprites.chars.npc_cat_grey, o.x, o.y, 20)
    w.olaf.walkable = function(x, y)
      local tx, ty = math.floor(x / 16), math.floor(y / 16)
      return w.map:in_bounds(tx, ty) and Collision.walk_at(w.map:cell(tx, ty), 0)
    end
    w.olaf:place(b.x, b.y, w.player.facing)
    g.audio.play('meow')
    w.fx:preset('sparkle', o.x, o.y - 10, 10, { color = { 1, 0.7, 0.75 } })
    Town.event(w, 'arrive', {})
  end
end

-- ---------------------------------------------------------------- punts de reciclatge
function Town.recycling(w)
  local g = w.game
  if g.recycling then return g.recycling end
  g.recycling = {}
  Streets.name_at(0, 0)
  local d = Streets._data and Streets._data()
  -- posició de l'OSM; s'ajusta a la casella transitable més propera quan el seu chunk ja és carregat
  for _, p in ipairs(d and d.recycling or {}) do g.recycling[#g.recycling + 1] = { x = p[1], y = p[2] } end
  return g.recycling
end

-- ---------------------------------------------------------------- interacció
-- abans del diàleg normal d'un personatge: missions (parlar, lliurar) i amics. true = ja està atès
function Town.on_talk(w, n)
  local g = w.game
  local p = n.props
  if p.parent then return Family.talk(w, n) end
  if p.farmer then return require('src.systems.farm').talk(w, n) end   -- el pagès dona pinso
  local target = p.friend and ('friend:' .. p.friend) or (p.service_id and ('service:' .. p.service_id))
  local _, s = Missions.current(Town.defs(g), w.state)
  if target and s and s.target == target and (s.type == 'deliver' or s.type == 'talk') then
    local res = Town.event(w, 'talk', { target = target })
    if s.type == 'deliver' then
      if res then w.dialogue:show(p.say_name, s.done_text or { 'Moltes gràcies!' }); return true end
      w.hud:toast('Et falta: ' .. ((g.items[s.item] or {}).name or s.item), 2.5)
    elseif res and p.friend then
      w.dialogue:show(p.say_name, Town.friend_lines(w, n)); return true
    end
    -- parlar amb un servei compta i després s'obre el servei com sempre
  end
  if p.friend then w.dialogue:show(p.say_name, Town.friend_lines(w, n)); return true end
  local line = Town.errand_line(w, n)
  if line and not p.dialogue and not p.ai then
    local pages = { line }
    for part in tostring(p.say or ''):gmatch('[^|]+') do pages[#pages + 1] = part end
    w.dialogue:show(p.say_name or n.name, pages)
    return true
  end
  return false
end

-- què fa un veí ara (clau de Errands.LINES; també la rep la IA: tools/web_server.py NPC_DOING) o nil
function Town.errand_key(w, n)
  local r = n.routine
  if not r or not r.seed then return nil end
  if r.haircut and (w.state.clock or 0) < r.haircut and (w.state.clock or 0) > r.haircut - 120 then return 'haircut' end
  if r.carry then return r.carry end
  if Errands.PLACE_NAMES[r.place] or r.place == 'shop' then return r.place end
  return nil
end

-- què explica un veí segons el seu encàrrec (o nil si no en fa cap)
function Town.errand_line(w, n)
  local k = Town.errand_key(w, n)
  return k and Errands.line(k, n.routine.seed) or nil
end

function Town.friend_lines(w, n)
  local f = Town.friend(w.game, n.props.friend) or {}
  local name = w.state.player_name or ''
  local place = n.routine and n.routine.place
  local where = ({ school = 'Ara tinc classe! Ens veiem a la tarda al parc?', park = 'Que bé, al parc! Juguem una estona?',
                   plaza = 'Estic fent encàrrecs per la plaça.', shop = 'He vingut a comprar. Vols res?',
                   home = 'Passa, passa! Estàs a casa teva.' })[place or 'home']
      or Errands.line(place, n.routine and n.routine.seed) or 'Passa, passa! Estàs a casa teva.'
  local hello = (f.role == 'avi' or f.role == 'avia') and ('Hola, ' .. name .. ', bonica criatura!') or ('Hola, ' .. name .. '!')
  local lines = { hello, where }
  if (w.state.scares or 0) > 0 and n.props.friend then
    lines[#lines + 1] = 'I recorda: amb la bici o el patinet, a poc a poc quan hi ha gent!'
  end
  return lines
end

-- contenidors i semàfors davant (per a l'indicador i la interacció)
function Town.interact(w, fx, fy)
  if w.id ~= 'overworld' then return Family.interact(w, fx, fy) end
  for _, r in ipairs(Town.recycling(w)) do
    if (r.x - fx) ^ 2 + (r.y - 4 - fy) ^ 2 < 16 ^ 2 then
      local g = w.game
      require('src.minigames.init').start(g, 'recycle', {}, function(res)
        if res.finished then
          w:reward(res.right * 3, 0, string.format('Reciclatge: %d de %d', res.right, res.total))
          if res.passed then Town.event(w, 'recycle', {}) end
        end
      end)
      return true
    end
  end
  return false
end

function Town.can_interact(w, fx, fy)
  if w.id ~= 'overworld' then return Family.can_interact(w, fx, fy) end
  for _, r in ipairs(Town.recycling(w)) do
    if (r.x - fx) ^ 2 + (r.y - 4 - fy) ^ 2 < 16 ^ 2 then return true end
  end
  return false
end

-- ---------------------------------------------------------------- dibuix
local BIN_C = { { 0.98, 0.82, 0.25 }, { 0.24, 0.44, 0.77 }, { 0.33, 0.62, 0.30 }, { 0.55, 0.36, 0.20 }, { 0.52, 0.52, 0.54 } }

-- elements del món ordenats per Y: add(y, fn)
function Town.draw_world(w, add, ox, oy)
  if w.id ~= 'overworld' then return end
  local cam = w.cam
  Town.draw_errands(w, add, ox, oy)
  for _, r in ipairs(Town.recycling(w)) do
    if cam:visible(r.x - 16, r.y - 16, 32, 24) then
      if not r.snapped then
        r.snapped = true
        local x, y = walkable_near(w.game, r.x, r.y, 3)
        if x then r.x, r.y = x, y end
      end
      add(r.y + 4, function()
        local x0, y0 = math.floor(r.x - 15 - ox), math.floor(r.y - 10 - oy)
        for i, c in ipairs(BIN_C) do
          local x = x0 + (i - 1) * 6
          love.graphics.setColor(0.12, 0.10, 0.14); love.graphics.rectangle('fill', x - 1, y0 - 1, 7, 13)
          love.graphics.setColor(c); love.graphics.rectangle('fill', x, y0, 5, 11)
          love.graphics.setColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7); love.graphics.rectangle('fill', x, y0, 5, 2)
        end
        love.graphics.setColor(1, 1, 1)
      end)
    end
  end
  -- semàfors
  local Traffic = require('src.systems.traffic')
  for _, cw in ipairs(w.traffic and w.traffic.crosswalks or {}) do
    if cw.light and cam:visible(cw.x - 40, cw.y - 40, 80, 80) then
      local nx, ny = -math.sin(cw.ang), math.cos(cw.ang)
      for _, side in ipairs({ -1, 1 }) do
        local px, py = cw.x + nx * (cw.r + 4) * side, cw.y + ny * (cw.r + 4) * side
        add(py + 2, function()
          local car, walk = Traffic.light_state(cw, w.traffic.clock)
          local x, y = math.floor(px - ox), math.floor(py - oy)
          love.graphics.setColor(0.25, 0.24, 0.27); love.graphics.rectangle('fill', x, y - 22, 2, 22)
          love.graphics.setColor(0.12, 0.10, 0.14); love.graphics.rectangle('fill', x - 2, y - 34, 6, 13)
          local lamps = { { 'red', { 0.95, 0.25, 0.2 } }, { 'amber', { 1, 0.7, 0.15 } }, { 'green', { 0.3, 0.9, 0.4 } } }
          for i, l in ipairs(lamps) do
            local on = car == l[1]
            love.graphics.setColor(l[2][1] * (on and 1 or 0.25), l[2][2] * (on and 1 or 0.25), l[2][3] * (on and 1 or 0.25))
            love.graphics.rectangle('fill', x - 1, y - 33 + (i - 1) * 4, 4, 3)
          end
          -- ninotet dels vianants
          love.graphics.setColor(0.12, 0.10, 0.14); love.graphics.rectangle('fill', x - 2, y - 19, 6, 8)
          love.graphics.setColor(walk and 0.3 or 0.95, walk and 0.9 or 0.25, walk and 0.4 or 0.2)
          love.graphics.rectangle('fill', x, y - 18, 2, 2); love.graphics.rectangle('fill', x - 1, y - 16, 4, 3)
          love.graphics.setColor(1, 1, 1)
        end)
      end
    end
  end
  -- marcador de l'objectiu de la missió a la vista: fletxa que bota damunt de qui has de parlar i
  -- anell al terra als llocs on has d'arribar (els infants el troben sense mirar la brúixola)
  local T = w.town
  local tg = T and T.target
  if tg and tg.x and not tg.raw and cam:visible(tg.x - 40, tg.y - 64, 80, 96) then
    local c = Missions.CAT_COLOR[T.cat] or { 1, 0.85, 0.3 }
    local goto_ = T.step_type == 'goto' or T.step_type == 'meet_olaf'
    add(tg.y + (goto_ and -400 or 30), function()
      local t = love.timer.getTime()
      local x, y = math.floor(tg.x - ox), math.floor(tg.y - oy)
      if goto_ then
        local r = math.min(40, (T.radius or 32) * 0.6) + math.sin(t * 3) * 2
        love.graphics.setLineWidth(2)
        love.graphics.setColor(c[1], c[2], c[3], 0.55 + 0.25 * math.sin(t * 3))
        love.graphics.ellipse('line', x, y, r, r * 0.5)
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.ellipse('line', x, y, r * 0.6, r * 0.3)
        love.graphics.setLineWidth(1)
      else
        local by = y - 40 - math.floor(math.abs(math.sin(t * 4)) * 5)
        love.graphics.setColor(0.12, 0.10, 0.14)
        love.graphics.polygon('fill', x - 6, by - 1, x + 6, by - 1, x, by + 8)
        love.graphics.setColor(c)
        love.graphics.polygon('fill', x - 4, by, x + 4, by, x, by + 6)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.rectangle('fill', x - 2, by, 2, 2)
      end
      love.graphics.setColor(1, 1, 1)
    end)
  end
  -- notes musicals que surten del campanar quan toquen les hores
  if T and T.bell_t and T.bell then
    local o = T.bell
    if cam:visible(o.x - 20, o.y - 60, 80, 80) then
      add(o.y + 200, function()
        for i = 0, 2 do
          local k = T.bell_t - i * 0.6
          if k > 0 and k < 2.4 then
            local x = math.floor(o.x + 16 - ox + math.sin(k * 3 + i) * 6 + (i - 1) * 8)
            local y = math.floor(o.y - 4 - oy - k * 14)
            love.graphics.setColor(0.12, 0.10, 0.14, 1 - k / 2.4)
            love.graphics.rectangle('fill', x, y, 3, 3); love.graphics.rectangle('fill', x + 2, y - 7, 1, 8)
            love.graphics.rectangle('fill', x + 3, y - 7, 3, 1)
            love.graphics.setColor(1, 0.9, 0.5, 1 - k / 2.4)
            love.graphics.rectangle('fill', x + 1, y + 1, 1, 1)
          end
        end
        love.graphics.setColor(1, 1, 1)
      end)
    end
  end
  -- l'Olaf esperant al parc
  local o = w.town and w.town.olaf_wait
  if o and cam:visible(o.x - 8, o.y - 20, 16, 24) then
    local sh = w.game.sprites.chars.npc_cat_grey
    add(o.y + 4, function()
      love.graphics.setColor(0.10, 0.08, 0.12, 0.28); love.graphics.ellipse('fill', math.floor(o.x - ox), math.floor(o.y + 3 - oy), 5, 2)
      love.graphics.setColor(1, 1, 1)
      local col = (math.floor(love.timer.getTime() * 2) % 6 == 0) and 5 or 4
      love.graphics.draw(sh.sheet, sh.quad(0, col), math.floor(o.x - 8 - ox), math.floor(o.y - 20 - oy))
      if math.floor(love.timer.getTime() * 1.5) % 2 == 0 then
        love.graphics.setColor(1, 0.6, 0.7); love.graphics.print('?', math.floor(o.x - 2 - ox), math.floor(o.y - 40 - oy))
        love.graphics.setColor(1, 1, 1)
      end
    end)
  end
end

-- bafarades de salutació (damunt de tot, a la vista)
function Town.draw_bubbles(w, ox, oy)
  local font = w.game.font
  for _, n in ipairs(w.npcs) do
    local bb = n.bubble
    if bb and not n.hidden and w.cam:visible(n.body.x - 40, n.body.y - 50, 80, 60) then
      local tw = math.min(160, font:getWidth(bb.text) + 8)
      local x = math.floor(n.body.x - ox - tw / 2)
      local y = math.floor(n.body.y - oy - 46)
      local a = math.min(1, bb.t * 3)
      love.graphics.setColor(0.98, 0.96, 0.9, 0.95 * a); love.graphics.rectangle('fill', x, y, tw, 17, 3)
      love.graphics.polygon('fill', x + tw / 2 - 3, y + 17, x + tw / 2 + 3, y + 17, x + tw / 2, y + 21)
      love.graphics.setColor(0.12, 0.10, 0.14, a)
      love.graphics.setScissor(x, y, tw, 17)
      love.graphics.print(bb.text, x + 4, y)
      love.graphics.setScissor()
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- cartell de les cases dels amics (nom a sobre de la porta quan t'hi acostes)
-- casa del jugador: testos amb flors a banda i banda de la porta, estoreta i el rètol en apropar-s'hi
local POT_FLOWERS = { { 0.93, 0.33, 0.36 }, { 0.98, 0.82, 0.3 }, { 0.82, 0.5, 0.9 } }
local function draw_pot(x, y, i)
  local lg = love.graphics
  lg.setColor(0, 0, 0, 0.25); lg.ellipse('fill', x, y + 1, 5, 1.5)
  lg.setColor(0.72, 0.38, 0.22); lg.polygon('fill', x - 4, y - 6, x + 4, y - 6, x + 3, y, x - 3, y)
  lg.setColor(0.55, 0.27, 0.15); lg.rectangle('fill', x - 4, y - 7, 8, 2)
  lg.setColor(0.3, 0.55, 0.25); lg.ellipse('fill', x, y - 10, 5, 4)
  lg.setColor(0.22, 0.42, 0.2); lg.ellipse('fill', x + 1, y - 9, 3, 2)
  for k = 0, 2 do
    local c = POT_FLOWERS[(i + k) % 3 + 1]
    lg.setColor(c); lg.rectangle('fill', x - 3 + k * 3, y - 13 + (k % 2) * 2, 2, 2)
  end
end

local function draw_own_home(w, ox, oy, font, b)
  local hd = w.house_door
  if not hd then return end
  local x, y = hd[1] * 16 + 8, hd[2] * 16
  if not w.cam:visible(x - 32, y - 24, 64, 48, 0) then return end
  local lg = love.graphics
  lg.setColor(0.62, 0.32, 0.25); lg.rectangle('fill', math.floor(x - 6 - ox), math.floor(y + 17 - oy), 12, 5)   -- estoreta
  lg.setColor(0.78, 0.48, 0.32); lg.rectangle('fill', math.floor(x - 5 - ox), math.floor(y + 18 - oy), 10, 1)
  draw_pot(math.floor(x - 13 - ox), math.floor(y + 22 - oy), 0)
  draw_pot(math.floor(x + 13 - ox), math.floor(y + 22 - oy), 1)
  if (x - b.x) ^ 2 + (y - b.y) ^ 2 < 90 ^ 2 then
    local nm = w.game.profile and w.game.profile.name
    local text = nm and ('Casa de ' .. nm) or 'Casa'
    local tw = font:getWidth(text) + 8
    lg.setColor(0.36, 0.62, 0.95, 0.9)
    lg.rectangle('fill', math.floor(x - ox - tw / 2), math.floor(y - oy - 22), tw, 17, 3)
    lg.setColor(1, 1, 1)
    lg.print(text, math.floor(x - ox - tw / 2 + 4), math.floor(y - oy - 22))
  end
  lg.setColor(1, 1, 1)
end

function Town.draw_homes(w, ox, oy)
  if w.id ~= 'overworld' then return end
  local font = w.game.font
  local b = w.player.body
  draw_own_home(w, ox, oy, font, b)
  for _, fr in ipairs(w.game.friends or {}) do
    local f = fr.def
    if f.home and f.home.door_x then
      local x, y = f.home.door_x * 16 + 8, f.home.door_y * 16
      if (x - b.x) ^ 2 + (y - b.y) ^ 2 < 90 ^ 2 then
        local text = 'Casa de ' .. f.name
        local tw = font:getWidth(text) + 8
        love.graphics.setColor(0.93, 0.52, 0.72, 0.9)
        love.graphics.rectangle('fill', math.floor(x - ox - tw / 2), math.floor(y - oy - 22), tw, 17, 3)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(text, math.floor(x - ox - tw / 2 + 4), math.floor(y - oy - 22))
      end
    end
  end
end

-- brúixola: fletxa cap a l'objectiu, distància en metres i el text del pas
function Town.draw_hud(w)
  local T = w.town
  if not T or not T.text then return end
  local font = w.game.font
  local c = Missions.CAT_COLOR[T.cat or 'nav']
  local tgt = T.target
  local b = w.player.body
  local text = T.closed and ('Tancat. ' .. T.closed.when .. ' · Menú: Esperar') or T.text
  local x0, y0 = 206, 202            -- a baix a la dreta: no tapa els avisos ni la vida
  love.graphics.setColor(0.12, 0.10, 0.14, 0.78)
  love.graphics.rectangle('fill', x0, y0, 112, 34, 4)
  love.graphics.setColor(c[1], c[2], c[3]); love.graphics.rectangle('line', x0 + 0.5, y0 + 0.5, 111, 33, 4)
  local cx, cy = x0 + 14, y0 + 17
  if tgt and w.id == 'overworld' then
    local dx, dy = tgt.x - b.x, tgt.y - b.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local meters = math.floor(dist / 16 * 4 / 5 + 0.5) * 5
    if dist < 40 then
      local k = 0.6 + 0.4 * math.abs(math.sin(love.timer.getTime() * 5))
      love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k); love.graphics.circle('fill', cx, cy, 7)
      love.graphics.setColor(1, 1, 1); love.graphics.print('Aquí!', x0 + 28, y0)
    else
      local a = math.atan2(dy, dx)
      local function p(r, da) return cx + math.cos(a + da) * r, cy + math.sin(a + da) * r end
      local ax, ay = p(11, 0)
      local bx, by = p(8, 2.5)
      local qx, qy = p(3, math.pi)
      local dx2, dy2 = p(8, -2.5)
      love.graphics.setColor(c[1], c[2], c[3])
      love.graphics.polygon('fill', ax, ay, bx, by, qx, qy, dx2, dy2)
      love.graphics.setColor(1, 1, 1)
      love.graphics.print(meters >= 1000 and string.format('%.1f km', meters / 1000) or (meters .. ' m'), x0 + 28, y0)
    end
  elseif T.inside and w.id:sub(1, #T.inside) == T.inside then
    love.graphics.setColor(1, 1, 1); love.graphics.print('És per aquí', x0 + 28, y0)
  elseif w.id ~= 'overworld' then
    love.graphics.setColor(1, 1, 1); love.graphics.print('Surt al carrer', x0 + 28, y0)
  end
  -- text de l'objectiu (es desplaça si és llarg)
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.setScissor(x0 + 28, y0 + 16, 82, 17)
  local tw = font:getWidth(text)
  local off = tw > 82 and ((love.timer.getTime() * 20) % (tw + 30)) or 0
  love.graphics.print(text, x0 + 28 - off, y0 + 16)
  if tw > 82 then love.graphics.print(text, x0 + 28 - off + tw + 30, y0 + 16) end
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1)
end

return Town
