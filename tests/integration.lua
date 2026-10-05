-- Escenario de integración (love . --test --mute). Se ejecuta dentro del juego como corrutina:
-- camina con el buscador de caminos, habla, completa misiones, entra en la cueva, combate,
-- abre el cofre, guarda y recupera. Sale con código 1 si alguna comprobación falla.
return function(api)
  local scene, state, player = api.scene, api.state, api.player
  api.wait(5)
  local function npc(name)
    for _, n in ipairs(scene().npcs) do if n.name == name then return n end end
  end
  local function talk(name)
    local n = npc(name)
    if not n then api.check(false, 'NPC ' .. name .. ' existe'); return false end
    local ok
    for _ = 1, 3 do
      ok = api.walk_next_to(n.body.x, n.body.y)
      local b = player().body
      if ok and math.abs(n.body.x - b.x) + math.abs(n.body.y - b.y) <= 20 then break end
    end
    api.check(ok, 'llegar junto a ' .. name)
    api.face(n.body.x, n.body.y)
    api.press('confirm')
    api.wait(2)
    local d = scene().dialogue
    local want = api.game_dialogue(n.props.dialogue)
    local opened = d.open and d.name == want
    api.check(opened, 'se abre el diálogo de ' .. name .. ' (' .. tostring(d.name) .. ')')
    return opened
  end

  -- inicio sin casa configurada: spawn público
  local sp = scene().map:object('spawn', 'spawn_public_centre')
  api.check(math.abs(player().body.x - sp.x) < 1 and math.abs(player().body.y - sp.y) < 1,
    'sin casa configurada se aparece en spawn_public_centre')

  -- T9: el diálogo no mueve al personaje
  if talk('npc_postie') then
    local x0, y0 = player().body.x, player().body.y
    api.wait(1)
    require('src.input').hold('right', true)
    api.wait(30)
    require('src.input').release_all()
    api.check(player().body.x == x0 and player().body.y == y0, 'durante el diálogo el jugador no se mueve')
    api.check(api.talk_through(), 'el diálogo se cierra')
  end
  api.check(state().flags.postal_taken and (state().inventory.postcard or 0) == 1, 'misión postal: recibida')

  -- quadern
  if talk('npc_baker') then api.talk_through() end
  api.check(state().flags.has_notebook == true, 'quadern recibido')

  -- trigger: entrar y salir de la zona de Sant Bartomeu no sella dos veces
  local zone
  for _, t in ipairs(scene().triggers) do if t.obj.name == 'zone_sant_bartomeu' then zone = t end end
  local visits_before = 0
  for _ in pairs(state().visited) do visits_before = visits_before + 1 end
  local stamps = 0
  local hud = scene().hud
  local orig = hud.toast
  hud.toast = function(self, text, d)
    if text:find('Segell') then stamps = stamps + 1 end
    return orig(self, text, d)
  end
  for _ = 1, 2 do
    api.walk_to(function(x, y) return x == math.floor((zone.rect.x + 40) / 16) and y == math.floor((zone.rect.y + 40) / 16) end)
    api.walk_to(function(x, y) return y > math.floor((zone.rect.y + zone.rect.h) / 16) + 2 end)
  end
  api.check(stamps <= 1, 'el trigger de lugar no se repite (sellos: ' .. stamps .. ')')
  api.check(state().visited.sant_bartomeu == true, 'Sant Bartomeu sellado')

  -- recorrido: entrega de la postal en el Roc (pasa por la AP-7 y la costa)
  if talk('npc_fisher') then api.talk_through() end
  api.check(state().flags.postal_done == true and not state().inventory.postcard, 'misión postal: entregada')
  local roc = scene().map:object('poi', 'roc_sant_gaieta')
  api.walk_to(function(x, y) return x == math.floor(roc.x / 16) and y == math.floor(roc.y / 16) end)
  api.check(state().visited.roc_sant_gaieta == true, 'Roc sellado al llegar a su puerta')

  -- agente forestal: espada y escudo
  if talk('npc_ranger') then api.talk_through() end
  api.check(state().equipment.weapon == 'sword_wood' and state().equipment.shield == 'shield_wood',
    'equipo inicial: espasa de fusta + escut')

  -- el senglar de la pedrera ataca: combatir en el exterior
  local function fight(e)
    local guard = 0
    local sc0 = scene()
    while e.state ~= 'dead' and guard < 1200 and scene() == sc0 do
      local b = player().body
      local d = math.sqrt((e.body.x - b.x) ^ 2 + (e.body.y - b.y) ^ 2)
      if d > 20 then
        api.walk_next_to(e.body.x, e.body.y)
      else
        api.face(e.body.x, e.body.y)
        api.press('attack')
        api.wait(18)
      end
      guard = guard + 1
      if state().hp <= 1 then state().hp = state().max_hp end -- el test no evalúa la dificultad
    end
    api.check(e.state == 'dead', 'enemigo ' .. e.name .. ' derrotado' .. (e.state == 'dead' and '' or
      string.format(' (en %d,%d; jugador en %d,%d; %s)', math.floor(e.body.x / 16), math.floor(e.body.y / 16),
        math.floor(player().body.x / 16), math.floor(player().body.y / 16), scene() == sc0 and 'misma escena' or 'otra escena')))
  end
  -- (la fauna salvatge apareix a l'atzar i fuig o persegueix pel bosc: la prova tests/fauna_flow.lua)
  for _, e in ipairs(scene().enemies) do if not e.fauna then fight(e) end end

  -- entrar a la cueva
  local door
  for _, d in ipairs(scene().doors) do if d.obj.name == 'door_pedrera_elies' then door = d end end
  local entered_by_walk = scene().id == 'overworld'
  if entered_by_walk then
    api.walk_to(function(x, y) return x == math.floor((door.rect.x + 8) / 16) and y == math.floor((door.rect.y + 8) / 16) end)
    api.wait(40)
  end
  api.check(scene().id == 'cova_pedrera', 'entrada a la cova_pedrera')
  local sp2 = scene().map:object('spawn', 'spawn_entrance')
  api.check(not entered_by_walk or math.abs(player().body.x - sp2.x) < 2 and math.abs(player().body.y - sp2.y) < 2,
    string.format('aparece en spawn_entrance (%.1f,%.1f vs %.1f,%.1f)', player().body.x, player().body.y, sp2.x, sp2.y))
  api.wait(30)
  api.check(scene().id == 'cova_pedrera', 'la puerta de salida no se dispara al aparecer')

  -- palanca → reja 1
  local lever = scene().levers[1]
  api.walk_next_to(lever.rect.x + 8, lever.rect.y + 4)
  api.face(lever.rect.x + 8, lever.rect.y + 4)
  api.press('confirm')
  api.check(state().flags.cova_lever == true, 'palanca activada')

  -- combate: acercarse a cada enemigo de la sala y atacar
  local hp0 = state().hp
  for _, e in ipairs(scene().enemies) do fight(e) end
  api.check(scene().sstate.defeated.boar_1 and scene().sstate.defeated.bat_1, 'derrotas persistidas en la escena')
  local gate2
  for _, g in ipairs(scene().gates) do if g.obj.name == 'gate2' then gate2 = g end end
  api.check(scene():gate_open(gate2), 'la reja 2 se abre al vaciar la sala')

  -- cofre: Espasa de Berà (cambio de equipo sin duplicar)
  local chest = scene().chests[1]
  api.walk_next_to(chest.rect.x + 8, chest.rect.y + 8)
  api.face(chest.rect.x + 8, chest.rect.y + 8)
  api.press('confirm')
  api.talk_through()
  api.check(state().equipment.weapon == 'sword_bera', 'Espasa de Berà equipada')
  api.check((state().inventory.sword_bera or 0) == 1, 'sin duplicados de la espada')
  api.press('confirm')
  api.talk_through()
  api.check((state().inventory.sword_bera or 0) == 1, 'el cofre abierto no vuelve a dar la espada')

  -- guardar, corromper, recuperar
  local Save = require('src.save')
  local ok = Save.write(state())
  api.check(ok, 'guardado escrito')
  local st2 = Save.read()
  api.check(st2 and st2.scene == 'cova_pedrera' and st2.scene_state.cova_pedrera.chests.cova_chest == true,
    'el guardado conserva escena y cofre')
  Save.write(state()) -- crea respaldo
  api.mem()['save.json'] = '{ roto'
  local st3, src = Save.read()
  api.check(st3 ~= nil and src == 'backup', 'guardado corrupto → se recupera el respaldo')

  -- salir de la cueva
  local exit
  for _, d in ipairs(scene().doors) do exit = d end
  api.walk_to(function(x, y) return x == math.floor((exit.rect.x + 8) / 16) and y == math.floor((exit.rect.y + 8) / 16) end)
  api.wait(40)
  api.check(scene().id == 'overworld', 'vuelta al exterior')
  api.wait(60)
  api.check(scene().id == 'overworld', 'la puerta de la cueva exige salir antes de reactivarse')
  api.check(api.player().body.level == 0, 'nivel 0 al volver')
end
