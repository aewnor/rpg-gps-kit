-- Misiones con muchos amigos y familiares (love . --test=tests/friends_flow.lua --mute): 12 personajes con casa,
-- la brújula resuelve sus objetivos, el diario lista las misiones y se desplaza, y la cadena «Reuneix la colla» se completa.
return function(api)
  local Town = require('src.systems.town')
  local Missions = require('src.systems.missions')
  local Profile = require('src.profile')
  local g = api.scene().game
  g.dev.turbo = 1
  api.wait(5)
  local w = api.scene()
  local st = g.state
  local roles = { 'amiga', 'amic', 'avia', 'avi', 'tieta', 'tiet', 'cosina', 'cosi' }
  local fr = {}
  for i = 1, Profile.MAX_FRIENDS do
    fr[i] = { id = 'x' .. i, name = 'Amic' .. i, role = roles[(i - 1) % #roles + 1],
              home = { scene = 'overworld', tile_x = 560 + i * 3, tile_y = 840 } }
  end
  g.profile = { name = 'Nena', friends = fr }
  local b = api.player().body
  g.home = g.home or { x = b.x, y = b.y, tx = math.floor(b.x / 16), ty = math.floor(b.y / 16) }
  local defs = Town.defs(g)
  local n = #fr
  api.check(defs.by_id.colla_final and defs.by_id.colla_final.steps[1].count == math.min(n, 6), 'la colla agafa com a molt 6 amics (' .. n .. ' al perfil)')
  local bad
  for _, m in ipairs(defs.order) do
    for _, s in ipairs(m.steps) do
      if s.target and not s.target:find('^boss:') and s.target ~= 'wallet' and s.target ~= 'service:escola' then   -- (escola se coloca en ejecución)
        local ok, p = pcall(Town.resolve, w, s.target)
        if not ok or not p then bad = m.id .. ' → ' .. s.target end
      end
    end
  end
  api.check(not bad, 'la brúixola resol tots els objectius (' .. tostring(bad) .. ')')
  local fh = Town.resolve(w, 'friendhome:x1')
  api.check(fh and fh.label == 'Casa de Amic1', 'friendhome: apunta a la casa del personatge')

  -- diari: tot a punt i amb molta llista
  local q = Missions.state(st)
  st.char_level = 9
  for _, m in ipairs(defs.by_chapter.poble.missions) do q.done[m.id] = true end
  q.active = nil
  g:open_journal()
  api.wait(5)
  local jr = g.menu
  api.check(#jr.rows > 12, 'el diari té més files que les que caben (' .. #jr.rows .. ')')
  jr.sel = #jr.rows
  for _ = 1, #jr.rows do if jr.rows[jr.sel].m then break end jr.sel = jr.sel - 1 end
  api.wait(3)
  local ok = pcall(function() jr:draw() end)
  api.check(ok, 'el diari es dibuixa amb la darrera missió seleccionada (scroll)')
  jr.sel = 1
  for _ = 1, 3 do jr:update(1 / 60, { right = true }, {}) end
  api.check(jr.rows[jr.sel] and jr.rows[jr.sel].m, '</> salta de capítol i deixa una missió seleccionada')
  g:close_menu()

  -- cadena principal: parlar amb cada amic, anar al lloc, tornar, i lliurar els fragments
  local h = Town.hooks(w)
  for _, m in ipairs(defs.by_chapter.colla.missions) do
    if m.id ~= 'colla_final' then
      Missions.activate(defs, st, m.id, h)
      for _ = 1, #m.steps do
        local _, s = Missions.current(defs, st)
        if not s then break end
        if s.type == 'talk' then Missions.event(defs, st, 'talk', { target = s.target }, h)
        else Missions.event(defs, st, 'arrive', {}, h) end
      end
      api.talk_through()
    end
  end
  api.check((st.inventory.fragment_mapa or 0) == math.min(n, 6), 'un fragment del mapa per amic (' .. tostring(st.inventory.fragment_mapa) .. ')')
  Missions.activate(defs, st, 'colla_final', h)
  Missions.event(defs, st, 'talk', { target = 'service:ajuntament' }, h)
  api.talk_through()
  api.check(q.done.colla_final and (st.inventory.mapa_muntanya or 0) == 1 and not st.inventory.fragment_mapa, 'cadena acabada: mapa de muntanya i fragments gastats')
end
