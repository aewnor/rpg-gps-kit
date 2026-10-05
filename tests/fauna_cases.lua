-- Pruebas de la fauna (perros, gatos, pájaros, salvajes): luajit tests/fauna_cases.lua
package.path = './?.lua;' .. package.path
love = { graphics = {}, keyboard = { isDown = function() return false end } }
local Fauna = require('src.systems.fauna')
local Enemy = require('src.entities.enemy')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end

-- ---- clasificación del suelo
check(Fauna.zone('g_urban_2') == 'street' and Fauna.zone('d_paving_7') == 'street', 'urban y paving son calle')
check(Fauna.zone('g_asphalt_0') == 'road' and Fauna.zone('d_main_3') == 'road', 'asfalto y carretera son calzada')
check(Fauna.zone('g_park_1') == 'park' and Fauna.zone('g_yard_0') == 'park', 'parque y jardín')
check(Fauna.zone('g_forest_2') == 'mountain' and Fauna.zone('g_rock_0') == 'mountain', 'bosque y roca son monte')
check(Fauna.zone('g_beach_0') == 'beach' and Fauna.zone('tw_beach_urban_3') == nil and Fauna.zone('tw_grass_park_1') == 'park' and Fauna.zone('tw_forest_scrub_2') == 'mountain' and Fauna.zone('tw_scrub_urban_1') == nil and Fauna.zone(nil) == nil, 'playa; transiciones sin zona')

