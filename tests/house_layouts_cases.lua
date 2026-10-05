-- 10 distribucions de casa (luajit tests/house_layouts_cases.lua): per a cada tipus i moltes llavors, a la casa,
-- al pis i a la planta de dalt, tota casella lliure s'enllaça amb la sortida (o amb l'escala), hi ha les
-- habitacions de la distribució i la mateixa llavor dona sempre el mateix interior. `ascii` en dibuixa un de cada.
package.path = './?.lua;' .. package.path
local P = require('src.world.procgen')
local HL = require('src.world.house_layouts')
local n_ok = 0
local function check(c, msg) if not c then error('FALLA: ' .. msg) end; n_ok = n_ok + 1 end
local WALK = { [''] = true, i_shower = true }
local function reachable(s, sx, sy)
  local w, h = s.w, s.h
  local function at(x, y) return s.structures[y * w + x + 1] end
  local seen, q, head = { [sy * w + sx] = true }, { { sx, sy } }, 1
  while q[head] do
    local x, y = q[head][1], q[head][2]; head = head + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      if nx > 0 and ny > 1 and nx < w - 1 and ny < h - 1 and not seen[ny * w + nx] and WALK[at(nx, ny)] then
        seen[ny * w + nx] = true; q[#q + 1] = { nx, ny }
      end
    end
  end
  local lost = 0
  for y = 2, h - 2 do for x = 1, w - 2 do if WALK[at(x, y)] and not seen[y * w + x] then lost = lost + 1 end end end
  return lost
end
local used = {}
for layout = 1, HL.COUNT do
  for seed = 1, 60 do
    local sd = seed * 7919 + layout * 104729
    for _, kind in ipairs({ 'house', 'flat' }) do
      local s = P.generate({ kind = kind, seed = sd, layout = layout })
      check(reachable(s, s.spawn[1], s.spawn[2]) == 0, kind .. ' ' .. layout .. ' llavor ' .. sd .. ': tot enllaçat amb la sortida')
      check(#P.rooms(s) >= 3, kind .. ' ' .. layout .. ': com a mínim 3 habitacions')
      used[s.layout] = (used[s.layout] or 0) + 1
    end
    local b = P.building({ kind = 'house', seed = sd, base = 'x', floors = 2 })
    local up = b.specs.x_p1
    check(reachable(up, 1, 3) == 0, 'planta de dalt ' .. layout .. ': tot enllaçat amb l\'escala')
    local again = P.building({ kind = 'house', seed = sd, base = 'x', floors = 2 })
    check(table.concat(again.specs.x.structures, ',') == table.concat(b.specs.x.structures, ','), 'mateixa llavor, mateixa casa')
  end
end
local kept = 0
for k = 1, HL.COUNT do if (used[k] or 0) > 60 then kept = kept + 1 end end
check(kept >= 9, 'gairebé totes les distribucions surten tal qual (' .. kept .. '/10; la resta torna a la clàssica si no hi cap)')
-- la porta tria el tipus: de 400 portes, surten els 10
local seen = {}
for i = 1, 400 do seen[HL.pick(i * 7919 + (i % 37) * 104729)] = true end
local k = 0; for _ in pairs(seen) do k = k + 1 end
check(k == HL.COUNT, 'les portes reparteixen els 10 tipus')
if arg[1] == 'ascii' then
  for layout = 1, HL.COUNT do
    local s = P.generate({ kind = 'house', seed = 4242 + layout, layout = layout })
    print(layout .. ' ' .. HL.NAMES[layout] .. ' ' .. s.w .. 'x' .. s.h)
    for y = 0, s.h - 1 do
      local row = {}
      for x = 0, s.w - 1 do
        local t = s.structures[y * s.w + x + 1]
        local g = s.ground[y * s.w + x + 1]
        row[#row + 1] = (t == 'i_wall_top' or t == 'i_wall' or t == 'i_wall_window') and '#' or (t ~= '' and 'o')
          or (g:match('^g_grass') and ',' or (g == 'i_exit' and 'E' or '.'))
      end
      print(table.concat(row))
    end
  end
end
print('TOTES LES PROVES DE DISTRIBUCIONS DE CASA OK (' .. n_ok .. ')')
