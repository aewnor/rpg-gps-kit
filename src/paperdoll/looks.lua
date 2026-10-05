-- Aspecto editable (avatar del perfil y personajes de amigos y abuelos) → spec del paperdoll.
-- Un «look» solo guarda índices y nombres cortos (se guarda en user_profile.json):
--   { body, age, skin, hair, hair_color, outfit, top, bottom, shoes, eyes, hat, acc = { glasses = true, … } }
-- Looks.spec(look) da la spec de src/paperdoll/chars.lua; Looks.build(look, full) genera las hojas (con
-- caché por aspecto: el mismo look no se vuelve a dibujar).
local Canvas = require('src.paperdoll.canvas')

local L = {}

-- tonos de piel (luz, sombra): del más claro al más oscuro
L.SKINS = {
  { '#f8d9bd', '#e0b394' }, { 'skin', 'skin2' }, { '#dca57f', '#bc8460' }, { '#b97e57', '#966140' },
  { '#8a5a3c', '#6d432b' }, { '#5e3b27', '#472b1c' },
}
L.HAIRS = { 'short', 'bob', 'long', 'pigtails', 'bun', 'spiky', 'bald' }
L.HAIR_NAMES = { short = 'Curt', bob = 'Mitja melena', long = 'Llarg', pigtails = 'Cuetes', bun = 'Monyo',
                 spiky = 'De punta', bald = 'Calb' }
L.HAIR_COLORS = { { 'ink', 'Negre' }, { 'asph3', 'Castany fosc' }, { 'ochre3', 'Castany' }, { 'terra3', 'Caoba' },
                  { 'terra2', 'Pèl-roig' }, { 'ochre', 'Ros' }, { 'sand', 'Ros clar' }, { 'white3', 'Gris' },
                  { 'white', 'Blanc' } }
L.OUTFITS = { 'shorts', 'tshirt', 'pants', 'dress', 'sweater', 'uniform' }
L.OUTFIT_NAMES = { shorts = 'Samarreta i pantaló curt', tshirt = 'Samarreta', pants = 'Pantaló llarg',
                   dress = 'Vestit', sweater = 'Jersei', uniform = 'Uniforme' }
L.CLOTH = { { 'red', 'Vermell' }, { 'blue', 'Blau' }, { 'sea', 'Turquesa' }, { 'pine2', 'Verd' }, { 'ochre', 'Groc' },
            { 'terra', 'Teula' }, { 'white', 'Blanc' }, { 'asph3', 'Gris fosc' }, { '#d47fa6', 'Rosa' },
            { '#8a6bc4', 'Lila' }, { 'sand2', 'Beix' } }
L.EYES = { { 'asph3', 'Foscos' }, { 'ochre3', 'Marrons' }, { 'sea2', 'Blaus' }, { 'pine3', 'Verds' } }
L.HATS = { 'none', 'cap', 'beanie', 'ranger' }
L.HAT_NAMES = { none = 'Cap', cap = 'Gorra', beanie = 'Gorro de llana', ranger = 'Barret' }
L.ACCESSORIES = { 'glasses', 'bag', 'scarf', 'beard', 'cane', 'apron', 'belt' }
L.ACC_NAMES = { glasses = 'Ulleres', bag = 'Bossa', scarf = 'Bufanda', beard = 'Barba', cane = 'Bastó',
                apron = 'Davantal', belt = 'Cinturó' }
L.BODIES = { 'nena', 'nen', 'altre' }
L.BODY_NAMES = { nena = 'Nena', nen = 'Nen', altre = 'Prefereixo no dir-ho' }
L.AGES = { 'kid', 'adult', 'elder' }
L.AGE_NAMES = { kid = 'Infant', adult = 'Adult', elder = 'Gran' }

-- aspecto por defecto (como la protagonista) y punts de partida per edat (avis: cabells blancs, ulleres i bastó)
function L.default(body)
  local l = { body = body or 'nena', age = 'kid', skin = 2, hair = 'bob', hair_color = 3, outfit = 'dress', top = 3,
              bottom = 3, shoes = 7, eyes = 3, hat = 'none', acc = {} }
  if body == 'nen' then l.hair, l.outfit, l.top, l.bottom = 'short', 'shorts', 7, 2 end
  return l
end

function L.preset_age(l, age)
  l.age = age
  if age == 'elder' then
    l.hair_color = 9; l.acc = l.acc or {}; l.acc.glasses = true
    if l.outfit == 'shorts' or l.outfit == 'tshirt' then l.outfit = 'sweater' end
  end
  return l
end

