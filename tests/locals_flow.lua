-- Locals reals (love . --test=tests/locals_flow.lua --mute): cada tipus de local amb rètol a la porta té
-- un interior propi (mobles i qui t'atén amb el nom del local). Desa local_<tipus>.png de cada interior.
return function(api)
  local g = api.scene().game
  api.talk_through()
  -- per defecte només es veuen els comprovats (config del servidor); per provar tots els tipus, s'activen
  local w0 = api.scene()
  local hidden, shown = 0, 0
  for _, o in ipairs(w0.signboards) do
    local spr = o.props.sprite or ''
    local loc = spr:sub(1, 11) == 'sign_local_' and g:local_info(spr:sub(12))
    if loc then
      if o.hidden then hidden = hidden + 1 elseif loc.verified then shown = shown + 1 end
      if o.hidden == (loc.verified or false) then api.check(false, loc.name .. ': visible només si està comprovat') end
    end
  end
  api.check(shown > 0, string.format('locals comprovats visibles (%d) i la resta amagats (%d)', shown, hidden))
  g.config.mostrar_tots_els_locals = true
  g:apply_config(g.config)
  api.wait(2)
  local want = { restaurant = true, animals = true, music = true, industry = true, sport = true, pharmacy = true }
  local seen = {}
  local world = api.scene()
  local list = {}
  for _, o in ipairs(world.signboards) do
    local spr = o.props.sprite or ''
    local loc = spr:sub(1, 11) == 'sign_local_' and g:local_info(spr:sub(12))
    if loc and not o.hidden and want[loc.kind] and not seen[loc.kind] then
      local tx, ty = math.floor(o.x / 16), math.floor(o.y / 16)
      local name = world:tile_name('structures', tx, ty) or ''
      if name:match('_door$') or name:match('_shop%d?$') then
        seen[loc.kind] = true
        list[#list + 1] = { loc = loc, tx = tx, ty = ty }
      end
    end
  end
  api.check(#list >= 4, 'hi ha portes amb rètol de local de ' .. #list .. ' tipus')
  for _, it in ipairs(list) do
    local w = api.scene()
    w.player.body.x, w.player.body.y = it.tx * 16 + 8, (it.ty + 1) * 16 + 10
    api.wait(5)
    w:enter_facade(it.tx, it.ty, 'door')
    for _ = 1, 300 do if g.scene ~= w and not g.transition then break end; api.wait(1) end
    local inside = api.scene()
    if inside == w then print('[test] no ha entrat', it.tx, it.ty, g.state.proc and g.state.proc.id, g.transition and g.transition.scene) end
    local who
    for _, n in ipairs(inside.npcs or {}) do
      local nm = (n.props and n.props.say_name) or n.name or ''
      if nm:find(it.loc.name, 1, true) then who = nm end
    end
    api.check(inside ~= w and who ~= nil, string.format('%s (%s): dins hi ha «%s»', it.loc.name, it.loc.kind, tostring(who)))
    api.wait(30)
    local file, done = 'local_' .. it.loc.kind .. '.png', false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
    -- tornar a fora per la sortida
    local back = g.state.proc and g.state.proc.back
    if back then
      g:change(back.scene, nil, { x = back.x, y = back.y, level = 0 })
      for _ = 1, 300 do if not g.transition then break end; api.wait(1) end
      api.wait(5)
    end
  end
end
