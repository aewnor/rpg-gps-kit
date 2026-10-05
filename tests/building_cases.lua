-- Edificis de diverses plantes (fase 6) sense ventana: luajit tests/building_cases.lua
-- Cada sortida porta a una escena que existeix i a un punt d'arribada que hi és; des de l'entrada de cada
-- planta s'arriba a totes les sortides; l'ascensor llista totes les plantes; mateixa llavor → mateix edifici.
package.path = './?.lua;./?/init.lua;' .. package.path
local json = require('src.lib.json')
local Procgen = require('src.world.procgen')
local f = assert(io.open('data/tiles.json')); local tiles = json.decode(f:read('*a')).tiles; f:close()

local fails = 0
local function check(c, m) if not c then print('FAIL ' .. m); fails = fails + 1 end; return c end

local function solid(spec, x, y, exits)
  if x < 0 or y < 0 or x >= spec.w or y >= spec.h then return true end
  if exits[y * spec.w + x] then return false end
  for _, l in ipairs({ 'ground', 'detail', 'structures' }) do
    local t = tiles[spec[l][y * spec.w + x + 1]]
    if t and t.solid then return true end
  end
  return false
end

-- comprova un edifici sencer
local function verify(b, label)
  local n = 0
  for id, spec in pairs(b.specs) do
    n = n + 1
    for _, l in ipairs({ 'ground', 'structures' }) do
      for i = 1, spec.w * spec.h do
        local nm = spec[l][i]
        if nm ~= '' and not tiles[nm] then check(false, label .. ' ' .. id .. ': tile desconegut ' .. nm) end
      end
    end
    local exits, spawns, start = {}, {}, nil
    for _, o in ipairs(spec.objects) do
      if o.type == 'exit' then exits[o.y * spec.w + o.x] = o end
      if o.type == 'spawn' then spawns[o.name] = o end
    end
    if spec.spawn then start = { spec.spawn[1], spec.spawn[2] } else
      for _, o in ipairs(spec.objects) do if o.type == 'spawn' and not start then start = { o.x, o.y } end end
    end
    check(start ~= nil, label .. ' ' .. id .. ': sense punt d\'entrada')
    -- abast des de l'entrada (4 veïns; les sortides són transitables però no s'hi passa a través)
    local seen, q, head = { [start[2] * spec.w + start[1]] = true }, { start }, 1
    while q[head] do
      local x, y = q[head][1], q[head][2]; head = head + 1
      if not exits[y * spec.w + x] then
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + d[1], y + d[2]
          if not seen[ny * spec.w + nx] and not solid(spec, nx, ny, exits) then
            seen[ny * spec.w + nx] = true; q[#q + 1] = { nx, ny }
          end
        end
      end
    end
    for k, o in pairs(exits) do
      check(seen[k], label .. ' ' .. id .. ': sortida inabastable a ' .. o.x .. ',' .. o.y)
      if o.target_scene then
        local dst = b.specs[o.target_scene]
        if check(dst, label .. ' ' .. id .. ': escena de destí inexistent ' .. o.target_scene) and o.target_spawn ~= 'spawn_in' then
          local ok = false
          for _, d in ipairs(dst.objects) do if d.type == 'spawn' and d.name == o.target_spawn then ok = true end end
          check(ok, label .. ' ' .. id .. ' → ' .. o.target_scene .. ': falta el punt ' .. tostring(o.target_spawn))
        end
      end
    end
    for name, sp in pairs(spawns) do
      check(seen[sp.y * spec.w + sp.x], label .. ' ' .. id .. ': punt ' .. name .. ' tancat')
      check(not exits[sp.y * spec.w + sp.x], label .. ' ' .. id .. ': punt ' .. name .. ' damunt d\'una sortida')
    end
    for _, o in ipairs(spec.objects) do
      if o.type == 'arcade' and o.game == 'lift' then
        check(#o.floors == b.floors, label .. ' ' .. id .. ': l\'ascensor no té totes les plantes')
        for _, fl in ipairs(o.floors) do check(b.specs[fl.scene], label .. ': planta de l\'ascensor inexistent') end
        check(spawns.lift, label .. ' ' .. id .. ': falta l\'arribada de l\'ascensor')
      end
    end
  end
  return n
end

local total, blocks, houses = 0, 0, 0
for seed = 1, 400 do
  local floors = seed % 6 + 1
  local kind = seed % 3 == 0 and 'house' or 'block'
  local b = Procgen.building({ kind = kind, seed = seed * 7919, base = 'proc_' .. seed, floors = floors })
  total = total + verify(b, kind .. '#' .. seed)
  if kind == 'block' then
    blocks = blocks + 1
    check(b.floors == math.max(2, floors), 'bloc amb les plantes demanades')
    check(b.specs[Procgen.flat_id('proc_' .. seed, b.floors - 1, b.flats)] ~= nil, 'pis de l\'última planta')
  else
    houses = houses + 1
    check(b.floors == (floors >= 2 and 2 or 1), 'casa: 1 o 2 plantes')
  end
end
local a = json.encode(Procgen.building({ kind = 'block', seed = 42, base = 'x', floors = 4 }).specs)
local c = json.encode(Procgen.building({ kind = 'block', seed = 42, base = 'x', floors = 4 }).specs)
check(a == c, 'mateixa llavor → mateix edifici')
print(string.format('%d edificis (%d blocs, %d cases), %d escenes', blocks + houses, blocks, houses, total))
print(fails == 0 and 'TOTES LES PROVES D\'EDIFICIS OK' or (fails .. ' FALLADES'))
os.exit(fails == 0 and 0 or 1)
