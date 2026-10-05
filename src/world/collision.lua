-- Colisión AABB contra la rejilla por niveles y contra bloqueadores dinámicos.
-- Lua puro (sin love.*) para poder probarlo con luajit. Misma regla que tools/walkgraph.py.
--
-- Código de celda: bits 0-1 tipo a nivel 0 (0 transitable, 1 sólido, 2 agua, 3 peligro),
-- 4 = transitable a nivel 1, 8 = transitable a nivel -1, 16 = rampa, 32 = pendiente de revisión.
local bit = require('src.lib.bitops')
local band = bit.band

local Collision = {}
local TILE = 16
local MAX_STEP = 4 -- px por subpaso: menor que la mitad del collider, evita atravesar paredes

function Collision.walk_at(code, level)
  if level == 0 then return band(code, 3) == 0 and band(code, 32) == 0 end
  if level == 1 then return band(code, 4) ~= 0 end
  return band(code, 8) ~= 0
end
local walk_at = Collision.walk_at

function Collision.is_ramp(code) return band(code, 16) ~= 0 end

function Collision.ramp_level(code)
  if band(code, 4) ~= 0 then return 1 end
  if band(code, 8) ~= 0 then return -1 end
  return 0
end

-- nivel resultante al pasar el centro de la celda c a la celda n (nil si no se puede)
function Collision.step_level(c, n, level)
  if band(n, 16) ~= 0 then
    if walk_at(n, level) then return level end
    local rl = Collision.ramp_level(n)
    if rl ~= 0 and walk_at(n, rl) then return rl end
    if walk_at(n, 0) then return 0 end
    return nil
  end
  if band(c, 16) ~= 0 then
    local rl = Collision.ramp_level(c)
    if rl ~= 0 and walk_at(n, rl) then return rl end
    if walk_at(n, 0) then return 0 end
    if walk_at(n, level) then return level end
    return nil
  end
  if walk_at(n, level) then return level end
  return nil
end

-- ¿puede la caja ocupar esta celda estando el cuerpo a `level` con su centro en `center_code`?
local function passable(code, level, center_code)
  if walk_at(code, level) then return true end
  if band(code, 16) ~= 0 then
    return walk_at(code, 0) or walk_at(code, Collision.ramp_level(code))
  end
  if band(center_code, 16) ~= 0 then
    return walk_at(code, 0) or walk_at(code, Collision.ramp_level(center_code))
  end
  return false
end

local function box(body, x, y)
  return x - body.w / 2, y - body.h / 2, x + body.w / 2, y + body.h / 2
end

local function overlaps(ax0, ay0, ax1, ay1, b)
  return ax0 < b.x + b.w and ax1 > b.x and ay0 < b.y + b.h and ay1 > b.y
end

-- Desnivel: se puede pasar de la casilla (fx, fy) a (tx, ty) si la diferencia de nivel de terreno no supera
-- body.max_slope (1 por defecto: rampas suaves de las calles; los bordes de roca ya son sólidos). En
-- puentes, túneles y rampas no se aplica (el tablero no sigue el terreno). Los vehículos (body.no_stairs)
-- tampoco pueden subir escaleras. Mapas sin capa de altura: siempre se puede.
function Collision.can_traverse(body, map, fx, fy, tx, ty)
  if not map.height_at or (fx == tx and fy == ty) or body.level ~= 0 then return true end
  local fc, tc = map:cell(fx, fy), map:cell(tx, ty)
  if band(fc, 28) ~= 0 or band(tc, 28) ~= 0 then return true end   -- bits 4, 8, 16: puente, túnel, rampa
  local hf = map:height_at(fx, fy)
  local ht, surf = map:height_at(tx, ty)
  if body.no_stairs and surf == 3 then return false end
  local d = math.abs(math.floor(ht / 8) - math.floor(hf / 8))
  return d <= (body.max_slope or 1)
end

