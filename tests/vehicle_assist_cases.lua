-- Conducció assistida (luajit tests/vehicle_assist_cases.lua): amb la fletxa dreta fixa per una carretera que es
-- va torçant cap avall, el vehicle la segueix; sense assistència en surt. Fora de la via no fa res.
package.path = './?.lua;' .. package.path
local V = require('src.systems.vehicles')
local n_ok = 0
local function check(c, msg) if not c then error('FALLA: ' .. msg) end; n_ok = n_ok + 1; print('OK   ' .. msg) end
-- mapa de 120 × 60: carretera de 3 caselles d'ample que baixa una casella cada 3 (≈ 18°)
local W, H = 120, 60
local function road_y(tx) return 10 + math.floor(tx / 3) end
local map = { chunk = 32 }
function map:in_bounds(tx, ty) return tx >= 0 and ty >= 0 and tx < W and ty < H end
function map:cell(tx, ty) return 0 end
function map:height_at(tx, ty)
  local r = road_y(tx)
  return 0, (ty >= r - 1 and ty <= r + 1) and 1 or 0
end
function map:component() return 1 end
local function drive(assist)
  local st = V.new_state('bici', 'right'); st.assist = assist
  local body = { x = 2 * 16 + 8, y = road_y(2) * 16 + 8, w = 10, h = 8, level = 0 }
  local on = 0
  for _ = 1, 600 do
    V.update(st, body, 1, 0, 1 / 60, map, {})
    local tx, ty = math.floor(body.x / 16), math.floor(body.y / 16)
    local _, surf = map:height_at(tx, ty)
    if surf == 1 then on = on + 1 end
  end
  return on, body
end
local on_a, ba = drive(true)
local on_n, bn = drive(false)
check(on_a > 560, 'amb assistència segueix la carretera (' .. on_a .. '/600 fotogrames a la via)')
check(on_n < 400, 'sense, se\'n surt recte (' .. on_n .. '/600)')
check(ba.y > bn.y + 40, 'i acaba més avall, on va la carretera')
-- fora de la via: el rumb és el que demanes
local st = V.new_state('bici', 'right'); st.speed = 100
local body = { x = 50 * 16, y = 50 * 16, w = 10, h = 8, level = 0 }
check(V.assist(st, body, 0, map) == 0, 'al camp no corregeix res')
-- un gir clar (perpendicular a la via) no es corregeix
body.x, body.y = 30 * 16 + 8, road_y(30) * 16 + 8
check(math.abs(V.assist(st, body, -math.pi / 2, map) + math.pi / 2) < 1e-9, 'si demanes sortir de la via, en surts')
-- carretera a 50° (avall a la dreta) i només la fletxa dreta: la segueix
local map2 = { chunk = 32 }
local function r2(tx) return 5 + math.floor(tx * 1.2) end
function map2:in_bounds(tx, ty) return tx >= 0 and ty >= 0 and tx < 120 and ty < 120 end
function map2:cell() return 0 end
function map2:height_at(tx, ty) local r = r2(tx); return 0, (ty >= r - 2 and ty <= r + 2) and 1 or 0 end
do
  local st2 = V.new_state('bici', 'right')
  local b2 = { x = 10 * 16 + 8, y = r2(10) * 16 + 8, w = 10, h = 8, level = 0 }
  local on = 0
  for _ = 1, 300 do
    V.update(st2, b2, 1, 0, 1 / 60, map2, {})
    local _, sf = map2:height_at(math.floor(b2.x / 16), math.floor(b2.y / 16))
    if sf == 1 then on = on + 1 end
  end
  check(on > 280, 'amb la fletxa dreta, segueix la carretera que baixa a 50° (' .. on .. '/300)')
