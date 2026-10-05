-- Pruebas de la lógica de los minijuegos (luajit tests/minigames_cases.lua): cinema,
-- penaltis, circuito de agilidad y ritmo del gimnasio. Entrada simulada paso a paso a 60 Hz.
package.path = './?.lua;./?/init.lua;' .. package.path
love = { math = { random = math.random } }
local Pen = require('src.minigames.penalties')
local Circ = require('src.minigames.circuit')
local Rhy = require('src.minigames.rhythm')
local M = require('src.minigames.init')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end
local DT = 1 / 60
local function seq(vals) local i = 0; return function() i = i % #vals + 1; return vals[i] end end
local function step(g, pressed, held)
  local act = { pressed = pressed or {} }
  for k, v in pairs(held or {}) do act[k] = v end
  g:update(DT, act)
end
local function run(g, n, held) for _ = 1, n do if g.done then return end step(g, nil, held) end end

-- ---------------------------------------------------------------- penals
check(Pen.outcome(0.9, 0.7, 'right') == 'goal', 'a tocar del pal i fort: gol encara que el porter endevini')
check(Pen.outcome(0.0, 0.5, 'center') == 'saved', 'al mig i el porter es queda: aturada')
check(Pen.outcome(-0.6, 0.5, 'right') == 'goal', 'porter al costat contrari: gol')
check(Pen.outcome(0.3, 0.97, 'left') == 'over', 'massa força: per sobre del travesser')
local p = Pen.new({}, seq({ 0.1 }))     -- porter sempre a l'esquerra
for _ = 1, 5 do
  local g0 = 0
  while not (p.state == 'aim' and p.aim > 0.6) and g0 < 600 do step(p); g0 = g0 + 1 end
  step(p, { confirm = true })
  g0 = 0
  while not (p.state == 'power' and p.power > 0.6 and p.power < 0.85) and g0 < 600 do step(p); g0 = g0 + 1 end
  step(p, { confirm = true })
  run(p, 60 * 2)
end
check(p.state == 'end' and p.goals == 5, 'cinc xuts a la dreta amb força: 5 gols (' .. p.goals .. ')')
step(p, nil); run(p, 40); step(p, { confirm = true })
check(p.done and p.result.perfect and p.result.shots == 5, 'resultat: ple')

-- ---------------------------------------------------------------- circuit
local c = Circ.new({ vehicle = 'bici' }, seq({ 0.2, 0.8, 0.5, 0.35, 0.65 }))
step(c, { confirm = true })
local g1 = 0
while c.state ~= 'end' and g1 < 60 * 60 do      -- pilot automàtic: cap a la porta següent
  local nxt
  for _, gt in ipairs(c.gates) do if not gt.state then nxt = gt; break end end
  local tx = nxt and nxt.x or 0
  step(c, nil, { left = c.x > tx + 2, right = c.x < tx - 2 })
  g1 = g1 + 1
end
check(c.state == 'end' and c.passed == Circ.GATES and c.bumps == 0, 'pilot automàtic: totes les portes sense tocar cons')
check(c.total <= c.par, string.format('temps %.1f s sota el de referència %.1f s', c.total or -1, c.par))
local c2 = Circ.new({ vehicle = 'bici' }, seq({ 0.9, 0.1 }))
step(c2, { confirm = true })
run(c2, 60 * 60, { right = true })            -- sempre a la dreta: es salta portes
check(c2.state == 'end' and c2.missed + c2.bumps > 0 and c2.total > c2.time, 'saltar-se portes o tocar cons penalitza')
check(Circ.new({ vehicle = 'patinete' }, math.random).speed > Circ.new({ vehicle = 'bici' }, math.random).speed,
  'amb patinet es va més ràpid')

-- ---------------------------------------------------------------- ritme
local h = Rhy.new({ stat = 'strength' }, math.random)
step(h, { confirm = true })
local g2 = 0
while h.state ~= 'end' and g2 < 60 * 60 do      -- prémer cada fletxa a temps
  local pressed = {}
  for _, n in ipairs(h.notes) do
    if not n.done and math.abs(n.time - (h.song_t + DT)) < DT / 2 + 0.001 then pressed[Rhy.LANES[n.lane]] = true end
  end
  step(h, pressed)
  g2 = g2 + 1
end
check(h:pct() > 0.95, string.format('prémer a temps: %.0f%%', h:pct() * 100))
step(h, nil); run(h, 40); step(h, { confirm = true })
check(h.done and h.result.passed and h.result.stat == 'strength', 'sessió aprovada (força)')
local h2 = Rhy.new({ stat = 'agility' }, math.random)
step(h2, { confirm = true }); run(h2, 60 * 30)
check(h2.state == 'end' and h2:pct() == 0, 'sense prémer res: 0 %')
local h3 = Rhy.new({ stat = 'resistance' }, math.random)
h3.state, h3.song_t = 'play', h3.notes[1].time - 0.1
check(h3:hit(h3.notes[1].lane, h3.song_t) == 'good', 'a 0,1 s: bé')
check(h3:hit(h3.notes[1].lane, h3.song_t) == nil, 'la mateixa fletxa no compta dues vegades')

-- ---------------------------------------------------------------- límits diaris
local st = { day = 4 }
local m = M.daily(st)
check(m.tokens == nil and m.roulette == nil, 'sense fitxes ni ruleta')
m.trained.strength = true
st.day = 5
m = M.daily(st)
check(not m.trained.strength, 'entrenament renovat el dia següent')

print(fails == 0 and 'TODAS LAS PRUEBAS DE MINIJUEGOS OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
