-- Pruebas del RPG, botín, vehículos, acompañante y desnivel (luajit tests/rpg_cases.lua).
package.path = './?.lua;' .. package.path
love = { keyboard = { isDown = function() return false end }, math = { newRandomGenerator = function()
  return { random = function(_, a, b) return a or 0.5 end } end }, graphics = {} }
local Rpg = require('src.systems.rpg')
local Loot = require('src.systems.loot')
local Vehicles = require('src.systems.vehicles')
local Follower = require('src.entities.follower')
local Collision = require('src.world.collision')
local State = require('src.state')
local json = require('src.lib.json')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end
local function read(p) local f = assert(io.open(p)); local s = f:read('*a'); f:close(); return s end
local items = json.decode(read('data/items.json'))
local loot = json.decode(read('data/loot.json'))
local world = json.decode(read('data/world.json'))

-- ---------------------------------------------------------------- nivel y experiencia
local st = State.new(world)
check(st.char_level == 1 and st.xp == 0 and st.next_xp == 100 and st.coins == 0, 'partida nueva: nivel 1, 0 XP, 0 monedas')
local s0 = Rpg.stats(st, items)
check(s0.total_attack == 10 and s0.total_defense == 5, 'estadísticas base: ataque 10, defensa 5')
local hp0 = st.max_hp
st.hp = 1
check(Rpg.add_xp(st, 99) == 0 and st.char_level == 1, '99 XP: aún nivel 1')
check(Rpg.add_xp(st, 1) == 1 and st.char_level == 2 and st.xp == 0 and st.next_xp == 150, '100 XP: nivel 2, siguiente a 150')
check(st.max_hp == hp0 + 2 and st.hp == st.max_hp, 'subir de nivel: +1 corazón y vida llena')
local s1 = Rpg.stats(st, items)
check(s1.attack == 13 and s1.defense == 7, 'subir de nivel: +3 ataque, +2 defensa')
check(Rpg.add_xp(st, 150 + 225) == 2 and st.char_level == 4, 'mucha XP de golpe: varios niveles')
for _ = 1, 30 do Rpg.add_xp(st, st.next_xp) end
check(st.max_hp == Rpg.MAX_HP, 'la vida máxima tiene tope (' .. Rpg.MAX_HP .. ')')

-- ---------------------------------------------------------------- equipo
st = State.new(world)
State.give(st, 'sword_wood'); State.give(st, 'sword_iron'); State.give(st, 'armadura_cuir'); State.give(st, 'casc_bici')
check(Rpg.equip(st, items, 'sword_wood') and st.equipment.weapon == 'sword_wood', 'equipar espada de madera')
local ok, why = Rpg.equip(st, items, 'sword_iron')
check(not ok and why == 'Requereix nivell 3', 'la espada de hierro pide nivel 3')
check(not Rpg.equip(st, items, 'shield_plata'), 'no se equipa lo que no se tiene')
Rpg.add_xp(st, 100)
check(Rpg.equip(st, items, 'armadura_cuir') and Rpg.equip(st, items, 'casc_bici'), 'armadura y casco en sus ranuras')
local s2 = Rpg.stats(st, items)
check(s2.bonus_attack == 2 and s2.bonus_defense == 5, 'bonus del equipo (+2 ataque, +5 defensa)')
Rpg.unequip(st, 'armor')
check(Rpg.stats(st, items).bonus_defense == 1, 'quitar la armadura resta su defensa')
st.char_level = 3; Rpg.equip(st, items, 'sword_iron')
check(st.equipment.weapon == 'sword_iron', 'equipar sustituye lo que había en la ranura')

