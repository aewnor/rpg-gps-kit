-- Recortes del mapa real a 1:1 (comprobación visual): love . --test=tests/map_crop.lua --mute
-- RODA_CROPS='nombre,x,y,w,h;…' cambia los recortes (p. ej. zonas reconocibles, tools/zonas_reconocibles.py).
-- Guarda crop_<nombre>.png con ground, vías, detalle, estructuras y cubiertas de la zona.
return function(api)
  local g = api.scene().game
  local map = g:get_map('overworld')
  local r = g.renderer
  local spots = {
    { 'escola', 560, 844, 30, 28 }, { 'silena', 718, 766, 30, 30 }, { 'urba', 315, 1235, 34, 26 },
    { 'cucurull', 684, 792, 34, 24 }, { 'cova', 302, 834, 36, 34 }, { 'cim', 540, 24, 36, 34 },
  }
  if os.getenv('RODA_CROPS') then
    spots = {}
    for item in os.getenv('RODA_CROPS'):gmatch('[^;]+') do
      local n, x, y, w, h = item:match('([%w_]+),(%d+),(%d+),(%d+),(%d+)')
      if n then spots[#spots + 1] = { n, tonumber(x), tonumber(y), tonumber(w), tonumber(h) } end
    end
  end
  for _, sp in ipairs(spots) do
    local x0, y0, w, h = sp[2] * 16, sp[3] * 16, sp[4] * 16, sp[5] * 16
    for cy = math.floor(sp[3] / 32), math.floor((sp[3] + sp[5]) / 32) do
      for cx = math.floor(sp[2] / 32), math.floor((sp[2] + sp[4]) / 32) do map.chunks:get(cx, cy) end
    end
    local cv = love.graphics.newCanvas(w, h)
    love.graphics.push('all')
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.origin()
    love.graphics.translate(-x0, -y0)
    local chunks = r:visible(map, { x = x0, y = y0, w = w, h = h })
    for _, c in ipairs(chunks) do if not c.batches then r:build(map, c) end end
    r:draw_layer(chunks, 'ground'); r:draw_vectors(chunks, 0); r:draw_layer(chunks, 'ground_detail')
    r:draw_relief(chunks)
    r:draw_layer(chunks, 'structures'); r:draw_layer(chunks, 'cover_low'); r:draw_layer(chunks, 'overhead')
    love.graphics.pop()
    cv:newImageData():encode('png', 'crop_' .. sp[1] .. '.png')
    print('[test] recorte', sp[1])
    api.wait(1)
  end
end
