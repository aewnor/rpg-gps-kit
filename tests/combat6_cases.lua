-- Combat de la fase 6 sense ventana (luajit tests/combat6_cases.lua): màgia (MP, arbre d'encanteris per nivell,
-- bastó), escalat d'estadístiques en pujar de nivell, projectils (parets, enemics, escut) i el drac.
package.path = './?.lua;./?/init.lua;' .. package.path
love = { math = { random = math.random } }
local json = require('src.lib.json')
local Rpg = require('src.systems.rpg')
local Magic = require('src.systems.magic')
local Projectiles = require('src.systems.projectiles')
local Enemy = require('src.entities.enemy')
local Dragon = require('src.entities.dragon')
local Player = require('src.entities.player')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end
local f = assert(io.open('data/items.json')); local items = json.decode(f:read('*a')); f:close()

-- ---------------------------------------------------------------- estadístiques i nivell
local st = Rpg.ensure({ hp = 6, max_hp = 6, inventory = {}, flags = {} })
check(st.base.magic == 5 and st.max_mp == 10 and st.mp == 10, 'nivell 1: Màgia 5 i 10 MP')
local a0, d0 = st.base.attack, st.base.defense
Rpg.add_xp(st, st.next_xp)
check(st.char_level == 2 and st.base.attack == a0 + 3 and st.base.defense == d0 + 2 and st.base.magic == 7
      and st.max_mp == 13 and st.mp == 13 and st.max_hp == 8, 'pujar de nivell: Força +3, Defensa +2, Màgia +2, MP +3, vida +1 cor')
local old = Rpg.ensure({ hp = 6, max_hp = 6, inventory = {}, char_level = 4, base = { attack = 19, defense = 11 } })
check(old.base.magic == 11 and old.max_mp == 19, 'partida antiga: màgia i MP segons el nivell')

