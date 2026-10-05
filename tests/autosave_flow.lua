-- Autoguardat (love . --test=tests/autosave_flow.lua --mute): la partida es desa sola cada `autosave_every`
-- segons de joc al món, no a mig diàleg, i el desat triga poc (no ha de fer saltar fotogrames a la Pi).
return function(api)
  local g = api.scene().game
  local Save = require('src.save')
  api.talk_through()
  g.dev.autosave, g.autosave_every = true, 2
  local writes, t_max = 0, 0
  local orig = Save.write
  Save.write = function(st)
    local t0 = love.timer.getTime()
    local ok, why = orig(st)
    t_max = math.max(t_max, love.timer.getTime() - t0)
    writes = writes + 1
    return ok, why
  end
  api.scene().dialogue:show('Prova', { 'Un diàleg obert no es desa.' })
  api.wait(60 * 3)
  api.check(writes == 0, 'no es desa amb un diàleg obert (' .. writes .. ')')
  api.talk_through()
  api.wait(60 * 5)
  api.check(writes >= 2, 'es desa sol cada 2 s de joc (' .. writes .. ' desats)')
  api.check(t_max < 0.05, string.format('cada desat triga %.1f ms (< 50 ms)', t_max * 1000))
  Save.write = orig
  g.dev.autosave = nil
end
