-- Bassals quan plou (2026-10-05): a les caselles transitables d'asfalt, vorera, aparcament, empedrat i patis, una
-- de cada ~14 (sempre les mateixes: hash de la casella) fa un bassal que creix amb la pluja (Weather.puddles 0..1)
-- i s'asseca a poc a poc quan para. Mentre plou, cercles de gotes. Reflex blavós del cel i vora clara.
local Puddles = {}

local GROUND = { g_asphalt = true, g_urban = true, g_parking = true, g_cobble = true, g_yard = true, g_site = true,
                 g_dry = true, g_miniroad = true, g_skate = true }

local function hash(x, y)
  local n = (x * 73856093 + y * 19349663) % 2147483647
  n = (n * 1103515245 + 12345) % 2147483648
  return n / 2147483648
end

-- ¿bassal a la casella? (memòria per casella: el nom del terra no canvia)
local function spot(w, tx, ty)
  local cache = w.puddle_cache
  if not cache then cache = {}; w.puddle_cache = cache end
  local k = ty * 4096 + tx
  local v = cache[k]
  if v == nil then
    v = false
    local h = hash(tx, ty)
    if h < 0.07 then
      local name = w:tile_name('ground', tx, ty)
      local base = name and name:match('^(.-)_%d+$') or name
      local Collision = require('src.world.collision')
      if base and GROUND[base] and Collision.walk_at(w.map:cell(tx, ty), 0)
          and (w.map:tile_at('structures', tx, ty) or 0) == 0 then
        local h2 = hash(ty + 17, tx + 3)
        v = { x = tx * 16 - 2 + math.floor(h2 * 5), y = ty * 16 + 3 + math.floor(hash(tx + 9, ty) * 6),
              w = 13 + math.floor(h2 * 9), h = 6 + math.floor(hash(tx, ty + 5) * 4), ph = h2 * 10 }
      end
    end
    cache[k] = v
  end
  return v or nil
end

-- dibuix en coordenades del món (dins del translate de la càmera), després del terra i abans de les estructures
function Puddles.draw(w)
  local g = w.game
  local wx = g.weather
  local lv = wx and wx.puddles or 0
  if lv < 0.03 or not w.def.outdoor or w.id ~= 'overworld' then return end
  local cam = w.cam
  local tx0, ty0 = math.floor(cam.x / 16), math.floor(cam.y / 16)
  local tx1, ty1 = math.floor((cam.x + cam.w) / 16), math.floor((cam.y + cam.h) / 16)
  local raining = wx:is_wet()
  local t = love.timer.getTime()
  for ty = ty0, ty1 do
    for tx = tx0, tx1 do
      local p = w.map:in_bounds(tx, ty) and spot(w, tx, ty)
      if p then
        local k = math.min(1, lv * 1.3)
        local pw, ph = math.max(2, math.floor(p.w * k + 0.5)), math.max(1, math.floor(p.h * k + 0.5))
        local x, y = p.x + math.floor((p.w - pw) / 2), p.y + math.floor((p.h - ph) / 2)
        love.graphics.setColor(0.30, 0.40, 0.52, 0.55 + 0.25 * k)
        love.graphics.rectangle('fill', x + 1, y, pw - 2, ph)
        love.graphics.rectangle('fill', x, y + 1, pw, math.max(1, ph - 2))
        love.graphics.setColor(0.62, 0.72, 0.84, 0.55 * k)          -- reflex del cel a la vora de dalt
        love.graphics.rectangle('fill', x + 2, y, math.max(1, pw - 5), 1)
        if raining and pw >= 5 then                                  -- cercles de les gotes
          local c = (t * 1.6 + p.ph) % 1
          local r = math.floor(c * 3) + 1
          local cx = x + 2 + math.floor((p.ph * 7) % math.max(1, pw - 4))
          local cy = y + math.floor(ph / 2)
          love.graphics.setColor(0.85, 0.92, 1, 0.7 * (1 - c))
          love.graphics.rectangle('line', cx - r + 0.5, cy - math.max(1, r - 1) + 0.5, r * 2, math.max(1, r - 1) * 2)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Puddles
