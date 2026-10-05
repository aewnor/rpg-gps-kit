-- Interiores procedurales y casa privada (love . --test=tests/proc_interiors.lua --mute):
--  1) empujar la puerta de una fachada → interior generado; todo accesible; la salida vuelve delante de la puerta;
--     volver a entrar da el mismo interior (misma semilla);
--  2) si hay casa (casa_privada.json + home.json): entrar desde el buzón, subir, bajar al sótano y salir.
return function(api)
  local Input = require('src.input')
  local Collision = require('src.world.collision')
  local game = api.scene().game
  api.wait(5)
  local map = api.scene().map
  local lk = game.renderer.light_kind
  local b = api.player().body
  local px, py = math.floor(b.x / 16), math.floor(b.y / 16)
  -- puerta de fachada más cercana con la celda de debajo transitable y sin tráfico
  local door
  local hd0 = api.scene().house_door
  for r = 4, 120 do
    for dy = -r, r do
      for dx = -r, r do
        if not door and math.max(math.abs(dx), math.abs(dy)) == r then
          local x, y = px + dx, py + dy
          if lk[map:tile_at('structures', x, y)] == 'door' and Collision.walk_at(map:cell(x, y + 1), 0)
              and Collision.walk_at(map:cell(x, y + 2), 0) and not Collision.is_ramp(map:cell(x, y + 1))
              and not (hd0 and hd0[1] == x and hd0[2] == y) then
            door = { x, y }
          end
        end
      end
    end
    if door then break end
  end
  api.check(door ~= nil, 'hay una puerta de fachada cerca del inicio')
  if not door then return end
  if api.scene().traffic then api.scene().traffic.cars = {} end
  local function push_door()
    api.teleport(door[1], door[2] + 1)
    api.scene().player.facing = 'up'
    Input.hold('up', true)
    for i = 1, 90 do
      api.wait(1)
      if game.transition or api.scene().id ~= 'overworld' then break end
    end
    Input.release_all()
    api.wait(80)
  end
  push_door()
  local sc = api.scene()
  api.check(sc.id:match('^proc_') ~= nil, 'empujar la puerta entra en un interior generado (' .. sc.id .. ')')
  if not sc.id:match('^proc_') then return end
  local first_id, m = sc.id, sc.map
  -- accesibilidad: todas las celdas libres conectadas con la salida
  local doorobj
  for _, o in ipairs(m.objects) do if o.type == 'door' and o.props.target_x then doorobj = o end end   -- la del carrer (no l'escala)
  local ex, ey = math.floor(doorobj.x / 16), math.floor(doorobj.y / 16)
  local comp = m:component(ex, ey)
  local lost = 0
  for y = 0, m.height - 1 do
    for x = 0, m.width - 1 do
      if Collision.walk_at(m:cell(x, y), 0) and m:component(x, y) ~= comp then lost = lost + 1 end
    end
  end
  api.check(lost == 0, 'interior sin celdas inaccesibles (' .. lost .. ')')
  local npcs = #sc.npcs
  api.check(npcs >= 1, 'el interior tiene habitantes (' .. npcs .. ')')
  local out = api.walk_to(function(x, y) return x == ex and y == ey end, 40)
  api.wait(90)
  api.check(out and api.scene().id == 'overworld', 'la salida vuelve al exterior')
  local pb = api.player().body
  api.check(math.abs(math.floor(pb.x / 16) - door[1]) <= 1 and math.floor(pb.y / 16) == door[2] + 1,
    'aparece delante de la puerta (' .. math.floor(pb.x / 16) .. ',' .. math.floor(pb.y / 16) .. ')')
  api.wait(20)
  push_door()
  api.check(api.scene().id == first_id, 'la misma puerta da el mismo interior')
  game.state.x, game.state.y = api.player().body.x, api.player().body.y
  game:save_game(false)
  local w0 = api.scene().map.width
  -- salir otra vez
  api.walk_to(function(x, y) return x == ex and y == ey end, 40)
  api.wait(90)

  -- casa privada
  if not game.house then print('[test] SKIP casa: no hay casa_privada.json/home.json'); return end
  if not game.home then print('[test] SKIP casa: ' .. tostring(game.home_warning)); return end
  local hd = api.scene().house_door
  api.check(hd ~= nil, 'la casa tiene puerta de fachada')
  -- (con la entrada por el este la puerta de fachada solo es el buzón: lo cubre tests/house_east.lua)
  if hd and not api.scene().house_east then door = hd; push_door() else game:change(game.house.entry, 'spawn_in'); api.wait(80) end
  api.check(api.scene().id == game.house.entry, 'entra en la casa (' .. api.scene().id .. ')')
  local function go_exit_to(target)
    local hm = api.scene().map
    local gx, gy
    for _, o in ipairs(hm.objects) do
      if o.type == 'door' and o.props.target_scene == target then gx, gy = math.floor(o.x / 16), math.floor(o.y / 16) end
    end
    if not gx then return false end
    local ok = api.walk_to(function(x, y) return x == gx and y == gy end, 60)
    api.wait(90)
    return ok and api.scene().id == target
  end
  local up = 'casa_privada_1'
  if game.scenes[up] then
    api.check(go_exit_to(up), 'sube al primer piso')
    api.check(go_exit_to(game.house.entry), 'baja a la planta baja')
    local cat = false   -- (el gato vive en la planta baja)
    for _, n in ipairs(api.scene().npcs) do if (n.props.sprite or ''):match('cat') then cat = true end end
    api.check(cat, 'hay un gato en la planta baja')
  end
  if game.scenes.casa_privada_s1 then
    -- (la escalera del sótano queda tras la del primer piso: se rodea por el lado este)
    for _, c in ipairs({ { 42, 6 }, { 42, 4 } }) do api.walk_to(function(x, y) return x == c[1] and y == c[2] end, 40) end
    api.check(go_exit_to('casa_privada_s1'), 'baja al sótano')
    api.check(go_exit_to(game.house.entry), 'sube del sótano')
  end
  api.check(go_exit_to(game.home.scene), 'sale de casa a la calle')
  local hb = api.player().body
  local e = api.scene().house_east   -- con entrada este se reaparece en ella (tests/house_east.lua); si no, delante de la puerta
  if e then
    api.check(math.floor(hb.x / 16) == e.wx + 1 and math.floor(hb.y / 16) == e.ty, 'aparece en la entrada este de casa')
  else
    api.check(hd and math.floor(hb.x / 16) == hd[1] and math.floor(hb.y / 16) == hd[2] + 1, 'aparece delante de la puerta de casa')
  end
end
