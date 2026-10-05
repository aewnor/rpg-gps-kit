-- Recorrido de los sistemas RPG dentro del juego: servicios, tren, cursa, vehículo, mazmorra, cofres y Olaf.
--   love . --test=tests/rpg_flow.lua --mute
return function(api)
  local Input = require('src.input')
  local sc = api.scene()
  local g = sc.game
  local st = api.state()

  local function service(id)
    for _, n in ipairs(api.scene().npcs) do if n.props.service_id == id then return n end end
  end
  -- ponerse debajo del personaje, mirarlo y hablar
  local function talk(n)
    api.teleport(math.floor(n.body.x / 16), math.floor(n.body.y / 16) + 1)
    api.player().facing = 'up'
    api.wait(2)
    api.press('confirm')
    api.wait(4)
  end
  local function pick(i)   -- elegir la opción i de la lista abierta
    local m = g.menu
    if not (m and m.list and m.list[i]) then return false end
    m.list[i][2]()
    api.wait(3)
    return true
  end

  api.check(sc.olaf ~= nil, 'Olaf acompaña al jugador')
  local n_services = 0
  for _, n in ipairs(sc.npcs) do if n.props.service then n_services = n_services + 1 end end
  api.check(n_services >= 15, 'servicios en el mapa: ' .. n_services)

  -- comprar en el Bonpreu
  st.coins = 50
  talk(service('bonpreu'))
  api.check(g.menu and g.menu.screen == 'list', 'el Bonpreu abre su tienda')
  pick(2)            -- 1 = entrar al súper (passadissos i caixes)
  api.check(st.coins < 50 and (st.inventory.poma or 0) == 1, 'comprar una poma descuenta monedas (' .. st.coins .. ')')

  -- revisión en el CAP
  st.hp = 1
  talk(service('metge'))
  pick(1)
  api.talk_through()
  api.check(st.hp == st.max_hp, 'la revisión médica cura')

  -- gimnàs: fuerza
  st.coins = 40
  talk(service('gimnas'))
  pick(2)            -- 1 = entrar al gimnàs (aparells amb minijocs)
  api.check(st.train.strength == 1 and st.coins == 30, 'entrenar fuerza (+1, 10 monedas)')

  -- Correus: llevar un paquete
  talk(service('correus'))
  pick(1)
  api.talk_through()
  local del = st.missions.delivery
  api.check(del ~= nil and (st.inventory.paquet or 0) == 1, 'Correus da un paquete para ' .. tostring(del and del.label))
  local xp0, lv0 = st.xp, st.char_level
  talk(service(del.to))
  api.talk_through()
  api.check(st.missions.delivery == nil and (st.xp > xp0 or st.char_level > lv0), 'paquete entregado: experiencia')

  -- tren: descubrir dos estaciones y viajar
  local a, b = service('estacio_roda_de_mar'), service('baixador_roc')
  api.teleport(math.floor(a.body.x / 16), math.floor(a.body.y / 16) + 1); api.wait(3)
  api.teleport(math.floor(b.body.x / 16), math.floor(b.body.y / 16) + 1); api.wait(3)
  api.check(st.stations.estacio_roda_de_mar and st.stations.baixador_roc, 'estaciones descubiertas al pasar')
  talk(b)
  api.check(pick(1), 'el tren ofrece destinos')
  api.wait(60)
  local p = api.player().body
  api.check((p.x - a.body.x) ^ 2 + (p.y - a.body.y) ^ 2 < 64 ^ 2, 'el tren lleva a Roda de Mar')

  -- cursa del Poliesportiu
  sc = api.scene()
  talk(service('poliesportiu'))
  pick(2)            -- 1 = entrar (penals i circuit)
  api.talk_through()
  local race = sc.race
  api.check(race ~= nil and race.t > 0, 'empieza una cursa con meta y tiempo')
  if race then
    local c0 = st.coins
    api.player().body.x, api.player().body.y = race.x, race.y
    api.wait(3)
    api.check(sc.race == nil and st.coins > c0, 'llegar a la meta a tiempo da premio')
  end

  -- vehículo: el scooter con su plano y nivel
  st.vehicles.scooter = true
  st.char_level, st.vehicle = 3, 'scooter'
  local n = service('bonpreu')
  api.teleport(math.floor(n.body.x / 16), math.floor(n.body.y / 16) + 2)
  Input.press('bike'); api.wait(3)
  api.check(api.player().vehicle and api.player().vehicle.id == 'scooter', 'subir al scooter (B)')
  local x0 = api.player().body.x
  Input.hold('right', true); api.wait(60); Input.release_all()
  local dx = math.abs(api.player().body.x - x0)
  api.check(dx > 70, string.format('el scooter avanza más que andando (%.0f px en 1 s)', dx))
  Input.press('bike'); api.wait(3)
  api.check(api.player().vehicle == nil, 'bajar del scooter (B)')

  -- mazmorra del Castell (nivel 3) y cofre legendario
  local ow = api.scene()
  local door
  for _, d in ipairs(ow.doors) do if d.obj.props.target_scene == 'masmorra_castell' then door = d end end
  api.check(door ~= nil, 'el Castell de Creixell tiene la puerta de la mazmorra')
  st.char_level = 1
  api.player().body.x, api.player().body.y = door.rect.x + 16, door.rect.y + 8 + 16
  api.wait(5)
  api.player().body.y = door.rect.y + 8; api.wait(10)
  api.check(api.scene() == ow, 'con nivel 1 la mazmorra no se abre')
  api.talk_through()
  st.char_level = 3
  api.player().body.y = door.rect.y + 8 + 20; api.wait(5)
  api.player().body.y = door.rect.y + 8; api.wait(60)
  local dun = api.scene()
  api.check(dun.id == 'masmorra_castell', 'con nivel 3 se entra en la mazmorra')
  api.check(#dun.torches >= 10 and dun.def.dark, 'mazmorra oscura con antorchas')
  local leg
  for _, c in ipairs(dun.chests) do if c.obj.props.tier == 'legend' then leg = c end end
  api.check(leg ~= nil, 'hay un cofre legendario')
  local reixa
  for _, gt in ipairs(dun.gates) do if gt.obj.name == 'reixa_tresor' then reixa = gt end end
  api.check(reixa ~= nil and not dun:gate_open(reixa), 'el cofre legendario está tras una reja cerrada')
  local bl, pla = dun.puzzle.blocks[1], dun.puzzle.plates[1]
  api.check(bl ~= nil and pla ~= nil, 'la sala del tesoro tiene bloque y placa')
  if bl and pla then   -- el bloque ya en la placa (el empuje lo prueban tests/tower_flow.lua y castle_puzzle_flow.lua)
    bl.tx, bl.ty = pla.tx, pla.ty; bl.rect.x, bl.rect.y = pla.tx * 16 + 1, pla.ty * 16 + 1
    api.wait(3)
    api.check(reixa and dun:gate_open(reixa), 'con el bloque en la placa, la reja se abre')
  end
  if leg then
    for _, e in ipairs(dun.enemies) do e.state = 'dead' end
    api.player().body.x, api.player().body.y = leg.rect.x + 8, leg.rect.y + 16 + 8
    api.player().facing = 'up'
    api.wait(2); api.press('confirm'); api.wait(4)
    api.talk_through(); api.wait(10)
    api.check(st.vehicles.cotxe == true, 'el cofre legendario desbloquea el coche')
  end
  api.check(api.scene().olaf ~= nil, 'Olaf también entra en la mazmorra')
end
