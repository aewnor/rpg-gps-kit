-- Zoom del mapa (M, diari, selector de casa), duplicar perfil i pares dins del joc
-- (love . --test=tests/map_zoom_flow.lua --mute). Els perfils són en memòria (src/devtools.lua).
return function(api)
  local Input = require('src.input')
  local Profile = require('src.profile')
  local Z = require('src.ui.mapzoom')
  local g = api.scene().game
  g.dev.turbo = 1

  -- mapa M: botons, tecles, roda i clic
  g:open_menu('map'); api.wait(2)
  local m = g.menu
  local v = m:map_view()
  api.check(v.i == 1, 'el mapa comença sense zoom')
  local cx, cy = v.fx, v.fy
  m:update(1 / 60, { zoom_in = true }, {})
  api.check(v.i == 2, 'zoom_in acosta el mapa')
  for _ = 1, 10 do m:update(1 / 60, { zoom_in = true }, {}) end
  api.check(v.i == #Z.STEPS, 'el zoom té un màxim')
  for _ = 1, 10 do m:update(1 / 60, { zoom_out = true }, {}) end
  api.check(v.i == 1, 'el zoom té un mínim')
  api.wait(2)
  -- clic al botó +
  local b = v.btns.zoom_in
  g.view = g.view or { s = 1, ox = 0, oy = 0 }
  Input.clear()
  g:pointer(g.view.ox + (b.x + 4) * g.view.s, g.view.oy + (b.y + 4) * g.view.s)
  api.wait(2)
  api.check(g.menu == m and m:map_view().i == 2, 'clicar el botó + fa zoom')
  Input.wheel(-1); api.wait(2)
  api.check(m:map_view().i == 1, 'la roda del ratolí allunya')
  g:close_menu()

  -- diari de missions
  g:open_journal(false); api.wait(2)
  local j = g.menu
  j:update(1 / 60, { zoom_in = true }, {})
  api.check(j.view.i == 2, 'el diari també fa zoom')
  g:close_menu()

  -- perfils: pares, duplicar i límit d'amics
  g:to_title(); g:open_profiles(); api.wait(2)
  local ui = g.menu
  api.check(Profile.MAX_FRIENDS == 12, 'fins a 12 amics i família')
  ui.slots = Profile.list()
  local function press(k) ui:update(1 / 60, { [k] = true }, {}); api.wait(1) end
  local function find(rows, prefix)
    for i, r in ipairs(rows) do if r[1]:sub(1, #prefix) == prefix then return i end end
  end
  local free
  for i, e in ipairs(ui.slots) do if not e.exists then free = i; break end end
  api.check(free, 'hi ha una ranura lliure per provar')
  ui:push('slot_menu', { slot = free, profile = nil })
  ui:pop()
  local p = Profile.new('Prova', 'nena')
  api.check(Profile.write(free, p), 'es crea un perfil de prova')
  ui.slots = Profile.list()
  ui:push('slot_menu', { slot = free, profile = Profile.read(free) })
  local s = ui:top()
  local rows = ui:rows(s)
  api.check(find(rows, 'Pares: '), 'el menú del perfil té «Pares»')
  api.check(find(rows, 'Duplicar'), 'el menú del perfil té «Duplicar el perfil»')
  rows[find(rows, 'Duplicar')].action()
  api.wait(1)
  local n = 0
  for _, e in ipairs(Profile.list()) do if e.exists and e.name == 'Prova 2' then n = n + 1 end end
  api.check(n == 1, 'duplicar crea «Prova 2» a una altra ranura')
  api.check(ui.flash_text and ui.flash_text:find('duplicat'), 'avís de perfil duplicat')
  -- editar els pares
  rows = ui:rows(s)
  rows[find(rows, 'Pares: ')].action()
  local ps = ui:top()
  api.check(ps.kind == 'parents' and #ui:rows(ps) == 3, 'pantalla de pares')
  ui:rows(ps)[1].action()
  api.check(ui:top().kind == 'name', 'el nom del pare s\'edita amb el teclat de lletres')
  ui:top().value = ''
  ui:textinput('Quim'); ui:keypressed('return'); api.wait(2)
  api.check(Profile.read(free).parents.pare == 'Quim', 'el nom del pare es desa')

  -- selector de casa amb zoom
  ui:pick_place(nil, 'prova', function() end)
  local pk = ui:top()
  ui:update(1 / 60, { zoom_in = true }, {})
  api.check(pk.view.i == 2, 'el selector fa zoom a la vista general')
  ui:update(1 / 60, { confirm = true }, {})
  api.check(pk.zoom, 'Z apropa el selector')
  ui:update(1 / 60, { zoom_in = true }, {})
  api.check(pk.cz == 3, 'zoom a la vista de prop')
  for _ = 1, 4 do ui:update(1 / 60, { zoom_out = true }, {}) end
  api.check(pk.cz == 1, 'zoom mínim a la vista de prop')
  api.wait(2)
  g.menu:draw()
  Profile.delete(free)
  for i, e in ipairs(Profile.list()) do if e.exists and e.name == 'Prova 2' then Profile.delete(i) end end
end
