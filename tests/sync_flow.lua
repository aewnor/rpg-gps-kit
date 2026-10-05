-- Perfils entre aparells, de punta a punta (love . --test=tests/sync_flow.lua --mute), contra un servidor
-- temporal: RODA_SYNC_URL=http://127.0.0.1:8199 (tools/web_server.py 8199 amb RODA_SYNC_DIR temporal).
-- L'aparell A crea un perfil amb partida i el puja; l'aparell B (sense res local) el baixa.
return function(api)
  local url = os.getenv('RODA_SYNC_URL')
  if not url then print('[test] sense RODA_SYNC_URL: no es prova'); return end
  local Net, Sync, P = require('src.net'), require('src.sync'), require('src.profile')
  local Save, json = require('src.save'), require('src.lib.json')
  Net.base, Sync.off = url, false
  P.set_owner('proves_sync_' .. os.time())
  local function wait_for(fn, n) for _ = 1, n or 600 do if fn() then return true end; api.wait(1) end return false end
  -- aparell A
  local p = P.new('Sync A', 'nena')
  api.check(P.write(1, p), 'A crea el perfil')
  Save.use(P.dir(1))
  api.check(Save.write({ schema = 1, scene = 'overworld', x = 10, y = 20, flags = { prova = true } }), 'A desa una partida')
  Sync.wait = 0
  api.check(wait_for(function() Sync.update(1 / 60); return not next(Sync.dirty) and not Sync.busy end), 'A puja el perfil')
  -- aparell B: res local
  P.delete(1, true)
  api.check(P.read(1) == nil, 'B no té cap perfil')
  local done, changed = false, nil
  Sync.pull(function(c) done, changed = true, c end)
  api.check(wait_for(function() return done end), 'B baixa del servidor')
  local q = P.read(1)
  api.check(changed and q and q.name == 'Sync A' and q.uid == p.uid, 'B té el perfil de A (' .. tostring(q and q.name) .. ')')
  local raw = P.fs.read(P.dir(1) .. '/save.json')
  local s = raw and json.decode(raw)
  api.check(s and s.flags and s.flags.prova and s.x == 10, 'i la seva partida')
  -- esborrar a B l'esborra al servidor; A (que encara el tindria) el perd en baixar
  P.delete(1)
  api.wait(60)
  P.write(1, q, true)   -- A encara el té
  done = false
  Sync.pull(function(c) done = true end)
  wait_for(function() return done end)
  api.check(P.read(1) == nil, 'esborrat en un aparell, desapareix de l\'altre')
  P.delete(1, true)
  P.set_owner(nil)
  Sync.off = true
end
