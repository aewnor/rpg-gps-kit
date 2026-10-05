-- Perfils entre aparells (luajit tests/sync_cases.lua): src/sync.lua aplica el que retorna el servidor
-- sobre un sistema de fitxers en memòria. El perfil creat en un altre aparell va a una ranura lliure, la
-- versió més nova guanya, el que només és aquí es marca per pujar i els esborrats desapareixen.
package.path = './?.lua;' .. package.path
local P = require('src.profile')
local Sync = require('src.sync')
local json = require('src.lib.json')
local files = {}
P.fs = {
  exists = function(n) return files[n] ~= nil end,
  read = function(n) return files[n] end,
  write = function(n, d) files[n] = d; return true end,
  remove = function(n) files[n] = nil; return true end,
  rename = function(a, b) files[b] = files[a]; files[a] = nil; return true end,
}
local n_ok = 0
local function check(c, msg) assert(c, msg); n_ok = n_ok + 1; print('OK   ' .. msg) end
local function save_of(name, t) return { schema = 1, scene = 'overworld', x = 1, y = 2, flags = {}, saved_at = t, who = name } end

-- 1) perfil local sense uid (d'abans) + perfil remot nou
local old = P.new('Local', 'nena'); old.uid = nil
assert(P.write(1, old))
files[P.path(1)] = files[P.path(1)]:gsub('"uid":"[^"]*",?', '')   -- com un fitxer antic
Sync.dirty = {}
local remote_prof = P.sanitize(P.new('Remot', 'nen')); remote_prof.home_player_location = nil
local res = { profiles = { remot_1 = { t = 100, profile = remote_prof, save_t = 50, save = save_of('remot', 50) } }, deleted = {} }
local changed = Sync.apply(res)
check(changed, 'hi ha canvis en baixar')
check(P.read(1).name == 'Local' and P.read(1).uid ~= nil, 'el perfil local d\'abans rep un uid')
check(Sync.dirty[1], 'el perfil local (que no és al servidor) es puja')
local r2 = P.read(2)
check(r2 and r2.name == 'Remot' and r2.uid == 'remot_1' and r2.updated == 100, 'el perfil de l\'altre aparell va a la ranura 2')
local s2 = json.decode(files[P.dir(2) .. '/save.json'])
check(s2 and s2.who == 'remot', 'amb la seva partida')
check(not Sync.dirty[2], 'el que ve del servidor no es torna a pujar')

-- 2) versió remota més nova del mateix perfil; partida local més nova
Sync.dirty = {}
local newer = P.sanitize(r2); newer.name = 'Remot nou'; newer.home_player_location = nil
files[P.dir(2) .. '/save.json'] = json.encode(save_of('local', 80))
Sync.apply({ profiles = { remot_1 = { t = 200, profile = newer, save_t = 60, save = save_of('remot vell', 60) } }, deleted = {} })
check(P.read(2).name == 'Remot nou', 'el perfil més nou del servidor substitueix el local')
check(json.decode(files[P.dir(2) .. '/save.json']).who == 'local', 'la partida local més nova es conserva')
check(Sync.dirty[2], 'i es marca per pujar')

-- 3) la ranura que s'està jugant no es toca
Sync.dirty = {}
local newest = P.sanitize(P.read(2)); newest.name = 'No toquis'; newest.home_player_location = nil
Sync.apply({ profiles = { remot_1 = { t = 999, profile = newest } }, deleted = {} }, 2)
check(P.read(2).name == 'Remot nou', 'la ranura en joc no es sobreescriu')

-- 4) esborrat en un altre aparell
local uid2 = P.read(2).uid
Sync.apply({ profiles = {}, deleted = { [uid2] = 10 ^ 9 + os.time() } })
check(P.read(2) == nil, 'un perfil esborrat en un altre aparell desapareix')
check(P.read(1) ~= nil, 'els altres es queden')

