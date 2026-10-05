-- Perfils, editor d'amics i família, missions «Coneix el teu poble», horaris i semàfors dins del joc
-- (love . --test=tests/profile_flow.lua --mute [--shots]). Els perfils són en memòria (src/devtools.lua).
return function(api)
  local Input = require('src.input')
  local Profile = require('src.profile')
  local Missions = require('src.systems.missions')
  local Town = require('src.systems.town')
  local Streets = require('src.systems.streets')
  local g = api.scene().game
  g.dev.turbo = 1
  local shots = false
  for _, a in ipairs(arg or {}) do if a == '--shots' then shots = true end end
  local function shot(name)
    if not shots then return end
    love.graphics.captureScreenshot(function(d) d:encode('png', name .. '.png') end)
    api.wait(2)
  end
  local function ui() return g.menu end
  local function press(k) ui():update(1 / 60, { [k] = true }, {}); api.wait(1) end

  -- ------------------------------------------------ perfil nou: nom, avatar i casa
  g:to_title()
  g:open_profiles()
  api.wait(2)
  api.check(#Profile.list() == 5 and not Profile.list()[1].exists, '5 ranures buides')
  shot('pf_slots')
  press('confirm')                                   -- ranura 1 → nom
  api.check(ui():top().kind == 'name', 'crear: primer el nom')
  ui():textinput('Nena'); api.wait(1)
  ui():keypressed('return'); api.wait(2)
  api.check(Profile.read(1) and Profile.read(1).name == 'Nena', 'el perfil es desa amb el nom (user_profile.json)')
  local e = ui():top()
  api.check(e.kind == 'editor' and e.mode == 'player', 'després, l\'editor de l\'avatar')
  -- canviar pell, cabell i roba
  for _ = 1, 2 do press('down') end                  -- Pell
  press('right'); press('right'); press('right')
  press('down'); press('right')                      -- Cabell
  for _ = 1, 3 do press('down') end                  -- Roba
  press('right')
  api.wait(10)
  shot('pf_editor')
  local look = e.look
  api.check(look.skin == 5 and look.hair == 'long' and look.outfit == 'sweater', 'l\'editor canvia pell, cabell i roba (' ..
    look.skin .. ', ' .. look.hair .. ', ' .. look.outfit .. ')')
  local rows = ui():rows(e)
  e.sel = #rows - 1                                  -- Desar
  press('confirm')
  api.check(Profile.read(1).avatar.hair == 'long', 'avatar desat')
  -- casa: el selector de mapa
  local pk = ui():top()
  api.check(pk.kind == 'picker', 'tria de casa al mapa')
  shot('pf_picker_far')
  local map = g:get_map('overworld')
  local sp = map:object('spawn', g.world.start_spawn)
  local UI = require('src.ui.profiles')
  local door
  for r = 2, 40, 2 do
    door = UI.find_door(map, g.renderer.light_kind, math.floor(sp.x / 16), math.floor(sp.y / 16) + r, 6)
    if door then
      local ok = require('src.home').resolve({ configured = true, tile_x = door[1], tile_y = door[2] + 1 },
        function(s) return g:get_map(s) end, g.world.start_spawn)
      if ok then break end
      door = nil
    end
  end
  api.check(door ~= nil, 'hi ha portes de cases a prop del centre')
  press('confirm')                                   -- apropar-s'hi
  pk.cx, pk.cy = door[1], door[2]
  api.wait(5)
  shot('pf_picker_zoom')
  press('confirm')
  local p = Profile.read(1)
  api.check(p.home and p.home.door_x == door[1] and p.home.tile_y == door[2] + 1, 'casa desada a user_profile.json (' ..
    tostring(p.home and p.home.street) .. ')')
  api.check(ui():top().kind == 'slot_menu', 'torna al menú del perfil')

  -- ------------------------------------------------ amics i família: una àvia
  local s = ui():top()
  ui():push('friends', { slot = 1, profile = s.profile })
  local fr = ui():top()
  fr.sel = 1                                          -- + Afegir
  press('confirm')
  local ch = ui():top()
  api.check(ch.kind == 'choice', 'triar qui és')
  ch.sel = 3                                          -- Àvia
  press('confirm')
  local fe = ui():top()
  api.check(fe.kind == 'editor' and fe.mode == 'friend' and fe.target.role == 'avia', 'editor del personatge (àvia)')
  api.check(fe.look.age == 'elder' and fe.look.acc.glasses, 'l\'àvia comença gran, amb cabells blancs i ulleres')
  fe.target.name = 'Iaia Rosa'
  -- casa de l'àvia: una altra porta
  local door2
  for r = 6, 60, 3 do
    local d2 = UI.find_door(map, g.renderer.light_kind, door[1] + r, door[2], 4)
    if d2 and (d2[1] ~= door[1] or d2[2] ~= door[2]) and require('src.home').resolve({ configured = true, tile_x = d2[1], tile_y = d2[2] + 1 },
        function(sc) return g:get_map(sc) end, g.world.start_spawn) then door2 = d2; break end
  end
  ui():pick_place(nil, 'On viu?', function(h) fe.target.home = h end)
  local pk2 = ui():top()
  pk2.zoom, pk2.cx, pk2.cy = true, door2[1], door2[2]
  press('confirm')
  fe.target.interior.cat = true
  fe.target.interior.floor = 'carpet'
  shot('pf_friend_editor')
  fe.sel = #ui():rows(fe) - 2                         -- Desar (després: Esborrar, Cancel·lar)
  press('confirm')
  p = Profile.read(1)
  api.check(#p.friends == 1 and p.friends[1].name == 'Iaia Rosa' and p.friends[1].home and p.friends[1].interior.cat,
    'l\'àvia es desa amb nom, casa i interior')

  -- ------------------------------------------------ jugar amb el perfil
  ui():play(1, p, 'new')
  api.wait(40)
  local w = api.scene()
  local st = api.state()
  api.check(st.player_name == 'Nena' and st.skin == 'avatar', 'partida nova amb el nom i l\'avatar del perfil')
  api.check(g.sprites.player.sheet:getWidth() == 96, 'l\'avatar és una fulla paperdoll generada')
  api.check(g.home and g.home.tx == door[1] and g.home.ty == door[2] + 1, 'comença a casa seva')
  local avia
  for _, n in ipairs(w.npcs) do if n.props.friend == p.friends[1].id then avia = n end end
  api.check(avia ~= nil and avia.routine.kind == 'elder', 'l\'àvia és al món amb horari de gran')
  shot('pf_home_start')

  -- ------------------------------------------------ missions: escola
  local defs = Town.defs(g)
  api.check(defs.by_id['visit_' .. p.friends[1].id] and defs.by_id['errand_' .. p.friends[1].id],
    'missions de família generades per a l\'àvia (visita i encàrrec)')
  local q = Missions.state(st)
  api.check(q.active == 'escola', 'primera missió activa: l\'escola')
  api.wait(20)
  local tgt = Town.target(w)
  api.check(tgt and tgt.label == 'Escola Salvador Espriu', 'la brúixola apunta a l\'escola')
  shot('pf_compass')
  api.player().body.x, api.player().body.y = tgt.x, tgt.y
  api.wait(30)
  api.check(q.done.escola and q.active == 'casa', 'en arribar a l\'escola, feta; ara tornar a casa')
  local sa = Streets.area('Escola Salvador Espriu')
  api.check(math.sqrt((tgt.x - sa.cx) ^ 2 + (tgt.y - sa.cy) ^ 2) < 160, 'el punt de l\'escola és al costat del recinte')
  api.talk_through()                                 -- presentació de la missió següent
  api.wait(20)
  local home_t = Town.target(w)
  api.check(home_t and home_t.label == 'Casa', 'la brúixola apunta a casa')
  if home_t then api.player().body.x, api.player().body.y = home_t.x, home_t.y end
  api.wait(30)
  api.check(q.done.casa and q.active == 'metge', 'a casa: feta; ara el metge')
  api.talk_through()
  -- metge
  local function service(id) for _, n in ipairs(api.scene().npcs) do if n.props.service_id == id then return n end end end
  local function talk(n)
    api.teleport(math.floor(n.body.x / 16), math.floor(n.body.y / 16) + 1)
    api.player().facing = 'up'
    api.wait(2); api.press('confirm'); api.wait(4)
  end
  talk(service('metge'))
  api.check(q.done.metge and q.active == 'mestra', 'parlar amb la metgessa completa la missió; ara la mestra')
  if g.menu then g:close_menu() end
  api.wait(3); api.talk_through()
  Missions.activate(defs, st, 'objecte_perdut', Town.hooks(w))   -- (la resta del capítol, en un altre ordre)
  api.wait(3); api.talk_through()
  api.check((st.inventory.clauer or 0) == 1, 'la missió dona el clauer perdut')
  talk(service('policia'))
  api.talk_through()
  api.check(q.done.objecte_perdut and not st.inventory.clauer, 'el clauer es lliura a la Policia Local')
  if g.menu then g:close_menu() end

  -- ------------------------------------------------ diari
  g:open_journal()
  api.wait(5)
  shot('pf_journal')
  local jr = g.menu
  local found = false
  for _, r in ipairs(jr.rows) do if r.m and r.m.id == 'visit_' .. p.friends[1].id and (r.status == 'open' or r.status == 'active') then found = true end end
  api.check(found, 'al diari, «Visita Iaia Rosa» oberta (capítol 2 desbloquejat)')
  g:close_menu()

  -- ------------------------------------------------ pas de vianants
  Missions.activate(defs, st, 'passos', Town.hooks(w))
  api.wait(2); api.talk_through()
  local cw
  for _, c in ipairs(w.traffic.crosswalks) do if c.ang and not c.light and (c.level or 0) == 0 then cw = c; break end end
  w.traffic.cars = {}
  local nx, ny = -math.sin(cw.ang), math.cos(cw.ang)
  local b = api.player().body
  b.x, b.y = cw.x - nx * (cw.r + 8), cw.y - ny * (cw.r + 8)
  api.wait(3)
  for _ = 1, 40 do b.x, b.y = b.x + nx * 1.5, b.y + ny * 1.5; api.wait(1) end
  api.wait(3)
  api.check((q.count.passos or 0) == 1, 'creuar un carrer pel pas de vianants compta (1/3)')
  b.x, b.y = cw.x - nx * (cw.r + 30), cw.y - ny * (cw.r + 30)
  api.wait(3)

  -- ------------------------------------------------ semàfor: en vermell no compta
  Missions.activate(defs, st, 'semafor', Town.hooks(w))
  api.wait(2); api.talk_through()
  local lc
  for _, c in ipairs(w.traffic.crosswalks) do if c.light then lc = c; break end end
  api.check(lc ~= nil, 'hi ha passos amb semàfor')
  local Traffic = require('src.systems.traffic')
  local function cross(want_green)
    local t = 0
    while select(2, Traffic.light_state(lc, w.traffic.clock)) ~= want_green and t < 60 * 30 do api.wait(1); t = t + 1 end
    local lx, ly = -math.sin(lc.ang), math.cos(lc.ang)
    b.x, b.y = lc.x - lx * (lc.r + 8), lc.y - ly * (lc.r + 8)
    api.wait(2)
    for _ = 1, 30 do b.x, b.y = b.x + lx * 2, b.y + ly * 2; api.wait(1) end
    api.wait(3)
    b.x, b.y = lc.x - lx * (lc.r + 40), lc.y - ly * (lc.r + 40)
    api.wait(2)
  end
  cross(false)
  api.check((q.count.semafor or 0) == 0, 'creuar en vermell no compta')
  cross(true)
  api.check((q.count.semafor or 0) == 1, 'creuar en verd compta (1/2)')
  shot('pf_light')

  -- ------------------------------------------------ reciclatge
  Missions.activate(defs, st, 'reciclar', Town.hooks(w))
  api.wait(2); api.talk_through()
  -- un contenidor amb lloc per posar-se davant (al sud, a nivell de carrer)
  local Collision = require('src.world.collision')
  local rp = Town.recycling(w)[1]
  for _, c in ipairs(Town.recycling(w)) do
    local ok = true
    for _, dx in ipairs({ -7, 7 }) do   -- tot l'ample del cos, no només el centre
      for _, dy in ipairs({ 8, 14, 22 }) do
        if not Collision.walk_at(w.map:cell(math.floor((c.x + dx) / 16), math.floor((c.y + dy) / 16)), 0) then ok = false end
      end
    end
    if ok then rp = c; break end
  end
  api.check(#Town.recycling(w) >= 20, 'punts de reciclatge de l\'OSM al mapa (' .. #Town.recycling(w) .. ')')
  -- es col·loca i prem en el mateix fotograma (un vianant que passi el pot empènyer abans)
  b = api.player().body
  for _ = 1, 3 do
    if g.minigame then break end
    b.x, b.y = rp.x, rp.y + 14
    api.player().facing = 'up'
    api.press('confirm'); api.wait(3)
  end
  local mg = g.minigame and g.minigame.mg
  api.check(mg and g.minigame.id == 'recycle', 'els contenidors obren el joc de reciclar')
  shot('pf_recycle')
  local R = require('src.minigames.recycle')
  for _ = 1, R.ROUNDS do
    local want = R.bin_of(mg.items[mg.i][2])
    mg.sel = want
    Input.press('confirm'); api.wait(2)
  end
  api.wait(40); Input.press('confirm'); api.wait(3)
  api.check(q.done.reciclar, 'separar bé els residus completa la missió')

  -- ------------------------------------------------ l'àvia: horari, salutació, casa
  st.clock = 10 * 60                                   -- dimarts 10:00: al parc
  api.wait(70)
  api.check(avia.routine.place == 'park' and not avia.hidden, 'a les 10 l\'àvia és al parc (' .. tostring(avia.routine.place) .. ')')
  b.x, b.y = avia.body.x + 24, avia.body.y
  api.wait(5)
  api.check(avia.bubble ~= nil and avia.bubble.text:find('Nena'), 'l\'àvia saluda pel nom (' .. tostring(avia.bubble and avia.bubble.text) .. ')')
  shot('pf_greet')
  -- reacció a un vehicle massa ràpid
  avia.scared_t = nil
  st.vehicles.scooter = true; st.char_level = 4; st.vehicle = 'scooter'
  Input.press('bike'); api.wait(3)
  b.x, b.y = avia.body.x - 20, avia.body.y + 12
  api.player().vehicle.speed = 170                   -- passa pel costat molt de pressa
  w.town.last_speed = 170
  Town.reactions(w, avia, 1 / 60)
  api.check(avia.hop ~= nil or (st.scares or 0) > 0, 'passar molt de pressa a prop de la gent els espanta')
  Input.press('bike'); api.wait(3)
  -- a les 14 h, a casa: entrar-hi per la porta
  st.clock = 14 * 60
  Missions.activate(defs, st, 'visit_' .. p.friends[1].id, Town.hooks(w))
  api.wait(2); api.talk_through()
  local h = p.friends[1].home
  b.x, b.y = h.door_x * 16 + 8, (h.door_y + 1) * 16 + 6
  api.player().facing = 'up'
  api.wait(2); api.press('confirm'); api.wait(40)
  w = api.scene()
  api.check(w.id == 'friend_' .. p.friends[1].id, 'la porta de l\'àvia porta a casa seva (' .. w.id .. ')')
  local inside, cat
  for _, n in ipairs(w.npcs) do
    if n.props.friend then inside = n end
    if n.props.sprite == 'npc_cat_orange' then cat = n end
  end
  api.check(inside ~= nil and cat ~= nil, 'a dins hi ha l\'àvia i el seu gat')
  shot('pf_friend_home')
  talk(inside)
  api.check(q.done['visit_' .. p.friends[1].id], 'parlar amb l\'àvia completa «Visita Iaia Rosa»')
  api.talk_through()

  -- ------------------------------------------------ desar i continuar el perfil
  g:save_game(false)
  g:to_title()
  local l = Profile.list()
  api.check(l[1].exists and l[1].has_save and l[1].name == 'Nena', 'el títol mostra el perfil amb partida desada')
  g:start_profile(1, Profile.read(1), 'continue')
  api.wait(40)
  api.check(api.state().player_name == 'Nena' and Missions.state(api.state()).done.escola, 'continuar recupera la partida del perfil')
  api.check(api.scene().id == 'friend_' .. p.friends[1].id, 'i torna a casa de l\'àvia, on era')
  -- la casa del perfil: una de les 10 distribucions (src/world/house_layouts.lua), triada per l'adreça
  -- (amb el plànol de casa al directori de dades, la casa del protagonista és la del plànol: casa_plano_flow)
  if g.house and g.house.entry == 'casa_perfil' then
    api.check(g.house.layout ~= nil,
      'la casa del perfil té interior propi (distribució ' .. tostring(g.house and g.house.layout) .. ')')
    g.scene_manager:change('overworld', nil, { x = g.home.x, y = g.home.y, level = 0 })
    api.wait(40)
    w = api.scene()
    local hd = w.house_door
    api.check(hd ~= nil, 'es troba la porta de casa')
    if hd then
      api.player().body.x, api.player().body.y = hd[1] * 16 + 8, (hd[2] + 1) * 16 + 6
      api.player().facing = 'up'
      api.wait(2); api.press('confirm'); api.wait(40)
      api.check(api.scene().id == 'casa_perfil', 'per la porta s\'entra a casa (' .. api.scene().id .. ')')
      shot('pf_casa_perfil')
    end
  end
end
