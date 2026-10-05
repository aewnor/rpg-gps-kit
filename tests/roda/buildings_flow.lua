-- Edificis importants amb interior propi (love . --test=tests/buildings_flow.lua --mute): l'església, la
-- biblioteca, l'ajuntament i l'ermita tenen porta; el CAP, la Policia, Correus i l'estació, interior propi des de
-- la porta de la façana. Desa esglesia.png i biblioteca.png.
return function(api)
  local Input = require('src.input')
  local g = api.scene().game
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  local function settle()
    for _ = 1, 120 do if not g.transition then break end; api.wait(1) end
    api.wait(15)
  end
  local function has_tile(w, name)
    for ty = 0, w.map.height - 1 do
      for tx = 0, w.map.width - 1 do if w:tile_name('structures', tx, ty) == name then return true end end
    end
  end
  local ow = api.scene()
  local expect = { sant_bartomeu = { 'Església de Sant Bartomeu', 'i_pew' }, biblioteca = { 'Biblioteca', 'i_shelf' },
                   ajuntament = { 'Ajuntament', 'i_flag' }, ermita_bera = { 'Ermita', 'i_altar' } }
  for _, id in ipairs({ 'sant_bartomeu', 'biblioteca', 'ajuntament', 'ermita_bera' }) do
    local door
    for _, d in ipairs(ow.doors) do if d.obj.props.poi_id == id then door = d end end
    api.check(door ~= nil, 'el monument ' .. id .. ' té porta')
    if door then
      local tx, ty = math.floor(door.rect.x / 16), math.floor(door.rect.y / 16)
      api.teleport(tx, ty + 2); api.player().facing = 'up'; api.wait(3)
      Input.hold('up', true)
      for _ = 1, 120 do if api.scene() ~= ow then break end; api.wait(1) end
      Input.release_all()
      settle()
      local w = api.scene()
      api.check(w ~= ow and (w.map.props and w.map.props.name or ''):find(expect[id][1], 1, true) ~= nil,
        'entres a ' .. expect[id][1] .. ' (' .. tostring(w.map.props and w.map.props.name) .. ')')
      api.check(has_tile(w, expect[id][2]), 'té el seu mobiliari propi (' .. expect[id][2] .. ')')
      if id == 'sant_bartomeu' then shot('esglesia.png') end
      if id == 'biblioteca' then
        local books = 0
        for _, s in ipairs(w.signs) do if s.props.book then books = books + 1 end end
        api.check(books >= 4, 'a la biblioteca hi ha llibres per llegir (' .. books .. ')')
        shot('biblioteca.png')
      end
      -- sortir: torna davant la porta
      local ex
      for _, d in ipairs(w.doors) do ex = d end
      api.teleport(math.floor(ex.rect.x / 16), math.floor(ex.rect.y / 16) - 1); api.player().facing = 'down'; api.wait(3)
      Input.hold('down', true)
      for _ = 1, 120 do if api.scene() ~= w then break end; api.wait(1) end
      Input.release_all()
      settle()
      ow = api.scene()
      local b = api.player().body
      api.check(ow.id == 'overworld' and math.abs(b.x - (door.rect.x + 8)) < 24, 'en sortir, ets davant de la porta')
      api.wait(20)
    end
  end
  -- façanes: el CAP
  local found
  local n = 0
  for key, sid in pairs(ow:poi_doors()) do
    n = n + 1
    if sid == 'metge' then local x, y = key:match('(%d+),(%d+)'); found = { tonumber(x), tonumber(y) } end
  end
  api.check(n >= 5, 'portes de façana amb interior propi (' .. n .. ')')
  api.check(found ~= nil, 'hi ha una porta de façana al CAP')
  if found then
    ow:enter_facade(found[1], found[2], 'door')
    settle()
    local w = api.scene()
    api.check(w.id == 'poi_metge' and has_tile(w, 'i_bench'), 'la porta del CAP porta a la sala d\'espera (' .. tostring(w.id) .. ')')
  end
  -- personatges en diagonal (src/paperdoll/diag.lua)
  g.scene_manager:change('overworld', nil, { x = api.player().body.x, y = api.player().body.y + 40, level = 0 })
  settle()
  local sp = g.sprites.player
  api.check(sp.diag, 'la fulla del protagonista té files en diagonal')
  Input.hold('down', true); Input.hold('left', true); api.wait(8)
  local row = api.player():frame(sp)
  Input.release_all()
  api.check(row == 4, 'caminant avall-esquerra fa servir la fila en diagonal (' .. tostring(row) .. ')')
  local npc_diag = 0
  for _, n in pairs(g.sprites.chars) do if n.diag then npc_diag = npc_diag + 1 end end
  api.check(npc_diag > 10, 'els personatges també en tenen (' .. npc_diag .. ')')
  api.on_frame = nil
end
