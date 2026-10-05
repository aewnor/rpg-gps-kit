-- Perfiles de jugador: hasta 5 ranuras independientes en el directorio de datos de LÖVE (nunca en el paquete
-- ni en el repositorio). Cada ranura:
--   profiles/slot<N>/user_profile.json   avatar, casa (home_player_location) y hasta 12 amigos/abuelos
--   profiles/slot<N>/save.json (+ .bak)  la partida (src/save.lua)
-- Los datos privados (nombres, casas) solo existen ahí. Todo lo leído se sanea antes de usarlo.
local json = require('src.lib.json')
local Looks = require('src.paperdoll.looks')

local P = { MAX_SLOTS = 5, MAX_FRIENDS = 12, NAME_MAX = 14, SCHEMA = 1, FILE = 'user_profile.json' }

P.ROLES = { 'amiga', 'amic', 'avia', 'avi', 'tieta', 'tiet', 'cosina', 'cosi' }
P.ROLE_NAMES = { amiga = 'Amiga', amic = 'Amic', avia = 'Àvia', avi = 'Avi', tieta = 'Tieta', tiet = 'Tiet',
                 cosina = 'Cosina', cosi = 'Cosí' }
P.INTERIORS = { 'house', 'block' }
P.INTERIOR_NAMES = { house = 'Casa', block = 'Pis' }
P.FLOORS = { 'wood', 'tile', 'carpet' }
P.FLOOR_NAMES = { wood = 'Parquet', tile = 'Rajola', carpet = 'Moqueta' }

-- sistema de archivos (love.filesystem en el juego; tabla en memoria o io en los tests)
local Storage = require('src.storage')
local love_fs = Storage.filesystem
P.fs = nil
local function fs() P.fs = P.fs or love_fs(); return P.fs end

