-- Horaris dels personatges (Schedule System) segons l'hora del joc (state.clock, minuts) i el dia
-- (state.day: 6 i 7 de cada setmana, cap de setmana). Lua pur (tests/schedule_cases.lua).
--   kid      escola al matí i a primera hora de la tarda, parc fins al vespre, la resta a casa
--   adult    plaça (feina, encàrrecs) al matí, súper a la tarda
--   elder    passeig pel parc, plaça a migdia, parc a la tarda
--   townsfolk veïns del mapa: al seu lloc de dia, alguns al parc a la tarda, a casa (no es veuen) de nit
--   service  personatges dels serveis: obert de 7:30 a 21:30, tancat de nit
local S = {}

local function hm(h, m) return h * 60 + (m or 0) end

S.ROUTINES = {
  kid = {
    weekday = { { hm(8, 30), hm(13, 30), 'school' }, { hm(15, 0), hm(16, 30), 'school' }, { hm(17, 0), hm(19, 30), 'park' } },
    weekend = { { hm(10, 30), hm(13, 0), 'park' }, { hm(17, 0), hm(20, 0), 'park' } },
  },
  adult = {
    weekday = { { hm(9, 0), hm(13, 30), 'plaza' }, { hm(17, 0), hm(19, 30), 'shop' } },
    weekend = { { hm(11, 0), hm(13, 30), 'park' }, { hm(18, 0), hm(20, 0), 'plaza' } },
  },
  elder = {
    weekday = { { hm(9, 30), hm(12, 0), 'park' }, { hm(12, 0), hm(13, 30), 'plaza' }, { hm(17, 0), hm(19, 30), 'park' } },
    weekend = { { hm(10, 0), hm(13, 0), 'plaza' }, { hm(17, 0), hm(19, 30), 'park' } },
  },
  townsfolk = {
    weekday = { { hm(7, 30), hm(16, 0), 'post' }, { hm(16, 0), hm(19, 0), 'park' }, { hm(19, 0), hm(22, 0), 'post' } },
    weekend = { { hm(9, 0), hm(13, 0), 'post' }, { hm(16, 0), hm(20, 0), 'park' }, { hm(20, 0), hm(22, 0), 'post' } },
  },
  service = {
    weekday = { { hm(7, 30), hm(21, 30), 'post' } },
    weekend = { { hm(7, 30), hm(21, 30), 'post' } },
  },
  -- la mestra: a l'escola (pati o aula) en horari escolar
  teacher = {
    weekday = { { hm(8, 0), hm(17, 30), 'post' } },
    weekend = {},
  },
  -- agents de la Policia Local: patrullen tot el dia pels voltants de la comissaria
  patrol = {
    weekday = { { 0, hm(24, 0), 'patrol' } },
    weekend = { { 0, hm(24, 0), 'patrol' } },
  },
}
-- on és quan no toca res
S.IDLE = { kid = 'home', adult = 'home', elder = 'home', townsfolk = 'home', service = 'closed', teacher = 'home',
           patrol = 'patrol' }

S.PLACE_NAMES = { home = 'a casa', school = 'a l\'escola', park = 'al parc', plaza = 'a la plaça', shop = 'al súper',
                  post = 'pel barri', closed = 'tancat' }

function S.weekend(day) local d = ((day or 1) - 1) % 7 + 1; return d == 6 or d == 7 end

-- lloc on ha de ser un personatge del tipus `kind` a l'hora `clock` del dia `day`
function S.place(kind, clock, day)
  local r = S.ROUTINES[kind] or S.ROUTINES.townsfolk
  local list = S.weekend(day) and r.weekend or r.weekday
  local c = (clock or 0) % 1440
  for _, b in ipairs(list) do
    if c >= b[1] and c < b[2] then return b[3] end
  end
  return S.IDLE[kind] or 'home'
end

-- tipus de rutina d'un personatge del perfil (rol i edat)
function S.kind_of_friend(f)
  local age = f.look and f.look.age
  if f.role == 'avi' or f.role == 'avia' or age == 'elder' then return 'elder' end
  if age == 'adult' or f.role == 'tiet' or f.role == 'tieta' then return 'adult' end
  return 'kid'
end

-- llocs on no es veu el personatge al carrer (a casa o tancat): a dins de casa seva, si en té
function S.hidden(place) return place == 'home' or place == 'closed' end

return S