-- ¿la caja del cuerpo en (x, y) es válida? blockers: lista de rects {x,y,w,h} dinámicos
function Collision.fits(body, x, y, map, blockers, from_x, from_y)
  local x0, y0, x1, y1 = box(body, x, y)
  local cx, cy = math.floor(body.x / TILE), math.floor(body.y / TILE)
  if not Collision.can_traverse(body, map, cx, cy, math.floor(x / TILE), math.floor(y / TILE)) then return false end
  local center = map:cell(cx, cy)
  for ty = math.floor(y0 / TILE), math.floor((y1 - 0.001) / TILE) do
    for tx = math.floor(x0 / TILE), math.floor((x1 - 0.001) / TILE) do
      if not passable(map:cell(tx, ty), body.level, center) then return false end
    end
  end
  if blockers then
    local fx0, fy0, fx1, fy1 = box(body, from_x or body.x, from_y or body.y)
    for i = 1, #blockers do
      local b = blockers[i]
      if b ~= body.self_blocker and overlaps(x0, y0, x1, y1, b) and not overlaps(fx0, fy0, fx1, fy1, b) then
        return false, b
      end
    end
  end
  return true
end

local function update_level(body, map, ox, oy)
  local otx, oty = math.floor(ox / TILE), math.floor(oy / TILE)
  local ntx, nty = math.floor(body.x / TILE), math.floor(body.y / TILE)
  if otx ~= ntx or oty ~= nty then
    local lv = Collision.step_level(map:cell(otx, oty), map:cell(ntx, nty), body.level)
    if lv then body.level = lv end
  end
end

-- Mueve el cuerpo resolviendo X y luego Y. Devuelve true si se movió en cada eje.
function Collision.move(body, dx, dy, map, blockers)
  local moved_x, moved_y = false, false
  local hit
  local n = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / MAX_STEP))
  local sx, sy = dx / n, dy / n
  for _ = 1, n do
    if sx ~= 0 then
      local ok, b = Collision.fits(body, body.x + sx, body.y, map, blockers)
      if ok then
        local ox = body.x
        body.x = body.x + sx
        update_level(body, map, ox, body.y)
        moved_x = true
      else
        hit = hit or b or 'map'
        -- acercarse al obstáculo píxel a píxel (sin atravesarlo)
        local s = sx > 0 and 1 or -1
        local rem = math.abs(sx)
        while rem >= 1 and Collision.fits(body, body.x + s, body.y, map, blockers) do
          local ox = body.x
          body.x = body.x + s
          update_level(body, map, ox, body.y)
          rem = rem - 1
        end
        sx = 0
      end
    end
    if sy ~= 0 then
      local ok, b = Collision.fits(body, body.x, body.y + sy, map, blockers)
      if ok then
        local oy = body.y
        body.y = body.y + sy
        update_level(body, map, body.x, oy)
        moved_y = true
      else
        hit = hit or b or 'map'
        local s = sy > 0 and 1 or -1
        local rem = math.abs(sy)
        while rem >= 1 and Collision.fits(body, body.x, body.y + s, map, blockers) do
          local oy = body.y
          body.y = body.y + s
          update_level(body, map, body.x, oy)
          rem = rem - 1
        end
        sy = 0
      end
    end
  end
  return moved_x, moved_y, hit
end

-- Corrección de esquinas: si el movimiento en un eje se bloquea por poco, deslizar en el otro
function Collision.slide_assist(body, dx, dy, map, blockers, tolerance)
  tolerance = tolerance or 8
  if dx ~= 0 and dy == 0 then
    for off = 1, tolerance do
      for _, s in ipairs({ -1, 1 }) do
        if Collision.fits(body, body.x + dx, body.y + s * off, map, blockers) and
           Collision.fits(body, body.x, body.y + s * off, map, blockers) then
          return 0, s * math.min(math.abs(dx), 1)
        end
      end
    end
  elseif dy ~= 0 and dx == 0 then
    for off = 1, tolerance do
      for _, s in ipairs({ -1, 1 }) do
        if Collision.fits(body, body.x + s * off, body.y + dy, map, blockers) and
           Collision.fits(body, body.x + s * off, body.y, map, blockers) then
          return s * math.min(math.abs(dy), 1), 0
        end
      end
    end
  end
  return 0, 0
end

return Collision
