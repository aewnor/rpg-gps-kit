-- Dibujo vectorial (pixel art, sin antialias) de carreteras, caminos y ferrocarril sobre un lienzo
-- por chunk. Así las diagonales y las rotondas no salen en escalera de tiles.
local Vectors = {}

local function hex(h, a)
  return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1 }
end
-- colores de la paleta común (data/palette.json, la escribe tools/make_tiles.py desde tools/pixel.py):
-- así las calles vectoriales usan exactamente los mismos tonos que los tiles
local C = {}
do
  local ok, pal = pcall(function()
    return require('src.lib.json').decode(love.filesystem.read('data/palette.json'))
  end)
  if not ok or type(pal) ~= 'table' then
    pal = { ink = '#1f1a24', white = '#f6f1e3', white2 = '#dcd3bf', white3 = '#b2a790', asph = '#85827f',
            asph2 = '#6c6a69', asph3 = '#4a4749', ochre = '#e3b866', ochre3 = '#8a5f34', dry2 = '#a68b62',
            dry3 = '#806a4a', stone = '#c9bba0', stone2 = '#a6957a', stone3 = '#786852', sea2 = '#2e7a92',
            sea = '#4aa3b0' }
  end
  for k, v in pairs(pal) do C[k] = hex(v) end
end

local ROADS = { ROAD = true, ROAD_MAIN = true, MOTORWAY = true }

-- Textura dels camins (fase 6): en lloc del blanc pla, panot, llambordes, empedrat (nucli antic), terra o
-- grava, amb un shader que calcula el dibuix a partir de les coordenades del món. Només s'executa quan es
-- pinta el llenç d'un chunk (un cop): no costa res per fotograma. Sense shader (GPU antiga), colors plans.
local MAT = { panot = 1, llamborda = 2, empedrat = 3, terra = 4, grava = 5 }
Vectors.MAT = MAT
local SHADER_SRC = [[
uniform vec2 origin;
uniform float mat;
float hash(vec2 p) { p = mod(p, 251.0); return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 w = floor(sc + origin);
  float k = 1.0;
  if (mat < 1.5) {                       // panot: rajoles de 4 px amb junta
    vec2 m = mod(w, 4.0);
    k = (m.x < 1.0 || m.y < 1.0) ? 0.86 : 1.0 - 0.05 * hash(floor(w / 4.0));
  } else if (mat < 2.5) {                // llambordes 4×3 a trencajunts
    float row = floor(w.y / 3.0);
    float qx = w.x + mod(row, 2.0) * 2.0;
    k = (mod(qx, 4.0) < 1.0 || mod(w.y, 3.0) < 1.0) ? 0.8 : 0.98 - 0.07 * hash(vec2(floor(qx / 4.0), row));
  } else if (mat < 3.5) {                // empedrat: pedres irregulars
    vec2 c = floor(w / 3.0);
    vec2 m = mod(w, 3.0);
    float h = hash(c);
    k = ((m.x < 1.0 && h > 0.35) || (m.y < 1.0 && h < 0.65)) ? 0.74 : 0.88 + 0.14 * h;
  } else if (mat < 4.5) {                // terra amb pedretes
    float h = hash(w);
    k = 0.94 + 0.08 * hash(floor(w / 5.0));
    if (h > 0.94) k = 0.8;
    if (h < 0.03) k = 1.1;
  } else {                               // grava
    float h = hash(w);
    k = h > 0.62 ? 0.84 : (h < 0.2 ? 1.08 : 0.97);
  }
  return vec4(color.rgb * k, color.a);
}
]]
local shader, shader_tried
local function get_shader()
  if not shader_tried then
    shader_tried = true
    local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
    if ok then shader = sh end
  end
  return shader
