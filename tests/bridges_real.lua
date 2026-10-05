-- Cruza a pie, en el juego real, cada puente y paso inferior del informe de
-- tools/check_crossings.py (love . --test=tests/bridges_real.lua --mute; RODA_BIKE=1: en bici).
-- Obliga a pasar por la celda «over» (solo transitable al nivel del paso: sobre lo que cruza el puente
-- o bajo lo que tapa el túnel) y después a llegar al otro extremo.
return function(api)
  local json = require('src.lib.json')
  local cases = json.decode(assert(love.filesystem.read('maps/source/crossings-report.json')))
  api.wait(5)
  -- els avisos de missió surten sols al cap d'una estona i aturen el jugador: es tanquen
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local n, ok_n, forced = 0, 0, 0
  for _, c in ipairs(cases) do
    if c.ok and c.from and c.to and (not os.getenv('RODA_WAY') or os.getenv('RODA_WAY'):find(c.way, 1, true)) then
      n = n + 1
      api.teleport(c.from[1], c.from[2])
      api.wait(2)
      if os.getenv('RODA_BIKE') and c.way_kind ~= 'footway' then   -- també en bici (no puja escales)
        local pl = api.player()
        pl.vehicle = require('src.systems.vehicles').new_state('bici', pl.facing)
        pl.bike, pl.body.no_stairs = true, true
      end
      local via, lv_ok = true, true
      if c.over then
        forced = forced + 1
        local ox, oy = c.over[1], c.over[2]
        via = api.walk_to(function(x, y) return x == ox and y == oy end, 90)
        lv_ok = via and api.player().body.level == c.level
      end
      local tx, ty = c.to[1], c.to[2]
      local arrived = via and api.walk_to(function(x, y) return math.abs(x - tx) + math.abs(y - ty) <= 1 end, 90)
      local good = arrived and lv_ok
      if good then ok_n = ok_n + 1 end
      api.check(good, string.format('%s %s (nivel %d) de %d,%d a %d,%d%s%s', c.name or '?', c.way, c.level,
        c.from[1], c.from[2], tx, ty, c.over and string.format(' por %d,%d', c.over[1], c.over[2]) or '',
        not via and ' — no llega al paso' or (not lv_ok and ' — llega al paso a otro nivel') or (not arrived and ' — no llega al final') or ''))
    end
  end
  api.on_frame = nil
  print(string.format('[test] pasos cruzados: %d/%d (%d obligados a pisar el puente o túnel)', ok_n, n, forced))
end
