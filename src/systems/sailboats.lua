-- Velers que naveguen pel mar (2026-10-05). tools/decorate_map.py (sail_lanes) deixa objectes 'sailboat' amb un
-- circuit tancat de punts en mar obert; aquí van d'un punt al següent a poc a poc, girant suau, i es dibuixen
-- amb la fulla sailboat (24 × 24, 8 rumbs × 2 colors de vela). Fora de la càmera també es mouen (és barat).
local Sailboats = {}
Sailboats.__index = Sailboats

function Sailboats.new(map)
  local self = setmetatable({ boats = {} }, Sailboats)
  for _, o in ipairs(map:objects_of('sailboat')) do
    local pts = {}
    for x, y in tostring(o.props.path or ''):gmatch('(%-?%d+),(%-?%d+)') do pts[#pts + 1] = { tonumber(x), tonumber(y) } end
    if #pts >= 2 then
      self.boats[#self.boats + 1] = { pts = pts, i = 2, x = pts[1][1], y = pts[1][2], ang = 0,
                                      speed = o.props.speed or 18, color = o.props.color or 1, t = 0 }
    end
  end
  return self
end

function Sailboats:update(dt)
  for _, b in ipairs(self.boats) do
    local p = b.pts[b.i]
    local dx, dy = p[1] - b.x, p[2] - b.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 6 then
      b.i = b.i % #b.pts + 1
    else
      local want = math.atan2(dy, dx)
      local diff = (want - b.ang + math.pi) % (2 * math.pi) - math.pi
      b.ang = b.ang + math.max(-0.6 * dt, math.min(0.6 * dt, diff))   -- gira com un veler: a poc a poc
      local k = math.max(0.35, math.cos(diff))
      b.x = b.x + math.cos(b.ang) * b.speed * k * dt
      b.y = b.y + math.sin(b.ang) * b.speed * k * dt
    end
    b.t = b.t + dt
  end
end

-- add(y, fn): llista d'ordre de dibuix del món; sheet = { img, quads } (8 × 2)
function Sailboats:draw(add, cam, sheet, ox, oy)
  if not sheet then return end
  for _, b in ipairs(self.boats) do
    if cam:visible(b.x - 28, b.y - 28, 56, 56) then
      add(b.y + 4, function()
        local dir = math.floor(((b.ang % (2 * math.pi)) / (math.pi / 4)) + 0.5) % 8
        local bob = math.floor(math.sin(b.t * 2) + 0.5)
        love.graphics.draw(sheet.img, sheet.quads[(b.color - 1) * 8 + dir + 1],   -- al doble: un veler fa ~10 m
          math.floor(b.x - 24 - ox + 0.5), math.floor(b.y - 24 - oy + bob + 0.5), 0, 2, 2)
      end)
    end
  end
end

return Sailboats