-- copia saneada (datos del perfil: nunca confiar en lo leído del disco)
function L.sanitize(l)
  l = type(l) == 'table' and l or {}
  local out = L.default(l.body)
  local function pick(v, list) for _, x in ipairs(list) do if x == v then return v end end end
  local function idx(v, n) v = tonumber(v); if v and v >= 1 and v <= n then return math.floor(v) end end
  out.body = pick(l.body, L.BODIES) or out.body
  out.age = pick(l.age, L.AGES) or out.age
  out.skin = idx(l.skin, #L.SKINS) or out.skin
  out.hair = pick(l.hair, L.HAIRS) or out.hair
  out.hair_color = idx(l.hair_color, #L.HAIR_COLORS) or out.hair_color
  out.outfit = pick(l.outfit, L.OUTFITS) or out.outfit
  out.top = idx(l.top, #L.CLOTH) or out.top
  out.bottom = idx(l.bottom, #L.CLOTH) or out.bottom
  out.shoes = idx(l.shoes, #L.CLOTH) or out.shoes
  out.eyes = idx(l.eyes, #L.EYES) or out.eyes
  local special = { hood = true, helmet = true, helmet_ride = true }   -- xubasquer i cascos: no s'editen al perfil
  out.hat = pick(l.hat, L.HATS) or (special[l.hat] and l.hat) or 'none'
  out.armor = (l.armor == 'dragon') and 'dragon' or nil   -- armadura visible (no s'edita al perfil)
  out.acc = {}
  if type(l.acc) == 'table' then for _, a in ipairs(L.ACCESSORIES) do if l.acc[a] then out.acc[a] = true end end end
  return out
end

local function shade(c, k) return Canvas.mix(c, 'ink', k) end

function L.spec(l)
  l = L.sanitize(l)
  local sk = L.SKINS[l.skin]
  local hc = L.HAIR_COLORS[l.hair_color][1]
  local top = L.CLOTH[l.top][1]
  local spec = {
    s = sk[1], S = sk[2], p = Canvas.mix(sk[1], 'terra', l.skin >= 5 and 0.25 or 0.35),
    h = hc, H = shade(hc, hc == 'ink' and 0 or 0.3), L = hc == 'ink' and 'asph3' or nil,
    w = top, W = shade(top, 0.18), b = L.CLOTH[l.bottom][1], o = shade(L.CLOTH[l.shoes][1], 0.25),
    e = L.EYES[l.eyes][1], c = top, C = shade(top, 0.3),
    _hair = l.hair, _outfit = l.outfit, _extra = {},
  }
  if l.hat ~= 'none' then spec._hat = l.hat end
  for _, a in ipairs(L.ACCESSORIES) do if l.acc[a] then spec._extra[#spec._extra + 1] = a end end
  if l.armor then spec._extra[#spec._extra + 1] = l.armor end
  if l.age == 'kid' then spec._age = 'kid' end
  return spec
end

-- el mateix aspecte amb el xubasquer groc i la caputxa (quan plou a l'exterior)
function L.raincoat(l)
  local r = L.sanitize(l)
  r.outfit, r.top, r.hat = 'sweater', 5, 'hood'
  return r
end

-- amb casc en anar en vehicle (bici, patinet, moto: vermell; cavall: d'hípica)
function L.helmet(l, ride)
  local r = L.sanitize(l)
  r.hat = ride and 'helmet_ride' or 'helmet'
  return r
end

-- amb l'Armadura del Drac equipada
function L.dragon(l)
  local r = L.sanitize(l)
  r.armor = 'dragon'
  if r.outfit == 'dress' or r.outfit == 'shorts' or r.outfit == 'tshirt' then r.outfit = 'pants' end
  r.bottom = 4
  return r
end

-- clave estable del aspecto (caché de hojas)
function L.key(l)
  l = L.sanitize(l)
  local acc = {}
  for _, a in ipairs(L.ACCESSORIES) do if l.acc[a] then acc[#acc + 1] = a end end
  return table.concat({ l.body, l.age, l.skin, l.hair, l.hair_color, l.outfit, l.top, l.bottom, l.shoes, l.eyes, l.hat,
                        table.concat(acc, '+'), l.armor or '' }, '|')
end

-- ---------------------------------------------------------------- hojas (love.graphics)
local cache = {}
local function grid_quads(image, w, h)
  local out = {}
  local cols, rows = image:getWidth() / w, image:getHeight() / h
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do out[#out + 1] = love.graphics.newQuad(c * w, r * h, w, h, image:getDimensions()) end
  end
  return out
end

-- full = true: también ataque, bici y vehículos (protagonista). Devuelve:
--   { sheet, quad(row, col) }  y, con full, action/action_quads, bike/bike_quads, vehicles[v] = {img, quads}
function L.build(l, full)
  local key = L.key(l) .. (full and '#full' or '')
  if cache[key] then return cache[key] end
  local Chars = require('src.paperdoll.chars')
  local spec = L.spec(l)
  local data, diag = require('src.paperdoll.diag').extend_data(Chars.sheet(spec):to_imagedata())   -- + diagonals
  local sheet = love.graphics.newImage(data)
  sheet:setFilter('nearest', 'nearest')
  local quads = grid_quads(sheet, 16, 24)
  local out = { sheet = sheet, diag = diag, quad = function(row, col) return quads[row * 6 + col + 1] end }
  if full then
    local S = require('src.paperdoll.sheets')
    out.action = Canvas.to_image(S.action(spec)); out.action_quads = grid_quads(out.action, 32, 32)
    out.bike = Canvas.to_image(S.bike(spec)); out.bike_quads = grid_quads(out.bike, 32, 32)
    -- vistes en diagonal (S.diag): fulla a part per vehicle
    local function diag(kind) local i = Canvas.to_image(S.diag(spec, kind)); return { img = i, quads = grid_quads(i, 32, 32) } end
    out.bike_diag = diag('bike')
    out.vehicles = {}
    for _, v in ipairs({ 'patinete', 'scooter', 'motocross', 'cavall_brown', 'cavall_white', 'cavall_chestnut' }) do
      local i = Canvas.to_image(S.vehicle(spec, v))
      out.vehicles[v] = { img = i, quads = grid_quads(i, 32, 32), diag = diag(v) }
    end
  end
  cache[key] = out
  return out
end

-- el editor cambia mucho de aspecto: la caché no debe crecer sin límite
function L.forget(l) cache[L.key(l)] = nil; cache[L.key(l) .. '#full'] = nil end
function L.clear_cache() cache = {} end

return L
