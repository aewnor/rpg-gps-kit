-- Cova de Roda i el Drac (love . --test=tests/cave_flow.lua --mute): boca a les coordenades reals tancada sense
-- llanterna → tres nivells foscos amb torxes que baixen per escales → Bastó màgic i Cristall del Drac → màgia
-- amb el bastó → el cau del cim (cristall i nivell 5) → vèncer el drac.
return function(api)
  local game = api.scene().game
  local st = game.state
  game.dev.turbo = 1
  api.wait(5)
  local function door_named(name)
    for _, d in ipairs(api.scene().doors) do if d.obj.name == name then return d end end
  end
  local function walk_into(d)
    local gx, gy = math.floor(d.rect.x / 16), math.floor(d.rect.y / 16)
    return api.walk_to(function(x, y) return x == gx and y == gy end, 60)
  end
  local function calm()   -- els enemics no molesten mentre es camina (els combats es proven a part)
    for _, e in ipairs(api.scene().enemies) do if not e.kind.boss then e.state = 'dead' end end
    api.player().invuln = 9999
  end
  local function shot(name)
    love.graphics.captureScreenshot(function(d) d:encode('png', 'cave_' .. name .. '.png') end)
    api.wait(3)
  end
  -- boca de la cova
  local d = door_named('door_cova_roda')
  api.check(d ~= nil, 'la boca de la Cova de Roda és al mapa')
  if not d then return end
  local tx, ty = math.floor(d.rect.x / 16), math.floor(d.rect.y / 16)
  api.check(math.abs(tx - 320) <= 3 and math.abs(ty - 851) <= 3, 'a les coordenades reals (casella ' .. tx .. ',' .. ty .. ' ≈ 320,851)')
  if api.scene().traffic then api.scene().traffic.cars = {} end
  api.teleport(tx, ty + 2)
  api.wait(30)
  shot('mouth')
  st.inventory.llanterna = nil
  walk_into(d)
  api.wait(40)
  api.check(api.scene().id == 'overworld', 'sense llanterna no s\'hi pot entrar')
  st.inventory.llanterna = 1
  api.teleport(tx, ty + 2); api.wait(10)
  walk_into(d)
  api.wait(90)
  api.check(api.scene().id == 'cova_roda_1', 'amb la llanterna s\'entra al nivell 1 (' .. api.scene().id .. ')')
  api.check(api.scene().def.dark and #api.scene().torches >= 4, 'fosc i amb torxes (' .. #api.scene().torches .. ')')
  api.check(#api.scene().enemies >= 3, 'hi ha enemics (' .. #api.scene().enemies .. ')')
  api.wait(20); shot('level1')
  -- baixar els tres nivells
  for lvl = 1, 2 do
    calm()
    local dd = door_named('door_down')
    api.check(dd ~= nil and walk_into(dd), 'arriba a l\'escala del nivell ' .. lvl)
    api.wait(90)
    api.check(api.scene().id == 'cova_roda_' .. (lvl + 1), 'baixa al nivell ' .. (lvl + 1))
  end
  calm()
  -- cofres del fons
  for _, c in ipairs(api.scene().chests) do
    api.walk_next_to(c.rect.x + 8, c.rect.y + 8)
    api.face(c.rect.x + 8, c.rect.y + 8)
    api.wait(2)
    api.scene():interact()
    api.wait(5)
    api.talk_through()
  end
  api.check((st.inventory.baston_magic or 0) > 0, 'troba el Bastó màgic')
  api.check((st.inventory.cristall_drac or 0) > 0, 'troba el Cristall del Drac')
  shot('level3')
  -- màgia amb el bastó
  local Rpg = require('src.systems.rpg')
  while st.char_level < 5 do Rpg.add_xp(st, st.next_xp) end
  api.check(Rpg.equip(st, game.items, 'baston_magic'), 'equipa el bastó')
  st.spell = 'foc'
  local mp0 = st.mp
  api.press('spell')
  api.wait(2)
  api.check(st.mp == mp0 - 4 and #api.scene().shots.list == 1, 'la tecla V llança una bola de foc')
  api.press('spell_next')
  api.check(st.spell == 'rafaga', 'E canvia a la ràfaga de vent')
  -- tornar amunt per les escales
  for lvl = 3, 2, -1 do
    calm()
    walk_into(door_named('door_up'))
    api.wait(90)
    api.check(api.scene().id == 'cova_roda_' .. (lvl - 1), 'puja al nivell ' .. (lvl - 1))
  end
  calm()
  walk_into(door_named('door_up'))
  api.wait(90)
  api.check(api.scene().id == 'overworld', 'surt de la cova')
  -- el cau del drac al cim
  local ld = door_named('door_cau_drac')
  api.check(ld ~= nil, 'la roca segellada és al cim')
  if not ld then return end
  local lx, ly = math.floor(ld.rect.x / 16), math.floor(ld.rect.y / 16)
  api.teleport(lx, ly + 2); api.wait(30)
  shot('summit')
  walk_into(ld)
  api.wait(90)
  api.check(api.scene().id == 'cau_drac', 'amb el cristall i nivell 5 s\'entra al cau del drac')
  local boss = api.scene().boss
  api.check(boss ~= nil and boss.state == 'sleep', 'el drac dorm al cau')
  if not boss then return end
  api.player().invuln = 0
  api.teleport(math.floor(boss.body.x / 16), math.floor(boss.body.y / 16) + 4)
  api.player().facing = 'up'
  st.spell = 'foc'
  local t = 0
  local hurt_before = st.hp
  st.hp, st.max_hp = 24, 24
  local fired = false
  api.on_frame = nil
  for i = 1, 60 * 40 do
    st.mp = st.max_mp
    if i % 20 == 0 then
      -- apunta cap al drac
      local b, pb = boss.body, api.player().body
      api.face(b.x, b.y - 10)
      api.press('spell')
    else api.wait(1) end
    if #api.scene().shots.list > 0 then for _, s in ipairs(api.scene().shots.list) do if s.owner == 'enemy' then fired = true end end end
    if i == 300 then shot('boss') end
    st.hp = math.max(st.hp, 10)
    if boss.state == 'dead' then break end
  end
  api.check(fired, 'el drac llança foc')
  api.check(boss.state == 'dead' and game.state.flags.drac_vencut, 'el drac és vençut amb màgia')
  api.check((st.inventory.corona_drac or 0) > 0, 'premi: la Corona del Drac')
  api.talk_through()
end
