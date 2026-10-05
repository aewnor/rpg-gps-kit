-- BFS por niveles sobre la rejilla (herramienta de desarrollo: benchmark y tests).
local Collision = require('src.world.collision')

local Path = {}

-- start: {tx, ty, level}; goal(tx, ty) -> bool. Devuelve lista de {tx, ty, level} o nil.
function Path.find(map, start, goal, max_nodes, blocked)
  max_nodes = max_nodes or 3000000
  local W = map.width
  local function key(x, y, l) return ((l + 1) * map.height + y) * W + x end
  local prev = {}
  local qx, qy, ql = { start[1] }, { start[2] }, { start[3] or 0 }
  local head = 1
  prev[key(start[1], start[2], start[3] or 0)] = -1
  local n = 0
  while head <= #qx do
    local x, y, l = qx[head], qy[head], ql[head]
    head = head + 1
    if goal(x, y) then
      local out = {}
      local k = key(x, y, l)
      while k ~= -1 do
        local lv = math.floor(k / (W * map.height)) - 1
        local rem = k % (W * map.height)
        table.insert(out, 1, { rem % W, math.floor(rem / W), lv })
        k = prev[k]
      end
      return out
    end
    local c = map:cell(x, y)
    for d = 1, 4 do
      local nx = x + (d == 1 and 1 or d == 2 and -1 or 0)
      local ny = y + (d == 3 and 1 or d == 4 and -1 or 0)
      if map:in_bounds(nx, ny) then
        local nl = Collision.step_level(c, map:cell(nx, ny), l)
        if nl and not (blocked and blocked[ny * W + nx]) then
          local k = key(nx, ny, nl)
          if not prev[k] then
            prev[k] = key(x, y, l)
            qx[#qx + 1], qy[#qy + 1], ql[#ql + 1] = nx, ny, nl
          end
        end
      end
    end
    n = n + 1
    if n > max_nodes then return nil end
  end
  return nil
end

-- comprime a puntos de giro (centros de tile en píxeles)
function Path.waypoints(path)
  local out = {}
  for i, p in ipairs(path) do
    local prev, nxt = path[i - 1], path[i + 1]
    local turn = not prev or not nxt or (p[1] - prev[1] ~= nxt[1] - p[1]) or (p[2] - prev[2] ~= nxt[2] - p[2])
    if turn then out[#out + 1] = { p[1] * 16 + 8, p[2] * 16 + 8 } end
  end
  return out
end

return Path
