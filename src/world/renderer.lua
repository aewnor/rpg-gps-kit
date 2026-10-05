-- Render de tiles por chunk con SpriteBatch estáticos (uno por capa y chunk, construidos una vez).
-- El agua animada va en batches propios por frame; las entidades se dibujan aparte (ver world_scene).
local Renderer = {}
Renderer.__index = Renderer

local LAYERS = { 'ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead' }
local ANIM_FRAMES = 4
local ANIM_FPS = 4
local WIND_FRAMES = 8          -- arbres que es mouen amb el vent (lots propis, cada arbre amb la seva fase)
local WIND_AMP = 1.6           -- px que es desplaça la copa

function Renderer.new(atlas_path)
  local self = setmetatable({}, Renderer)
  self.atlas = love.graphics.newImage(atlas_path)
  self.atlas:setFilter('nearest', 'nearest')
  local cols = math.floor(self.atlas:getWidth() / 16)
  local rows = math.floor(self.atlas:getHeight() / 16)
  self.quads = {}
  for i = 0, cols * rows - 1 do
    self.quads[i + 1] = love.graphics.newQuad((i % cols) * 16, math.floor(i / cols) * 16, 16, 16,
      self.atlas:getDimensions())
  end
  self.time = 0
  self.batches_built = 0
  -- piscines (aigua sense fotogrames propis): van en un lot a part que es dibuixa amb el shader d'aigua
  self.water = {}
  self.tree, self.roof = {}, {}   -- arbres (vent) i teulades (neu): van en lots a part
  local ok, man = pcall(function() return require('src.lib.json').decode(love.filesystem.read('data/tiles.json')) end)
  if ok and man and man.tiles then
    for name, t in pairs(man.tiles) do
      if name:sub(1, 5) == 'pool_' then self.water[t.id + 1] = true end
      if name:sub(1, 5) == 'tree_' then self.tree[t.id + 1] = name:sub(-4) == '_top' and 'top' or 'bot' end
      if name:sub(1, 2) == 'r_' then self.roof[t.id + 1] = true end
    end
  end
  self.snow = 0                 -- neu acumulada 0..1 (World:update_weather)
  self.wind_fps = 3
  return self
end

-- Ones i reflexos que passen per damunt de l'aigua (mar i piscines): bandes de llum en coordenades del món,
-- quantitzades al píxel perquè quedin pixel art. Només afecta els colors blavosos (l'escuma blanca no).
local WATER_SRC = [[
varying vec2 wpos;
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  wpos = vertex_position.xy;
  return transform_projection * vertex_position;
}
#endif
#ifdef PIXEL
uniform float t;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 c = Texel(tex, uv) * color;
  vec2 p = floor(wpos);
  float w1 = sin(p.x * 0.085 + p.y * 0.045 - t * 1.7);
  float w2 = sin(p.y * 0.12 - p.x * 0.035 - t * 1.15 + 1.7);
  float w3 = sin((p.x + p.y) * 0.31 + t * 2.3);
  float v = w1 * 0.55 + w2 * 0.35 + w3 * 0.10;
  float water = step(c.r + 0.06, c.b);
  float k = step(0.80, v) * 0.15 + step(0.55, v) * 0.05 - step(v, -0.75) * 0.05;
  c.rgb += water * k;
  return c;
}
#endif
]]
-- Neu (2026-10-05): sobre el terra, les teulades i les copes, taques blanques que creixen amb la neu acumulada
-- (soroll per píxel del món, estable). L'aigua (blavosa) no es neva.
local SNOW_SRC = [[
varying vec2 wpos;
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  wpos = vertex_position.xy;
  return transform_projection * vertex_position;
}
#endif
#ifdef PIXEL
uniform float amount;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 c = Texel(tex, uv) * color;
  vec2 p = floor(wpos);
  float n = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
  float m = fract(sin(dot(floor(p / 3.0), vec2(39.346, 11.135))) * 24634.6345);
  float water = step(c.r + 0.06, c.b) * step(0.30, c.b);
  float lum = dot(c.rgb, vec3(0.30, 0.59, 0.11));
  float cover = clamp(amount * 1.4 - n * 0.25 - m * 0.35, 0.0, 1.0) * (1.0 - water);
  vec3 snow = vec3(0.92, 0.95, 1.0) * (0.86 + 0.14 * lum);
  c.rgb = mix(c.rgb, snow, cover * 0.9);
  return c;
}
#endif
]]
local snow_shader, snow_tried
local function get_snow_shader()
  if not snow_tried then
    snow_tried = true
    local ok, sh = pcall(love.graphics.newShader, SNOW_SRC)
    if ok then snow_shader = sh end
  end
  return snow_shader
