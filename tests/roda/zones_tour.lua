-- Capturas de los lugares de las misiones y monumentos tal como los ve el jugador
-- (love . --test=tests/zones_tour.lua --mute): guarda zone_<nombre>.png en el directorio de datos de LÖVE.
-- RODA_ZONES='nombre=objetivo;…' cambia la lista (objetivo: service:x, area:x o x,y en casillas).
return function(api)
  local Town = require('src.systems.town')
  local g = api.scene().game
  local w = api.scene()
  g.dev.turbo = 1
  local q = require('src.systems.missions').state(g.state)
  for id in pairs(Town.defs(g).by_id) do q.done[id] = true end
  q.active = nil
  api.talk_through()
  local zones = {
    { 'escola', 'service:escola' }, { 'ajuntament', 'service:ajuntament' }, { 'policia', 'service:policia' },
    { 'metge', 'service:metge' }, { 'biblioteca', 'service:biblioteca' }, { 'correus', 'service:correus' },
    { 'parc_roda', 'area:Parc Roda de Berà' }, { 'parc_rodoreda', 'area:Parc Mercé Rodoreda' },
    { 'parc_navas', 'area:Parc de Las Navas de Tolosa' }, { 'parc_silena', 'area:Parc de la Silena' },
    { 'placa_esglesia', "area:Plaça de l'Església" }, { 'placa_sardana', 'area:Plaça de la Sardana' },
    { 'arc', '921,1162' }, { 'roc', '1171,1299' }, { 'sant_bartomeu', '611,803' }, { 'ermita', '989,1348' },
    { 'port', 'area:Port de Roda de Berà' }, { 'port_moll', '1262,1262' }, { 'port_bocana', '1214,1352' },
    { 'poliesportiu', '678,816' }, { 'cap_parc', '590,862' },
    -- llocs que va revisar en el pare amb coordenades reals (2026-10-04)
    { 'parking_ajuntament', '663,817' }, { 'escola_cucurull', '701,807' }, { 'hipica', '679,1096' },
    { 'benzinera_petrocat', '690,1240' }, { 'hivernacles', '808,1227' }, { 'bonpreu', '1107,1045' },
    { 'benzinera_repsol', '1331,1021' }, { 'leroy', '1351,1013' }, { 'garden', '911,1158' },
  }
  if os.getenv('RODA_ZONES') then
    zones = {}
    for item in os.getenv('RODA_ZONES'):gmatch('[^;]+') do
      local n, t = item:match('^([%w_]+)=(.+)$')
      if n then zones[#zones + 1] = { n, t } end
    end
  end
  if os.getenv('RODA_ZOOM') then api.press('view'); api.wait(5) end   -- vista allunyada (tecla N)
  for _, z in ipairs(zones) do
    local name, t = z[1], z[2]
    local x, y
    local tx, ty = t:match('^(%d+),(%d+)$')
    if tx then
      x, y = tonumber(tx) * 16 + 8, tonumber(ty) * 16 + 8
    else
      local r = Town.resolve(w, t)
      if r then
        w.player.body.x, w.player.body.y = r.x, r.y + 24
        api.wait(20)
        r = Town.resolve(w, t) or r
        x, y = r.x, r.y + 20
      end
    end
    if not x then
      print('[test] SIN DESTINO ' .. name .. ' ' .. t)
    else
      local nx, ny = g:nearest_walkable('overworld', x, y, 0, 12)
      w.player.body.x, w.player.body.y = nx or x, ny or y
      api.wait(40)
      api.talk_through()
      local file, done = 'zone_' .. name .. '.png', false
      love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
      for _ = 1, 300 do if done then break end; api.wait(1) end
      print(string.format('[test] captura %s %s (%d,%d)', file, t, math.floor(w.player.body.x / 16), math.floor(w.player.body.y / 16)))
    end
  end
end