end
-- nucli antic (al voltant de l'església de Sant Bartomeu): empedrat
local CTX = { origin = { 0, 0 } }
function Vectors.set_context(ctx) for k, v in pairs(ctx) do CTX[k] = v end end

local function material(it)
  local c = it.c
  if c == 'PATH' then return MAT.terra end
  if c == 'TRACK' then return MAT.grava end
  if c == 'PEDESTRIAN' or c == 'FOOTWAY' then
    local o = CTX.oldtown
    if o and (it.p[1] - o[1]) ^ 2 + (it.p[2] - o[2]) ^ 2 < o[3] ^ 2 then return MAT.empedrat end
    return c == 'PEDESTRIAN' and MAT.llamborda or MAT.panot
  end
end
Vectors.material = material


local PAVED = { PEDESTRIAN = true, FOOTWAY = true, STEPS = true, PLATFORM = true }

local function setc(c) love.graphics.setColor(c[1], c[2], c[3], c[4]) end

local function poly(it)
  local p = it.p
  if it.k and (p[1] ~= p[#p - 1] or p[2] ~= p[#p]) then
    local q = {}
    for i = 1, #p do q[i] = p[i] end
    q[#q + 1], q[#q + 2] = p[1], p[2]
    return q
  end
  return p
end

-- línea gruesa con extremos redondeados (los tableros de puente, con extremos rectos)
local FLAT = false
local function stroke(p, w, c)
  setc(c)
  love.graphics.setLineWidth(w)
  if #p >= 4 then love.graphics.line(p) end
  if FLAT then return end
  local r = w / 2
  love.graphics.circle('fill', p[1], p[2], r)
  love.graphics.circle('fill', p[#p - 1], p[#p], r)
end

local function textured(p, w, col, mat)
  local sh = get_shader()
  if sh then
    love.graphics.setShader(sh)
    sh:send('mat', mat)
    sh:send('origin', CTX.origin)
  end
  stroke(p, w, col)
  if sh then love.graphics.setShader() end
end

-- recorre la polilínea cada `step` px: fn(x, y, nx, ny) con la normal unitaria
local function walk(p, step, fn)
  local carry = 0
  for i = 1, #p - 3, 2 do
    local x0, y0, x1, y1 = p[i], p[i + 1], p[i + 2], p[i + 3]
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
      local ux, uy = dx / len, dy / len
      local d = carry
      while d < len do
        fn(x0 + ux * d, y0 + uy * d, -uy, ux, ux, uy)
        d = d + step
      end
      carry = d - len
    end
  end
end

-- polilínea desplazada `off` px a la izquierda (normales por vértice)
local function offset(p, off)
  local out = {}
  local n = #p / 2
  for i = 1, n do
    local x, y = p[2 * i - 1], p[2 * i]
    local ax, ay, bx, by = 0, 0, 0, 0
    if i > 1 then ax, ay = x - p[2 * i - 3], y - p[2 * i - 2] end
    if i < n then bx, by = p[2 * i + 1] - x, p[2 * i + 2] - y end
    local tx, ty = ax + bx, ay + by
    local l = math.sqrt(tx * tx + ty * ty)
    if l == 0 then tx, ty, l = 1, 0, 1 end
    out[2 * i - 1], out[2 * i] = x - ty / l * off, y + tx / l * off
  end
  return out
end

local function dashed(p, on, off, w, c)
  setc(c)
  love.graphics.setLineWidth(w)
  local period = on + off
  local acc = 0
  for i = 1, #p - 3, 2 do
    local x0, y0, x1, y1 = p[i], p[i + 1], p[i + 2], p[i + 3]
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    local d = 0
    while d < len do
      local phase = (acc + d) % period
      if phase < on then
        local seg = math.min(on - phase, len - d)
        love.graphics.line(x0 + dx / len * d, y0 + dy / len * d, x0 + dx / len * (d + seg), y0 + dy / len * (d + seg))
        d = d + seg
      else
        d = d + (period - phase)
      end
    end
    acc = acc + len
  end
end

local function rail(it, p, bridge)
  local hs = it.c == 'RAIL_HS'
  stroke(p, 16, C.stone3)
  stroke(p, 14, C.stone2)
  setc(C.ochre3)
  love.graphics.setLineWidth(2)
  walk(p, 5, function(x, y, nx, ny)
    love.graphics.line(x - nx * 6, y - ny * 6, x + nx * 6, y + ny * 6)
  end)
  local rc = hs and C.white3 or C.asph3
  setc(rc)
  love.graphics.setLineWidth(1)
  local a, b = offset(p, 4), offset(p, -4)
  if #a >= 4 then love.graphics.line(a); love.graphics.line(b) end
end

local INK_SOFT = { 0.12, 0.10, 0.14, 0.38 }
local INK_DEEP = { 0.08, 0.06, 0.10, 0.62 }

local function shifted(p, dx, dy)
  local q = {}
  for i = 1, #p, 2 do q[i], q[i + 1] = p[i] + dx, p[i + 1] + dy end
  return q
end

-- barandillas a ambos lados del tablero, con postes
local function parapet(p, w)
  for _, side in ipairs({ 1, -1 }) do
    local q = offset(p, side * (w / 2 + 2))
    if #q >= 4 then
      setc(C.stone3); love.graphics.setLineWidth(3); love.graphics.line(q)
      setc(C.white2); love.graphics.setLineWidth(1); love.graphics.line(offset(q, side * -1))
      setc(C.ink)
      walk(q, 7, function(x, y) love.graphics.rectangle('fill', math.floor(x), math.floor(y) - 1, 1, 2) end)
    end
  end
end

-- pasadas en orden; cada elemento decide si dibuja en esa pasada
local PASSES = { 'under', 'edge', 'side', 'fill', 'mark', 'rail' }

local function draw_item(it, pass, bridge)
  local c, w = it.c, it.w
  local p = poly(it)
  if bridge and pass == 'under' then
    stroke(p, w + 8, C.ink)
    stroke(p, w + 6, C.stone)
  end
  if c == 'SHADOW' then          -- sombra del puente sobre lo que cruza
    if pass == 'under' then stroke(shifted(p, 0, 7), w + 6, INK_SOFT) end
    return
  elseif c == 'PARAPET' then
    if pass == 'rail' then parapet(p, w) end
    return
  elseif c == 'SHADE' then        -- boca del paso inferior: oscuro bajo lo que pasa por encima
    if pass == 'mark' then stroke(p, w + 2, INK_DEEP) end
    return
  elseif c == 'ZEBRA' then        -- paso de peatones
    if pass == 'mark' then
      setc(C.white); love.graphics.setLineWidth(2)
      walk(p, 4, function(x, y, nx, ny, ux, uy)
        love.graphics.line(x - nx * w / 2, y - ny * w / 2, x + nx * w / 2, y + ny * w / 2)
      end)
    end
    return
  end
  if pass == 'under' then
    if c == 'TORRENT' then
      -- lecho de torrente: talud oscuro, grava y un hilo de agua (no se puede cruzar a pie)
      stroke(p, w + 6, C.stone3); stroke(p, w - 2, C.stone2); stroke(p, w - 10, C.stone)
      stroke(p, math.max(2, w - 24), C.sea2)
    elseif c == 'STREAM' then
      stroke(p, w, C.stone); stroke(p, math.max(2, w - 6), C.sea2)
    elseif c == 'PATH' then
      textured(p, w, C.dry2, MAT.terra)
    elseif c == 'TRACK' then
      stroke(p, w, C.dry3); textured(p, math.max(2, w - 8), C.stone2, MAT.grava)
    end
  elseif pass == 'edge' then
    if ROADS[c] then stroke(p, w + 2, C.white3)
    elseif PAVED[c] then stroke(p, w + 2, C.stone2) end
  elseif pass == 'side' then
    if c == 'ROAD' or c == 'ROAD_MAIN' then stroke(p, w, C.white2) end
  elseif pass == 'fill' then
    -- acera (lado), bordillo y calzada
    if c == 'ROAD' then stroke(p, math.max(4, w - 10), C.stone2); stroke(p, math.max(4, w - 12), C.asph)
    elseif c == 'ROAD_MAIN' then stroke(p, math.max(4, w - 10), C.stone2); stroke(p, math.max(4, w - 12), C.asph2)
    elseif c == 'MOTORWAY' then stroke(p, w, C.asph3)
    elseif c == 'PEDESTRIAN' or c == 'FOOTWAY' then
      local m = material(it)
      textured(p, w, m == MAT.empedrat and C.stone2 or (m == MAT.llamborda and C.stone or C.white2), m)
    elseif c == 'STEPS' then stroke(p, w, C.stone)
    elseif c == 'PLATFORM' then stroke(p, w, C.white2) end
  elseif pass == 'mark' then
    if c == 'ROAD_MAIN' then dashed(p, 6, 6, 1, C.white)
    elseif c == 'MOTORWAY' then dashed(p, 8, 8, 1, C.white)
    elseif c == 'STEPS' then
      setc(C.stone3); love.graphics.setLineWidth(1)
      walk(p, 4, function(x, y, nx, ny)
        love.graphics.line(x - nx * w / 2, y - ny * w / 2, x + nx * w / 2, y + ny * w / 2)
      end)
    end
  elseif pass == 'rail' then
    if c == 'RAIL' or c == 'RAIL_HS' then rail(it, p, bridge) end
  end
end

-- items: lista de líneas (ya ordenadas por nivel y clase); level: qué nivel dibujar
function Vectors.draw(items, level)
  love.graphics.setLineStyle('rough')
  love.graphics.setLineJoin('bevel')
  local bridge = level == 1
  FLAT = bridge
  for _, pass in ipairs(PASSES) do
    for _, it in ipairs(items) do
      local ok = it.l == level
      -- pasos inferiores: solo los cortos se ven (en su propio lienzo, bajo lo que cruzan)
      if level == -1 and ((it.len or 0) >= 600 or pass == 'rail') then ok = false end
      if ok then draw_item(it, pass, bridge) end
    end
  end
  FLAT = false
  love.graphics.setColor(1, 1, 1, 1)
end

function Vectors.prepare(lines)
  for _, it in ipairs(lines.items) do
    local p, len = it.p, 0
    for i = 1, #p - 3, 2 do len = len + math.sqrt((p[i + 2] - p[i]) ^ 2 + (p[i + 3] - p[i + 1]) ^ 2) end
    it.len = len
  end
end

return Vectors