end

local water_shader, water_tried
local NO_WATER = os.getenv('RODA_SIN_AGUA')   -- (A/B de rendiment)
local function get_water_shader()
  if not water_tried then
    water_tried = true
    local ok, sh = pcall(love.graphics.newShader, WATER_SRC)
    if ok then water_shader = sh end
  end
  return water_shader
end

-- volteos de Tiled: bit 4 = H, 2 = V, 1 = diagonal
local function flip_params(f)
  local h, v, d = f >= 4, (f % 4) >= 2, (f % 2) == 1
  if d then
    -- diagonal = transponer; combinaciones equivalentes a rotaciones
    if h and v then return math.pi / 2, -1, 1 end
    if h then return math.pi / 2, 1, 1 end
    if v then return -math.pi / 2, 1, 1 end
    return math.pi / 2, 1, -1
  end
  return 0, h and -1 or 1, v and -1 or 1
end

function Renderer:build(map, c)
  local cs = map.chunk
  local bx, by = c.cx * cs * 16, c.cy * cs * 16
  c._b = {}
  c._anim = {}
  for _, name in ipairs(LAYERS) do
    local data = c[name]
    if data then
      local batch = love.graphics.newSpriteBatch(self.atlas, c.w * c.h, 'static')
      local flips = c.flips and c.flips[name]
      local anim_cells, water_cells, tree_cells, roof
      for i = 1, #data do
        local t = data[i]
        if t ~= 0 then
          local x = bx + ((i - 1) % c.w) * 16
          local y = by + math.floor((i - 1) / c.w) * 16
          local a = map.anim[t]
          if a then
            anim_cells = anim_cells or {}
            anim_cells[#anim_cells + 1] = { x, y, a }
          elseif name == 'ground' and self.water[t] then
            water_cells = water_cells or {}
            water_cells[#water_cells + 1] = { x, y, t }
          elseif self.tree[t] and (name == 'structures' or name == 'overhead') and not (flips and flips[i]) then
            tree_cells = tree_cells or {}
            tree_cells[#tree_cells + 1] = { x, y, t, self.tree[t] }
          elseif name == 'structures' and self.roof[t] and not (flips and flips[i]) then
            roof = roof or love.graphics.newSpriteBatch(self.atlas, 256, 'static')
            roof:add(self.quads[t], x, y)
          else
            local f = flips and flips[i]
            if f then
              local r, sx, sy = flip_params(f)
              batch:add(self.quads[t], x + 8, y + 8, r, sx, sy, 8, 8)
            else
              batch:add(self.quads[t], x, y)
            end
          end
        end
      end
      c._b[name] = batch
      if roof then c._b.roof = roof end
      if tree_cells then
        -- vent: cada fotograma, l'arbre inclinat (cisalla) segons la seva fase; el tronc (bot) poc i la copa (top)
        -- més, enganxats per la vora (la copa comença on acaba el desplaçament del tronc)
        c._wind = c._wind or {}
        c._wind[name] = {}
        for fr = 1, WIND_FRAMES do
          local wb = love.graphics.newSpriteBatch(self.atlas, #tree_cells, 'static')
          for _, tc in ipairs(tree_cells) do
            local tx, ty = math.floor(tc[1] / 16), math.floor(tc[2] / 16)
            local ph = (fr - 1 + (tx * 3 + (tc[4] == 'top' and ty + 1 or ty) * 5)) % WIND_FRAMES
            local sway = math.sin(ph / WIND_FRAMES * 2 * math.pi) * WIND_AMP
            local mid = sway * 0.35
            if tc[4] == 'top' then
              wb:add(self.quads[tc[3]], tc[1] + mid, tc[2] + 16, 0, 1, 1, 0, 16, -(sway - mid) / 16, 0)
            else
              wb:add(self.quads[tc[3]], tc[1], tc[2] + 16, 0, 1, 1, 0, 16, -mid / 16, 0)
            end
          end
          c._wind[name][fr] = wb
        end
      end
      if name == 'structures' and self.light_kind then  -- focos para el ciclo de noche
        c._lights = {}
        local th, tb = self.theme, nil
        local Themes = th and require('src.themes')
        for i = 1, #data do
          local kind = self.light_kind[data[i]]
          if kind then
            local gx, gy = (i - 1) % c.w, math.floor((i - 1) / c.w)
            c._lights[#c._lights + 1] = { bx + gx * 16 + 8, by + gy * 16 + 8, kind }
            -- adornos de temporada: junto a las puertas y en las farolas
            local list = th and (kind == 'door' and th.decor or kind == 'lamp' and th.lamp_decor)
            if list then
              local r, acc = Themes.cell_rand(c.cx * cs + gx, c.cy * cs + gy, 1), 0
              for _, d in ipairs(list) do
                acc = acc + d[2]
                if r < acc then
                  local px, py = bx + gx * 16 + (kind == 'door' and 9 or 0), by + gy * 16 + (kind == 'door' and 14 or 0)
                  tb = tb or love.graphics.newSpriteBatch(self.atlas, 64, 'static')
                  tb:add(self.quads[d[1]], px, py)
                  if th.glow[d[1]] then c._lights[#c._lights + 1] = { px + 8, py + 10, th.glow[d[1]] } end
                  break
                end
              end
            end
          end
        end
        c._b.theme = tb
      end
      if anim_cells then
        c._anim[name] = {}
        for fr = 1, ANIM_FRAMES do
          local ab = love.graphics.newSpriteBatch(self.atlas, #anim_cells, 'static')
          for _, ac in ipairs(anim_cells) do
            local frames = ac[3].frames
            ab:add(self.quads[frames[(fr - 1) % #frames + 1]], ac[1], ac[2])
          end
          c._anim[name][fr] = ab
        end
      end
      if water_cells then
        local wb = love.graphics.newSpriteBatch(self.atlas, #water_cells, 'static')
        for _, wc in ipairs(water_cells) do wb:add(self.quads[wc[3]], wc[1], wc[2]) end
        c._b.water = wb
      end
    end
  end
  if c.height then self:build_relief(map, c, bx, by) end
  -- vías vectoriales: un lienzo para el nivel 0 (con pasos inferiores) y otro para puentes
  local lines = map.lines and map.lines.chunks[c.cy * 1024 + c.cx]
  if lines then
    local items, has1, hasu = {}, false, false
    for i, idx in ipairs(lines) do
      local it = map.lines.items[idx]
      items[i] = it
      if it.l == 1 then has1 = true end
      if it.l == -1 then hasu = true end
    end
    local Vectors = require('src.world.vectors')
    local size = cs * 16
    -- textura dels camins: coordenades del món (origen del chunk) i nucli antic (empedrat)
    if map._oldtown == nil then
      local ch = map.object and map:object('poi', 'sant_bartomeu')
      map._oldtown = ch and { ch.x, ch.y, 420 } or false
    end
    Vectors.set_context({ origin = { bx, by }, oldtown = map._oldtown or nil })
    local function paint(level)
      local cv = love.graphics.newCanvas(size, size)
      cv:setFilter('nearest', 'nearest')
      love.graphics.push('all')
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.origin()
      love.graphics.translate(-bx, -by)
      Vectors.draw(items, level)
      -- las zonas rediseñadas tapan las vías originales
      if map.index.zones then
        love.graphics.setBlendMode('replace')
        love.graphics.setColor(0, 0, 0, 0)
        for _, zr in ipairs(map.index.zones) do
          if zr.poly then  -- zona poligonal: solo se tapa su forma (puede ser cóncava)
            local ok, tris = pcall(love.math.triangulate, zr.poly)
            if ok then
              for _, t in ipairs(tris) do love.graphics.polygon('fill', t) end
            else
              love.graphics.rectangle('fill', zr.x, zr.y, zr.w, zr.h)
            end
          else
            love.graphics.rectangle('fill', zr.x, zr.y, zr.w, zr.h)
          end
        end
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(1, 1, 1, 1)
      end
      love.graphics.pop()
      return cv
    end
    c._v0 = paint(0)
    if has1 then c._v1 = paint(1) end
    if hasu then c._vu = paint(-1) end   -- pasos inferiores: bajo el jugador que va por el túnel
    c._vx, c._vy = bx, by
  end
  self.batches_built = self.batches_built + 1
end

-- Relieve (desnivel): sombreado por pendiente con luz del noroeste y sombra en la base de cada cambio de
-- nivel (8 m), como si la casilla de arriba proyectara su altura. Se pinta encima del suelo y las calles.
local RELIEF_K, RELIEF_MAX = 0.035, 0.22

function Renderer:build_relief(map, c, bx, by)
  local cs = map.chunk
  local w, h = c.w, c.h
  -- alturas del chunk con un borde de 1 casilla (de los vecinos ya cargados; si no, se repite el borde)
  local E = {}
  local hc = c.height
  local function own(gx, gy) return hc[gy * w + gx + 1] % 1024 end
  local live = map.chunks.live
  local function at(gx, gy)
    if gx >= 0 and gy >= 0 and gx < w and gy < h then return own(gx, gy) end
    local tx, ty = c.cx * cs + gx, c.cy * cs + gy
    local nc = live[math.floor(ty / cs) * 1024 + math.floor(tx / cs)]
    if nc and nc.height then return nc.height[(ty % cs) * nc.w + (tx % cs) + 1] % 1024 end
    return own(math.max(0, math.min(w - 1, gx)), math.max(0, math.min(h - 1, gy)))
  end
  for gy = -1, h do
    local row = {}
    for gx = -1, w do row[gx] = at(gx, gy) end
    E[gy] = row
  end
  -- sombreado suave: un píxel por casilla (blanco cálido o violeta oscuro con alfa) en una imagen pequeña que
  -- se dibuja ampliada ×16 con filtro lineal: degradados continuos, sin cuadros
  local id = love.image.newImageData(w, h)
  local any, strips = false, {}
  for gy = 0, h - 1 do
    local r0, rm, rp = E[gy], E[gy - 1], E[gy + 1]
    for gx = 0, w - 1 do
      local code = c.coll[gy * w + gx + 1]
      if code % 4 ~= 2 then   -- el agua no se sombrea
        -- pendiente hacia el sureste: la ladera mira al noroeste (al sol) → más clara; al revés, más oscura
        local sl = (r0[gx + 1] - r0[gx - 1]) + (rp[gx] - rm[gx])
        local a = math.max(-RELIEF_MAX, math.min(RELIEF_MAX, sl * RELIEF_K))
        if a > 0.01 then id:setPixel(gx, gy, 1, 0.96, 0.85, a * 0.6); any = true
        elseif a < -0.01 then id:setPixel(gx, gy, 0.10, 0.08, 0.16, -a); any = true end
        -- base del desnivel: la casilla de arriba (norte) un nivel más alta proyecta sombra
        if math.floor(rm[gx] / 8) > math.floor(r0[gx] / 8) then strips[#strips + 1] = { gx * 16, gy * 16 } end
      end
    end
  end
  if any then
    local img = love.graphics.newImage(id)
    img:setFilter('linear', 'linear')
    c._relief_img = img
  end
  if #strips > 0 then
    local cv = love.graphics.newCanvas(cs * 16, cs * 16)
    love.graphics.push('all')
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    for _, st in ipairs(strips) do
      for k = 0, 2 do
        love.graphics.setColor(0.10, 0.08, 0.16, 0.28 * (1 - k / 3))
        love.graphics.rectangle('fill', st[1], st[2] + k * 2, 16, 2)
      end
    end
    love.graphics.pop()
    c._relief = cv
  end
  c._rx, c._ry = bx, by
end

function Renderer:draw_relief(chunks)
  for i = 1, #chunks do
    local c = chunks[i]
    if c._relief_img then love.graphics.draw(c._relief_img, c._rx + 8, c._ry + 8, 0, 16, 16, 0.5, 0.5) end
    if c._relief then love.graphics.draw(c._relief, c._rx, c._ry) end
  end
end

function Renderer.release(c)
  if c._relief then c._relief:release(); c._relief = nil end
  if c._relief_img then c._relief_img:release(); c._relief_img = nil end
  if c._b then
    for _, b in pairs(c._b) do b:release() end
    for _, frames in pairs(c._anim) do for _, b in pairs(frames) do b:release() end end
    for _, frames in pairs(c._wind or {}) do for _, b in pairs(frames) do b:release() end end
    c._wind = nil
    if c._v0 then c._v0:release() end
    if c._v1 then c._v1:release() end
    if c._vu then c._vu:release() end
    c._b, c._anim, c._v0, c._v1, c._vu, c._lights = nil, nil, nil, nil, nil, nil
  end
end

function Renderer:update(dt)
  self.time = self.time + dt
end

-- chunks visibles para la cámara (x, y = esquina superior izquierda en píxeles)
function Renderer:visible(map, cam)
  local size = map.chunk * 16
  local out = {}
  local cx0, cy0 = math.floor(cam.x / size), math.floor(cam.y / size)
  local cx1, cy1 = math.floor((cam.x + cam.w - 1) / size), math.floor((cam.y + cam.h - 1) / size)
  for cy = cy0, cy1 do
    for cx = cx0, cx1 do
      if map.chunks:valid(cx, cy) then
        local c = map.chunks:get(cx, cy)
        if not c._b then self:build(map, c) end
        out[#out + 1] = c
      end
    end
  end
  return out
end

function Renderer:draw_vectors(chunks, level)
  for i = 1, #chunks do
    local c = chunks[i]
    local cv
    if level == 1 then cv = c._v1 elseif level == -1 then cv = c._vu else cv = c._v0 end
    if cv then love.graphics.draw(cv, c._vx, c._vy) end
  end
end

function Renderer:draw_layer(chunks, name)
  local fr = math.floor(self.time * ANIM_FPS) % ANIM_FRAMES + 1
  local sh = name == 'ground' and not NO_WATER and get_water_shader()
  if sh then
    sh:send('t', self.time)
    love.graphics.setShader(sh)
    for i = 1, #chunks do
      local c = chunks[i]
      local an = c._anim.ground
      if an and an[fr] then love.graphics.draw(an[fr]) end
      if c._b.water then love.graphics.draw(c._b.water) end
    end
    love.graphics.setShader()
  end
  local snow = self.snow > 0.01 and (name == 'ground' or name == 'ground_detail' or name == 'overhead'
                                      or name == 'structures') and get_snow_shader()
  if snow then snow:send('amount', self.snow) end
  local wfr = math.floor(self.time * self.wind_fps) % WIND_FRAMES + 1
  for i = 1, #chunks do
    local c = chunks[i]
    local an = c._anim[name]
    if not sh and an and an[fr] then love.graphics.draw(an[fr]) end
    if not sh and name == 'ground' and c._b.water then love.graphics.draw(c._b.water) end
    local b = c._b[name]
    if b then
      if snow and name ~= 'structures' then love.graphics.setShader(snow) end   -- (façanes sense neu)
      love.graphics.draw(b)
      if snow then love.graphics.setShader() end
    end
    if name == 'structures' and c._b.roof then
      if snow then love.graphics.setShader(snow) end
      love.graphics.draw(c._b.roof)
      if snow then love.graphics.setShader() end
    end
    local wd = c._wind and c._wind[name]
    if wd and wd[wfr] then
      if snow and name == 'overhead' then love.graphics.setShader(snow) end
      love.graphics.draw(wd[wfr])
      if snow then love.graphics.setShader() end
    end
    if name ~= 'ground' and an and an[fr] then love.graphics.draw(an[fr]) end
  end
end

Renderer.LAYERS = LAYERS
return Renderer
