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


  local n = npc('npc_fisher')
  local last, still, dumped = nil, 0, false
  api.on_frame = function()
    local b = player().body
    local p = b.x * 100000 + b.y
    if last and p == last then still = still + 1 else still = 0 end
    last = p
    if still == 150 and not dumped then
      dumped = true
      print('[probe] stuck at', b.x, b.y, b.level, 'hour', tostring(api.state().clock or api.state().time))
      scene():rebuild_blockers()
      for _, r in ipairs(scene().blockers) do
        if math.abs(r.x + r.w/2 - b.x) < 48 and math.abs(r.y + r.h/2 - b.y) < 48 then print('[probe] blocker', r.x, r.y, r.w, r.h) end
      end
      local C = require('src.world.collision')
      for ty = math.floor(b.y/16)-1, math.floor(b.y/16)+1 do
        local row = {}
        for tx = math.floor(b.x/16)-2, math.floor(b.x/16)+3 do row[#row+1] = tostring(scene().map:cell(tx, ty)) end
        print('[probe] cells', ty, table.concat(row, ' '))
      end
      
    end
  end
  local gx, gy = math.floor(n.body.x / 16), math.floor(n.body.y / 16)
  api.walk_to(function(tx, ty) return math.abs(tx - gx) + math.abs(ty - gy) == 1 end)
end
