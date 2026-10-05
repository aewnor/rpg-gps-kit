-- Ningún personaje ni servicio del exterior dentro de un edificio (love . --test=tests/npc_placement.lua --mute).
return function(api)
  local Collision = require('src.world.collision')
  local w = api.scene(); local map = w.map
  local bad = 0
  for _, o in ipairs(map.objects) do
    if o.type == 'service' or o.type == 'npc' or o.type == 'spot' then
      local tx, ty = math.floor(o.x / 16), math.floor(o.y / 16)
      for cy = math.floor(ty / 32) - 1, math.floor(ty / 32) + 1 do for cx = math.floor(tx / 32) - 1, math.floor(tx / 32) + 1 do map.chunks:get(cx, cy) end end
      local ok = Collision.walk_at(map:cell(tx, ty), 0)
      local free = 0
      for dy = -1, 1 do for dx = -1, 1 do if Collision.walk_at(map:cell(tx + dx, ty + dy), 0) then free = free + 1 end end end
      if not ok or free < 3 then
        bad = bad + 1
        print(string.format('[test] %s %s en %d,%d transitable=%s vecinos libres=%d', o.type, o.props.service_id or o.name or '', tx, ty, tostring(ok), free))
      end
    end
  end
  print('[test] mal colocados: ' .. bad)
end
