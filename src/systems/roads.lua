-- Eixos de les vies (data/roads.json, tools/make_roads.py) per a la conducció guiada. Graella espacial de 128 px
-- (com src/systems/streets.lua): Roads.near(x, y, r) dona els trams a prop sense recórrer les 2.000 vies.
-- Tram: { li, i, x0, y0, x1, y1, c, o } (línia, índex del primer punt, classe 'road' | 'track' | 'path', sentit únic).
local Roads = {}

local CELL = 128
local data, grid

local function build(d)
  data, grid = d, {}
  for li, l in ipairs(d.lines) do
    local p = l.p
    for i = 1, #p - 3, 2 do
      local s = { li = li, i = i, x0 = p[i], y0 = p[i + 1], x1 = p[i + 2], y1 = p[i + 3], c = l.c, o = l.o }
      for cy = math.floor(math.min(s.y0, s.y1) / CELL), math.floor(math.max(s.y0, s.y1) / CELL) do
        for cx = math.floor(math.min(s.x0, s.x1) / CELL), math.floor(math.max(s.x0, s.x1) / CELL) do
          local k = cy * 4096 + cx
          grid[k] = grid[k] or {}
          grid[k][#grid[k] + 1] = s
        end
      end
    end
  end
  return data
end

local function load()
  if data ~= nil then return data end
  local txt
  if love and love.filesystem and love.filesystem.read then
    txt = love.filesystem.getInfo('data/roads.json') and love.filesystem.read('data/roads.json')
  else
    local f = io.open('data/roads.json'); if f then txt = f:read('*a'); f:close() end
  end
  if not txt then data = false; return data end
  local ok, d = pcall(require('src.lib.json').decode, txt)
  if not ok or type(d) ~= 'table' then data = false; return data end
  return build(d)
end

function Roads.line(li) local d = load(); return d and d.lines[li] end

-- trams que passen a menys de r px del punt (sense repetir); out es reaprofita
function Roads.near(x, y, r, out)
  out = out or {}
  for i = #out, 1, -1 do out[i] = nil end
  if not load() then return out end
  local seen = {}
  for cy = math.floor((y - r) / CELL), math.floor((y + r) / CELL) do
    for cx = math.floor((x - r) / CELL), math.floor((x + r) / CELL) do
      for _, s in ipairs(grid[cy * 4096 + cx] or {}) do
        if not seen[s] then
          seen[s] = true
          local dx, dy = s.x1 - s.x0, s.y1 - s.y0
          local l2 = dx * dx + dy * dy
          local t = l2 > 0 and math.max(0, math.min(1, ((x - s.x0) * dx + (y - s.y0) * dy) / l2)) or 0
          if (s.x0 + dx * t - x) ^ 2 + (s.y0 + dy * t - y) ^ 2 <= r * r then out[#out + 1] = s end
        end
      end
    end
  end
  return out
end

-- per a les proves: dades pròpies ({ lines = { { c, p, o } } }) o nil per tornar a data/roads.json
function Roads.set_data(d) if d then build(d) else data, grid = nil, nil end end

return Roads