end
-- algú al davant (st.obs): peató al mig → l'esquiva; cotxe que va igual → s'hi posa darrere; sense lloc → frena
do
  local st3 = V.new_state('bici', 'right'); st3.speed = 100; st3.angle = 0
  local b3 = { x = 40 * 16 + 8, y = road_y(40) * 16 + 8, w = 10, h = 8, level = 0 }
  local base = V.assist(st3, b3, 0, map)
  st3.obs = { { x = b3.x + 30, y = b3.y + math.sin(base) * 30, r = 6, kind = 'ped' } }
  local a = V.assist(st3, b3, 0, map)
  check(math.abs(V.angle_diff(base, a)) > 0.2 and not st3.cap, 'un peató al davant: l\'esquiva')
  st3.obs = { { x = b3.x + 50 * math.cos(base), y = b3.y + 50 * math.sin(base), r = 10, kind = 'car', ang = base, v = 60 } }
  V.assist(st3, b3, 0, map)
  check(st3.cap and st3.cap > 30 and st3.cap <= 63 and st3.yield == 'car', 'un cotxe al davant: va darrere a la seva velocitat (' .. tostring(st3.cap) .. ')')
  local wall = {}
  for k = -3, 3 do wall[#wall + 1] = { x = b3.x + 24 * math.cos(base) - k * 9 * math.sin(base), y = b3.y + 24 * math.sin(base) + k * 9 * math.cos(base), r = 6, kind = 'ped' } end
  st3.obs = wall
  V.assist(st3, b3, 0, map)
  check(st3.cap and st3.cap < 40, 'una colla de gent que tapa la via: frena (' .. tostring(st3.cap) .. ')')
end
-- eix de via (src/systems/roads.lua): carretera en L sobre camp obert. Amb la fletxa dreta fixa, la segueix i
-- gira el revolt; per la dreta de l'eix (carril)
do
  local Roads = require('src.systems.roads')
  Roads.set_data({ lines = { { c = 'road', p = { 40, 100, 400, 100 } }, { c = 'road', p = { 400, 100, 400, 600 } } } })
  local open = { chunk = 32 }
  function open:in_bounds(tx, ty) return tx >= 0 and ty >= 0 and tx < 60 and ty < 60 end
  function open:cell() return 0 end
  function open:height_at() return 0, 0 end
  local st4 = V.new_state('scooter', 'right')
  local b4 = { x = 60, y = 100, w = 10, h = 8, level = 0 }
  local maxdev, lanes = 0, 0
  for i = 1, 480 do
    st4.lines = Roads.near(b4.x, b4.y, 40, st4.lines)
    V.update(st4, b4, 1, 0, 1 / 60, open, {})
    if b4.x < 380 and i > 30 then maxdev = math.max(maxdev, math.abs(b4.y - 100 - V.LANE)); lanes = lanes + 1 end
  end
  check(maxdev < 4, 'segueix l\'eix pel carril de la dreta (desviació màxima ' .. string.format('%.1f', maxdev) .. ' px)')
  check(b4.y > 250 and math.abs(b4.x - 400 + V.LANE) < 8, 'i gira el revolt de 90° encara que mantinguis la dreta (' ..
    math.floor(b4.x) .. ', ' .. math.floor(b4.y) .. ')')
  -- cruïlla en T: amb la dreta, recte; si en arribar-hi prems avall, agafa el carrer que baixa
  Roads.set_data({ lines = { { c = 'road', p = { 40, 100, 800, 100 } }, { c = 'road', p = { 400, 100, 400, 600 } } } })
  local function drive2(steps)
    local st5 = V.new_state('scooter', 'right')
    local b5 = { x = 60, y = 105, w = 10, h = 8, level = 0 }
    for _, sp in ipairs(steps) do
      for _ = 1, sp[3] do
        st5.lines = Roads.near(b5.x, b5.y, 40, st5.lines)
        V.update(st5, b5, sp[1], sp[2], 1 / 60, open, {})
      end
    end
    return b5
  end
  local s1 = drive2({ { 1, 0, 300 } })
  check(s1.x > 480 and math.abs(s1.y - 105) < 6, 'a la cruïlla, amb la dreta segueix recte (' .. math.floor(s1.x) .. ', ' .. math.floor(s1.y) .. ')')
  local s2 = drive2({ { 1, 0, 100 }, { 0, 1, 200 } })
  check(s2.y > 200 and math.abs(s2.x - 395) < 10, 'prement avall a la cruïlla, gira pel carrer que baixa (' .. math.floor(s2.x) .. ', ' .. math.floor(s2.y) .. ')')
  -- cul-de-sac: la via s'acaba a x = 300; amb la dreta, en arribar al final segueix recte pel camp (no gira en rodó)
  Roads.set_data({ lines = { { c = 'road', p = { 40, 100, 300, 100 } } } })
  local st6 = V.new_state('scooter', 'right')
  local b6 = { x = 60, y = 105, w = 10, h = 8, level = 0 }
  local miny, maxy = 1e9, -1e9
  for _ = 1, 400 do
    st6.lines = Roads.near(b6.x, b6.y, 40, st6.lines)
    V.update(st6, b6, 1, 0, 1 / 60, open, {})
    if b6.x > 290 then miny, maxy = math.min(miny, b6.y), math.max(maxy, b6.y) end
  end
  check(b6.x > 420 and maxy - miny < 12, 'al final del camí deixa de guiar i continua cap on demanes (' ..
    math.floor(b6.x) .. ', ' .. math.floor(b6.y) .. ')')
  Roads.set_data(nil)
end
print('TOTES LES PROVES DE CONDUCCIÓ ASSISTIDA OK (' .. n_ok .. ')')
