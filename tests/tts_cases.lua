-- Veu (TTS) sense ventana (luajit tests/tts_cases.lua): pronúncia dels noms (lèxic), neteja del text i que
-- dir una frase no bloquegi el bucle del joc (només s'envia un missatge: res d'esperar la veu).
package.path = './?.lua;./?/init.lua;' .. package.path
local Tts = require('src.tts')
local json = require('src.lib.json')

local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end

-- pronúncia
check(Tts.prepare('Hola, Olaf!', 'ca') == 'Hola, Òlaf!', 'ca: nom → pronúncia')
check(Tts.prepare('la mestra i Olaf', 'ca') == 'la mestra i Òlaf', 'ca: Olaf amb accent de pronúncia')
check(Tts.prepare('Hola, Olaf!', 'es') == 'Hola, Ólaf!', 'es: Olaf → Ólaf')
check(Tts.prepare('Olafo i la mestras', 'ca') == 'Olafo i la mestras', 'només paraules senceres')
check(Tts.prepare('+40 XP', 'ca') == '40 punts d\'experiència', 'símbols i abreviatures del joc')
check(Tts.prepare('Missió: ves-hi  (J: diari)', 'ca') == 'Missió: ves-hi', 'sense la pista de la tecla del diari')

-- no bloqueja: el fil d'espeak només rep missatges (aquí, un canal fals que compta)
local pushed = 0
love = { thread = { getChannel = function() return { push = function() pushed = pushed + 1 end } end } }
Tts.settings = { tts = { on = true, volume = 0.8, rate = 1, lang = 'ca' } }
Tts.backend, Tts.bin = 'espeak', 'espeak-ng'
local t0 = os.clock()
for i = 1, 200 do Tts.say('La la metgessa t\'espera al CAP. Frase ' .. i, i % 2 == 0) end
local ms = (os.clock() - t0) * 1000 / 200
check(pushed == 200, 'cada frase és un missatge al fil de la veu')
check(ms < 1.0, string.format('dir una frase costa %.3f ms al fil del joc (< 1 ms)', ms))
check(#Tts.history <= 30, 'historial limitat')
Tts.settings.tts.on = false
Tts.say('res')
check(pushed == 200, 'amb la veu apagada no s\'envia res')
-- web: una línia JSON al dispositiu (JavaScript la diu de manera asíncrona)
local wrote = {}
local real_open = io.open
io.open = function(p, m) if p == '/dev/rodatts' then return { write = function(_, s) wrote[#wrote + 1] = s end, close = function() end } end return real_open(p, m) end
Tts.settings.tts.on, Tts.backend = true, 'web'
Tts.say('Hola, Olaf!', true)
io.open = real_open
local msg = wrote[1] and json.decode(wrote[1])
check(msg and msg.cmd == 'say' and msg.text == 'Hola, Òlaf!' and msg.lang == 'ca-ES' and msg.interrupt == true,
  'web: missatge JSON amb el text, l\'idioma i si talla l\'anterior')

print(fails == 0 and 'TOTES LES PROVES DE VEU OK' or (fails .. ' FALLADES'))
os.exit(fails == 0 and 0 or 1)