P.owner=nil
function P.set_owner(id)
  if id~=nil and (type(id)~='string' or #id==0 or #id>64) then return false end
  P.owner=id
  return true
end
function P.base()
  if not P.owner then return '' end
  return 'owners/'..(P.owner:gsub('.',function(c)return string.format('%02x',c:byte())end))..'/'
end
function P.quick_dir() return P.owner and (P.base()..'quick') or nil end
function P.dir(slot) return P.base() .. 'profiles/slot' .. slot end
function P.path(slot) return P.dir(slot) .. '/' .. P.FILE end

-- ---------------------------------------------------------------- saneado
local function clean_name(s, fallback)
  s = tostring(s or ''):gsub('[%c|<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
  -- cortar por caracteres UTF-8, no por bytes
  local out, n = {}, 0
  for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    n = n + 1
    if n > P.NAME_MAX then break end
    out[#out + 1] = ch
  end
  s = table.concat(out)
  return s ~= '' and s or fallback
end
P.clean_name = clean_name

-- texto a medio escribir (sin recortar espacios): solo quita controles y limita la longitud
function P.limit_name(s)
  s = tostring(s or ''):gsub('[%c|<>]', '')
  local out, n = {}, 0
  for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    n = n + 1
    if n > P.NAME_MAX then break end
    out[#out + 1] = ch
  end
  return table.concat(out)
end

local function clean_place(h)
  if type(h) ~= 'table' then return nil end
  local tx, ty = tonumber(h.tile_x), tonumber(h.tile_y)
  if not tx or not ty then return nil end
  local out = { scene = 'overworld', tile_x = math.floor(tx), tile_y = math.floor(ty) }
  if tonumber(h.door_x) and tonumber(h.door_y) then out.door_x, out.door_y = math.floor(h.door_x), math.floor(h.door_y) end
  if type(h.street) == 'string' then out.street = h.street:sub(1, 60) end
  return out
end

-- padres (editables): por defecto, nombres catalanes elegidos de forma determinista a partir de una clave
local PARE_NAMES = { 'Jordi', 'Marc', 'Pere', 'Joan', 'Albert', 'Josep', 'Xavier', 'Ramon', 'Ferran', 'Toni', 'Jaume', 'Oriol' }
local MARE_NAMES = { 'Marta', 'Núria', 'Montse', 'Carme', 'Anna', 'Laia', 'Roser', 'Mercè', 'Neus', 'Elena', 'Júlia', 'Cristina' }
local function hash(str)
  local h = 7
  for i = 1, #str do h = (h * 31 + str:byte(i)) % 1000003 end
  return h
end
function P.default_parents(key)
  local h = hash(tostring(key or ''))
  return { pare = PARE_NAMES[h % #PARE_NAMES + 1], mare = MARE_NAMES[math.floor(h / 7) % #MARE_NAMES + 1] }
end
local function clean_parents(v, key)
  v = type(v) == 'table' and v or {}
  local d = P.default_parents(key)
  return { pare = clean_name(v.pare, d.pare), mare = clean_name(v.mare, d.mare) }
end

-- padres del jugador (f = nil) o de un amigo/familiar
function P.parents_of(p, f)
  local owner = f or p
  if owner and type(owner.parents) == 'table' and owner.parents.pare and owner.parents.mare then return owner.parents end
  return clean_parents(owner and owner.parents, f and ('f:' .. tostring(f.id)) or ('p:' .. tostring(p and p.name)))
end

local function pick(v, list, default) for _, x in ipairs(list) do if x == v then return v end end return default end

-- identificador estable del perfil (src/sync.lua: el mateix perfil a tots els aparells)
function P.new_uid()
  local r = (love and love.math and love.math.random) or math.random
  return string.format('p%d_%06d', os.time(), r(0, 999999))
end
local function clean_uid(u) return type(u) == 'string' and #u >= 4 and #u <= 40 and u:match('^[%w_-]+$') and u or nil end

-- avís a la sincronització (si el joc la té; als tests de luajit no hi és)
local function sync_call(fn, ...)
  local ok, Sync = pcall(require, 'src.sync')
  if ok and type(Sync) == 'table' and Sync[fn] then Sync[fn](...) end
end
P.sync_call = sync_call

function P.sanitize(p)
  p = type(p) == 'table' and p or {}
  -- al fitxer la casa es diu home_player_location (com a data/world.json); a la memòria, home
  local out = { schema = P.SCHEMA, name = clean_name(p.name, 'Jugador'), avatar = Looks.sanitize(p.avatar),
                home = clean_place(p.home_player_location or p.home), friends = {}, created = tonumber(p.created) or 0 }
  out.parents = clean_parents(p.parents, 'p:' .. out.name)
  out.uid, out.updated = clean_uid(p.uid), tonumber(p.updated) or 0
  local used = {}
  if type(p.friends) == 'table' then
    for _, f in ipairs(p.friends) do
      if #out.friends >= P.MAX_FRIENDS then break end
      if type(f) == 'table' then
        local id = tostring(f.id or ''):gsub('[^%w_]', ''):sub(1, 16)
        if id == '' or used[id] then id = 'f' .. (#out.friends + 1) end
        while used[id] do id = id .. 'x' end
        used[id] = true
        local it = type(f.interior) == 'table' and f.interior or {}
        out.friends[#out.friends + 1] = {
          id = id, name = clean_name(f.name, 'Amic ' .. (#out.friends + 1)), role = pick(f.role, P.ROLES, 'amic'),
          look = Looks.sanitize(f.look), home = clean_place(f.home),
          interior = { kind = pick(it.kind, P.INTERIORS, 'house'), floor = pick(it.floor, P.FLOORS, 'wood'),
                       cat = it.cat == true, dog = it.dog == true },
          parents = clean_parents(f.parents, 'f:' .. id),
        }
      end
    end
  end
  return out
end

function P.new(name, body)
  return P.sanitize({ name = name, avatar = Looks.default(body), friends = {}, created = os.time(), uid = P.new_uid() })
end

function P.new_friend(p, role)
  local n = #p.friends + 1
  local id = 'f' .. n
  local used = {}
  for _, f in ipairs(p.friends) do used[f.id] = true end
  while used[id] do n = n + 1; id = 'f' .. n end
  local look = Looks.default((role == 'amiga' or role == 'avia' or role == 'tieta' or role == 'cosina') and 'nena' or 'nen')
  if role == 'avi' or role == 'avia' then Looks.preset_age(look, 'elder')
  elseif role == 'tiet' or role == 'tieta' then look.age = 'adult' end
  return { id = id, name = P.ROLE_NAMES[role] or 'Amic', role = role or 'amic', look = look, home = nil,
           interior = { kind = 'house', floor = 'wood', cat = false, dog = false }, parents = P.default_parents('f:' .. id) }
end

-- ---------------------------------------------------------------- lectura y escritura
local function valid(p)
  return type(p)=='table' and p.schema==P.SCHEMA and type(p.name)=='string' and p.name~=''
end
function P.read(slot)
  local f=fs(); local path=P.path(slot)
  local p,err=Storage.read(f,path,valid)
  if p then return P.sanitize(p) end
  local backup,berr=Storage.read(f,path..'.bak',valid)
  if backup then return P.sanitize(backup), 'Perfil recuperat de la còpia' end
  return nil,err or berr
end
-- from_sync: ve d'un altre aparell (conserva la data i no es torna a pujar)
function P.write(slot,p,from_sync)
  local out=P.sanitize(p)
  out.home_player_location,out.home=out.home,nil
  out.uid=out.uid or P.new_uid()
  if not from_sync then out.updated=os.time() end
  local path=P.path(slot)
  local ok,err=Storage.write(fs(),path,path..'.tmp',path..'.bak',out,valid)
  if ok and not from_sync then sync_call('mark',slot) end
  return ok,err
end

function P.delete(slot, from_sync)
  local f = fs()
  if not from_sync then
    local p = P.read(slot)
    if p and p.uid then sync_call('deleted', p.uid) end
  end
  for _, n in ipairs({ P.FILE, P.FILE..'.bak', P.FILE..'.tmp', P.FILE..'.bak.tmp', 'save.json', 'save.bak', 'save.tmp' }) do
    if f.exists(P.dir(slot) .. '/' .. n) then f.remove(P.dir(slot) .. '/' .. n) end
  end
  if f.exists(P.dir(slot)) then f.remove(P.dir(slot)) end
end

-- primera ranura sin perfil (ni fichero dañado), o nil
function P.free_slot()
  local f = fs()
  for i = 1, P.MAX_SLOTS do
    if not (f.exists(P.path(i)) or f.exists(P.path(i) .. '.bak') or f.exists(P.dir(i) .. '/save.json')) then return i end
  end
end

-- copia el perfil de la ranura src (avatar, casa, amigos, padres) a la primera ranura libre; con
-- with_save también la partida. Devuelve la ranura nueva, o nil y un mensaje en catalán.
function P.duplicate(src, with_save)
  local p, err = P.read(src)
  if not p then return nil, err or 'No es pot llegir el perfil' end
  local dst = P.free_slot()
  if not dst then return nil, 'No hi ha cap ranura lliure' end
  local base, n = {}, 0
  for ch in p.name:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    n = n + 1
    if n > P.NAME_MAX - 2 then break end
    base[#base + 1] = ch
  end
  p.name = clean_name(table.concat(base) .. ' 2', p.name)
  p.created, p.uid = os.time(), P.new_uid()
  local ok, werr = P.write(dst, p)
  if not ok then return nil, werr or 'No es pot desar la còpia' end
  if with_save then
    local f = fs()
    local sp = P.dir(src) .. '/save.json'
    if f.exists(sp) then
      local raw = f.read(sp)
      if not (raw and f.write(P.dir(dst) .. '/save.json', raw)) then
        P.delete(dst)
        return nil, 'No es pot copiar la partida'
      end
    end
  end
  return dst
end

-- resumen de las 5 ranuras para el menú: { [i] = { exists, name, level, play_time, has_save } }
function P.list()
  local out = {}
  local f = fs()
  for i = 1, P.MAX_SLOTS do
    local p,err = P.read(i)
    local e = { slot = i, exists = p ~= nil or err ~= nil, error = not p and err or nil, warning = p and err, name = p and p.name }
    local sp = P.dir(i) .. '/save.json'
    if p and f.exists(sp) then
      local ok, s = pcall(json.decode, f.read(sp) or '')
      if ok and type(s) == 'table' then
        e.has_save, e.level, e.play_time = true, tonumber(s.char_level) or 1, tonumber(s.play_time) or 0
      end
    end
    out[i] = e
  end
  return out
end

-- casa del perfil → configuración de src/home.lua
function P.home_cfg(p)
  if not (p and p.home) then return nil end
  return { configured = true, profile = true, scene = 'overworld', tile_x = p.home.tile_x, tile_y = p.home.tile_y }
end

return P
