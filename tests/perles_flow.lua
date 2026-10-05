-- Perles del Drac i marca del mapa (love . --test=tests/perles_flow.lua --mute): les 7 perles són en caselles
-- transitables i s'agafen passant-hi; amb les set s'equipa l'Armadura del Drac (es veu a l'avatar). La pantalla
-- del mapa posa una marca (Z) o va passant per les cases (X) i al joc surt la brúixola; en arribar s'esborra.
-- Desa perla.png, armadura.png, mapa_marca.png i brujola.png.
return function(api)
  local g = api.scene().game
  local w = api.scene()
  local State = require('src.state')
  local Perles = require('src.systems.perles')
  local Marker = require('src.systems.marker')
  local Collision = require('src.world.collision')
  local Looks = require('src.paperdoll.looks')
  local Input = require('src.input')
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  api.talk_through()
  g.config.temps = 'sol'
  g.profile = g.profile or { name = 'Proves' }
  g.profile.avatar = g.profile.avatar or Looks.default('nena')
  g:apply_skin('avatar')
  api.check(#w.perles == 7, 'hi ha 7 perles col·locades (' .. #w.perles .. ')')
  for _, p in ipairs(w.perles) do
    api.check(Perles.resolve(w, p, true), p.id .. ' té casella')
    if p.x then
      local tx, ty = math.floor(p.x / 16), math.floor(p.y / 16)
      api.check(Collision.walk_at(w.map:cell(tx, ty), 0), string.format('%s a %d,%d és transitable', p.id, tx, ty))
      print(string.format('[test] %s %d,%d', p.id, tx, ty))
    end
  end
  -- totes lluny de l'inici de la partida (no s'agafen sense voler)
  for _, p in ipairs(w.perles) do
    if p.x then
      api.check(not State.flag(w.state, p.id), p.id .. ' no s\'ha agafat sola')
    end
  end
  -- agafar-les una a una
  for i, p in ipairs(w.perles) do
    w.player.body.x, w.player.body.y = p.x, p.y + 24
    api.wait(20)
    if i == 1 then w.cam:follow(p.x, p.y, w.map.width * 16, w.map.height * 16); api.wait(10); shot('perla.png') end
    w.player.body.x, w.player.body.y = p.x, p.y
    api.wait(5)
    api.check(State.flag(w.state, p.id), p.id .. ' agafada (' .. Perles.count(w.state) .. '/7)')
  end
  api.check((w.state.inventory.perla_drac or 0) == 7, 'tens 7 Perles del Drac a la motxilla')
  api.check(w.state.equipment.armor == 'armadura_drac', 'l\'Armadura del Drac queda equipada')
  api.wait(5)
  api.check(g.avatar_key and g.avatar_key:find('dragon', 1, true) ~= nil, 'l\'armadura es veu al personatge')
  api.wait(60)
  shot('armadura.png')

  -- marca del mapa: X passa per casa i les cases dels amics; Z al centre la posa o la treu
  Marker.clear(w.state)
  local saved_friends = g.friends
  g.friends = { { def = { name = 'Amiga de prova', home = { tile_x = 700, tile_y = 820 } } },
                { def = { name = 'Avi de prova', home = { tile_x = 760, tile_y = 880 } } } }
  g:open_menu('map')
  api.wait(5)
  local places = Marker.places(g)
  if #places > 0 then
    Input.press('attack'); api.wait(3)
    local m = Marker.get(g.state)
    api.check(m and m.label == places[1].label, 'X marca ' .. tostring(places[1].label))
    Input.press('attack'); api.wait(10)
    m = Marker.get(g.state)
    api.check(m and m.label == places[2].label, 'X un altre cop marca ' .. tostring(places[2].label))
    shot('mapa_amics.png')
  end
  g.friends = saved_friends
  Marker.clear(g.state)
  Input.press('confirm'); api.wait(3)
  local m1 = Marker.get(g.state)
  api.check(m1 ~= nil, 'Z posa una marca al centre: ' .. tostring(m1 and m1.label))
  Input.press('confirm'); api.wait(3)
  api.check(Marker.get(g.state) == nil, 'Z al mateix lloc treu la marca')
  Input.press('confirm'); api.wait(3)
  Input.press('zoom_in'); api.wait(3); Input.press('zoom_in'); api.wait(10)
  shot('mapa_marca.png')
  Input.press('cancel'); api.wait(10)
  api.check(g.menu == nil, 'Esc tanca el mapa')
  -- brúixola i arribada
  local wx = api.scene()
  Marker.set(wx.state, wx.player.body.x + 300, wx.player.body.y, 'Prova')
  api.wait(10)
  shot('brujola.png')
  wx.player.body.x = wx.player.body.x + 300
  api.wait(5)
  api.check(Marker.get(wx.state) == nil, 'en arribar a la marca s\'esborra')
end
