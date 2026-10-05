-- Pesca i encanteris de l'escola, lògica pura (luajit tests/fishing_cases.lua).
package.path = './?.lua;' .. package.path
local Fishing = require('src.systems.fishing')
local Magic = require('src.systems.magic')
local n_ok = 0
local function check(c, msg) assert(c, msg); n_ok = n_ok + 1; print('OK   ' .. msg) end

-- generador determinista com love.math.random
local seed = 12345
local function rng(a, b)
  seed = (seed * 1103515245 + 12345) % 2147483648
  local u = seed / 2147483648
  if a then return a + math.floor(u * (b - a + 1)) end
  return u
end

-- cada peix surt on toca i amb una mida dins el seu rang
local seen = { mar = {}, port = {} }
for _, spot in ipairs({ 'mar', 'port' }) do
  for _ = 1, 3000 do
    local id, cm = Fishing.roll(spot, 12, rng)
    local f = Fishing.BY_ID[id]
    assert(f.where == 'tots' or f.where == spot, id .. ' no és de ' .. spot)
    assert(cm >= f.cm[1] and cm <= f.cm[2], id .. ' fora de mida')
    seen[spot][id] = true
  end
end
check(seen.port.pop and seen.port.cranc and not seen.port.mabre, 'al port hi ha pops i crancs, i no mabres')
check(seen.mar.mabre and not seen.mar.pop, 'a la platja hi ha mabres, i no pops')
-- de nit, més calamars
local day_n, night_n = 0, 0
for _ = 1, 4000 do if Fishing.roll('mar', 12, rng) == 'calamar' then day_n = day_n + 1 end end
for _ = 1, 4000 do if Fishing.roll('mar', 23, rng) == 'calamar' then night_n = night_n + 1 end end
check(night_n > day_n * 2, string.format('de nit surten més calamars (%d de dia, %d de nit)', day_n, night_n))

-- quadern: espècies noves, rècords i la bota no compta
local st = {}
check(Fishing.log(st, 'orada', 30) == true, 'la primera orada és espècie nova')
check(Fishing.log(st, 'orada', 41) == false and st.fish_log.orada.best == 41 and st.fish_log.orada.n == 2, 'el rècord es guarda')
Fishing.log(st, 'bota_vella', 28)
check(Fishing.species(st) == 1, 'la bota vella no compta com a espècie')
check(Fishing.total_species() == #Fishing.FISH - 1, 'el quadern té totes les espècies menys la brossa')

-- encanteris de l'escola: no surten fins que la mestra els ensenya
local ps = { char_level = 4, mp = 20, max_mp = 20, hp = 6, max_hp = 6, equipment = { weapon = 'basto' } }
local items = { basto = { magic = 3 } }
check(not Magic.unlocked(ps, 'llamp'), 'el Llamp no se sap sense la classe')
check(Magic.learn(ps, 'llamp') and Magic.unlocked(ps, 'llamp'), 'després de la classe, el Llamp es pot fer')
check(not Magic.learn(ps, 'foc'), 'la Bola de foc no és de l\'escola')
local out = Magic.cast(ps, items, 'llamp', 0, 0, 'down')
check(out and out.bolt and out.bolt.dmg > 0 and ps.mp == 13, 'el Llamp gasta MP i torna un objectiu per al món')
Magic.learn(ps, 'escut')
out = Magic.cast(ps, items, 'escut', 0, 0, 'down')
check(out and out.ward == 8 and ps.ward_t == 8, 'l\'Escut màgic dura 8 segons')
check(not Magic.cast(ps, items, 'escut', 0, 0, 'down'), 'no es pot tornar a fer mentre dura')
Magic.regen(ps, 9)
check(ps.ward_t == 0, 'l\'escut s\'acaba')
Magic.learn(ps, 'gel')
ps.mp = 20
out = Magic.cast(ps, items, 'gel', 0, 0, 'right')
check(out and #out.shots == 1 and out.shots[1].kind == 'ice' and out.shots[1].freeze == 2.5, 'el Raig de gel congela')
local low = { char_level = 1, learned_spells = { retorn = true }, mp = 20, equipment = { weapon = 'basto' } }
check(not Magic.unlocked(low, 'retorn'), 'cal el nivell encara que l\'hagis après')
print('TOTES LES PROVES DE PESCA I ENCANTERIS OK (' .. n_ok .. ')')
