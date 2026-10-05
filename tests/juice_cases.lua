-- Pruebas de la fase 4 sin ventana (luajit tests/juice_cases.lua): partículas con tope, números flotantes,
-- sacudida, elección de música adaptativa, tráfico con motos/patinetes y peatones en los pasos de cebra.
package.path = './?.lua;./?/init.lua;' .. package.path
love = { math = { random = math.random } }
local Particles = require('src.fx.particles')
local Popups = require('src.fx.popups')
local Shake = require('src.fx.shake')
local Audio = require('src.audio')
local Traffic = require('src.systems.traffic')
local Pedestrians = require('src.systems.pedestrians')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end
local DT = 1 / 60

-- ---------------------------------------------------------------- partículas
local p = Particles.new(50, function() return 0.5 end)
p:burst(0, 0, 80, { 1, 1, 1 }, 10, 0.5, 2)
check(p.n == 50 and p.dropped == 30, 'el bloque no crece: 50 de tope, 30 descartadas')
for _ = 1, 20 do p:update(DT) end
check(p.n == 50, 'a media vida siguen todas')
for _ = 1, 30 do p:update(DT) end
check(p.n == 0, 'al acabar la vida desaparecen (sin table.remove)')
local q = Particles.new(10, function() return 0.5 end)
q:add(0, 0, 0, 0, 1, 1, 1, 1, 1, 0); q:add(5, 5, 0, 0, 0.1, 1, 1, 1, 1, 0); q:add(9, 9, 0, 0, 1, 0.5, 0.5, 0.5, 1, 0)
for _ = 1, 10 do q:update(DT) end
check(q.n == 2 and q.x[2] == 9 and q.r[2] == 0.5, 'la que muere se cambia por la última (orden y campos intactos)')
local sp = Particles.new(10, function() return 0.5 end)
sp:preset('spark', 0, 0, 1, { dir = 0, spread = 0 })
for _ = 1, 10 do sp:update(DT) end
check(sp.vy[1] > 0, 'las chispas caen (gravedad)')
local lf = Particles.new(10, function() return 0.3 end)
lf:preset('leaf', 0, 0, 1)
for _ = 1, 60 do lf:update(DT) end
check(lf.n == 1 and lf.y[1] > 5 and lf.y[1] < 20, string.format('las hojas caen despacio (%.1f px en 1 s)', lf.y[1]))
for _, name in ipairs({ 'dust', 'skid', 'smoke', 'spark', 'sparkle', 'leaf', 'confetti', 'levelup' }) do
  local t = Particles.new(20); t:preset(name, 0, 0, 3)
  if t.n ~= 3 then check(false, 'efecto ' .. name) end
end
check(true, 'todos los efectos con nombre emiten')

