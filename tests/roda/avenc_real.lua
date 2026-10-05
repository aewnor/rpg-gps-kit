-- Recorre a pie, en el juego real, la Avinguda de l'Avenc de punta a punta (love . --test=tests/avenc_real.lua --mute).
-- Regresión: el Camí de Roda - Vendrell traía layer=-1 en todo el trazado y el importador lo trataba como túnel,
-- así que la avenida desaparecía a partir de (914,778). Aquí exigimos que la cadena de la vía sea de nivel 0,
-- continua, sin tramos subterráneos bajo el punto del corte y transitable de extremo a extremo.
return function(api)
  local Collision = require('src.world.collision')
  api.wait(5)
  local map = api.scene().map
  local CUT = { 917.8, 776.9 }   -- 41,1870539, 1,4688699

  local roads = {}
  for _, it in ipairs(map.lines.items) do
    if it.c == 'ROAD_MAIN' or it.c == 'ROAD' then roads[#roads + 1] = it end
  end
  local function endpoints(it) local p = it.p; return p[1] / 16, p[2] / 16, p[#p - 1] / 16, p[#p] / 16 end
  local function dist2(ax, ay, bx, by) return (ax - bx) ^ 2 + (ay - by) ^ 2 end

  -- ningún tramo subterráneo de calzada junto al punto del corte
  local under = 0
  for _, it in ipairs(roads) do
    if it.l == -1 then
      for i = 1, #it.p - 1, 2 do
        if dist2(it.p[i] / 16, it.p[i + 1] / 16, CUT[1], CUT[2]) < 9 then under = under + 1; break end
      end
    end
  end
  api.check(under == 0, 'sin vía subterránea (nivel -1) junto al corte de la avenida (' .. under .. ')')

  -- el tramo de nivel 0 que pasa por el punto del corte
  local start, best = nil, 1e9
  for _, it in ipairs(roads) do
    if it.l == 0 and it.c == 'ROAD_MAIN' then
      for i = 1, #it.p - 1, 2 do
        local d = dist2(it.p[i] / 16, it.p[i + 1] / 16, CUT[1], CUT[2])
        if d < best then best, start = d, it end
      end
    end
  end
  api.check(start ~= nil and best < 40 * 40, 'hay calzada de nivel 0 cerca del corte')
  if not start then return end

  -- cadena de tramos de nivel 0 enlazados por sus extremos, hacia los dos lados
  local used, chain = { [start] = true }, { start }
  local function extend(front)
    while true do
      local it = front and chain[#chain] or chain[1]
      local ax, ay, bx, by = endpoints(it)
      local ex, ey = front and bx or ax, front and by or ay
      local nxt
      for _, o in ipairs(roads) do
        if not used[o] and o.l == 0 and o.c == 'ROAD_MAIN' then
          local oax, oay, obx, oby = endpoints(o)
          if dist2(ex, ey, oax, oay) < 2 or dist2(ex, ey, obx, oby) < 2 then nxt = o; break end
        end
      end
      if not nxt then return end
      used[nxt] = true
      if front then chain[#chain + 1] = nxt else table.insert(chain, 1, nxt) end
    end
  end
  extend(true)
  extend(false)

  -- puntos de la cadena (orientada de oeste a este) cada ~14 celdas
  local pts = {}
  for _, it in ipairs(chain) do
    local seg = {}
    for i = 1, #it.p - 1, 2 do seg[#seg + 1] = { it.p[i] / 16, it.p[i + 1] / 16 } end
    if #seg > 1 and seg[1][1] > seg[#seg][1] then
      local r = {}
      for i = #seg, 1, -1 do r[#r + 1] = seg[i] end
      seg = r
    end
    for _, q in ipairs(seg) do pts[#pts + 1] = q end
  end
  table.sort(pts, function(a, b) return a[1] < b[1] end)
  api.check(pts[1][1] < 700 and pts[#pts][1] > 1100,
    string.format('la avenida de nivel 0 va de x=%.0f a x=%.0f (debe cubrir 700..1100)', pts[1][1], pts[#pts][1]))

  local way, last = {}, nil
  for _, q in ipairs(pts) do
    if not last or dist2(q[1], q[2], last[1], last[2]) >= 14 * 14 then way[#way + 1] = q; last = q end
  end
  -- toda la calzada (muestreada cada ~1,5 celdas sobre los segmentos) es transitable a nivel 0
  local total, walkable = 0, 0
  for _, it in ipairs(chain) do
    for i = 1, #it.p - 3, 2 do
      local ax, ay, bx, by = it.p[i] / 16, it.p[i + 1] / 16, it.p[i + 2] / 16, it.p[i + 3] / 16
      local n = math.max(1, math.floor(math.sqrt(dist2(ax, ay, bx, by)) / 1.5))
      for k = 0, n do
        local x, y = math.floor(ax + (bx - ax) * k / n), math.floor(ay + (by - ay) * k / n)
        total = total + 1
        if map:in_bounds(x, y) and Collision.walk_at(map:cell(x, y), 0) then walkable = walkable + 1 end
      end
    end
  end
  api.check(walkable == total, string.format('calzada transitable a nivel 0: %d/%d muestras', walkable, total))

  -- recorrido a pie de punta a punta, pasando por el punto del corte
  local x0, y0 = math.floor(way[1][1]), math.floor(way[1][2])
  api.teleport(x0, y0)
  api.wait(3)
  local reached = 0
  for i = 2, #way do
    local tx, ty = math.floor(way[i][1]), math.floor(way[i][2])
    local ok = api.walk_to(function(x, y) return math.abs(x - tx) + math.abs(y - ty) <= 2 end, 120)
    if ok then reached = reached + 1 end
    api.check(ok and api.player().body.level == 0, string.format('avenida: tramo %d/%d llega a %d,%d', i - 1, #way - 1, tx, ty))
    if not ok then break end
  end
  local b = api.player().body
  api.check(reached == #way - 1, string.format('avenida recorrida de punta a punta (%d/%d tramos); acabo en %d,%d',
    reached, #way - 1, math.floor(b.x / 16), math.floor(b.y / 16)))
end
