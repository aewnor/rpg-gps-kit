-- Preguntes als veïns de les cases (love . --test=tests/chat_flow.lua --mute): entres a una casa, parles amb un
-- veí i, després de la seva frase, pots triar preguntes; cada resposta surt en un diàleg i torna a la llista.
return function(api)
  local g = api.scene().game
  local w = api.scene()
  local pl = api.player()
  local tx0, ty0 = math.floor(pl.body.x / 16), math.floor(pl.body.y / 16)
  local found
  for r = 1, 60 do
    for ty = ty0 - r, ty0 + r do
      for tx = tx0 - r, tx0 + r do
        if not found and (math.abs(tx - tx0) == r or math.abs(ty - ty0) == r) then
          local nm = w:tile_name('structures', tx, ty) or ''
          if nm:match('^f_.*_door$') then found = { tx, ty } end
        end
      end
    end
    if found then break end
  end
  api.check(found ~= nil, 'hi ha una porta de casa a prop (' .. tostring(found and found[1]) .. ')')
  if not found then return end
  -- buscar una casa amb algun veí a dins (algunes estan buides)
  local inside, npc
  for k = 0, 30 do
    local tx, ty = found[1], found[2]
    w = api.scene()
    w.player.body.x, w.player.body.y = tx * 16 + 8, (ty + 1) * 16 + 10
    api.wait(3)
    w:enter_facade(tx, ty, 'door')
    for _ = 1, 300 do if g.scene ~= w and not g.transition then break end; api.wait(1) end
    inside = api.scene()
    for _, n in ipairs(inside.npcs or {}) do
      if n.props.say and require('src.systems.chat').applies(inside, n) then npc = n end
    end
    if npc then break end
    local back = g.state.proc and g.state.proc.back
    g:change(back.scene, nil, { x = back.x, y = back.y, level = 0 })
    for _ = 1, 300 do if not g.transition then break end; api.wait(1) end
    api.wait(3)
    -- la porta següent cap a la dreta
    w = api.scene()
    local nx
    for x = found[1] + 2, found[1] + 80 do
      local nm = w:tile_name('structures', x, found[2]) or ''
      if not nx and nm:match('^f_.*_door$') then nx = x end
    end
    if not nx then break end
    found = { nx, found[2] }
  end
  api.check(npc ~= nil, 'a la casa hi ha un veí (' .. tostring(inside and inside.id) .. ')')
  if not npc then return end
  inside.player.body.x, inside.player.body.y = npc.body.x, npc.body.y + 14
  inside.player.facing = 'up'
  api.wait(2)
  inside:interact()
  api.check(inside.dialogue.open, 'el veí diu la seva frase')
  for _ = 1, 20 do
    if not inside.dialogue.open then break end
    inside.dialogue.open = false
    if inside.dialogue.on_close then inside.dialogue.on_close() end
    api.wait(1)
  end
  local items = g.menu and g.menu:items() or {}
  api.check(#items >= 4 and items[#items - 1][1] == 'Adéu!', 'després surten preguntes per triar (' .. #items .. ')')
  local q = items[1] and items[1][1]
  if items[1] then items[1][2]() end
  api.wait(2)
  api.check(inside.dialogue.open, 'en triar «' .. tostring(q) .. '», el veí respon')
  love.graphics.captureScreenshot(function(d) d:encode('png', 'veins.png') end)
  api.wait(3)
  inside.dialogue.open = false
  if inside.dialogue.on_close then inside.dialogue.on_close() end
  api.wait(2)
  items = g.menu and g.menu:items() or {}
  local again = true
  for _, it in ipairs(items) do if it[1] == q then again = false end end
  api.check(#items >= 2 and again, 'torna a la llista sense la pregunta que ja has fet')
end
