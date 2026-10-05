-- Edificis de diverses plantes al joc (love . --test=tests/floors_flow.lua --mute):
-- porta d'un bloc (3+ files de façana) → portal → escala → replà → pis → replà → ascensor → portal → carrer;
-- desar dins d'un pis i continuar torna al mateix pis.
return function(api)
  local Input = require('src.input')
  local Collision = require('src.world.collision')
  local game = api.scene().game
  api.wait(5)
  local sc0, map = api.scene(), api.scene().map
  local lk = game.renderer.light_kind
  local b = api.player().body
  local px, py = math.floor(b.x / 16), math.floor(b.y / 16)
  local door
  for r = 4, 200 do
    for dy = -r, r do
      for dx = -r, r do
        if not door and math.max(math.abs(dx), math.abs(dy)) == r then
          local x, y = px + dx, py + dy
          if lk[map:tile_at('structures', x, y)] == 'door' and Collision.walk_at(map:cell(x, y + 1), 0)
              and Collision.walk_at(map:cell(x, y + 2), 0) and not Collision.is_ramp(map:cell(x, y + 1))
              and sc0:facade_floors(x, y) >= 3 then
            door = { x, y }
          end
        end
      end
    end
    if door then break end
  end
  api.check(door ~= nil, 'hi ha un bloc de pisos (3+ plantes) a prop')
  if not door then return end
  local floors = sc0:facade_floors(door[1], door[2])
  if sc0.traffic then sc0.traffic.cars = {} end
  api.teleport(door[1], door[2] + 1)
  api.scene().player.facing = 'up'
  Input.hold('up', true)
  for _ = 1, 90 do api.wait(1); if game.transition or api.scene().id ~= 'overworld' then break end end
  Input.release_all()
  api.wait(80)
  local base = api.scene().id
  api.check(base:match('^proc_%-?%d+_%-?%d+$') ~= nil, 'entra al portal (' .. base .. ', ' .. floors .. ' plantes)')
  api.check(game.scenes[base .. '_p' .. (floors - 1)] ~= nil, 'hi ha tantes plantes com files de façana')
  local function go_exit(pred)
    local m = api.scene().map
    local gx, gy
    for _, o in ipairs(m.objects) do
      if o.type == 'door' and pred(o.props) then gx, gy = math.floor(o.x / 16), math.floor(o.y / 16) end
    end
    if not gx then return false end
    local ok = api.walk_to(function(x, y) return x == gx and y == gy end, 60)
    api.wait(90)
    return ok
  end
  -- escala amunt
  go_exit(function(p) return p.target_scene == base .. '_p1' end)
  api.check(api.scene().id == base .. '_p1', 'puja per l\'escala al replà de la 1a planta (' .. api.scene().id .. ')')
  -- entrar al pis 1r 1a i sortir
  go_exit(function(p) return p.target_scene == base .. '_p1_1' end)
  api.check(api.scene().id == base .. '_p1_1', 'entra al pis 1r 1a')
  api.check(#api.scene().npcs >= 1, 'al pis hi viu algú')
  local flat_pos = { api.player().body.x, api.player().body.y }
  go_exit(function(p) return p.target_scene == base .. '_p1' end)
  api.check(api.scene().id == base .. '_p1', 'surt del pis al replà')
  local pb = api.player().body
  local fl
  for _, o in ipairs(api.scene().map.objects) do
    if o.type == 'door' and o.props.target_scene == base .. '_p1_1' then fl = o end
  end
  api.check(fl and math.floor(pb.x / 16) == math.floor(fl.x / 16) and math.floor(pb.y / 16) == math.floor(fl.y / 16) + 1,
    'apareix davant de la porta del pis')
  -- ascensor: a la planta de dalt i tornar a baix
  local lift
  for _, a in ipairs(api.scene().arcades) do if a.obj.props.game == 'lift' then lift = a end end
  api.check(lift ~= nil, 'el replà té ascensor')
  local top = base .. '_p' .. (floors - 1)
  if lift then
    api.teleport(math.floor(lift.rect.x / 16), math.floor(lift.rect.y / 16) + 1)
    api.scene().player.facing = 'up'
    api.wait(2)
    api.scene():interact()
    api.check(game.menu and #game.menu.list == floors, 'el menú de l\'ascensor llista les ' .. floors .. ' plantes')
    if game.menu then game.menu.list[floors][2]() end
    api.wait(90)
    api.check(api.scene().id == top, 'l\'ascensor porta a l\'última planta (' .. api.scene().id .. ')')
    api.scene().player.facing = 'up'
    api.wait(2)
    api.scene():interact()
    if game.menu then game.menu.list[1][2]() end
    api.wait(90)
    api.check(api.scene().id == base, 'i torna a la planta baixa')
  end
  -- carrer
  go_exit(function(p) return p.target_x ~= nil end)
  api.check(api.scene().id == 'overworld', 'surt al carrer')
  -- continuar (sessió nova) una partida desada dins del pis: l'edifici es torna a generar
  game.state.scene, game.state.x, game.state.y = base .. '_p1_1', flat_pos[1], flat_pos[2]
  game:save_game(false)
  for id in pairs(game.scenes) do
    if id:sub(1, #base) == base then game.scenes[id], game.generated[id], game.maps[id] = nil, nil, nil end
  end
  game:continue_game()
  api.wait(90)
  api.check(api.scene().id == base .. '_p1_1', 'continuar: torna al pis on s\'havia desat (' .. api.scene().id .. ')')
end