-- ---------------------------------------------------------------- daño
st = State.new(world)
check(Rpg.damage_dealt(st, items, items.sword_wood) == 1, 'nivel 1 con espada de madera: 1 de daño')
State.give(st, 'sword_bera'); Rpg.equip(st, items, 'sword_bera')
check(Rpg.damage_dealt(st, items, items.sword_bera) == 3, 'espada de Berà (+5 ataque): 3 de daño')
check(Rpg.damage_taken(st, items, 2) == 2, 'defensa 5: no reduce un golpe de 2')
st.base.defense = 25
check(Rpg.damage_taken(st, items, 2) == 1 and Rpg.damage_taken(st, items, 1) == 1, 'mucha defensa: mínimo 1 de daño')

-- ---------------------------------------------------------------- monedas y consumibles
st = State.new(world)
check(not Rpg.pay(st, 5) and st.coins == 0, 'sin monedas no se paga')
Rpg.earn(st, 12)
check(Rpg.pay(st, 5) and st.coins == 7, 'pagar descuenta')
State.give(st, 'pa'); st.hp = 2
check(Rpg.use(st, items, 'pa') and st.hp == 4 and not st.inventory.pa, 'el pan cura 1 corazón y se gasta')
State.give(st, 'farmaciola'); st.hp = 1
Rpg.use(st, items, 'farmaciola')
check(st.hp == st.max_hp, 'la farmaciola cura del todo')
State.give(st, 'poma')
check(Rpg.use(st, items, 'poma') == 'Ja tens tota la vida' and st.inventory.poma == 1, 'con la vida llena no se gasta comida')

