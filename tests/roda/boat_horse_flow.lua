-- Barca d'en Toni i cavalls de la hípica (love . --test=tests/boat_horse_flow.lua --mute).
-- Sense petxines, en Toni t'ho explica; amb 3 et porta per mar fins al Roc de Sant Gaietà (la ruta és tota
-- d'aigua) i baixes a terra. A la hípica, parlar amb un cavall hi puja; B en baixa i el cavall es queda allà.
-- Desa barca.png, cavall.png i platja.png.
return function(api)
  local g = api.scene().game
  local w = api.scene()
  local State = require('src.state')
  local Boat = require('src.systems.boat')
  local Collision = require('src.world.collision')
  local Input = require('src.input')
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  g.dev.turbo = 1
  api.talk_through()
  g.config.temps = 'sol'
  w.state.clock = 660
  -- NPCs de la platja
  local beach = {}
  for _, n in ipairs(w.npcs) do
    if n.name == 'npc_marta_socorrista' or n.name == 'npc_pau_castells' or n.name == 'npc_nuria_gelats'
        or n.name == 'npc_avi_joan_canya' then beach[#beach + 1] = n end
  end
  api.check(#beach == 4, 'hi ha 4 personatges a la platja (' .. #beach .. ')')
  local toni
  for _, n in ipairs(w.npcs) do if n.name == Boat.NPC then toni = n end end
  api.check(toni ~= nil, 'en Toni és al port')
  if not toni then return end
  -- ruta d'aigua fins al Roc
  local pts = Boat.route(w, math.floor(toni.body.x / 16), math.floor(toni.body.y / 16), Boat.DEST[1], Boat.DEST[2])
  api.check(pts and #pts > 3, 'hi ha camí per mar del port al Roc (' .. (pts and #pts or 0) .. ' punts)')
  local all_water = true
  for _, p in ipairs(pts or {}) do
    if w.map:cell(math.floor(p[1] / 16), math.floor(p[2] / 16)) % 4 ~= 2 then all_water = false end
  end
  api.check(all_water, 'tota la ruta és aigua')
  -- sense petxines: pista
  w.state.inventory.petxina = nil
  w.player.body.x, w.player.body.y = toni.body.x, toni.body.y + 14
  w.player.facing = 'up'
  api.wait(3)
  Input.press('confirm'); api.wait(3)
  api.check(w.dialogue.open, 'sense petxines en Toni explica què vol')
  for _ = 1, 20 do if not w.dialogue.open then break end; Input.press('confirm'); api.wait(3) end
  -- amb 3 petxines: menú i viatge
  State.give(w.state, 'petxina', 3)
  w.player.body.x, w.player.body.y = toni.body.x, toni.body.y + 14
  w.player.facing = 'up'
  api.wait(3)
  Input.press('confirm'); api.wait(3)
  api.check(g.menu ~= nil, 'amb 3 petxines en Toni ofereix la barca')
  if g.menu then g.menu.list[1][2]() end
  api.wait(5)
  api.check(w.boat_ride ~= nil, 'la barca surt')
  api.check((w.state.inventory.petxina or 0) == 0, 'paga 3 petxines')
  api.wait(240)
  shot('barca.png')
  for _ = 1, 4000 do if not w.boat_ride then break end; api.wait(1) end
  api.check(w.boat_ride == nil, 'la barca arriba')
  local b = w.player.body
  local d = math.sqrt((b.x / 16 - 1171) ^ 2 + (b.y / 16 - 1299) ^ 2)
  api.check(Collision.walk_at(w.map:cell(math.floor(b.x / 16), math.floor(b.y / 16)), 0) and d < 25,
    string.format('baixes a terra vora el Roc (%.0f caselles)', d))
  api.check(not toni.hidden, 'en Toni torna a ser al port')
  -- hípica
  local horse
  for _, o in ipairs(w.props) do if (o.props.sprite or ''):sub(1, 6) == 'horse_' then horse = o; break end end
  api.check(horse ~= nil, 'hi ha cavalls a la hípica')
  if not horse then return end
  w.player.body.x, w.player.body.y = horse.x, horse.y + 14
  w.player.facing = 'up'
  api.wait(3)
  Input.press('confirm'); api.wait(3)
  api.check(w.player.vehicle and w.player.vehicle.id == 'cavall', 'parlar amb el cavall hi puja')
  api.check(horse.hidden, 'el cavall de la pista desapareix (el portes tu)')
  Input.hold('left', true); api.wait(40); Input.release_all(); api.wait(10)
  shot('cavall.png')
  -- amb l'avatar del perfil, el genet surt a la fulla del paperdoll (4 direccions)
  local Looks = require('src.paperdoll.looks')
  g.profile = g.profile or { name = 'Proves' }
  g.profile.avatar = g.profile.avatar or Looks.default('nena')
  g:apply_skin('avatar')
  api.check(g.sprites.player_vehicles[w.player.vehicle.skin] ~= nil, 'l\'avatar té fulla de genet a cavall')
  api.wait(3)
  api.check(g.avatar_key and g.avatar_key:find('helmet_ride', 1, true) ~= nil, 'a cavall porta casc d\'hípica')
  Input.hold('down', true); api.wait(20); Input.release_all(); api.wait(5)
  shot('cavall_avatar.png')
  Input.press('bike'); api.wait(5)
  api.check(not w.player.vehicle, 'B baixa del cavall')
  api.wait(3)
  api.check(g.avatar_key and not g.avatar_key:find('helmet', 1, true), 'en baixar es treu el casc')
  api.check(not horse.hidden and math.abs(horse.x - w.player.body.x) < 20, 'el cavall es queda al costat')
  -- platja
  local m = beach[1]
  if m then w.player.body.x, w.player.body.y = m.body.x + 20, m.body.y; api.wait(30); shot('platja.png') end
end
