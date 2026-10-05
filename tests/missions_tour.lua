-- Recorrido de los objetivos de todas las misiones (love . --test=tests/missions_tour.lua --mute):
-- cada objetivo de cada paso se resuelve como en el juego (Town.resolve), se comprueba que hay camino a pie
-- desde el punto de inicio y se guarda una captura del sitio (tour_<misión>_<paso>.png en el directorio de
-- datos de LÖVE). Los objetivos de personajes del perfil, casa, cartera y «nearest» dependen de la partida.
return function(api)
  local Town = require('src.systems.town')
  local g = api.scene().game
  local w = api.scene()
  local defs = Town.defs(g)
  local seen, n_ok, n_bad = {}, 0, 0
  local shots = os.getenv('RODA_TOUR_SHOTS') ~= '0'
  -- sin misiones activas ni diálogos: al teletransportarse no se completa nada ni se congela la escena
  local q = require('src.systems.missions').state(g.state)
  for id in pairs(defs.by_id) do q.done[id] = true end
  q.active = nil
  api.talk_through()
  local start = { w.player.body.x, w.player.body.y }
  for _, m in ipairs(defs.order) do
    for i, s in ipairs(m.steps) do
      local t = s.target
      if t and not seen[t] and not t:match('^friend') and not t:match('^nearest') and t ~= 'home' and t ~= 'wallet'
          and not t:match('^boss') and not t:match('{') and not s.inside then
        seen[t] = true
        local r = Town.resolve(w, t)
        if not r then
          api.check(false, 'objetivo ' .. t .. ' (' .. m.id .. ') se resuelve')
          n_bad = n_bad + 1
        else
          -- cargar la zona y recalcular (las áreas se afinan cuando el chunk está cargado)
          w.player.body.x, w.player.body.y = r.x, r.y + 24
          api.wait(20)
          r = Town.resolve(w, t) or r
          w.player.body.x, w.player.body.y = start[1], start[2]
          api.wait(2)
          local gx, gy = math.floor(r.x / 16), math.floor(r.y / 16)
          local path = api.path_to(function(x, y) return math.abs(x - gx) <= 2 and math.abs(y - gy) <= 2 end)
          api.check(path ~= nil, string.format('camino a %s (%s, casilla %d,%d)', t, m.id, gx, gy))
          if path then n_ok = n_ok + 1 else n_bad = n_bad + 1 end
          if shots then
            w.player.body.x, w.player.body.y = r.x, r.y + 20
            api.wait(30)
            api.talk_through()
            local name = ('tour_' .. m.id .. '_' .. i .. '.png')
            local done = false
            love.graphics.captureScreenshot(function(data) data:encode('png', name); done = true end)
            for _ = 1, 300 do if done then break end; api.wait(1) end   -- la captura llega al dibujar
            print('[test] captura ' .. name .. ' ' .. t)
            w.player.body.x, w.player.body.y = start[1], start[2]
            api.wait(5)
          end
        end
      end
    end
  end
  -- objetivos fijos de las plantillas de familia y amigos y de la cadena (sin personajes del perfil no se
  -- generan): solo camino, sin captura
  for _, ch in ipairs(g.missions_data.chapters) do
    local tpls = {}
    for _, key in ipairs({ 'templates', 'pair_templates' }) do
      for k, t in pairs(ch[key] or {}) do tpls[#tpls + 1] = { k, t } end
    end
    if ch.chain then
      tpls[#tpls + 1] = { 'chain.slot', ch.chain.slot }
      for _, p in ipairs(ch.chain.places or {}) do tpls[#tpls + 1] = { 'chain.places', { steps = { { target = p.target } } } } end
      for _, f in ipairs(ch.chain.fallback or {}) do tpls[#tpls + 1] = { 'chain.fallback', { steps = { { target = f.target } } } } end
    end
    for _, kt in ipairs(tpls) do
      for _, st in ipairs(kt[2].steps or {}) do
        local t = st.target
        if t and not seen[t] and t:match('^(%w+):') and not t:match('{') and not t:match('^friend') and not t:match('^nearest') then
          seen[t] = true
          local r = Town.resolve(w, t)
          if r then
            w.player.body.x, w.player.body.y = r.x, r.y + 24
            api.wait(20)
            r = Town.resolve(w, t) or r
            w.player.body.x, w.player.body.y = start[1], start[2]
            api.wait(2)
          end
          local gx, gy = r and math.floor(r.x / 16), r and math.floor(r.y / 16)
          local path = r and api.path_to(function(x, y) return math.abs(x - gx) <= 2 and math.abs(y - gy) <= 2 end)
          api.check(path ~= nil, string.format('camino a %s (plantilla %s.%s)', t, ch.id, kt[1]))
          if path then n_ok = n_ok + 1 else n_bad = n_bad + 1 end
        end
      end
    end
  end
  print(string.format('[test] objetivos con camino: %d · sin camino o sin resolver: %d', n_ok, n_bad))
end