-- ---------------------------------------------------------------- botín
local a = Loot.roll(loot, 'wood', 'cofre_fusta_1')
local b = Loot.roll(loot, 'wood', 'cofre_fusta_1')
check(#a.items == 2 and a.items[1] == b.items[1] and a.coins == b.coins, 'mismo cofre → mismo botín (determinista)')
check(a.items[1] ~= a.items[2], 'sin repetir objeto en un cofre')
check(a.coins >= 3 and a.coins <= 8, 'monedas dentro del rango del cofre de madera')
local leg = Loot.roll(loot, 'legend', 'cofre_masmorra_4')
check(leg.items[1] == 'pla_cotxe' and #leg.items == 4, 'el cofre legendario siempre trae el plano del coche')
st = State.new(world)
Loot.apply(st, items, leg)
check(st.vehicles.cotxe and st.inventory.pla_cotxe == 1 and st.coins >= 60, 'el plano desbloquea el coche y suma monedas')
local seen = {}
for i = 1, 40 do for _, id in ipairs(Loot.roll(loot, 'iron', 'c' .. i).items) do seen[id] = true end end
local kinds = 0
for _ in pairs(seen) do kinds = kinds + 1 end
check(kinds >= 5, 'variedad de botín en cofres de hierro (' .. kinds .. ' objetos distintos)')

-- ---------------------------------------------------------------- vehículos
local open_map = { cell = function() return 0 end }
local body = { x = 100, y = 100, w = 10, h = 8, level = 0 }
local v = Vehicles.new_state('scooter', 'right')
for _ = 1, 60 do Vehicles.update(v, body, 1, 0, 1 / 60, open_map, {}) end
check(v.speed > 150 and v.speed <= 205 and body.x > 180, string.format('acelera hacia la máxima (%.0f px/s)', v.speed))
local sp = v.speed
for _ = 1, 30 do Vehicles.update(v, body, 0, 0, 1 / 60, open_map, {}) end
check(v.speed < sp * 0.6 and v.speed > 0, 'sin gas: rozamiento (0,98 por paso)')
v.speed = 200
for _ = 1, 20 do Vehicles.update(v, body, -1, 0, 1 / 60, open_map, {}) end
check(v.speed < 60, 'pedir el sentido contrario frena')
v = Vehicles.new_state('cotxe', 'right'); v.speed = 200
Vehicles.update(v, body, 0, 1, 1 / 60, open_map, {})
check(math.abs(v.angle - 3.6 / 60) < 0.01, 'el giro está limitado por la manejabilidad')
v = Vehicles.new_state('bici', 'right')
Vehicles.update(v, body, 0, 1, 1 / 60, open_map, {})
check(math.abs(v.angle - math.pi / 2) < 1e-6, 'parado gira en el sitio')
check(Vehicles.facing(0) == 'right' and Vehicles.facing(math.pi / 2) == 'down' and Vehicles.facing(-math.pi / 2) == 'up',
  'dirección del sprite según el rumbo')
-- pendiente y superficie: mapa con altura que sube hacia el este
local hill = { cell = function() return 0 end,
               height_at = function(_, tx, ty) return tx * 2, 1 end }
local flat = { cell = function() return 0 end, height_at = function() return 0, 1 end }
local b1, b2 = { x = 100, y = 100, w = 10, h = 8, level = 0 }, { x = 100, y = 100, w = 10, h = 8, level = 0 }
local up, fl = Vehicles.new_state('scooter', 'right'), Vehicles.new_state('scooter', 'right')
for _ = 1, 120 do Vehicles.update(up, b1, 1, 0, 1 / 60, hill, {}); Vehicles.update(fl, b2, 1, 0, 1 / 60, flat, {}) end
check(up.speed < fl.speed * 0.75, string.format('cuesta arriba va más lento (%.0f frente a %.0f)', up.speed, fl.speed))
local field = { cell = function() return 0 end, height_at = function() return 0, 0 end }
local car, b3 = Vehicles.new_state('cotxe', 'right'), { x = 100, y = 100, w = 10, h = 8, level = 0 }
local enduro, b4 = Vehicles.new_state('motocross', 'right'), { x = 100, y = 100, w = 10, h = 8, level = 0 }
for _ = 1, 180 do Vehicles.update(car, b3, 1, 0, 1 / 60, field, {}); Vehicles.update(enduro, b4, 1, 0, 1 / 60, field, {}) end
check(car.speed < 110 and enduro.speed > 190, 'campo a través: el coche se atasca, la moto de enduro no')

-- ---------------------------------------------------------------- desnivel (canTraverse)
local terr = { cell = function() return 0 end,
               height_at = function(_, tx, ty) if tx >= 10 then return 20, (tx == 12 and 3 or 1) end return 0, 1 end }
local walker = { x = 9 * 16 + 8, y = 40, w = 10, h = 8, level = 0 }
check(not Collision.can_traverse(walker, terr, 9, 2, 10, 2), 'no se sube un desnivel de 2 niveles (16 m) de golpe')
walker.max_slope = 3
check(Collision.can_traverse(walker, terr, 9, 2, 10, 2), 'con max_slope mayor sí (p. ej. escaladores)')
local rider = { x = 11 * 16 + 8, y = 40, w = 10, h = 8, level = 0, no_stairs = true }
check(not Collision.can_traverse(rider, terr, 11, 2, 12, 2), 'los vehículos no suben escaleras')
check(Collision.can_traverse({ level = 0 }, terr, 11, 2, 12, 2), 'a pie, las escaleras sí')

-- ---------------------------------------------------------------- Olaf
local f = Follower.new('Olaf', nil, 100, 100, 20)
for i = 1, 60 do f:update(1 / 60, 100 + i * 2, 100) end
local gap = 100 + 120 - f.x
check(math.abs(gap - 20) < 1.5 and f.facing == 'right', string.format('Olaf sigue a 20 px por el camino (%.1f)', gap))
for i = 1, 60 do f:update(1 / 60, 220, 100 + i * 2) end
check(math.abs(f.x - 220) < 0.5 and f.facing == 'down', 'Olaf dobla la esquina por el mismo camino')
f:update(1 / 60, 900, 900)
check(math.abs(f.x - 900) < 20 and math.abs(f.y - 900) < 20, 'tras un salto largo (tren, bus) aparece junto al jugador')

print(fails == 0 and 'TODAS LAS PRUEBAS DE RPG/BOTÍN/VEHÍCULOS/OLAF OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
