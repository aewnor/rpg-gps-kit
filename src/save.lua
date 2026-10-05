-- Guardado versionado con escritura atómica (temporal + reemplazo) y respaldo recuperable.
-- `fs` abstrae el sistema de archivos (love.filesystem en el juego; io en los tests).
local json = require('src.lib.json')

local Save = { SCHEMA = 1, FILE = 'save.json', TMP = 'save.tmp', BAK = 'save.bak', DIR = nil }

-- ranura de perfil (src/profile.lua): profiles/slot<N>/save.json; sin directorio, el guardado clásico
function Save.use(dir)
  Save.DIR = dir
  local pre = dir and (dir .. '/') or ''
  Save.FILE, Save.TMP, Save.BAK = pre .. 'save.json', pre .. 'save.tmp', pre .. 'save.bak'
end

local Storage = require('src.storage')
local love_fs = Storage.filesystem
Save.fs = nil
local function fs() Save.fs = Save.fs or love_fs(); return Save.fs end

-- validación mínima del esquema
function Save.validate(state)
  if type(state) ~= 'table' then return false, 'no es un objeto' end
  if state.schema ~= Save.SCHEMA then return false, 'versión de esquema ' .. tostring(state.schema) end
  if type(state.scene) ~= 'string' then return false, 'escena ausente' end
  if type(state.x) ~= 'number' or type(state.y) ~= 'number' then return false, 'posición ausente' end
  if type(state.flags) ~= 'table' then return false, 'flags ausentes' end
  return true
end

function Save.migrate(state)
  -- punto de extensión para versiones futuras del esquema
  return state
end

function Save.write(state)
  state.schema = Save.SCHEMA
  state.saved_at = os.time()   -- src/sync.lua: la partida més nova guanya entre aparells
  local ok, err = Storage.write(fs(),Save.FILE,Save.TMP,Save.BAK,state,Save.validate)
  local slot = ok and Save.DIR and tonumber(Save.DIR:match('profiles/slot(%d+)$'))
  if slot then
    local good, Sync = pcall(require, 'src.sync')
    if good and type(Sync) == 'table' then Sync.mark(slot) end
  end
  return ok, err
end
local function try_load(name)
  local v,err=Storage.read(fs(),name,Save.validate)
  return v,err or (not v and 'no existe' or nil)
end

-- devuelve estado, origen ('save'|'backup'|nil) y aviso
function Save.read()
  local st, why = try_load(Save.FILE)
  if st then return st, 'save' end
  local bak, why2 = try_load(Save.BAK)
  if bak then return bak, 'backup', 'Guardat danyat (' .. tostring(why) .. '): s\'ha recuperat la còpia.' end
  if why ~= 'no existe' then
    return nil, nil, 'Guardat danyat i sense còpia vàlida (' .. tostring(why) .. ', ' .. tostring(why2) .. ').'
  end
  return nil
end

function Save.exists()
  local f = fs()
  return f.exists(Save.FILE) or f.exists(Save.BAK)
end

return Save
