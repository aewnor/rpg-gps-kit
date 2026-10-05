-- Entra en la escuela por su puerta, habla con la mestra y vuelve a salir
-- (love . --test=tests/school_door.lua --mute).
return function(api)
  local json = require('src.lib.json')
  local z = json.decode(assert(love.filesystem.read('maps/source/zones/escola_espriu.json')))
  local door
  for _, o in ipairs(z.objects) do if o.type == 'door' then door = o end end
  api.wait(5)
  -- els avisos de missió (p. ex. «Visita la metgessa») surten al cap d'uns segons i aturen el jugador
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  api.talk_through()
  local dx, dy = z.x + door.x, z.y + door.y
  api.teleport(dx, dy + 2)
  api.wait(5)
  local entered = api.walk_to(function(x, y) return x == dx and y == dy end, 30)
  api.wait(90)
  local sc = api.scene()
  api.check(entered and sc.id == door.interior, 'entra en ' .. door.interior .. ' (escena ' .. tostring(sc.id) .. ')')
  api.wait(30)
  local b = api.player().body
  local ex, ey
  for _, o in ipairs(z.interiors[door.interior].objects) do if o.type == 'exit' then ex, ey = o.x, o.y end end
  local out = api.walk_to(function(x, y) return x == ex and y == ey end, 30)
  api.wait(90)
  api.check(api.scene().id == z.scene, 'sale al exterior (escena ' .. tostring(api.scene().id) .. ')')
  local p = api.player().body
  api.on_frame = nil
  api.check(math.abs(math.floor(p.x / 16) - dx) <= 1 and math.floor(p.y / 16) >= dy, 'aparece frente a la puerta')
end
