-- Pruebas de combate, equipo y bucle (luajit tests/combat_cases.lua).
package.path = './?.lua;' .. package.path
-- stubs mínimos de love para módulos que no dibujan
love = { keyboard = { isDown = function() return false end }, math = { newRandomGenerator = function()
  return { random = function(_, a, b) return a or 0.5 end } end } }
local Player = require('src.entities.player')
local Enemy = require('src.entities.enemy')
local State = require('src.state')
local Loop = require('src.loop')
local Input = require('src.input')
local json = require('src.lib.json')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end
local function read(p) local f = assert(io.open(p)); local s = f:read('*a'); f:close(); return s end
local items = json.decode(read('data/items.json'))
local world = json.decode(read('data/world.json'))
local open_map = { cell = function() return 0 end }

local function setup()
  local st = State.new(world)
  State.give(st, 'sword_wood'); State.give(st, 'shield_wood')
  State.equip(st, items, 'sword_wood'); State.equip(st, items, 'shield_wood')
  local p = Player.new(100, 100, 0, world.player)
  local ctx = { map = open_map, blockers = {}, state = st, items = items, player = p }
  return st, p, ctx
end
local NONE = { pressed = {} }
local function run(p, ctx, act, frames)
  for _ = 1, frames do p:update(1 / 60, act or NONE, ctx) end
end

-- ventanas de ataque: anticipación 0,08 / activa 0,10 / recuperación 0,18
local st, p, ctx = setup()
p.facing = 'right'
p:update(1 / 60, { pressed = { attack = true } }, ctx)
check(p.state == 'attack' and p:attack_box() == nil, 'durante la anticipación no hay caja de daño')
run(p, ctx, NONE, 5) -- t ≈ 0,10
check(p:attack_box() ~= nil, 'en la ventana activa hay caja de daño')
run(p, ctx, NONE, 8) -- t ≈ 0,23
check(p:attack_box() == nil and p.state == 'attack', 'en la recuperación no hay caja de daño')
run(p, ctx, NONE, 12)
check(p.state ~= 'attack', 'el ataque termina tras la recuperación')

-- un único daño por ataque aunque la caja siga solapando varios frames
st, p, ctx = setup()
p.facing = 'right'
local e = Enemy.new({ name = 'b', x = 112, y = 100, props = { kind = 'boar', patrol = 'h', range = 0 } })
local hp0 = e.hp
p.invuln = 5 -- que el contacto del jabalí no interrumpa el ataque
p:update(1 / 60, { pressed = { attack = true } }, ctx)
for _ = 1, 20 do p:update(1 / 60, NONE, ctx); e:update(1 / 60, ctx) end
check(e.hp == hp0 - 1, 'doble impacto evitado (vida ' .. hp0 .. ' → ' .. e.hp .. ')')

-- enemigo pegado al jugador mirando hacia arriba: el golpe también lo alcanza (antes la caja empezaba 16 px más arriba)
for _, dir in ipairs({ 'up', 'down', 'left', 'right' }) do
  st, p, ctx = setup()
  p.facing = dir
  p.invuln = 5
  local e0 = Enemy.new({ name = 'b_' .. dir, x = 100, y = 100, props = { kind = 'boar', patrol = 'h', range = 0 } })
  local hp_0 = e0.hp
  p:update(1 / 60, { pressed = { attack = true } }, ctx)
  for _ = 1, 8 do p:update(1 / 60, NONE, ctx); e0:update(1 / 60, ctx) end
  check(e0.hp < hp_0, 'enemigo pegado: el golpe hacia ' .. dir .. ' lo alcanza')
end

-- enemigo justo encima del jugador: antes la dirección 0/0 daba NaN y se quedaba congelado encima
st, p, ctx = setup()
p.invuln = 5
e = Enemy.new({ name = 'b2', x = 100, y = 100, props = { kind = 'boar', patrol = 'h', range = 2 } })
for _ = 1, 10 do e:update(1 / 60, ctx) end
check(e.body.x == e.body.x and e.body.x ~= 100, 'enemigo sobre el jugador: se sigue moviendo (sin NaN)')

-- el golpe de espada avisa al mundo ('hit') para las chispas; la muerte, con 'dead'
st, p, ctx = setup()
p.facing = 'right'; p.invuln = 5
e = Enemy.new({ name = 'b3', x = 112, y = 100, props = { kind = 'boar', patrol = 'h', range = 0 } })
p:update(1 / 60, { pressed = { attack = true } }, ctx)
local evs = {}
for _ = 1, 20 do p:update(1 / 60, NONE, ctx); local ev = e:update(1 / 60, ctx); if ev then evs[ev] = true end end
check(evs.hit and not evs.dead, 'evento de impacto al golpear (sin morir)')

