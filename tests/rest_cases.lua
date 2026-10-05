-- Pruebas de comer y dormir, botiquines y restaurantes (luajit tests/rest_cases.lua).
package.path = './?.lua;' .. package.path
love = { keyboard = { isDown = function() return false end }, math = { newRandomGenerator = function()
  return { random = function(_, a, b) return a or 0.5 end } end }, graphics = {} }
local Rest = require('src.systems.rest')
local Rpg = require('src.systems.rpg')
local Daylight = require('src.systems.daylight')
local State = require('src.state')
local json = require('src.lib.json')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end
local function read(p) local f = assert(io.open(p)); local s = f:read('*a'); f:close(); return s end
local items = json.decode(read('data/items.json'))
local world = json.decode(read('data/world.json'))
local services = json.decode(read('data/services.json')).services

-- mundo falso con lo mínimo que usa Rest
local function fake(st)
  local toasts, saved, played = {}, 0, {}
  local w = { state = st, id = 'proc_1_1', npcs = {}, sstate = {}, player = { stamina = 1, max_stamina = 5 },
    hud = { toast = function(_, t) toasts[#toasts + 1] = t end },
    game = { items = items, audio = { play = function(n) played[#played + 1] = n end },
             save_game = function() saved = saved + 1 end, generated = {} } }
  w.toasts, w.played = toasts, played
  w.saved = function() return saved end
  return w
end

-- ---------------------------------------------------------------- Daylight.skip
local st = State.new(world)
st.clock, st.day = 22 * 60, 3
Daylight.skip(st, 480)
check(st.clock == 6 * 60 and st.day == 4, 'dormir a las 22:00 → 06:00 del día siguiente')
st.clock, st.day = 8 * 60, 3
Daylight.skip(st, 480)
check(st.clock == 16 * 60 and st.day == 3, 'dormir a las 8:00 no cambia de día')

-- ---------------------------------------------------------------- objetos
check(items.botiqui and items.botiqui.kind == 'food' and items.botiqui.heal > 0 and items.botiqui.mp > 0,
  'botiqui: objeto de comida que cura vida y MP')
local loot = json.decode(read('data/loot.json'))
local in_loot = false
for _, cat in pairs(loot) do
  if type(cat) == 'table' and cat.table then for _, e in ipairs(cat.table) do if e[1] == 'botiqui' then in_loot = true end end end
end
check(in_loot, 'el botiquí sale en los cofres')
local sold = 0
for _, sv in ipairs(services) do for _, id in ipairs(sv.stock or {}) do if id == 'botiqui' then sold = sold + 1 end end end
check(sold >= 3, 'el botiquí se vende en varias tiendas (' .. sold .. ')')

-- ---------------------------------------------------------------- Rpg.use con MP
st = State.new(world)
st.max_hp = 24; st.hp, st.mp = 2, 1
st.inventory.botiqui = 2
local msg = Rpg.use(st, items, 'botiqui', nil)
check(msg and st.hp == 14 and st.mp == math.min(st.max_mp, 11) and st.inventory.botiqui == 1, 'usar botiqui: +12 vida y +10 MP')
st.hp, st.mp = st.max_hp, st.max_mp
check(Rpg.use(st, items, 'botiqui', nil) == 'Ja tens tota la vida' and st.inventory.botiqui == 1, 'con vida y MP llenos no se gasta')
st.hp, st.mp = st.max_hp, 0
check(Rpg.use(st, items, 'botiqui', nil) ~= 'Ja tens tota la vida' and st.mp > 0, 'con vida llena pero sin MP sí se usa')

-- ---------------------------------------------------------------- tecla G
st = State.new(world)
local w = fake(st)
st.hp = 4
check(Rest.use_medkit(w) == false and w.toasts[#w.toasts] == 'No tens cap botiquí', 'sin botiquines avisa')
st.inventory.farmaciola = 1
check(Rest.use_medkit(w) and st.hp == st.max_hp and not st.inventory.farmaciola, 'sin botiquí usa la farmaciola')
st.hp = 4; st.inventory.farmaciola = 1; st.inventory.botiqui = 1
Rest.use_medkit(w)
check(not st.inventory.botiqui and st.inventory.farmaciola == 1, 'con ambos usa antes el botiquí')

-- ---------------------------------------------------------------- botiquín gratis diario
st = State.new(world); st.day = 5
w = fake(st)
check(Rest.free_kit(w, 'metge') and st.inventory.botiqui == 1, 'CAP: primer botiquí del día')
check(not Rest.free_kit(w, 'metge') and st.inventory.botiqui == 1, 'CAP: solo uno al día')
check(Rest.free_kit(w, 'policia') and st.inventory.botiqui == 2, 'comisaría tiene el suyo')
st.day = 6
check(Rest.free_kit(w, 'metge'), 'al día siguiente otro')

-- ---------------------------------------------------------------- comer en casa
st = State.new(world); st.hp = 4; st.mp = 0; st.clock = 600; st.day = 2
w = fake(st)
check(Rest.eat(w) and st.hp > 4 and st.mp > 0, 'la nevera cura vida y MP')
local hp1 = st.hp
check(Rest.eat(w) == false and st.hp == hp1, 'cooldown: no se come dos veces seguidas')
st.clock = 600 + 130
check(Rest.eat(w, { name = 'Prueba', hp = 1, mp = 1 }) and st.hp == st.max_hp and st.mp == st.max_mp, 'plato completo cura todo')
check(Rest.eat(w) == false and w.toasts[#w.toasts]:find('gana'), 'sin heridas no hace falta comer')

-- ---------------------------------------------------------------- dormir
st = State.new(world); st.hp = 2; st.mp = 0; st.clock = 22 * 60; st.day = 1
w = fake(st)
w.npcs[1] = { routine = nil }
check(Rest.sleep(w) == true and w.rest_fx, 'dormir arranca la pantalla Zzz')
check(Rest.sleep(w) == false, 'no se puede dormir dos veces a la vez')
check(Rest.update(w, 0.1) == true and st.hp == 2, 'durante el fundido de entrada aún no ha curado')
Rest.update(w, Rest.FADE_OUT)
check(st.hp == st.max_hp and st.mp == st.max_mp, 'a oscuras cura vida y MP')
check(st.clock == 6 * 60 and st.day == 2, 'pasan 8 horas y cambia de día')
check(w.saved() == 1, 'guarda la partida una vez')
Rest.update(w, Rest.HOLD)
check(Rest.update(w, Rest.FADE_IN + 0.1) == true and w.rest_fx == nil, 'la pantalla termina y devuelve el control')
check(Rest.update(w, 0.1) == false and w.saved() == 1, 'sin pantalla Zzz no bloquea ni guarda de nuevo')

-- ---------------------------------------------------------------- botiquines de pared e interiores
local P = require('src.world.procgen')
local spec = P.generate({ kind = 'house', seed = 5 })
st = State.new(world); st.day = 7
w = fake(st)
w.map = { objects = { { type = 'bed', x = 32, y = 32, w = 16, h = 16 }, { type = 'fridge', x = 64, y = 32, w = 16, h = 16 } } }
w.game.generated[w.id] = { spec = spec }
w.cam = { visible = function() return true end }
Rest.attach(w)
check(#w.medkits == 1 and #w.beds_fridges == 2, 'una casa tiene un botiquín de pared y se leen cama y nevera del mapa')
local k = w.medkits[1]
check(Rest.can_interact(w, k.x, k.y + 8) and not Rest.can_interact(w, 300, 300), 'se puede interactuar solo junto al botiquín')
check(Rest.interact(w, k.x, k.y + 8) and st.inventory.botiqui == 1, 'el botiquín de pared da un botiquí')
check(Rest.interact(w, k.x, k.y + 8) and st.inventory.botiqui == 1, 'vacío el mismo día')
st.day = 8
Rest.interact(w, k.x, k.y + 8)
check(st.inventory.botiqui == 2, 'se rellena al día siguiente')
Rest.interact(w, 40, 40)
check(w.rest_fx ~= nil, 'una cama del mapa duerme')
for _, kind in ipairs({ 'flat', 'upper', 'school' }) do
  local sp = kind == 'school' and P.poi({ kind = 'school', seed = 3 }) or P.generate({ kind = kind, seed = 3 })
  local w2 = fake(State.new(world)); w2.map = { objects = {} }; w2.game.generated[w2.id] = { spec = sp }
  Rest.attach(w2)
  check(#w2.medkits == 1, 'interior ' .. kind .. ' tiene botiquín de pared')
end

-- ---------------------------------------------------------------- restaurantes
local rest_ids = {}
for _, sv in ipairs(services) do if sv.kind == 'restaurant' then rest_ids[#rest_ids + 1] = sv end end
check(#rest_ids >= 5, 'hay restaurantes en data/services.json (' .. #rest_ids .. ')')
local ok_menus = true
for _, sv in ipairs(rest_ids) do if sv.menu and not Rest.MENUS[sv.menu] then ok_menus = false end end
check(ok_menus, 'cada restaurante usa un menú existente')
st = State.new(world); st.hp = 2; st.mp = 0; st.coins = 100
w = fake(st)
local opened
w.game.open_list = function(_, title, list) opened = list end
w.game.close_menu = function() end
local shown
w.dialogue = { show = function(_, who, pages) shown = pages end }
Rest.restaurant(w, { props = { say_name = 'Cambrer' } }, { label = 'Bar', menu = 'cat' })
check(opened and #opened == #Rest.MENUS.cat + 1, 'el menú lista los platos y «Res, gràcies»')
opened[3][2]()
check(st.hp == st.max_hp and st.mp == st.max_mp and st.coins == 100 - Rest.MENUS.cat[3][2], 'el menú del día cura todo y cuesta lo que dice')
st.hp = 1; st.coins = 3
opened[1][2]()
check(st.hp == 1 and st.coins == 3, 'sin monedas no cura')

print(fails == 0 and 'TODAS LAS PRUEBAS DE COMER Y DORMIR OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
