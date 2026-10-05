-- Polilínea dirigida con distancia acumulada: posición, ángulo y nivel a una distancia `s`.
local Route = {}
Route.__index = Route

function Route.new(obj)
  local self = setmetatable({}, Route)
  self.name = obj.name
  self.pts = obj.points
  self.cum = { 0 }
  for i = 2, #self.pts do
    local a, b = self.pts[i - 1], self.pts[i]
    self.cum[i] = self.cum[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
  end
  self.length = self.cum[#self.cum]
  local lv = {}
  for v in tostring(obj.props.levels or ''):gmatch('-?%d+') do lv[#lv + 1] = tonumber(v) end
  self.levels = lv
  self.stops = {}
  for v in tostring(obj.props.stops or ''):gmatch('%d+') do
    self.stops[#self.stops + 1] = self.cum[tonumber(v) + 1]
  end
  table.sort(self.stops)
  self.label = obj.props.label
  return self
end

-- índice del segmento que contiene s (búsqueda binaria)
function Route:segment(s)
  local lo, hi = 1, #self.cum - 1
  if s <= 0 then return 1 end
  if s >= self.length then return hi end
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if self.cum[mid] <= s then lo = mid else hi = mid - 1 end
  end
  return lo
end

function Route:at(s)
  local i = self:segment(s)
  local a, b = self.pts[i], self.pts[i + 1]
  local seg = self.cum[i + 1] - self.cum[i]
  local t = seg > 0 and (s - self.cum[i]) / seg or 0
  t = math.max(0, math.min(1, t))
  local x, y = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
  local ang = math.atan2(b[2] - a[2], b[1] - a[1])
  local la, lb = self.levels[i] or 0, self.levels[i + 1] or 0
  local level = (la ~= 0 and la) or lb
  if la ~= 0 and lb ~= 0 and la ~= lb then level = 0 end
  return x, y, ang, level
end

-- distancia a lo largo de la ruta del punto más cercano a (px, py)
function Route:project(px, py)
  local best, bs = math.huge, 0
  for i = 1, #self.pts - 1 do
    local a, b = self.pts[i], self.pts[i + 1]
    local vx, vy = b[1] - a[1], b[2] - a[2]
    local l2 = vx * vx + vy * vy
    local t = l2 > 0 and math.max(0, math.min(1, ((px - a[1]) * vx + (py - a[2]) * vy) / l2)) or 0
    local qx, qy = a[1] + vx * t, a[2] + vy * t
    local d = (qx - px) ^ 2 + (qy - py) ^ 2
    if d < best then best, bs = d, self.cum[i] + math.sqrt(l2) * t end
  end
  return bs, math.sqrt(best)
end

-- orientación cuantizada para elegir sprite: 'h', 'v', 'd1' (\), 'd2' (/) y si va «al revés»
function Route.orient(ang)
  local deg = math.deg(ang) % 360
  local reverse = false
  if deg >= 180 then deg = deg - 180; reverse = true end
  -- deg en [0, 180): 0 = este, 90 = sur (y hacia abajo)
  if deg < 22.5 or deg >= 157.5 then
    if deg >= 157.5 then reverse = not reverse end
    return 'h', reverse
  elseif deg < 67.5 then return 'd1', reverse
  elseif deg < 112.5 then return 'v', reverse
  else return 'd2', reverse end
end

return Route