-- parpadeo: en reposo se ve la columna 5 un instante cada pocos segundos
st, p, ctx = setup()
local cols = {}
for _ = 1, 60 * 4 do p:update(1 / 60, NONE, ctx); local _, c = p:frame(); cols[c] = (cols[c] or 0) + 1 end
check(cols[4] and cols[5] and cols[5] < cols[4] / 10, 'parpadeo breve en reposo (' .. tostring(cols[5]) .. ' frames)')

-- invulnerabilidad de 0,6 s tras recibir daño
st, p, ctx = setup()
p:hit(1, 130, 100, ctx)
local hp1 = st.hp
p:hit(1, 130, 100, ctx)
check(st.hp == hp1, 'segundo golpe inmediato ignorado (invulnerable)')
run(p, ctx, NONE, 40)
p:hit(1, 130, 100, ctx)
check(st.hp == hp1 - 1, 'tras 0,6 s vuelve a recibir daño')

-- bloqueo frontal sí, lateral/trasero no
st, p, ctx = setup()
p.facing = 'right'
run(p, ctx, { pressed = {}, shield = true }, 2)
check(p.state == 'block', 'mantener C pone el escudo')
local hpb = st.hp
local hurt, why = p:hit(1, 130, 94, ctx)
check(not hurt and why == 'blocked' and st.hp == hpb, 'golpe frontal bloqueado')
p.invuln = 0
run(p, ctx, { pressed = {}, shield = true }, 1)
hurt = p:hit(1, 70, 94, ctx)
check(hurt and st.hp == hpb - 1, 'golpe por la espalda no se bloquea')
p.invuln = 0; p.state = 'idle'
run(p, ctx, { pressed = {}, shield = true }, 1)
hurt = p:hit(1, 100, 140, ctx)
check(hurt, 'golpe lateral (90°) no se bloquea con cono de 120°')

-- el escudo deja de bloquear al agotarse la energía
st, p, ctx = setup()
p.facing = 'right'
p.stamina = 10
local frames = 0
while p.stamina > 0 and frames < 600 do run(p, ctx, { pressed = {}, shield = true }, 1); frames = frames + 1 end
run(p, ctx, { pressed = {}, shield = true }, 1)
check(p.block_exhausted and p.state ~= 'block', 'al agotarse la energía deja de bloquear')
run(p, ctx, { pressed = {}, shield = true }, 120)
check(p.state == 'block', 'con energía recuperada vuelve a bloquear')

-- equipo: cambiar sin duplicar; quitar el objeto lo desequipa
st = State.new(world)
State.give(st, 'sword_wood'); State.equip(st, items, 'sword_wood')
State.give(st, 'sword_bera'); State.equip(st, items, 'sword_bera')
check(st.equipment.weapon == 'sword_bera' and st.inventory.sword_wood == 1 and st.inventory.sword_bera == 1,
  'cambio de arma sin duplicar')
check(not State.equip(st, items, 'shield_wood'), 'no se equipa lo que no se tiene')
State.take(st, 'sword_bera')
check(st.equipment.weapon == nil, 'quitar el arma la desequipa')
local enc = json.decode(json.encode(st))
check(enc.equipment.weapon == nil and enc.inventory.sword_wood == 1, 'el equipo sobrevive a guardar/cargar')

-- bucle: pulsación breve sobrevive a un frame sin paso; pausa no acumula pasos
local loop = Loop.new(1 / 60, 6, 0.1)
Input.keypressed('z')
local got = 0
loop:advance(0.001, function() if Input.step().pressed.confirm then got = got + 1 end end)
check(got == 0, 'frame sin paso: la pulsación sigue pendiente')
for _ = 1, 3 do loop:advance(1 / 60, function() if Input.step().pressed.confirm then got = got + 1 end end) end
check(got == 1, 'la pulsación se consume exactamente una vez')
loop:pause(true)
check(loop:advance(5, function() end) == 0, 'en pausa no se simula')
loop:pause(false)
local n = loop:advance(5, function() end)
check(n <= 6 and loop.acc < 1 / 60, 'al volver no se acumulan pasos (' .. n .. ' pasos)')

print(fails == 0 and 'TODAS LAS PRUEBAS DE COMBATE/EQUIPO/BUCLE OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
