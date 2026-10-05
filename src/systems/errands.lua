-- Encàrrecs dels veïns (2026-10-05): sobre l'horari de src/systems/schedule.lua, cada personatge té el seu dia
-- (determinista per persona i dia): anar a buscar el pa, a la perruqueria, a comprar, regar el jardí i, si fa sol
-- a l'estiu, banyar-se a la platja o a la piscina. Després tornen a casa (amb la barra de pa o la bossa).
-- Els llocs són objectes 'errand' del mapa (tools/decorate_map.py errand_spots). Lua pur: tests/errands_cases.lua.
local E = {}

local function hm(h, m) return h * 60 + (m or 0) end

-- hash enter petit i estable (mateix resultat a LuaJIT i a love.js)
local function hash(n)
  n = (n * 1664525 + 1013904223) % 4294967296
  n = (n * 1664525 + 1013904223) % 4294967296
  return n / 4294967296
end

-- llavor estable d'un personatge (nom + casa)
function E.seed(name, hx, hy)
  local s = math.floor(hx or 0) * 7 + math.floor(hy or 0) * 13
  for i = 1, #(name or '') do s = (s * 31 + name:byte(i)) % 1000003 end
  return s
end

local function weekend(day) local d = ((day or 1) - 1) % 7 + 1; return d == 6 or d == 7 end

E.KINDS = { townsfolk = true, adult = true, elder = true, kid = true }
E.SWIM_MONTHS = { [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }   -- Costa Daurada

-- llocs que són botigues: hi entren (no es veuen) i en surten amb el que han comprat
E.INDOOR = { bakery = true, hair = true }
E.CARRY = { bakery = 'bread', shop = 'bag' }

E.PLACE_NAMES = { bakery = 'a buscar el pa', hair = 'a la perruqueria', beach = 'a la platja', pool = 'a la piscina',
                  garden = 'al jardí' }

-- el que diuen si hi parles (segons on van o d'on vénen)
E.LINES = {
  bakery = { 'Vaig a buscar el pa, que encara és calentó!', 'Una barra i dos croissants, com cada matí.' },
  hair = { 'Tinc hora a la perruqueria. Ja tocava!', 'Avui em tallo els cabells... no gaire curts!' },
  shop = { 'Vaig a fer la compra: llet, fruita i ous.', 'Se m\'ha acabat l\'oli! Corro al súper.' },
  beach = { 'Quin sol! Anem a la platja a fer un bany.', 'L\'aigua està bonísima avui.' },
  pool = { 'Fa calor: cap a la piscina!', 'Faig uns llargs a la piscina i torno.' },
  garden = { 'Rego les tomaqueres i les flors.', 'Si no les rego, les plantes es pansen.' },
  bread = { 'Ja tinc el pa! Ara cap a casa a esmorzar.' },
  bag = { 'Quina bossa més plena! Cap a casa.' },
  haircut = { 'Què et sembla el meu tall de cabell nou?' },
}

function E.line(key, seed)
  local l = E.LINES[key]
  if not l then return nil end
  return l[(seed or 0) % #l + 1]
end

-- encàrrec del personatge a l'hora `clock` del dia `day`, o nil (llavors mana l'horari normal)
-- ctx: { sunny = bool, month = 1-12, garden = bool (té jardí a prop de casa) }
function E.pick(kind, seed, clock, day, ctx)
  if not E.KINDS[kind] then return nil end
  ctx = ctx or {}
  local c = (clock or 0) % 1440
  local we = weekend(day)
  local d = day or 1
  local function r(salt) return hash(seed * 7 + d * 131 + salt) end
  local off = (seed % 4) * 10                       -- no hi van tots alhora
  -- bany: dies de sol a l'estiu
  if ctx.sunny and E.SWIM_MONTHS[ctx.month or 0] and r(1) < 0.55 then
    local a, b
    if kind == 'elder' then a, b = hm(10, 0), hm(11, 30)
    elseif we then a, b = hm(11, 0), hm(13, 30)
    elseif kind ~= 'kid' then a, b = hm(17, 30), hm(19, 30)
    end
    if a and c >= a + off and c < b then return r(2) < 0.35 and 'pool' or 'beach' end
  end
  if kind == 'kid' then return nil end
  -- el pa: al matí, més d'hora entre setmana
  local pa = we and hm(9, 30) or hm(8, 0)
  if r(3) < 0.6 and c >= pa + off and c < pa + off + 40 then return 'bakery' end
  -- perruqueria: un dia de cada deu, entre setmana
  if not we and (d + seed) % 10 == 0 and c >= hm(10, 0) + off and c < hm(11, 0) + off then return 'hair' end
  -- compra del matí (els adults ja hi van a la tarda per horari)
  if kind ~= 'adult' and r(4) < 0.4 and c >= hm(11, 0) + off and c < hm(11, 45) + off then return 'shop' end
  -- regar el jardí: al vespre (i la gent gran també al matí)
  if ctx.garden and not ctx.wet then
    if r(5) < 0.6 and c >= hm(19, 0) + off and c < hm(20, 0) + off then return 'garden' end
    if kind == 'elder' and r(6) < 0.5 and c >= hm(9, 0) and c < hm(9, 45) then return 'garden' end
  end
  return nil
end

-- en acabar l'encàrrec `place` (ja hi ha estat): què porta a la mà fins a casa
function E.carry_after(place) return E.CARRY[place] end

return E
