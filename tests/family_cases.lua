-- Pares i interiors de cases d'amics (luajit tests/family_cases.lua des de l'arrel).
package.path = './?.lua;./?/init.lua;' .. package.path
local Family = require('src.systems.family')
local Procgen = require('src.world.procgen')
local Profile = require('src.profile')

local fails = 0
local function check(cond, msg)
  print((cond and 'OK   ' or 'FAIL ') .. msg)
  if not cond then fails = fails + 1 end
end

-- horari: de nit al llit, matí a la cuina, migdia el pare al despatx entre setmana i al sofà el cap de setmana
check(Family.slot('pare', 23 * 60, 2) == 'bed' and Family.slot('mare', 6 * 60, 2) == 'bed', 'de nit dormen')
check(Family.slot('mare', 7 * 60 + 30, 2) == 'kitchen', 'al matí la mare és a la cuina')
check(Family.slot('pare', 12 * 60, 2) == 'office', 'entre setmana el pare és al despatx a migdia')
check(Family.slot('pare', 12 * 60, 6) == 'sofa' or Family.slot('pare', 12 * 60, 7) == 'sofa', 'el cap de setmana el pare és al sofà')
for _, r in ipairs(Family.ROLES) do
  local ok = true
  for m = 0, 1439, 30 do
    local s = Family.slot(r, m, 3)
    if not (s == 'bed' or s == 'kitchen' or s == 'sofa' or s == 'office') then ok = false end
  end
  check(ok, r .. ': cada franja horària té un lloc vàlid')
end

