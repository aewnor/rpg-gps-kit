-- Pruebas de la fase 5 sin ventana (luajit tests/missions_cases.lua): perfiles (saneado y límites), aspecto
-- del paperdoll, motor de misiones, horarios, A*, calles y el juego de reciclar.
package.path = './?.lua;./?/init.lua;' .. package.path
love = { math = { random = math.random } }
local json = require('src.lib.json')
local Profile = require('src.profile')
local Looks = require('src.paperdoll.looks')
local Missions = require('src.systems.missions')
local Schedule = require('src.systems.schedule')
local AStar = require('src.world.astar')
local Streets = require('src.systems.streets')
local Recycle = require('src.minigames.recycle')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end
local function read(p) local f = assert(io.open(p)); local s = f:read('*a'); f:close(); return s end

-- ---------------------------------------------------------------- perfiles
local mem = {}
Profile.fs = { read = function(p) return mem[p] end, write = function(p, d) mem[p] = d; return true end,
               exists = function(p) return mem[p] ~= nil end, remove = function(p) mem[p] = nil; return true end }
check(#Profile.list() == 5 and not Profile.list()[3].exists, '5 ranuras, todas vacías')
local p = Profile.new('Nena', 'nena')
for i = 1, Profile.MAX_FRIENDS + 3 do p.friends[i] = Profile.new_friend(p, i % 2 == 0 and 'avia' or 'amiga') end
p.friends[1].name = string.rep('Ñ', 30) .. '<script>'
p.friends[2].home = { tile_x = '12', tile_y = 40.7, street = 'Carrer Major' }
p.home = { tile_x = 600, tile_y = 800 }
Profile.write(2, p)
local r = Profile.read(2)
check(r and #r.friends == Profile.MAX_FRIENDS, 'como mucho MAX_FRIENDS personajes por perfil')
check(not r.friends[1].name:find('<') and #r.friends[1].name <= 2 * Profile.NAME_MAX, 'los nombres se limpian y se cortan (UTF-8)')
check(r.friends[2].home.tile_x == 12 and r.friends[2].home.tile_y == 40, 'casas saneadas a enteros')
check(r.home.tile_x == 600 and Profile.home_cfg(r).configured, 'la casa del perfil se convierte en configuración de casa')
check(mem[Profile.path(2)]:find('home_player_location') ~= nil, 'en user_profile.json la casa es home_player_location')
local ids = {}
for _, f in ipairs(r.friends) do check(not ids[f.id], 'id único ' .. f.id); ids[f.id] = true end
mem[Profile.path(3)] = '{esto no es json'
check(Profile.read(3) == nil and Profile.list()[3].exists and Profile.list()[3].error, 'un perfil corrupto no rompe la lista')
Profile.delete(2)
check(not Profile.list()[2].exists, 'borrar un perfil')

-- ---------------------------------------------------------------- aspecto (paperdoll)
local l = Looks.sanitize({ skin = 99, hair = 'mohawk', acc = { glasses = true, laser = true } })
check(l.skin == 2 and l.hair == 'bob' and l.acc.glasses and not l.acc.laser, 'aspecto saneado (valores fuera de la lista)')
local elder = Looks.preset_age(Looks.default('nen'), 'elder')
local spec = Looks.spec(elder)
check(spec.h == 'white' and table.concat(spec._extra, ','):find('glasses'), 'gran: pelo blanco y gafas')
check(Looks.spec(Looks.default('nena'))._age == 'kid', 'infant: 1 px más bajo (_age = kid)')
check(Looks.key(l) == Looks.key(Looks.sanitize(l)), 'clave estable para la caché')
local Chars = require('src.paperdoll.chars')
local sh = Chars.sheet(Looks.spec(Looks.default('nena')))
check(sh.w == 96 and sh.h == 96, 'la hoja paperdoll es 96 × 96 (6 × 4 fotogramas de 16 × 24)')

-- ---------------------------------------------------------------- misiones
local data = json.decode(read('tests/fixtures/missions_roda.json'))   -- (les missions de Roda de Berà, l'exemple original)
local friends = { { id = 'f1', name = 'Laia', role = 'amiga', home = { tile_x = 1, tile_y = 1 } },
                  { id = 'f2', name = 'Avi Joan', role = 'avi', home = { tile_x = 2, tile_y = 2 } },
                  { id = 'f3', name = 'Sense casa', role = 'amic' } }
local defs = Missions.build(data, friends)
check(defs.by_id.visit_f1 and defs.by_id.visit_f2 and not defs.by_id.visit_f3, 'una visita por personaje con casa')
check(defs.by_id.errand_f2 and not defs.by_id.errand_f1, 'el encargo solo para los abuelos')
check(defs.by_id.visit_f1.title == 'Visita Laia' and defs.by_id.visit_f1.steps[1].target == 'friend:f1', 'plantillas rellenadas')
local st = {}
check(Missions.status(defs, st, defs.by_id.escola) == 'open' and Missions.status(defs, st, defs.by_id.metge) == 'locked',
  'capítulo 1: una misión tras otra')
check(Missions.status(defs, st, defs.by_id.passos) == 'locked', 'seguridad bloqueada al empezar')
local log = {}
local hooks = function(kind, a) log[#log + 1] = kind; if kind == 'has' then return true end end
Missions.activate(defs, st, 'escola', hooks)
check(Missions.event(defs, st, 'talk', { target = 'service:metge' }, hooks) == nil, 'un evento que no toca no hace nada')
check(Missions.event(defs, st, 'arrive', {}, hooks) == 'done' and st.quests.done.escola, 'llegar a la escuela la completa')
check(st.quests.active == 'metge', 'se activa sola la siguiente')
Missions.event(defs, st, 'talk', { target = 'service:metge' }, hooks)
check(Missions.status(defs, st, defs.by_id.passos) == 'open' and Missions.status(defs, st, defs.by_id.visit_f1) == 'open',
  'con 2 hechas se abren familia y seguridad')
Missions.activate(defs, st, 'compra', hooks)
Missions.event(defs, st, 'arrive', {}, hooks)
check(Missions.event(defs, st, 'buy', { item = 'poma', service = 'mercadona' }, hooks) == nil, 'comprar en otra tienda no cuenta')
Missions.event(defs, st, 'buy', { item = 'poma', service = 'bonpreu' }, hooks)
check(Missions.event(defs, st, 'buy', { item = 'pa', service = 'lidl' }, hooks) == 'done', 'poma y pan (Bonpreu o Lidl): hecho')
Missions.activate(defs, st, 'passos', hooks)
Missions.event(defs, st, 'crosswalk', {}, hooks); Missions.event(defs, st, 'crosswalk', {}, hooks)
check(st.quests.count.passos == 2 and not st.quests.done.passos, 'contador de pasos de cebra (2/3)')
Missions.event(defs, st, 'crosswalk', {}, hooks)
check(st.quests.done.passos, '3 pasos de cebra: hecho')
Missions.activate(defs, st, 'semafor', hooks)
Missions.event(defs, st, 'light_red', {}, hooks)
check((st.quests.count.semafor or 0) == 0 and log[#log] == 'warn', 'cruzar en rojo: aviso y no cuenta')
Missions.activate(defs, st, 'errand_f2', hooks)
Missions.event(defs, st, 'arrive', {}, hooks)
check(Missions.event(defs, st, 'talk', { target = 'friend:f2' }, hooks) == 'done', 'encargo entregado al abuelo')
local done, total = Missions.progress(defs, st)
check(done == 5 and total == #defs.order, string.format('progreso %d/%d', done, total))

-- ---------------------------------------------------------------- fase 6: missions evolutives
local d6 = Missions.build(data, friends, { home = true })
check(d6.by_id.casa and not defs.by_id.casa, '«On és casa teva?» només si hi ha casa')
local s6 = { char_level = 1 }
local inv = {}
local log6 = {}
local h6 = function(kind, a, b)
  log6[#log6 + 1] = kind
  if kind == 'has' then return (inv[a] or 0) > 0 end
  if kind == 'give' then inv[a] = 1 end
  if kind == 'take' then inv[a] = nil end
end
local carta = d6.by_id.correus_carta
check(Missions.status(d6, s6, carta) == 'locked' and Missions.lock_reason(d6, s6, carta) == 'capítol',
  'encàrrecs: tancats fins acabar 4 missions del poble')
local q6 = Missions.state(s6)
for _, id in ipairs({ 'casa', 'escola', 'metge', 'mestra' }) do q6.done[id] = true end
check(Missions.lock_reason(d6, s6, carta) == 'Nv 2', 'després, cal nivell 2')
s6.char_level = 2
check(Missions.status(d6, s6, carta) == 'open', 'amb nivell 2 s\'obre el carter')
Missions.activate(d6, s6, 'correus_carta', h6)
Missions.event(d6, s6, 'talk', { target = 'service:correus' }, h6)
check(inv.carta_urgent == 1, 'en acabar el pas es rep la carta (give)')
check(Missions.event(d6, s6, 'talk', { target = 'service:ajuntament' }, h6) == 'done' and not inv.carta_urgent,
  'carta lliurada a l\'Ajuntament')
Missions.activate(d6, s6, 'escut', h6)
check(Missions.tick(d6, s6, h6) == nil, 'sense l\'escut el pas no avança')
inv.shield_roda = 1
check(Missions.tick(d6, s6, h6) == 'done', 'amb l\'escut a l\'inventari: fet (have)')
local drac = d6.by_id.llums
check(Missions.lock_reason(d6, s6, drac) == 'capítol', 'l\'èpica s\'obre després dels encàrrecs')
q6.done.correus_paquet = true
s6.char_level = 3
check(Missions.status(d6, s6, drac) == 'open', 'amb 3 encàrrecs i nivell 3: les llums de la muntanya')
Missions.activate(d6, s6, 'llums', h6)
Missions.event(d6, s6, 'talk', { target = 'service:policia' }, h6)
check(log6[#log6 - 2] == 'say' or log6[#log6 - 1] == 'say' or log6[#log6] == 'say', 'l\'agent explica les llums (say)')
Missions.activate(d6, s6, 'cova', h6)
check(Missions.event(d6, s6, 'enter', { scene = 'cova_pedrera' }, h6) == nil and
      Missions.event(d6, s6, 'enter', { scene = 'cova_roda_1' }, h6) == 'done', 'entrar a la Cova de Roda (enter)')
Missions.activate(d6, s6, 'fort', h6)
check(Missions.tick(d6, s6, h6) == nil, 'nivell 3: encara no')
s6.char_level = 5
check(Missions.event(d6, s6, 'level', {}, h6) == 'done', 'nivell 5: fet (level)')
Missions.activate(d6, s6, 'drac', h6)
check(Missions.event(d6, s6, 'defeat', { target = 'boss:dragon' }, h6) == 'done', 'vèncer el drac (defeat)')
Missions.activate(d6, s6, 'cartera', h6)
Missions.event(d6, s6, 'event', { name = 'wallet_started' }, h6)
inv.cartera = 1; Missions.tick(d6, s6, h6)
check(Missions.event(d6, s6, 'event', { name = 'wallet_returned' }, h6) == 'done', 'la cartera: feina, trobar-la i tornar-la')

-- ---------------------------------------------------------------- amigos y familia: misiones principales y secundarias
RODA = (json.decode(read('data/world.json')).name or 'Roda de Berà') == 'Roda de Berà'
local items = json.decode(read('data/items.json'))
local svc = {}
for _, sv in ipairs(json.decode(read('data/services.json')).services) do svc[sv.id] = true end
local ROLES = { 'amiga', 'amic', 'avia', 'avi', 'tieta', 'tiet', 'cosina', 'cosi' }
local function crew(n, parents)
  local out = {}
  for i = 1, n do
    out[i] = { id = 'f' .. i, name = 'Pers' .. i, role = ROLES[(i - 1) % #ROLES + 1], home = { tile_x = i, tile_y = i } }
    if parents then out[i].parents = { pare = 'Pare' .. i, mare = 'Mare' .. i } end
  end
  return out
end
local function unresolved(v)
  if type(v) == 'string' then return v:find('{[%w_]+}') ~= nil end
  if type(v) == 'table' then for _, x in pairs(v) do if unresolved(x) then return true end end end
  return false
end
local KNOWN = { door = true, boss = true, area = true, street = true, service = true, friend = true, friendhome = true, home = true, nearest = true,
                spot = true, chest = true, wallet = true }
local function valid_target(t, fr)
  local kind, arg = t:match('^(%w+):?(.*)$')
  if not KNOWN[kind] then return false end
  if kind == 'area' then return Streets.area(arg) ~= nil end
  if kind == 'street' then return Streets.street(arg) ~= nil end
  if kind == 'service' then return svc[arg] == true end
  if kind == 'friend' or kind == 'friendhome' then
    for _, f in ipairs(fr) do if f.id == arg and f.home then return true end end
    return false
  end
  return true
end
-- recorre una partida completa con ganchos simulados; devuelve el inventario y si se acabó sin atascarse
local function play(defsx, stx)
  local inv = {}
  local h = function(kind, a, b)
    if kind == 'has' then return (inv[a] or 0) >= (b or 1) end
    if kind == 'give' then inv[a] = (inv[a] or 0) + 1 end
    if kind == 'take' then inv[a] = (inv[a] or 0) - (b or 1); if inv[a] <= 0 then inv[a] = nil end end
  end
  local q = Missions.state(stx)
  for _ = 1, 2000 do
    local m, s = Missions.current(defsx, stx)
    if not m then
      local nxt
      for _, o in ipairs(defsx.order) do
        if Missions.status(defsx, stx, o) == 'open' and Missions.can_start(defsx, stx, o.id) then nxt = o; break end
      end
      if not nxt then return inv end
      Missions.activate(defsx, stx, nxt.id, h)
    else
      local t = s.type
      local r
      if t == 'talk' or t == 'deliver' then r = Missions.event(defsx, stx, 'talk', { target = s.target }, h)
      elseif t == 'goto' or t == 'meet_olaf' then r = Missions.event(defsx, stx, 'arrive', {}, h)
      elseif t == 'buy' then
        for _, it in ipairs(s.items) do inv[it] = (inv[it] or 0) + 1; r = Missions.event(defsx, stx, 'buy', { item = it, service = s.at[1] }, h) end
      elseif t == 'event' then r = Missions.event(defsx, stx, 'event', { name = s.event }, h)
      elseif t == 'enter' then r = Missions.event(defsx, stx, 'enter', { scene = s.scene }, h)
      elseif t == 'have' then inv[s.item] = s.count or 1; r = Missions.tick(defsx, stx, h)
      elseif t == 'level' then r = Missions.tick(defsx, stx, h)
      elseif t == 'defeat' then r = Missions.event(defsx, stx, 'defeat', { target = s.target }, h)
      else r = Missions.event(defsx, stx, t, { n = s.count or 1 }, h) end
      if not r then return inv, m.id .. ' (' .. t .. ')' end
    end
  end
  return inv, 'bucle'
end
for _, n in ipairs({ 0, 1, 5, 12 }) do
  local fr = crew(n, n == 5)
  local dn = Missions.build(data, fr, { home = true })
  local seen, bad, badt, badi, unres = {}, nil, nil, nil, nil
  for _, m in ipairs(dn.order) do
    if seen[m.id] then bad = m.id end
    seen[m.id] = true
    if unresolved(m.title) or unresolved(m.intro) or unresolved(m.steps) then unres = m.id end
    for _, s in ipairs(m.steps) do
      if s.target and not valid_target(s.target, fr) then badt = m.id .. ' → ' .. s.target end
      for _, a in ipairs(s.alt or {}) do if not valid_target(a, fr) then badt = m.id .. ' → ' .. a end end
      if s.item and not items[s.item] then badi = s.item end
      if s.give and not items[s.give] then badi = s.give end
      for _, it in ipairs(s.items or {}) do if not items[it] then badi = it end end
    end
    if m.reward_item and not items[m.reward_item] then badi = m.reward_item end
    if m.give and not items[m.give] then badi = m.give end
  end
  check(not bad, n .. ' amigos: ids de misión únicos' .. (bad and (' (' .. bad .. ')') or ''))
  check(not unres, n .. ' amigos: sin marcadores {…} sin rellenar' .. (unres and (' (' .. unres .. ')') or ''))
  -- (els objectius de les missions de Roda només existeixen al mapa de Roda; el d'aquí el valida tools/validate_content.py)
  check(not RODA or not badt, n .. ' amigos: todos los objetivos existen (' .. tostring(badt) .. ')')
  check(not badi, n .. ' amigos: todos los objetos existen en items.json (' .. tostring(badi) .. ')')
  local colla = dn.by_chapter.colla
  check(#colla.missions == math.min(math.max(n, 3), 6) + 1, n .. ' amigos: cadena «colla» de ' .. #colla.missions .. ' misiones')
  local again = Missions.build(data, fr, { home = true })
  local same = #again.order == #dn.order
  for i, m in ipairs(dn.order) do if again.order[i].id ~= m.id then same = false end end
  check(same, n .. ' amigos: la generación es estable (mismo orden)')
  local stx = { char_level = 9 }
  local inv, stuck = play(dn, stx)
  local done, total = Missions.progress(dn, stx)
  check(not stuck and done == total, string.format('%d amigos: partida completa %d/%d%s', n, done, total, stuck and (' atascada en ' .. stuck) or ''))
  check(stx.quests.done.colla_final and inv.mapa_muntanya == 1 and not inv.fragment_mapa,
    n .. ' amigos: la cadena termina con el mapa y consume los fragmentos')
end
do
  local fr = crew(3, true)
  local dn = Missions.build(data, fr, { home = true })
  check(dn.by_id.pares_f1.steps[2].text:find('Pare1 i Mare1', 1, true) and dn.by_id.pares_f1.intro[1]:find('Pare1 i Mare1', 1, true),
    'los pares del perfil salen por su nombre')
  fr[1].parents = nil
  dn = Missions.build(data, fr, { home = true })
  local dp = Profile.default_parents('f:f1')
  check(dn.by_id.pares_f1.steps[2].text:find(dp.pare .. ' i ' .. dp.mare, 1, true), 'sin nombres: los de por defecto del perfil')
  fr[1].name = '100%\\1 d\'Ar'
  dn = Missions.build(data, fr, { home = true })
  check(dn.by_id.visit_f1.title == 'Visita 100%\\1 d\'Ar', 'un nombre con % o \\ no rompe las plantillas')
  check(dn.by_id.joguet_f1 and not dn.by_id.compra_avis_f1 and dn.by_id.compra_avis_f3 and not dn.by_id.joguet_f3,
    'secundarias según el rol (amiga / avia)')
end
do
  -- sin casa no hay misiones de ese personaje; la colla usa vecinos del pueblo
  local fr = crew(3)
  fr[2].home = nil
  local dn = Missions.build(data, fr, { home = true })
  check(not dn.by_id.visit_f2 and not dn.by_id.colla_f2 and dn.by_id.colla_f1 and dn.by_id.colla_f3, 'un personaje sin casa no genera misiones')
  local none = Missions.build(data, {}, { home = true })
  check(none.by_id.colla_mestra and none.by_id.colla_final and none.by_id.colla_mestra.steps[1].target == 'service:escola',
    'sin amigos, la cadena principal usa a los vecinos')
  -- la colla se abre tras 6 misiones del pueblo y pide nivel 2
  local sx = { char_level = 1 }
  local qx = Missions.state(sx)
  check(Missions.lock_reason(none, sx, none.by_id.colla_mestra) == 'capítol', 'la colla está cerrada al principio')
  for _, id in ipairs({ 'escola', 'casa', 'metge', 'mestra', 'cartera', 'carrers' }) do qx.done[id] = true end
  check(Missions.lock_reason(none, sx, none.by_id.colla_mestra) == 'Nv 2' and Missions.status(none, sx, none.by_id.colla_metgessa) == 'locked',
    'con 6 hechas pide nivel 2 y va en orden')
  -- límite de misiones empezadas a la vez
  local fr12 = crew(12)
  local d12 = Missions.build(data, fr12, { home = true })
  local s12 = { char_level = 9 }
  for _, m in ipairs(d12.by_chapter.poble.missions) do Missions.state(s12).done[m.id] = true end
  local opened = {}
  for _, m in ipairs(d12.order) do if Missions.status(d12, s12, m) == 'open' then opened[#opened + 1] = m.id end end
  for i = 1, Missions.MAX_STARTED do check(Missions.can_start(d12, s12, opened[i]), 'puedo empezar la misión ' .. i) ; Missions.activate(d12, s12, opened[i]) end
  check(not Missions.can_start(d12, s12, opened[Missions.MAX_STARTED + 1]), 'tope de misiones empezadas a la vez')
  check(Missions.can_start(d12, s12, opened[1]), 'las ya empezadas se pueden retomar')
  s12.quests.done[opened[1]] = true
  check(Missions.can_start(d12, s12, opened[Missions.MAX_STARTED + 1]), 'al acabar una, vuelve a haber hueco')
end

-- ---------------------------------------------------------------- horarios
check(Schedule.place('kid', 9 * 60, 2) == 'school' and Schedule.place('kid', 18 * 60, 2) == 'park', 'infant: escuela y parque')
check(Schedule.place('kid', 9 * 60, 6) == 'home' and Schedule.place('kid', 11 * 60, 6) == 'park', 'fin de semana: sin escuela')
check(Schedule.place('elder', 10 * 60, 1) == 'park' and Schedule.place('elder', 23 * 60, 1) == 'home', 'abuelos')
check(Schedule.place('service', 3 * 60, 1) == 'closed' and Schedule.hidden('closed'), 'servicios cerrados de noche')
check(Schedule.kind_of_friend({ role = 'avia' }) == 'elder' and Schedule.kind_of_friend({ role = 'amic', look = { age = 'kid' } }) == 'kid',
  'tipo de rutina según rol y edad')

-- ---------------------------------------------------------------- A*
local wall = function(x, y) return x >= 0 and y >= 0 and x < 40 and y < 40 and not (x == 20 and y < 35) end
local path, full = AStar.find(wall, 2, 2, 38, 2, 5000)
check(full and path[#path][1] == 38 and path[#path][2] == 2, 'A* rodea el muro')
for i = 2, #path do
  local a, b = path[i - 1], path[i]
  if math.abs(a[1] - b[1]) > 1 or math.abs(a[2] - b[2]) > 1 or not wall(b[1], b[2]) then check(false, 'camino continuo') break end
end
local part, ok2 = AStar.find(wall, 2, 2, 38, 2, 50)
check(not ok2 and #part > 1, 'con poco presupuesto: camino parcial hacia el destino')
local corner = function(x, y) return x >= 0 and y >= 0 and x < 3 and y < 3 and not (x == 1 and y == 0) and not (x == 0 and y == 1) end
local _, okc = AStar.find(corner, 0, 0, 1, 1, 100)
check(not okc, 'no corta esquinas en diagonal')

-- ---------------------------------------------------------------- calles y plazas
local sd = json.decode(read('data/streets.json'))
local an = nil
for _, ar in ipairs(sd.areas or {}) do if ar.n and ar.n ~= '' then an = ar.n; break end end
local a = an and Streets.area(an)
check(a ~= nil, 'una plaça o parc amb nom als dades (' .. tostring(an) .. ')')
local ix, iy                                       -- un punt de dins (pot tenir forma de L)
for y = a.box[2], a.box[4], 4 do
  for x = a.box[1], a.box[3], 4 do
    if not ix and Streets.contains(a, x, y) then ix, iy = x, y end
  end
end
check(ix and Streets.name_at(ix, iy) == an, 'dins de l\'àrea, el seu nom')
local sn = nil
for _, ln in ipairs(sd.lines or {}) do if ln.n and ln.n:find('^Carrer') then sn = ln.n; break end end
local cm = sn and Streets.street(sn)
check(cm and Streets.name_at(cm.cx, cm.cy, 40) == sn, 'al costat d\'un carrer, el seu nom (' .. tostring(sn) .. ')')
local tr
tr = Streets.tracker(function(n) tr.got = n end)
for _ = 1, 8 do Streets.track(tr, 0.25, cm.cx, cm.cy) end
check(tr.got == sn, 'el cartell surt al cap d\'una estona al carrer nou')
check(not RODA or #Streets._data().recycling >= 20, 'puntos de reciclaje de OSM')

-- ---------------------------------------------------------------- reciclar
local g = Recycle.new({}, function() return 0.5 end)
for _ = 1, Recycle.ROUNDS do
  local want = Recycle.bin_of(g.items[g.i][2])
  g.sel = want; g:update(1 / 60, { pressed = { confirm = true } })
end
check(g.state == 'end' and g.right == Recycle.ROUNDS, 'cada residuo a su contenedor: 8/8')
local g2 = Recycle.new({}, function() return 0.5 end)
local it = g2.items[1]
local wrong = Recycle.bin_of(it[2]) % #Recycle.BINS + 1
g2.sel = wrong; g2:update(1 / 60, { pressed = { confirm = true } })
check(g2.msg and not g2.msg[2] and g2.msg[1]:find(it[1], 1, true), 'si te equivocas, explica dónde va')

print(fails == 0 and 'TODAS LAS PRUEBAS DE PERFILES/MISIONES/HORARIOS OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