-- ---------------------------------------------------------------- arbre d'encanteris
check(not Magic.unlocked(st, 'rafaga') and Magic.unlocked(st, 'foc'), 'nivell 2: només la bola de foc')
local ok, why = Magic.can_cast(st, items, 'foc')
check(not ok and why:find('Bastó'), 'sense el bastó no hi ha màgia')
st.inventory.baston_magic = 1
check(Rpg.equip(st, items, 'baston_magic'), 'equipar el Bastó màgic')
check(Magic.total(st, items) == 7 + 6, 'el bastó suma +6 de Màgia')
local out = Magic.cast(st, items, 'foc', 100, 100, 'right')
check(out and #out.shots == 1 and out.shots[1].vx > 0 and st.mp == 13 - 4, 'bola de foc cap a la dreta (4 MP)')
check(out.shots[1].dmg == Magic.damage(st, items, Magic.BY_ID.foc) and out.shots[1].dmg >= 4, 'dany = poder × màgia / 10')
st.mp = 2
check(not Magic.can_cast(st, items, 'foc'), 'sense prou MP no es pot')
Magic.regen(st, 1.5 * 3)
check(st.mp == 5, 'recupera 1 MP cada 1,5 s')
st.char_level = 6
local k = Magic.known(st)
check(#k == 4 and k[4].id == 'foc_triple', 'nivell 6: quatre encanteris (pluja de foc després de la bola de foc)')
st.mp = 40
check(#Magic.cast(st, items, 'foc_triple', 0, 0, 'up').shots == 3, 'pluja de foc: tres boles en ventall')
st.spell = 'foc'
check(Magic.next(st) == 'rafaga' and Magic.next(st, -1) == 'foc', 'Q/E canvien d\'encanteri')
st.hp = 2
local h = Magic.cast(st, items, 'cura', 0, 0, 'down')
check(h and h.heal == 4 and st.hp == 6, 'curació: +2 cors')

-- ---------------------------------------------------------------- projectils
local shots = Projectiles.new()
local boar = Enemy.new({ name = 'b', x = 150, y = 100, props = { kind = 'boar' } })
shots:spawn({ x = 100, y = 96, vx = 200, vy = 0, r = 5, dmg = 2, owner = 'player', kind = 'fire', life = 2 })
for _ = 1, 30 do shots:update(1 / 60, function() return false end, { boar }, nil, nil) end
local evs = shots:take_events()
check(#evs == 1 and evs[1].kind == 'hit' and boar.hp == 1 and #shots.list == 0, 'la bola de foc fereix el senglar i desapareix')
shots:spawn({ x = 0, y = 0, vx = 100, vy = 0, owner = 'player', kind = 'fire', dmg = 1 })
shots:update(0.1, function(x) return x > 5 end, {}, nil, nil)
check(#shots.list == 0 and shots:take_events()[1].kind == 'wall', 'xoca amb la paret')
local b1 = Enemy.new({ name = 'a', x = 50, y = 0, props = { kind = 'bat' } })
local b2 = Enemy.new({ name = 'c', x = 80, y = 0, props = { kind = 'bat' } })
shots:spawn({ x = 0, y = -4, vx = 150, vy = 0, r = 8, owner = 'player', kind = 'gust', dmg = 1, pierce = true, push = 260, life = 1 })
for _ = 1, 50 do shots:update(1 / 60, function() return false end, { b1, b2 }, nil, nil) end
check(b1.state == 'dead' and b2.state == 'dead', 'la ràfaga travessa i tomba dos ratpenats')
for i = 1, 100 do shots:spawn({ x = 0, y = 0, vx = 1, vy = 0, owner = 'enemy', life = 9 }) end
check(#shots.list == Projectiles.MAX, 'màxim de projectils alhora (' .. Projectiles.MAX .. ')')
shots:clear(); shots:take_events()

-- ---------------------------------------------------------------- foc del drac contra el jugador (i l'escut)
local map = { cell = function() return 0 end }
local wf = assert(io.open('data/world.json')); local cfg = json.decode(wf:read('*a')).player; wf:close()
local pst = Rpg.ensure({ hp = 10, max_hp = 10, inventory = { shield_roda = 1 }, flags = {}, equipment = {} })
Rpg.equip(pst, items, 'shield_roda')
local ctx = { map = map, blockers = {}, state = pst, items = items }
local pl = Player.new(200, 200, 0, cfg)
pl.facing = 'up'
pl:update(1 / 60, { shield = true, pressed = {} }, ctx)
shots:spawn({ x = 200, y = 150, vx = 0, vy = 120, r = 5, dmg = 2, owner = 'enemy', kind = 'dragonfire', life = 3 })
for _ = 1, 40 do pl:update(1 / 60, { shield = true, pressed = {} }, ctx); shots:update(1 / 60, nil, {}, pl, ctx) end
local ev = shots:take_events()
check(ev[1] and ev[1].kind == 'blocked' and pst.hp == 10, 'l\'escut para el foc del drac')
pl = Player.new(200, 200, 0, cfg)
shots:spawn({ x = 200, y = 150, vx = 0, vy = 120, r = 5, dmg = 2, owner = 'enemy', kind = 'dragonfire', life = 3 })
for _ = 1, 40 do shots:update(1 / 60, nil, {}, pl, ctx) end
check(pst.hp < 10, 'sense escut el foc fa mal')

-- ---------------------------------------------------------------- el drac
local seq = { 0.9, 0.9, 0.9, 0.1, 0.9 }
local si = 0
local dr = Dragon.new({ name = 'drac', x = 300, y = 200, props = { flag = 'drac_vencut' } }, function() si = si % #seq + 1; return seq[si] end)
local far = Player.new(300, 500, 0, cfg)
local fired = 0
local dctx = { player = far, state = pst, items = items, shoot = function(o) fired = fired + 1 end }
for _ = 1, 120 do dr:update(1 / 60, dctx) end
check(dr.state == 'sleep' and fired == 0, 'dorm fins que t\'hi acostes')
local near = Player.new(300, 290, 0, cfg)
near.invuln = 999
dctx.player = near
for _ = 1, 60 * 6 do dr:update(1 / 60, dctx) end
check(dr.state == 'fight' and fired >= 3, 'es desperta i llança boles de foc (' .. fired .. ')')
check(math.abs(dr.body.x - 300) <= 150 and dr.body.y >= 160 and dr.body.y <= 310, 'no surt de l\'arena')
local res
for _ = 1, 100 do res = dr:damage(1, 300, 300); if res == 'dead' then break end end
check(dr:enraged() == true or res == 'dead', 'amb poca vida s\'enfada')
check(res == 'dead' and dr.state == 'dead', 'es pot vèncer (' .. Dragon.KIND.hp .. ' de vida)')

print(fails == 0 and 'TOTES LES PROVES DE COMBAT (FASE 6) OK' or (fails .. ' FALLADES'))
os.exit(fails == 0 and 0 or 1)