-- scan sobre un interior sintètic: cel·les lliures al costat dels mobles
local W, H = 6, 5
local spec = { w = W, h = H, structures = {}, ground = {} }
for i = 1, W * H do spec.structures[i] = ''; spec.ground[i] = 'i_floor_wood_0' end
spec.structures[1 * W + 2 + 1] = 'i_stove'
spec.structures[3 * W + 3 + 1] = 'i_sofa'
spec.structures[2 * W + 1 + 1] = 'i_fridge'
local defs = { i_stove = { solid = true }, i_sofa = { solid = true }, i_fridge = { solid = true }, i_floor_wood_0 = {} }
local sc = Family.scan(spec, defs)
check(#sc.kitchen > 0 and #sc.sofa > 0 and #sc.fridge > 0, 'scan troba cuina, sofà i nevera')
local free = true
for _, k in ipairs({ 'kitchen', 'sofa', 'fridge' }) do
  for _, c in ipairs(sc[k]) do if spec.structures[c.y * W + c.x + 1] ~= '' then free = false end end
end
check(free, 'les cel·les de scan estan lliures')

-- diàlegs: en català, sempre amb salutació; els de nit manen anar a dormir; amb mala cara, la nevera
local l = Family.lines({ name = 'Aina', role = 'mare', slot = 'kitchen', clock = 12 * 60, talks = 1, we = false })
check(l[1]:find('Aina') ~= nil and #l >= 2, 'diàleg amb el nom del jugador')
local lt = table.concat(Family.lines({ name = 'Aina', role = 'pare', clock = 23 * 60, talks = 1 }), ' ')
check(lt:find('dormir') ~= nil, 'de nit diuen d\'anar a dormir')
local lh = table.concat(Family.lines({ name = 'Aina', role = 'pare', clock = 12 * 60, hp = 2, max_hp = 20, talks = 1 }), ' ')
check(lh:find('nevera') ~= nil, 'amb poca vida suggereixen la nevera')
local ask = false
for k = 1, 4 do
  if table.concat(Family.lines({ name = 'A', role = 'pare', clock = 12 * 60, talks = k, we = true }), ' '):find('escola') then ask = true end
end
check(ask, 'pregunten per l\'escola')
check(#Family.friend_lines({ name = 'Aina', friend = 'Pau', role = 'mare', here = true, talks = 1 }) >= 1, 'diàleg dels pares d\'un amic')

-- decoració per rol: sempre accessible, amb mobles propis i la mateixa llavor dóna el mateix interior
local function snap(s) return table.concat(s.structures, ',') .. '|' .. table.concat(s.ground, ',') end
local function reach_lost(s)
  local w, h = s.w, s.h
  local function at(x, y) return s.structures[y * w + x + 1] end
  local seen, q, head = { [s.spawn[2] * w + s.spawn[1]] = true }, { { s.spawn[1], s.spawn[2] } }, 1
  while q[head] do
    local x, y = q[head][1], q[head][2]; head = head + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      if nx > 0 and ny > 1 and nx < w - 1 and ny < h - 1 and not seen[ny * w + nx] and (at(nx, ny) == '' or at(nx, ny) == 'i_shower') then
        seen[ny * w + nx] = true; q[#q + 1] = { nx, ny }
      end
    end
  end
  local lost = 0
  for y = 2, h - 2 do for x = 1, w - 2 do if at(x, y) == '' and not seen[y * w + x] then lost = lost + 1 end end end
  return lost
end
local function count(s, name) local n = 0 for _, v in ipairs(s.structures) do if v == name then n = n + 1 end end return n end

local bad, determ, kinds = 0, true, {}
for _, age in ipairs({ 'kid', 'adult', 'elder' }) do
  local extra = 0
  for seed = 1, 60 do
    local a = Procgen.generate({ kind = 'house', seed = seed * 7919 })
    local base_lost = reach_lost(a)
    local plain = count(a, 'i_armchair') + count(a, 'i_toys') + count(a, 'i_desk') + count(a, 'i_clock') + count(a, 'i_bike')
    Procgen.enrich(a, { seed = seed, age = age })
    if reach_lost(a) > base_lost then bad = bad + 1 end
    local b = Procgen.enrich(Procgen.generate({ kind = 'house', seed = seed * 7919 }), { seed = seed, age = age })
    if snap(a) ~= snap(b) then determ = false end
    extra = extra + count(a, 'i_armchair') + count(a, 'i_toys') + count(a, 'i_desk') + count(a, 'i_clock') + count(a, 'i_bike') - plain
    local f = Procgen.generate({ kind = 'flat', seed = seed * 31 })
    local fl = reach_lost(f)
    Procgen.enrich(f, { seed = seed, age = age })
    if reach_lost(f) > fl then bad = bad + 1 end
  end
  kinds[age] = extra
end
check(bad == 0, 'enrich no deixa cel·les aïllades (cases i pisos, 3 edats, 60 llavors)')
check(determ, 'enrich és determinista per llavor')
check(kinds.elder > 60 and kinds.kid > 60 and kinds.adult > 60, 'enrich afegeix mobles de rol a cada casa')

-- pares d'amic: noms editats, avis sense pares, sense encastar-se a mobles i de nit no es veuen
local g = { tile_defs = {}, sprites = { chars = {} } }
for _, n in ipairs({ 'i_stove', 'i_counter', 'i_sink', 'i_fridge', 'i_sofa', 'i_armchair', 'i_table', 'i_wall', 'i_wall_top', 'i_bed_b',
                     'i_bed_t', 'i_tv', 'i_shelf', 'i_plant', 'i_lamp', 'i_toys', 'i_box', 'i_pc', 'i_bike', 'i_wardrobe' }) do
  g.tile_defs[n] = { solid = true }
end
g.tile_defs.i_floor_wood_0 = {}; g.tile_defs.i_floor_wood_1 = {}; g.tile_defs.i_floor_tile_0 = {}; g.tile_defs.i_floor_tile_1 = {}
g.tile_defs.i_rug_c = {}; g.tile_defs.i_rug = {}; g.tile_defs.i_exit = {}
local fr = { id = 'fx', role = 'amic', name = 'Pau', parents = { pare = 'Jordi', mare = 'Marta' } }
-- (sense LÖVE: Looks.build no es pot cridar; el sprite ja hi és)
g.sprites.chars['fparent_pare_fx'], g.sprites.chars['fparent_mare_fx'] = {}, {}
local house = Procgen.enrich(Procgen.generate({ kind = 'house', seed = 99 }), { seed = 1, age = 'kid' })
local ps = Family.friend_parents(g, house, fr, { clock = 12 * 60, day = 3 })
local names = {}
for _, o in ipairs(ps) do names[o.parent] = o.name end
check(#ps == 2 and names.pare == 'Jordi' and names.mare == 'Marta', 'els pares de l\'amic porten el nom editat')
local ok_cells = true
for _, o in ipairs(ps) do if house.structures[o.y * house.w + o.x + 1] ~= '' or o.owner ~= 'fx' then ok_cells = false end end
check(ok_cells, 'els pares ocupen cel·les lliures i tenen amo')
check(#Family.friend_parents(g, house, { id = 'fa', role = 'avia', name = 'Rosa' }, { clock = 12 * 60, day = 3 }) == 0, 'els avis no tenen pares a casa')
check(#Family.friend_parents(g, house, fr, { clock = 23 * 60, day = 3 }) == 0, 'de nit els pares dormen')
check(Profile.parents_of(nil, fr).pare == 'Jordi', 'Profile.parents_of respecta els noms editats')

print(fails == 0 and 'OK: family_cases' or ('FAIL: ' .. fails))
os.exit(fails == 0 and 0 or 1)