-- ---- mundo falso: calle (tx<50), parque (50-99), monte (100-149), playa (150+); todo transitable
local function make_world(px, py, opts)
  opts = opts or {}
  local w = { enemies = {}, blockers = {}, popups = {}, toasts = {} }
  w.map = { in_bounds = function(_, tx, ty) return tx >= 0 and ty >= 0 and tx < 300 and ty < 300 end,
            cell = function() return 0 end }
  w.tile_name = function(_, _, tx)
    if tx < 50 then return 'g_urban_0' elseif tx < 100 then return 'g_park_0'
    elseif tx < 150 then return 'g_forest_0' else return 'g_beach_0' end
  end
  w.player = { state = 'idle', body = { x = px, y = py, w = 10, h = 8, level = 0 },
               attack_box = function() return nil end, hurtbox = function(self) return { x = self.body.x - 5, y = self.body.y - 8, w = 10, h = 12 } end,
               hit = function(self, n) self.hits = (self.hits or 0) + n; return true end }
  w.cam = { visible = function(_, x, y, ww, hh, m)
    m = m or 32
    return x + ww > px - 160 - m and x < px + 160 + m and y + hh > py - 120 - m and y < py + 120 + m
  end }
  w.state = { hp = 24, max_hp = 24, mp = 3, max_mp = 10, char_level = opts.level or 1, clock = opts.clock or 12 * 60, inventory = {} }
  w.honk_t = 0
  w.game = { items = {}, sprites = { chars = {}, enemies = { boar = {}, fox = {}, snake = {}, wolf = {} },
    animals = { dog_brown = {}, dog_black = {}, cat_orange = {}, cat_grey = {}, bird_sparrow = {}, bird_pigeon = {}, bird_gull = {} } } }
  w.fx = { preset = function() end }
  w.hud = { toast = function(_, t) w.toasts[#w.toasts + 1] = t end }
  w.popup = function(self, t) self.popups[#self.popups + 1] = t end
  return w
end

local function run(f, w, secs)
  for _ = 1, math.floor(secs * 30) do
    f:update(1 / 30)
    assert(#f.list <= Fauna.CAP.total, 'ambient population cap')
    local ctx = { map = w.map, blockers = w.blockers, player = w.player, state = w.state, items = {} }
    for _, e in ipairs(w.enemies) do e:update(1 / 30, ctx) end
  end
end

math.randomseed(42)

-- ---- calle: topes, fuera de pantalla y solo en terreno permitido
local w = make_world(25 * 16, 100 * 16)
local f = Fauna.new(w, math.random)
local seen_cls, offscreen_ok, zone_ok = {}, true, true
local seen_dog_walk = false
for _ = 1, 20 * 30 do
  local before = #f.list
  f:update(1 / 30)
  for i = before + 1, #f.list do
    local a = f.list[i]
    seen_cls[a.cls] = true
    if w.cam:visible(a.x - 8, a.y - 16, 16, 16, 0) then offscreen_ok = false end
  end
end
for _, a in ipairs(f.list) do
  local z = Fauna.zone_at(w, a.x, a.y)
  if z ~= 'street' and z ~= 'park' then zone_ok = false end
end
check(#f.list > 0 and #f.list <= 14, 'en la calle aparecen animales (' .. #f.list .. ') sin pasar de 14')
check(f:count('cat') <= Fauna.CAP.cat and f:count('bird') <= Fauna.CAP.bird and f:count('dog') <= Fauna.CAP.dog, 'topes por especie')
check(f:count_zone('street') <= Fauna.ZONE_CAP.street, 'tope de la zona calle')
check(offscreen_ok, 'aparecen siempre fuera de pantalla')
check(zone_ok, 'viven en calle o parque')
check(seen_cls.cat and seen_cls.bird, 'hay gatos y pájaros en la calle')
check(#w.enemies == 0, 'en la calle no hay salvajes')

-- ---- pájaros: huyen al acercarse y se descargan
local w2 = make_world(25 * 16, 100 * 16)
local f2 = Fauna.new(w2, math.random)
f2.spawn_t = 999
local b = f2:spawn_bird(25 * 16 + 20, 100 * 16, 'street')
check(b.state == 'peck', 'el pájaro picotea al principio')
f2:update(1 / 30)
check(b.state == 'fly', 'el pájaro vuela si te acercas')
local zmax = 0
for _ = 1, 40 do f2:update(1 / 30); zmax = math.max(zmax, b.z) end
check(zmax > 10, 'sube en el aire al huir (z ' .. math.floor(zmax) .. ')')
run(f2, w2, 5)
check(f2:count('bird') == 0, 'el pájaro que huyó desaparece')

-- ---- gatos: el arisco huye, el manso se deja acariciar
local w3 = make_world(25 * 16, 100 * 16)
local f3 = Fauna.new(w3, math.random)
f3.spawn_t = 999
local shy = f3:spawn_cat(25 * 16 + 24, 100 * 16, 'street'); shy.tame = false
local d0 = (shy.x - w3.player.body.x)
run(f3, w3, 0.3)
check(shy.state == 'flee', 'el gato arisco huye al acercarte')
run(f3, w3, 1.2)
check((shy.x - w3.player.body.x) > d0 + 20, 'el gato arisco se aleja')
local tame = f3:spawn_cat(25 * 16 - 6, 100 * 16, 'street'); tame.tame = true
run(f3, w3, 0.5)
check(tame.state ~= 'flee', 'el gato manso no huye')
w3.state.mp = 3
check(f3:can_interact(tame.x, tame.y), 'se puede acariciar al gato manso')
check(f3:interact(tame.x, tame.y) and w3.state.mp == 4, 'acariciar da +1 MP')
check(f3:interact(tame.x, tame.y) and w3.state.mp == 4, 'no repite MP hasta pasados 30 s')
check(not f3:can_interact(shy.x + 200, shy.y), 'lejos de los animales no hay nada que acariciar')

-- ---- dueño con perro: el perro sigue al dueño
local w4 = make_world(25 * 16, 100 * 16)
local f4 = Fauna.new(w4, math.random)
f4.spawn_t = 999
local o = f4:spawn_owner(25 * 16 + 60, 100 * 16 + 40, 'street')
check(o and o.dog and o.dog.owner == o, 'el paseador nace con su perro')
local maxd = 0
for i = 1, 25 * 30 do
  f4:update(1 / 30)
  if i > 60 then maxd = math.max(maxd, math.sqrt((o.dog.x - o.x) ^ 2 + (o.dog.y - o.y) ^ 2)) end
end
check(maxd < 40, 'el perro va junto a su dueño (máx ' .. math.floor(maxd) .. ' px)')
check(o.x ~= 25 * 16 + 60 or o.y ~= 100 * 16 + 40, 'el dueño pasea')

-- ---- montaña: salvajes de verdad, con tope, nivel y hora
local function mountain(level, clock, hp)
  local wm = make_world(125 * 16, 100 * 16, { level = level, clock = clock })
  if hp then wm.state.hp = hp end
  local fm = Fauna.new(wm, math.random)
  for _ = 1, 40 * 30 do fm:update(1 / 30) end
  return wm, fm
end
local wm, fm = mountain(1, 12 * 60)
check(fm:count('bird') > 0, 'hay pájaros tranquilos también en el monte')
local nw = fm:count_wild()
check(nw > 0 and nw <= Fauna.CAP.wild, 'en la montaña aparecen salvajes (' .. nw .. ', tope ' .. Fauna.CAP.wild .. ')')
local wolves, kinds = 0, {}
for _, e in ipairs(wm.enemies) do
  check(e.fauna and e.kind.xp ~= nil, 'el salvaje es un Enemy con XP')
  for k, v in pairs(Enemy.KINDS) do if v == e.kind then kinds[k] = true; if k == 'wolf' then wolves = wolves + 1 end end end
  break
end
check(wolves == 0, 'de día y con nivel 1 no hay lobos')
local ww1 = mountain(2, 23 * 60)
local nwolf_low = 0
for _, e in ipairs(ww1.enemies) do if e.kind == Enemy.KINDS.wolf then nwolf_low = nwolf_low + 1 end end
check(nwolf_low == 0, 'con nivel 2 tampoco hay lobos de noche')
local found_wolf = false
for seed = 1, 6 do
  math.randomseed(seed)
  local wn = mountain(8, 23 * 60)
  for _, e in ipairs(wn.enemies) do if e.kind == Enemy.KINDS.wolf then found_wolf = true end end
end
check(found_wolf, 'de noche y con nivel alto salen lobos')
local weak = mountain(1, 12 * 60, 6)
check(#weak.enemies == 0, 'con poca vida no aparecen salvajes nuevos')

-- justicia: más nivel, algo más de vida (tope +3)
local wl = make_world(125 * 16, 100 * 16, { level = 16 })
local fl = Fauna.new(wl, math.random)
local e = fl:spawn_wild(125 * 16, 100 * 16, 'g_forest_0')
check(e.hp >= e.kind.hp + 3 or e.kind.lvl > 1, 'a nivel 16 los salvajes tienen más vida (' .. e.hp .. ')')
local wl1 = make_world(125 * 16, 100 * 16, { level = 1 })
local e1 = Fauna.new(wl1, math.random):spawn_wild(125 * 16, 100 * 16, 'g_forest_0')
check(e1.hp == e1.kind.hp, 'a nivel 1 vida base')

-- descarga al alejarse
wm.player.body.x = 20 * 16
wm.cam.visible = function() return false end
for _ = 1, 3 do fm:update(1 / 30) end
check(fm:count_wild() == 0 and #wm.enemies == 0, 'al irte lejos se descargan los salvajes')

-- ---- zorro tímido: huye sin morder; herido, ataca
local wf = make_world(125 * 16, 100 * 16)
local fox = Enemy.new({ x = 125 * 16 + 30, y = 100 * 16, name = 'z', props = { kind = 'fox' } }, {})
local ctx = { map = wf.map, blockers = wf.blockers, player = wf.player, state = wf.state, items = {} }
local x0 = fox.body.x
for _ = 1, 10 do fox:update(1 / 30, ctx) end
check(fox.state == 'flee' and fox.body.x > x0 + 8, 'el zorro huye del jugador')
check((wf.player.hits or 0) == 0, 'el zorro que huye no muerde')
fox.body.x, fox.body.y = wf.player.body.x + 30, wf.player.body.y
fox:damage(1, wf.player.body.x, wf.player.body.y)
fox.hurt_t = 0
for _ = 1, 20 do fox:update(1 / 30, ctx) end
check(fox.state == 'chase', 'un zorro herido ataca')

-- ---- el jabalí y el lobo hacen daño por contacto
local wolf = Enemy.new({ x = 125 * 16 + 20, y = 100 * 16, name = 'l', props = { kind = 'wolf' } }, {})
for _ = 1, 60 do wolf:update(1 / 30, ctx) end
check((wf.player.hits or 0) >= 2, 'el lobo muerde (daño ' .. (wf.player.hits or 0) .. ')')

-- ---- botín
local w5 = make_world(0, 0)
w5.game.items = { carn_senglar = { name = 'Carn de senglar' }, botiqui = { name = 'Botiquí' } }
local got = 0
for _ = 1, 40 do
  w5.state.inventory = {}
  Fauna.on_kill(w5, { kind = Enemy.KINDS.boar })
  if w5.state.inventory.carn_senglar then got = got + 1 end
end
check(got > 5 and got < 40, 'el jabalí suelta carne a veces (' .. got .. '/40)')

print(fails == 0 and 'fauna_cases: todo OK' or ('fauna_cases: ' .. fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
