-- Atacar caminant (love . --test=tests/move_attack_flow.lua --mute): amb la fletxa premuda, el cop no atura el
-- jugador; avança més a poc a poc i continua mirant cap on ha començat el cop.
return function(api)
  local Input = require('src.input')
  local g = api.scene().game
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local st = api.state()
  st.inventory = st.inventory or {}
  local pl = api.player()
  -- a la Plaça de l'Església hi ha lloc per caminar cap a la dreta
  local sx, sy = g:nearest_walkable('overworld', 611 * 16 + 8, 808 * 16 + 8, 0, 12)
  pl.body.x, pl.body.y = sx, sy
  pl.facing = 'right'
  api.wait(5)
  Input.hold('right', true)
  api.wait(10)
  local x0 = pl.body.x
  api.press('attack')
  local seen, moved_in_attack, facing_ok = false, false, true
  local xa
  for _ = 1, 40 do
    api.wait(1)
    if pl.state == 'attack' then
      if not seen then seen = true; xa = pl.body.x end
      if pl.body.x > xa + 1 then moved_in_attack = true end
      if pl.facing ~= 'right' then facing_ok = false end
    end
  end
  Input.release_all()
  api.check(seen, 'el cop comença mentre camina')
  api.check(moved_in_attack, string.format('continua avançant durant el cop (%.1f → %.1f)', xa or 0, pl.body.x))
  api.check(facing_ok, 'mira cap on ha començat el cop')
  api.check(pl.body.x > x0 + 8, 'en total ha avançat')
  api.on_frame = nil
end
