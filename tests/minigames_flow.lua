-- Minijuegos dentro de sus POIs: entrar en el Casino, el Gimnàs, el Poliesportiu y el Camp de futbol desde
-- el personaje del servicio, jugar en cada aparato y salir (love . --test=tests/minigames_flow.lua --mute).
-- Con --shots guarda capturas de cada minijuego en el directorio de datos.
return function(api)
  local Input = require('src.input')
  local g = api.scene().game
  local st = api.state()
  local shots = false
  for _, a in ipairs(arg or {}) do if a == '--shots' then shots = true end end
  local function shot(name)
    if not shots then return end
    love.graphics.captureScreenshot(function(d) d:encode('png', name .. '.png') end)
    api.wait(2)
  end
  local function service(id)
    for _, n in ipairs(api.scene().npcs) do if n.props.service_id == id then return n end end
  end
  local function talk(n)
    api.teleport(math.floor(n.body.x / 16), math.floor(n.body.y / 16) + 1)
    api.player().facing = 'up'
    api.wait(2); api.press('confirm'); api.wait(4)
  end
  local function enter(id)
    local ow = api.scene()
    talk(service(id))
    local m = g.menu
    api.check(m and m.list and m.list[1][1]:find('Entrar'), id .. ': el menú ofrece entrar')
    m.list[1][2]()
    api.wait(40)
    api.check(api.scene().id == 'poi_' .. id, id .. ': dentro del interior (' .. api.scene().id .. ')')
    return ow
  end
  -- ponerse delante (debajo) de un aparato y usarlo
  local function use(game_id, stat)
    local sc = api.scene()
    for _, a in ipairs(sc.arcades) do
      if a.obj.props.game == game_id and (not stat or a.obj.props.stat == stat) then
        local b = api.player().body
        b.x, b.y = a.rect.x + 8, a.rect.y + 16 + 8
        api.player().facing = 'up'
        api.wait(2); api.press('confirm'); api.wait(2)
        return g.minigame and g.minigame.mg
      end
    end
  end
  local function until_(fn, max) local t = 0; while not fn() and t < (max or 3000) do api.wait(1); t = t + 1 end end
  local function leave(ow)
    local sc = api.scene()
    for _, d in ipairs(sc.doors) do
      api.player().body.x, api.player().body.y = d.rect.x + 8, d.rect.y - 8
      api.wait(3)
      api.player().body.y = d.rect.y + 8
      api.wait(40)
      break
    end
    api.check(api.scene().id == ow.id, 'se sale al exterior')
  end
  g.dev.turbo = 1

  -- Casino: restaurant, teatre i cinema.
  local ow = enter('casino')
  api.check(#api.scene().arcades == 2, 'dos accessos culturals')
  shot('casino_interior')
  local c0 = st.coins
  local mg = use('cinema')
  api.check(mg and g.minigame.id == 'cinema', 'el faristol obre el teatre')
  shot('casino_teatre')
  for _=1,4 do Input.press('confirm');api.wait(4) end
  api.check(g.minigame == nil and st.coins == c0, 'funció completa sense premis monetaris')
  for _,a in ipairs(api.scene().arcades) do
    if a.obj.props.mode == 'cinema' then
      api.teleport(math.floor(a.obj.x/16),math.floor(a.obj.y/16)+1)
      api.player().facing='up';api.wait(3);api.press('confirm');api.wait(4)
    end
  end
  api.check(g.minigame and g.minigame.mg.mode=='cinema','projector obre cinema')
  shot('casino_cinema')
  Input.press('cancel');api.wait(4)
  api.check(g.minigame==nil,'sortida del cinema disponible')
  talk(service('casino'))
  local found=false
  for _,row in ipairs(g.menu.list) do if row[1]=='Carta del restaurant' then row[2]();found=true;break end end
  api.check(found and #g.menu.list > 1, 'carta disponible')
  st.coins=100
  local before=st.inventory.sopa_peix or 0
  g.menu.list[1][2]();api.wait(3)
  api.check((st.inventory.sopa_peix or 0)==before+1 and st.coins==91,'comprar sopa del restaurant')
  g:close_menu()
  leave(ow)

  -- ------------------------------------------------ Gimnàs: ritme
  ow = enter('gimnas')
  local s0 = st.train.strength
  mg = use('rhythm', 'strength')
  api.check(mg and mg.stat == 'strength', 'els pesos obren l\'entrenament de força')
  Input.press('confirm')
  local t = 0
  while mg.state ~= 'end' and t < 60 * 40 do   -- prémer cada fletxa quan arriba
    for _, n in ipairs(mg.notes) do
      if not n.done and math.abs(n.time - (mg.song_t + 1 / 60)) < 1 / 120 + 0.001 then Input.press(mg.LANES and mg.LANES[n.lane] or ({ 'left', 'down', 'up', 'right' })[n.lane]) end
    end
    api.wait(1); t = t + 1
    if t == 400 then shot('mg_rhythm') end
  end
  api.wait(40); Input.press('confirm'); api.wait(3)
  api.check(st.train.strength == s0 + 1 and st.minigames.trained.strength, 'sessió aprovada: força +1')
  mg = use('rhythm', 'resistance')
  api.check(mg and mg.stat == 'resistance', 'la bici estàtica entrena la resistència')
  Input.press('cancel'); api.wait(3)
  leave(ow)

  -- ------------------------------------------------ Poliesportiu: penals i circuit
  ow = enter('poliesportiu')
  mg = use('penalties')
  api.check(mg and g.minigame.id == 'penalties', 'la porteria obre la tanda de penals')
  for k = 1, 5 do
    until_(function() return mg.state == 'aim' and mg.aim > 0.8 and mg.aim < 0.9 end, 600)
    Input.press('confirm'); api.wait(1)
    until_(function() return mg.state == 'power' and mg.power > 0.6 and mg.power < 0.8 end, 600)
    Input.press('confirm'); api.wait(1)
    if k == 1 then api.wait(14); shot('mg_penalties') end
    until_(function() return mg.state == 'aim' or mg.state == 'end' end, 600)
  end
  api.wait(40); Input.press('confirm'); api.wait(3)
  api.check(g.minigame == nil and st.coins > 0, 'tanda acabada amb premi (' .. mg.goals .. ' gols)')
  mg = use('circuit')
  api.check(mg and g.minigame.id == 'circuit', 'els cons obren el circuit d\'agilitat')
  Input.press('confirm')
  t = 0
  while mg.state ~= 'end' and t < 60 * 40 do
    local nxt
    for _, gt in ipairs(mg.gates) do if not gt.state then nxt = gt; break end end
    local tx = nxt and nxt.x or 0
    Input.hold('left', mg.x > tx + 2); Input.hold('right', mg.x < tx - 2)
    api.wait(1); t = t + 1
    if t == 200 then shot('mg_circuit') end
  end
  Input.release_all()
  api.check(mg.state == 'end' and mg.passed == #mg.gates, 'circuit acabat passant totes les portes')
  api.wait(40); Input.press('confirm'); api.wait(3)
  leave(ow)

  -- ------------------------------------------------ Camp de futbol: penals
  ow = enter('camp_futbol')
  api.check(#api.scene().arcades == 3, 'al camp hi ha la porteria')
  shot('mg_camp_interior')
  -- guardar dins i continuar: es torna al mateix interior
  g:save_game(false)
  g:continue_game()
  api.wait(40)
  api.check(api.scene().id == 'poi_camp_futbol', 'continuar la partida dins del camp hi torna')
  leave(ow)
end
