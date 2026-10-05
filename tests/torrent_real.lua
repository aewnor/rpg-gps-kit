-- Intenta cruzar a pie un torrente en línea recta en el juego real: no debe poder
-- (love . --test=tests/torrent_real.lua --mute).
return function(api)
  local Collision = require('src.world.collision')
  api.wait(5)
  local map = api.scene().map
  local tried, blocked = 0, 0
  for _, it in ipairs(map.lines.items) do
    if it.c == 'TORRENT' and #it.p >= 8 and tried < 8 then
      local p, i = it.p, math.floor(#it.p / 4) * 2 + 1
      local x0, y0, x1, y1 = p[i], p[i + 1], p[i + 2], p[i + 3]
      local dx, dy = x1 - x0, y1 - y0
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 0 then
        -- normal al cauce, redondeada a una dirección del teclado
        local nx, ny = -dy / len, dx / len
        local dir = math.abs(nx) > math.abs(ny) and (nx > 0 and 'right' or 'left') or (ny > 0 and 'down' or 'up')
        local sx, sy = (dir == 'right' and -1) or (dir == 'left' and 1) or 0, (dir == 'down' and -1) or (dir == 'up' and 1) or 0
        -- orilla de salida: primera celda transitable a 2–5 celdas del eje, del lado contrario
        local cx, cy = math.floor(x0 / 16), math.floor(y0 / 16)
        local start
        for t = 2, 6 do
          local tx, ty = cx + sx * t, cy + sy * t
          if map:in_bounds(tx, ty) and Collision.walk_at(map:cell(tx, ty), 0) then start = { tx, ty }; break end
        end
        if start then
          tried = tried + 1
          api.teleport(start[1], start[2])
          api.wait(3)
          local Input = require('src.input')
          Input.hold(dir, true)
          api.wait(150)
          Input.release_all()
          api.wait(2)
          local b = api.player().body
          local px, py = math.floor(b.x / 16), math.floor(b.y / 16)
          -- ¿ha pasado al otro lado del eje?
          local side0 = (start[1] - cx) * (dir == 'right' and 1 or dir == 'left' and -1 or 0) + (start[2] - cy) * (dir == 'down' and 1 or dir == 'up' and -1 or 0)
          local side1 = (px - cx) * (dir == 'right' and 1 or dir == 'left' and -1 or 0) + (py - cy) * (dir == 'down' and 1 or dir == 'up' and -1 or 0)
          local ok = side1 < 0 or (side0 < 0 and side1 <= 0)
          if ok then blocked = blocked + 1 end
          api.check(ok, string.format('torrente en %d,%d hacia %s: se queda en la orilla (%d,%d)', cx, cy, dir, px, py))
        end
      end
    end
  end
  api.check(tried >= 3, 'se han probado al menos 3 torrentes (' .. tried .. ')')
  print(string.format('[test] torrentes bloqueados: %d/%d', blocked, tried))
end