-- ---------------------------------------------------------------- números flotantes
local pp = Popups.new()
pp:add(10, 10, '+20 XP', 'xp'); pp:add(10, 10, '+5 mon.', 'coins')
check(pp.list[2].lift > pp.list[1].lift, 'dos números a la vez en el mismo sitio: se apilan')
for i = 1, 20 do pp:add(i * 100, 0, '+1', 'hp') end
check(#pp.list == 10, 'como mucho 10 a la vez')
for _ = 1, 70 do pp:update(DT) end
check(#pp.list == 0, 'desaparecen en poco más de un segundo')
check(Popups.rise(0) == 0 and Popups.rise(1.1) > Popups.rise(0.5) and Popups.rise(0.5) > 11, 'suben rápido y se frenan')

-- ---------------------------------------------------------------- sacudida
local sh = Shake.new(function() return 1 end)
sh:add(0.5); sh:update(DT)
local x, y = sh:offset()
check(x ~= 0 and math.abs(x) <= Shake.MAX_X, 'un golpe sacude la cámara (píxeles enteros)')
for _ = 1, 60 do sh:update(DT) end
check(select(1, sh:offset()) == 0, 'y se calma sola')
for _ = 1, 30 do sh:set_rumble(0.4); sh:update(DT) end
check(math.abs(sh.level - 0.4) < 1e-9, 'el retumbo del tren no se acumula')
sh:update(DT)
check(sh.level == 0, 'el retumbo se apaga en cuanto el tren se va')

-- ---------------------------------------------------------------- música adaptativa
local function pick(ctx, prev) return (Audio.pick(ctx, prev)) end
check(pick({ scene = 'overworld', outdoor = true, clock = 600, height = 5 }) == 'day', 'de día en el pueblo: tema alegre')
local tr, amb = Audio.pick({ scene = 'overworld', outdoor = true, clock = 23 * 60, height = 5 })
check(tr == 'night' and amb.crickets, 'de noche: tema tranquilo con grillos')
tr, amb = Audio.pick({ scene = 'overworld', outdoor = true, clock = 600, height = 90 })
check(tr == 'peaks' and amb.wind, 'en las cimas: tema misterioso con viento')
check(pick({ scene = 'overworld', outdoor = true, clock = 600, height = 60 }, 'peaks') == 'peaks' and
      pick({ scene = 'overworld', outdoor = true, clock = 600, height = 60 }, 'day') == 'day', 'histéresis en la altura')
check(pick({ scene = 'cave', outdoor = false }) == 'cave', 'cuevas y mazmorra: tema misterioso')
check(pick({ scene = 'overworld', outdoor = true, minigame = 'arcade' }) == 'arcade', 'minijuego: tema arcade')
check(pick({ scene = 'overworld', minigame = 'none' }) == nil, 'minijuego de ritmo: sin música (lleva metrónomo)')

-- ---------------------------------------------------------------- tráfico
-- calle recta de este a oeste (y = 100), paso de cebra en x = 400
local function road_map()
  return { routes = { { type = 'route_car', name = 'road_test', points = { { 0, 100 }, { 1000, 100 } }, props = {} } },
           objects = { { type = 'crosswalk', x = 400, y = 100, props = { r = 14 } } } }
end
local rng = { random = function(_, a, b) if a then return a end return 0.1 end }
local T = Traffic.new(road_map(), { speed = 60, gap = 40, count = { road_test = 1 } }, rng)
check(T.crosswalks[1].ang ~= nil and math.abs(T.crosswalks[1].ang) < 1e-6, 'el paso de cebra sabe la dirección de la calle')
T:spawn(-999, -999)
local car = T.cars[1]
car.kind, car.s, car.v, car.dir = 'car', 200, 60, 1
local far_player = { body = { x = -500, y = -500, level = 0 } }
-- alguien cruzando: el coche se para antes de la cebra
T.crosswalks[1].crossing = 1
for _ = 1, 60 * 4 do T:update(DT, far_player) end
local cx = Traffic.pos(car)
check(car.v == 0 and cx < 400 - 14, string.format('peatón cruzando: el coche se para antes (x = %.0f)', cx))
T.crosswalks[1].crossing = 0
for _ = 1, 60 * 3 do T:update(DT, far_player) end
check(car.v > 30, 'cuando la cebra queda libre, sigue')
-- tipos de vehículo
local KM = Traffic.KINDS
check(KM.moto.speed > KM.car.speed and KM.patinete.speed < KM.car.speed and KM.patinete.w < KM.car.w,
  'motos más rápidas, patinetes más lentos y pequeños')
local T2 = Traffic.new(road_map(), { speed = 60, gap = 40, count = { road_test = 1 } }, rng)
T2:spawn(-999, -999)
local pat = T2.cars[1]
pat.kind, pat.s, pat.v, pat.dir = 'patinete', 10, 0, 1
for _ = 1, 60 * 3 do T2:update(DT, far_player) end
check(math.abs(pat.v - 60 * KM.patinete.speed) < 1, 'el patinete va a su velocidad')
-- peatón (obstáculo) en el carril fuera de la cebra: frena igual
local T3 = Traffic.new(road_map(), { speed = 60, gap = 40, count = { road_test = 1 } }, rng)
T3:spawn(-999, -999)
local c3 = T3.cars[1]
c3.kind, c3.s, c3.v, c3.dir = 'car', 600, 60, 1
for _ = 1, 60 * 3 do T3:update(DT, far_player, { { x = 700, y = 105, who = 'ped', level = 0 } }) end
check(c3.v == 0 and Traffic.pos(c3) < 700, 'detecta un peatón en la calzada y se para')
-- jugador plantado delante: espera y toca el claxon
local T4 = Traffic.new(road_map(), { speed = 60, gap = 40, count = { road_test = 1 } }, rng)
T4:spawn(-999, -999)
local c4 = T4.cars[1]
c4.kind, c4.s, c4.v, c4.dir = 'car', 600, 0, 1
local pl = { body = { x = 640, y = 105, level = 0 } }
local horns = 0
for _ = 1, 60 * 5 do T4:update(DT, pl); for _, e in ipairs(T4:take_events()) do if e.type == 'horn' then horns = horns + 1 end end end
check(horns == 1, 'jugador plantado en la calle: un toque de claxon (no uno por paso)')

-- ---------------------------------------------------------------- peatones
local T5 = Traffic.new(road_map(), { speed = 60, gap = 40, count = { road_test = 1 } }, rng)
T5.cars = {}
local P = Pedestrians.new(T5, function() return 0.3 end)
local ped = P:spawn_near(400, 160)
check(ped ~= nil and ped.state == 'approach', 'aparece un peatón junto al paso de cebra')
local states = {}
for _ = 1, 60 * 12 do P:update(DT, 400, 160); if P.list[1] then states[P.list[1].state] = true end end
check(states.wait and states.cross and states.leave, 'espera, cruza y se va')
check(math.abs(ped.c[2] - ped.b[2]) > 30 and math.abs(ped.c[1] - ped.b[1]) < 1, 'cruza perpendicular a la calle')
-- con un coche acercándose, espera en el bordillo
local T6 = Traffic.new(road_map(), { speed = 60, gap = 40, count = { road_test = 1 } }, rng)
T6:spawn(-999, -999)
local c6 = T6.cars[1]
c6.kind, c6.s, c6.v, c6.dir = 'car', 360, 60, 1
check(not Pedestrians.safe(T6.crosswalks[1], T6.cars, Traffic.pos), 'coche a 40 px que se acerca: no es seguro cruzar')
c6.s = 450
check(Pedestrians.safe(T6.crosswalks[1], T6.cars, Traffic.pos), 'coche que ya ha pasado y se aleja: se puede cruzar')
c6.s, c6.v = 370, 0
check(Pedestrians.safe(T6.crosswalks[1], T6.cars, Traffic.pos), 'coche parado ante la cebra: se puede cruzar')

print(fails == 0 and 'TODAS LAS PRUEBAS DE JUICE/AUDIO/TRÁFICO OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
