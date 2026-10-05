-- A* sobre la rejilla de casillas (nivel 0, 8 vecinos sin cortar esquinas) con montículo binario y tope
-- de nodos: los personajes con horario (src/systems/schedule.lua) lo piden como mucho una vez por paso y,
-- si el destino está demasiado lejos para el presupuesto, devuelve el camino hacia el nodo más cercano
-- al destino (llegan por tramos). Lua puro: tests/schedule_cases.lua.
local Collision = require('src.world.collision')

local A = {}
local SQ2 = 1.41421356

-- walk(tx, ty) → bool (por defecto: transitable a nivel 0 en el mapa)
-- (només els chunks ja carregats: buscar un camí mai no llegeix el disc enmig de la partida)
function A.walker(map)
  local C = map.chunk or 32
  return function(x, y)
    if not map:in_bounds(x, y) then return false end
    if map.chunks.has and not map.chunks:has(math.floor(x / C), math.floor(y / C)) then return false end
    return Collision.walk_at(map:cell(x, y), 0)
  end
end

local function octile(dx, dy)
  dx, dy = math.abs(dx), math.abs(dy)
  return (dx + dy) + (SQ2 - 2) * math.min(dx, dy)
end

-- devuelve lista de casillas { {x, y}, … } desde (sx, sy) hasta (gx, gy) o el mejor parcial, y si es completo
function A.find(walk, sx, sy, gx, gy, max_nodes)
  max_nodes = max_nodes or 4000
  if sx == gx and sy == gy then return { { sx, sy } }, true end
  local function key(x, y) return y * 65536 + x end
  -- cada casella es consulta al mapa (chunks) un sol cop per cerca
  local wc = {}
  local raw = walk
  walk = function(x, y)
    local k = y * 65536 + x
    local v = wc[k]
    if v == nil then v = raw(x, y) and true or false; wc[k] = v end
    return v
  end
  local g, came, closed = {}, {}, {}
  local hx, hy, hf = {}, {}, {}      -- montículo (x, y, f)
  local n = 0
  local function push(x, y, f)
    n = n + 1
    local i = n
    hx[i], hy[i], hf[i] = x, y, f
    while i > 1 do
      local p = math.floor(i / 2)
      if hf[p] <= hf[i] then break end
      hx[p], hx[i] = hx[i], hx[p]; hy[p], hy[i] = hy[i], hy[p]; hf[p], hf[i] = hf[i], hf[p]
      i = p
    end
  end
  local function pop()
    local x, y = hx[1], hy[1]
    hx[1], hy[1], hf[1] = hx[n], hy[n], hf[n]
    hx[n], hy[n], hf[n] = nil, nil, nil
    n = n - 1
    local i = 1
    while true do
      local l, r = i * 2, i * 2 + 1
      local m = i
      if l <= n and hf[l] < hf[m] then m = l end
      if r <= n and hf[r] < hf[m] then m = r end
      if m == i then break end
      hx[m], hx[i] = hx[i], hx[m]; hy[m], hy[i] = hy[i], hy[m]; hf[m], hf[i] = hf[i], hf[m]
      i = m
    end
    return x, y
  end
  local sk = key(sx, sy)
  g[sk] = 0
  push(sx, sy, octile(gx - sx, gy - sy))
  local best, bh = sk, octile(gx - sx, gy - sy)
  local expanded = 0
  local found = false
  while n > 0 do
    local x, y = pop()
    local k = key(x, y)
    if not closed[k] then
      closed[k] = true
      if x == gx and y == gy then best = k; found = true; break end
      local h = octile(gx - x, gy - y)
      if h < bh then best, bh = k, h end
      expanded = expanded + 1
      if expanded > max_nodes then break end
      local gk = g[k]
      for dy = -1, 1 do
        for dx = -1, 1 do
          if dx ~= 0 or dy ~= 0 then
            local nx, ny = x + dx, y + dy
            -- en diagonal, las dos casillas laterales también libres (no cortar esquinas de edificios)
            if walk(nx, ny) and (dx == 0 or dy == 0 or (walk(x + dx, y) and walk(x, y + dy))) then
              local nk = key(nx, ny)
              local ng = gk + ((dx ~= 0 and dy ~= 0) and SQ2 or 1)
              if not closed[nk] and (g[nk] == nil or ng < g[nk]) then
                g[nk] = ng
                came[nk] = k
                push(nx, ny, ng + octile(gx - nx, gy - ny))
              end
            end
          end
        end
      end
    end
  end
  local path = {}
  local k = best
  while k do
    table.insert(path, 1, { k % 65536, math.floor(k / 65536) })
    k = came[k]
  end
  return path, found
end

-- casillas → puntos de giro en píxeles (centros de casilla)
function A.waypoints(path)
  local out = {}
  for i, p in ipairs(path) do
    local a, b = path[i - 1], path[i + 1]
    local turn = not a or not b or (p[1] - a[1] ~= b[1] - p[1]) or (p[2] - a[2] ~= b[2] - p[2])
    if turn and i > 1 then out[#out + 1] = { p[1] * 16 + 8, p[2] * 16 + 8 } end
  end
  return out
end

return A
