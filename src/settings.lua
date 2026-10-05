-- Opcions globals del joc (no van per perfil): settings.json al directori de dades de LÖVE.
-- Ara: veu (TTS) activada, volum, velocitat i idioma de la veu.
local json = require('src.lib.json')

local S = { FILE = 'settings.json' }
-- upper: tot el text en MAJÚSCULES (src/ui/upper.lua); tts.all: la veu llegeix també menús, avisos i bafarades
S.DEFAULTS = { reduced_motion = false, upper = false, audio = { custom=false, master=.6, music=.45, effects=1 },
               tts = { on = true, volume = 0.8, rate = 1.0, lang = 'ca', all = true } }

local function merge(d, v)
  local out = {}
  for k, dv in pairs(d) do
    if type(dv) == 'table' then out[k] = merge(dv, type(v) == 'table' and v[k] or nil)
    elseif type(v) == 'table' and type(v[k]) == type(dv) then out[k] = v[k]
    else out[k] = dv end
  end
  return out
end

function S.load()
  local v
  if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(S.FILE) then
    local ok, d = pcall(json.decode, love.filesystem.read(S.FILE) or '')
    if ok then v = d end
  end
  S.data = merge(S.DEFAULTS, v)
  -- valors dins de marges
  for _,k in ipairs({'master','music','effects'}) do
    local n=S.data.audio[k]
    S.data.audio[k]=n==n and math.max(0,math.min(1,n)) or S.DEFAULTS.audio[k]
  end
  local t = S.data.tts
  t.volume = math.max(0, math.min(1, t.volume))
  t.rate = math.max(0.6, math.min(1.6, t.rate))
  if t.lang ~= 'ca' and t.lang ~= 'es' then t.lang = 'ca' end
  return S.data
end

function S.save()
  if not (love and love.filesystem and love.filesystem.write) then return end
  local ok,written=pcall(love.filesystem.write, S.FILE, json.encode(S.data or S.DEFAULTS, true))
  if ok and written and love.system and love.system.getOS()=='Web' then
    require('src.webui').emit({type='saved'}) -- flush IndexedDB before a mobile tab is closed
  end
  return ok and written
end

function S.get() return S.data or S.load() end

return S
