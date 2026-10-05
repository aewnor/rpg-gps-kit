-- Encàrrecs dels veïns (luajit tests/errands_cases.lua): deterministes, repartits i amb sentit.
package.path = './?.lua;' .. package.path
local E = require('src.systems.errands')
local fails = 0
local function check(ok, msg) print((ok and 'OK   ' or 'FAIL ') .. msg); if not ok then fails = fails + 1 end end
local function count(kind, clock, day, ctx, want)
  local n = 0
  for seed = 1, 400 do if E.pick(kind, seed * 37, clock, day, ctx) == want then n = n + 1 end end
  return n
end
local sunny_june = { sunny = true, month = 7, garden = true }

check(E.pick('townsfolk', 1234, 8 * 60 + 15, 3, {}) == E.pick('townsfolk', 1234, 8 * 60 + 15, 3, {}), 'mateix dia i hora → mateix encàrrec')
local bread = count('townsfolk', 8 * 60 + 35, 2, {}, 'bakery')
check(bread > 60 and bread < 340, 'entre setmana a les 8:35 una part dels veïns va a buscar el pa (' .. bread .. '/400)')
check(count('townsfolk', 3 * 60, 2, {}, 'bakery') == 0, 'a les 3 de la matinada ningú va al forn')
check(count('kid', 8 * 60 + 35, 2, {}, 'bakery') == 0, 'els nens no van sols al forn')
check(count('service', 8 * 60 + 35, 2, {}, 'bakery') == 0, 'els dependents no deixen la botiga')
local hair = count('adult', 10 * 60 + 35, 3, {}, 'hair')
check(hair > 10 and hair < 100, 'un de cada deu dies, perruqueria (' .. hair .. '/400)')
local beach = count('townsfolk', 12 * 60, 6, sunny_june, 'beach') + count('townsfolk', 12 * 60, 6, sunny_june, 'pool')
check(beach > 80, 'dissabte de sol a l\'estiu, a migdia, a la platja o la piscina (' .. beach .. '/400)')
check(count('townsfolk', 12 * 60, 6, { sunny = false, month = 7 }, 'beach') == 0, 'si no fa sol, ningú a la platja')
check(count('townsfolk', 12 * 60, 6, { sunny = true, month = 1 }, 'beach') == 0, 'al gener, ningú es banya')
check(count('kid', 12 * 60, 6, sunny_june, 'beach') > 40, 'els caps de setmana de sol els nens també van a la platja')
local garden = count('elder', 19 * 60 + 35, 2, { garden = true }, 'garden')
check(garden > 80, 'al vespre reguen el jardí (' .. garden .. '/400)')
check(count('elder', 19 * 60 + 35, 2, { garden = false }, 'garden') == 0, 'sense jardí, no reguen')
check(count('elder', 19 * 60 + 35, 2, { garden = true, wet = true }, 'garden') == 0, 'quan plou no reguen')
check(E.carry_after('bakery') == 'bread' and E.carry_after('shop') == 'bag' and E.carry_after('beach') == nil,
  'tornen del forn amb pa i del súper amb la bossa')
check(E.line('bakery', 3) ~= nil and E.line('garden', 0) ~= nil and E.line('res', 0) == nil, 'frases per a cada encàrrec')
check(E.seed('Marta', 100, 200) == E.seed('Marta', 100, 200) and E.seed('Marta', 100, 200) ~= E.seed('Pere', 100, 200),
  'llavor estable i diferent per persona')
if fails > 0 then print(fails .. ' FALLADES'); os.exit(1) end
print('TOTS ELS ENCÀRRECS OK')
