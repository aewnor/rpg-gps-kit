-- Pas inferior del carrer de Cadaqués, vora el Bonpreu (love . --test=tests/cadaques_flow.lua --mute): s'hi
-- entra, es passa per dins (nivell -1) i se'n surt per l'altra punta, de sud a nord i de nord a sud. Abans el
-- túnel acabava sense rampa al nord i no es podia creuar (tools/import_osm.py: dead_end_ramps).
return function(api)
  api.wait(5)
  local S, N, VIA = { 1078, 1052 }, { 1074, 1033 }, { 1076, 1045 }
  for _, c in ipairs({ { S, N, 'sud → nord' }, { N, S, 'nord → sud' } }) do
    api.teleport(c[1][1], c[1][2])
    api.wait(3)
    local via = api.walk_to(function(x, y) return x == VIA[1] and y == VIA[2] end, 120)
    local lv = api.player().body.level
    local tx, ty = c[2][1], c[2][2]
    local ok = via and api.walk_to(function(x, y) return math.abs(x - tx) + math.abs(y - ty) <= 1 end, 120)
    api.check(via and ok, string.format('carrer de Cadaqués %s (per dins al nivell %d)', c[3], lv))
  end
end
