-- Veu (TTS): llegeix en veu alta els diàlegs i els avisos de missió.
--   · Web (love.js): Web Speech API del navegador (window.speechSynthesis). Lua escriu una línia JSON al
--     dispositiu /dev/rodatts (web/index.html) i JavaScript la diu de manera asíncrona: el bucle del joc no
--     espera mai.
--   · Escriptori (Raspberry Pi, Linux): espeak-ng (o espeak) en un fil propi (love.thread): l'ordre del
--     sistema s'executa allà, no al fil principal.
--   · Sense cap de les dues: no fa res.
-- Pronúncia: data/tts_lexicon.json canvia paraules (nom → pronúncia…) només per a l'àudio.
-- Text → veu en Lua pur (Tts.prepare) per poder-ho provar amb luajit.
local json = require('src.lib.json')

local Tts = { backend = 'none', queue = {} }

Tts.LANGS = { ca = 'ca-ES', es = 'es-ES' }
Tts.ESPEAK = { ca = 'ca', es = 'es' }

local lexicon
local function load_lexicon()
  if lexicon then return lexicon end
  local txt
  if love and love.filesystem and love.filesystem.read then txt = love.filesystem.read('data/tts_lexicon.json')
  else local f = io.open('data/tts_lexicon.json'); if f then txt = f:read('*a'); f:close() end end
  local ok, v = pcall(json.decode, txt or '{}')
  lexicon = ok and v or {}
  return lexicon
end

-- text de pantalla → text per dir: sense símbols de joc, amb la pronúncia del lèxic
function Tts.prepare(text, lang)
  local lx = load_lexicon()[lang or 'ca'] or {}
  local s = tostring(text or '')
  s = s:gsub('%(J: diari%)', ''):gsub('[<>%[%]|*_#]', ' '):gsub('·', ','):gsub('…', '...')
  s = s:gsub('%+(%d+)', '%1')
  -- abreviatures de pantalla (perfils, HUD): «Nv3» → «nivell 3», «1h05» → «1 h 05»
  s = s:gsub('Nv(%d+)', 'nivell %1'):gsub('(%d+)h(%d%d)', '%1 hores %2 minuts')
  -- paraules senceres (també amb punt, com «Dra.»): de més llargues a més curtes
  local keys = {}
  for k in pairs(lx) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return #a > #b end)
  for _, k in ipairs(keys) do
    local pat = k:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
    s = (' ' .. s .. ' '):gsub('([^%w\128-\255])' .. pat .. '([^%w\128-\255])', '%1' .. lx[k]:gsub('%%', '%%%%') .. '%2')
    s = s:sub(2, -2)
  end
  s = s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  return s
end

-- ---------------------------------------------------------------- motors
local THREAD = [[
require('love.timer')
local cmd_ch = love.thread.getChannel('tts_cmd')
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function busy(bin)
  local ok = os.execute('pgrep -x ' .. bin .. ' >/dev/null 2>&1')
  return ok == true or ok == 0
end
while true do
  local m = cmd_ch:demand()
  if m == 'quit' then break end
  if type(m) == 'table' then
    if m.stop then os.execute('pkill -x ' .. m.bin .. ' >/dev/null 2>&1') end
    if m.text and m.text ~= '' then
      -- sense interrompre: s'espera que acabi la frase anterior (aquí, mai al fil del joc)
      local waited = 0
      while not m.stop and busy(m.bin) and waited < 30 do love.timer.sleep(0.15); waited = waited + 0.15 end
      os.execute(string.format('%s -v %s -s %d -a %d %s >/dev/null 2>&1 &', m.bin, m.voice, m.wpm, m.amp, q(m.text)))
    end
  end
end
]]

function Tts.init(settings)
  Tts.settings = settings
  if not love or not love.system then return end
  if love.system.getOS() == 'Web' then
    local f = io.open('/dev/rodatts', 'w')
    if f then f:close(); Tts.backend = 'web' end
  elseif love.system.getOS() == 'Linux' and love.thread then
    -- una sola comprovació a l'arrencada (no durant la partida)
    for _, bin in ipairs({ 'espeak-ng', 'espeak' }) do
      local ok = os.execute('command -v ' .. bin .. ' >/dev/null 2>&1')
      if ok == true or ok == 0 then
        Tts.bin = bin
        Tts.thread = love.thread.newThread(THREAD)
        Tts.thread:start()
        Tts.backend = 'espeak'
        break
      end
    end
  end
end

function Tts.enabled()
  local s = Tts.settings and Tts.settings.tts
  return Tts.backend ~= 'none' and s and s.on and s.volume > 0 and require('src.audio').volume > 0
end

