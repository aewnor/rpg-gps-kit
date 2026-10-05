-- Comer y dormir dentro del juego real: tecla G, cama (Zzz, 8 h, guardado), nevera y botiquín del CAP.
--   love . --test=tests/rest_flow.lua --mute
return function(api)
  local sc = api.scene()
  local st = api.state()
  local Rest = require('src.systems.rest')

  -- tecla G con un botiquín
  st.hp, st.mp = 2, 0
  st.inventory.botiqui = 1
  api.press('heal')
  api.wait(3)
  api.check(st.hp > 2 and st.mp > 0 and not st.inventory.botiqui, 'la tecla G usa un botiquín: vida ' .. st.hp .. ', MP ' .. st.mp)

  -- dormir: el juego se detiene, pasan 8 h y se cura
  st.hp, st.mp = 3, 0
  st.clock, st.day = 23 * 60, 2
  Rest.sleep(sc)
  local d0 = st.day
  api.wait(30)
  api.check(sc.rest_fx ~= nil, 'la pantalla Zzz está en marcha')
  api.wait(60 * 5)
  api.check(sc.rest_fx == nil, 'la pantalla Zzz termina sola')
  api.check(st.hp == st.max_hp and st.mp == st.max_mp, 'dormir cura vida y MP')
  api.check(st.day == d0 + 1 and st.clock >= 7 * 60 - 1 and st.clock < 7 * 60 + 30, 'son las 7:00 del día siguiente (' .. math.floor(st.clock) .. ' min)')

  -- botiquín gratis en el CAP
  local metge
  for _, n in ipairs(sc.npcs) do if n.props.service_id == 'metge' then metge = n end end
  api.check(metge ~= nil, 'existe el CAP')
  st.inventory.botiqui = nil
  api.check(Rest.free_kit(sc, 'metge') and st.inventory.botiqui == 1, 'el CAP regala un botiquín')
end