-- 5) escriure un perfil o una partida marca la ranura
Sync.dirty = {}
assert(P.write(3, P.new('Tercer', 'nena')))
check(Sync.dirty[3] and P.read(3).updated > 0, 'desar un perfil el marca per pujar amb data')
local Save = require('src.save')
Save.fs = P.fs
Save.use(P.dir(3))
Sync.dirty = {}
assert(Save.write(save_of('x', 0)))
check(Sync.dirty[3] and json.decode(files[P.dir(3) .. '/save.json']).saved_at > 0, 'desar la partida també (amb saved_at)')

-- 6) carrera en arrencar: la baixada sense jugador encara no ha tornat quan el hub tria la protagonista. Abans la segona
-- es perdia (i la primera es descartava pel canvi de jugador): el mòbil no baixava mai els perfils del PC.
local pending, asked = {}, {}
package.loaded['src.net'] = { available = function() return true end,
  post = function(path, body, cb) asked[#asked + 1] = body.owner; pending[#pending + 1] = { body, cb } end }
Sync.off, Sync.pulling, Sync.again = false, false, nil
P.set_owner(nil)
Sync.pull()
P.set_owner('nena-id')
local got
local notified = false
Sync.on_change = function() notified = true end
Sync.pull(function(changed) got = changed end)
check(#pending == 1, 'la segona baixada espera que acabi la primera')
local nena_prof = P.sanitize(P.new('Perfil del PC', 'nena')); nena_prof.home_player_location = nil
local first = table.remove(pending, 1)
first[2]({ profiles = {}, deleted = {} })                         -- la de «sense jugador» (ja no compta)
check(#pending == 1 and asked[2] == 'nena-id', 'en acabar, torna a baixar amb el jugador nou')
local second = table.remove(pending, 1)
second[2]({ profiles = { pc_1 = { t = 200, profile = nena_prof } }, deleted = {} })
local found = false
for i = 1, P.MAX_SLOTS do local p = P.read(i); if p and p.uid == 'pc_1' then found = true end end
check(found and got == true and notified, 'els perfils del PC arriben i la pantalla de perfils se n\'assabenta')
Sync.on_change = nil
package.loaded['src.net'] = nil

-- 7) el hub tria la protagonista amb la pantalla de títol oberta: Game:to_title() fa Net.cancel_all(). Abans també
-- llençava la baixada en curs, Sync.pulling quedava a true i ja no es baixava res mai més (el mòbil, sense perfils).
_G.love = _G.love or { system = { getOS = function() return 'Web' end }, timer = { getTime = function() return 0 end } }
local Net = require('src.net')
local kept = {}
Net.pending.a = { cb = function() kept.sync = true end, t0 = 0, timeout = 20, keep = true }
Net.pending.b = { cb = function() end, t0 = 0, timeout = 20, keep = false }
local cancel = Net.cancel
Net.cancel = function(id) Net.pending[id] = nil end
Net.cancel_all()
Net.cancel = cancel
check(Net.pending.a and not Net.pending.b, 'tornar al títol no llença la sincronització (sí les converses)')
Net.pending.a = nil
local src = io.open('src/net.lua'):read('*a')
check(src:find("keep = path ~= '/api/npc_chat'", 1, true) ~= nil, 'només es llencen les converses: la sincronització, la casa i la configuració es conserven')
-- i si una resposta es perd igualment, passat el temps límit es torna a baixar
pending, asked = {}, {}
package.loaded['src.net'] = { available = function() return true end,
  post = function(path, body, cb) asked[#asked + 1] = body.owner; pending[#pending + 1] = { body, cb } end }
Sync.pulling, Sync.again, Sync.pull_t0 = true, nil, os.time() - 100
Sync.pull()
check(#pending == 1 and Sync.pulling, 'una baixada encallada no bloqueja les següents')
pending[1][2]({ profiles = {}, deleted = {} })
check(not Sync.pulling, 'en arribar la resposta queda lliure')
package.loaded['src.net'] = nil
print('TOTES LES PROVES DE SINCRONITZACIÓ OK (' .. n_ok .. ')')