-- darreres frases enviades a la veu (proves i depuració)
Tts.history = {}
local function remember(said)
  local h = Tts.history
  h[#h + 1] = said
  if #h > 30 then table.remove(h, 1) end
end

-- gènere de la veu a partir del nom de qui parla (diàlegs, bafarades): 'm' (home), 'f' (dona) o nil (narrador).
-- En català l'article ho diu quasi sempre: «En Jordi», «El pagès», «L'avi» → home; «La Carme», «Na Rosa», «L'àvia» → dona.
local MALE = { jordi = 1, pau = 1, marc = 1, joan = 1, ramon = 1, xavi = 1, toni = 1, pep = 1, pere = 1, olaf = 1,
               josep = 1, enric = 1, oriol = 1, albert = 1, jaume = 1, lluis = 1, ['lluís'] = 1, manel = 1,
               david = 1, carles = 1, pablo = 1, jorge = 1, avi = 1, ['senyor'] = 1, ['pagès'] = 1,
               policia = 0, metge = 0, doctor = 1, cambrer = 1, forner = 1, pescador = 1, guarda = 1, nen = 1, noi = 1,
               ['germà'] = 1, pare = 1, oncle = 1, tiet = 1, monitor = 1, mestre = 1, rei = 1, drac = 1, gat = 1 }
local FEMALE = { carme = 1, montse = 1, laia = 1, ['núria'] = 1, nuria = 1, rosa = 1, marta = 1, pilar = 1, nena = 1,
                 iaia = 1, avia = 1, ['àvia'] = 1, senyora = 1, mare = 1,
                 tieta = 1, tia = 1, germana = 1, nena = 1, noia = 1, metgessa = 1, doctora = 1, cambrera = 1,
                 fornera = 1, mestra = 1, dependenta = 1, caixera = 1, monitora = 1, reina = 1, gallina = 1 }
function Tts.gender(name)
  if type(name) ~= 'string' or name == '' then return nil end
  local n = name:gsub('·.*$', ''):gsub('^%s+', ''):gsub('%s+$', '')
  local low = n:lower():gsub('À', 'à'):gsub('Í', 'í')
  if low:match('^en ') or low:match('^el ') or low:match('^els ') then return 'm' end
  if low:match('^la ') or low:match('^na ') or low:match('^les ') then return 'f' end
  for w in low:gmatch("[%a\128-\255]+") do
    if FEMALE[w] then return 'f' end
    if MALE[w] == 1 then return 'm' end
  end
  return nil
end

-- interrupt: talla el que s'estava dient (diàleg nou, menú); si no, es posa a la cua del navegador o del fil.
-- voice: 'm' | 'f' | nil (Tts.gender): al navegador, una veu d'home o de dona si n'hi ha; si no, to més greu o agut
function Tts.say(text, interrupt, voice)
  if not Tts.enabled() then return end
  local s = Tts.settings.tts
  local said = Tts.prepare(text, s.lang)
  if said == '' then return end
  Tts.last = said
  remember(said)
  Tts.last_voice = voice
  Tts.seq = (Tts.seq or 0) + 1
  Tts.said_len = #said
  Tts.word = nil
  if Tts.backend == 'web' then
    local f = io.open('/dev/rodatts', 'w')
    if f then
      f:write(json.encode({ cmd = 'say', text = said, lang = Tts.LANGS[s.lang], rate = s.rate, volume = s.volume * require('src.audio').volume,
                            interrupt = interrupt and true or false, voice = voice, id = Tts.seq }) .. '\n')
      f:close()
    end
  elseif Tts.backend == 'espeak' then
    local ev = Tts.ESPEAK[s.lang] .. (voice == 'm' and '+m3' or (voice == 'f' and '+f3' or ''))
    love.thread.getChannel('tts_cmd'):push({ text = said, stop = interrupt, bin = Tts.bin, voice = ev,
                                             wpm = math.floor(160 * s.rate), amp = math.floor(180 * s.volume * require('src.audio').volume) })
  end
end

-- el navegador avisa de cada paraula (onboundary) i del final: { type = 'tts_word', id, i, n } / 'tts_end'
function Tts.event(m)
  if type(m) ~= 'table' or m.id ~= Tts.seq then return end
  if m.type == 'tts_word' and tonumber(m.i) and tonumber(m.n) and tonumber(m.n) > 0 then
    Tts.word = { id = m.id, frac = math.max(0, math.min(1, tonumber(m.i) / tonumber(m.n))) }
  elseif m.type == 'tts_end' then
    Tts.word = { id = m.id, frac = 1, done = true }
  end
end

function Tts.stop()
  if Tts.backend == 'web' then
    local f = io.open('/dev/rodatts', 'w')
    if f then f:write('{"cmd":"stop"}\n'); f:close() end
  elseif Tts.backend == 'espeak' then
    love.thread.getChannel('tts_cmd'):push({ stop = true, bin = Tts.bin })
  end
end

function Tts.quit()
  if Tts.thread then love.thread.getChannel('tts_cmd'):push('quit') end
end

return Tts
