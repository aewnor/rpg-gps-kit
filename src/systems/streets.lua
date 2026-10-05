-- Noms oficials de carrers, places i parcs (data/streets.json, de tools/make_streets.py) per als cartells
-- «Carrer de…» en entrar a cada zona i per a les missions. Consulta en una graella espacial (cel·les de
-- 128 px) per no recórrer els 1.100 trams a cada pas: la Raspberry Pi ho nota.
local Streets = {}

local CELL = 128
local data, grid

local function load()
  if data ~= nil then return data end
  local ok, txt
  if love and love.filesystem and love.filesystem.read then
    txt = love.filesystem.getInfo('data/streets.json') and love.filesystem.read('data/streets.json')
  else
    local f = io.open('data/streets.json'); if f then txt = f:read('*a'); f:close() end
  end
  if not txt then data = false; return data end
  ok, data = pcall(require('src.lib.json').decode, txt)
  if not ok then data = false; return data end
  grid = {}
  local function add(cx, cy, item)
    local k = cy * 4096 + cx
    grid[k] = grid[k] or {}
    local cell = grid[k]
    cell[#cell + 1] = item
  end
  for li, l in ipairs(data.lines) do
    local p = l.p
    for i = 1, #p - 3, 2 do
      local x0, y0, x1, y1 = p[i], p[i + 1], p[i + 2], p[i + 3]
      local seg = { li, x0, y0, x1, y1 }
      for cy = math.floor(math.min(y0, y1) / CELL), math.floor(math.max(y0, y1) / CELL) do
        for cx = math.floor(math.min(x0, x1) / CELL), math.floor(math.max(x0, x1) / CELL) do add(cx, cy, seg) end
      end
    end
  end
  for _, a in ipairs(data.areas) do
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #a.p, 2 do
      x0, x1 = math.min(x0, a.p[i]), math.max(x1, a.p[i])
      y0, y1 = math.min(y0, a.p[i + 1]), math.max(y1, a.p[i + 1])
    end
    a.box = { x0, y0, x1, y1 }
    a.cx, a.cy = (x0 + x1) / 2, (y0 + y1) / 2
  end
  return data
end

local function inside(p, x, y)
  local c = false
  local n = #p / 2
  local j = n
  for i = 1, n do
    local xi, yi, xj, yj = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
    if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then c = not c end
    j = i
  end
  return c
end

local function seg_d2(x, y, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, ((x - x0) * dx + (y - y0) * dy) / l2)) or 0
  local qx, qy = x0 + dx * t, y0 + dy * t
  return (qx - x) ^ 2 + (qy - y) ^ 2
end

function Streets.contains(a, x, y)
  local b = a.box
  return b and x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] and inside(a.p, x, y)
end

-- plaça o parc que conté el punt (o nil)
function Streets.area_at(x, y)
  local d = load()
  if not d then return nil end
  for _, a in ipairs(d.areas) do
    local b = a.box
    if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] and inside(a.p, x, y) then return a end
  end
end

-- nom del lloc on és el punt: plaça/parc si hi és a dins, si no el carrer més proper a menys de maxd px
function Streets.name_at(x, y, maxd)
  local d = load()
  if not d then return nil end
  local a = Streets.area_at(x, y)
  if a then return a.n, 'area' end
  maxd = maxd or 40
  local best, bn = maxd * maxd, nil
  local r = math.ceil(maxd / CELL)
  local cx0, cy0 = math.floor(x / CELL), math.floor(y / CELL)
  for cy = cy0 - r, cy0 + r do
    for cx = cx0 - r, cx0 + r do
      for _, s in ipairs(grid[cy * 4096 + cx] or {}) do
        local dd = seg_d2(x, y, s[2], s[3], s[4], s[5])
        if dd < best then best, bn = dd, d.lines[s[1]].n end
      end
    end
  end
  return bn, bn and 'street' or nil
end

-- lloc amb nom (parc o plaça) per a missions: { n, cx, cy, p } o nil
function Streets.area(name)
  local d = load()
  if not d then return nil end
  for _, a in ipairs(d.areas) do if a.n == name then return a end end
end

-- carrer amb nom: punt mig del tram més llarg
function Streets.street(name)
  local d = load()
  if not d then return nil end
  local best, bl
  for _, l in ipairs(d.lines) do
    if l.n == name then
      local len = 0
      for i = 1, #l.p - 3, 2 do len = len + math.sqrt((l.p[i + 2] - l.p[i]) ^ 2 + (l.p[i + 3] - l.p[i + 1]) ^ 2) end
      if not bl or len > bl then best, bl = l, len end
    end
  end
  if not best then return nil end
  local m = math.floor(#best.p / 4) * 2 + 1
  return { n = name, cx = best.p[m], cy = best.p[m + 1] }
end

-- ---------------------------------------------------------------- cartell en canviar de zona
-- Tracker: crida-ho cada pas; avisa (callback) quan el jugador porta 0,8 s en un carrer/plaça nou.
function Streets.tracker(on_change)
  return { t = 0, cur = nil, cand = nil, cand_t = 0, on_change = on_change }
end

function Streets.track(tr, dt, x, y)
  tr.t = tr.t + dt
  if tr.t < 0.25 then return end   -- consulta 4 cops per segon
  local step = tr.t
  tr.t = 0
  local n = Streets.name_at(x, y, 40)
  if not n or n == tr.cur then tr.cand, tr.cand_t = nil, 0; return end
  if n ~= tr.cand then tr.cand, tr.cand_t = n, 0; return end
  tr.cand_t = tr.cand_t + step
  if tr.cand_t >= 0.75 then
    tr.cur, tr.cand = n, nil
    if tr.on_change then tr.on_change(n) end
  end
end

-- dades carregades (punts de reciclatge, àrees)
function Streets._data() return load() or nil end

-- per a les proves
function Streets._reset() data, grid = nil, nil end

return Streets
