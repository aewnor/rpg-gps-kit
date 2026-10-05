-- Capturas de los edificios especiales (comprobación visual: love . --test=tests/signs_probe.lua --mute)
return function(api)
  local g = api.scene().game
  g.dev.turbo = 1
  local function find(id) for _, n in ipairs(api.scene().npcs) do if n.props.service_id == id then return n end end end
  for _, id in ipairs({ 'policia', 'metge', 'ajuntament', 'bonpreu', 'correus', 'escola' }) do
    local n = find(id)
    local sb
    for _, o in ipairs(api.scene().signboards) do if o.props.service_id == id then sb = o end end
    if n then
      local ax, ay = n.body.x, n.body.y
      if sb then ax, ay = sb.x, sb.y + 20 end
      api.player().body.x, api.player().body.y = ax + 20, ay + 30
      api.wait(40)
      print('[test]', id, n.props.say_name, n.hidden)
      love.graphics.captureScreenshot(function(d) d:encode('png', 'sg_' .. id .. '.png') end)
      api.wait(3)
    else print('[test] falta', id) end
  end
  local agents = 0
  for _, n in ipairs(api.scene().npcs) do if n.routine and n.routine.kind == 'patrol' then agents = agents + 1 end end
  print('[test] agentes', agents)
end
