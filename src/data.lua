-- Carga de datos JSON del paquete (data/*.json) con caché.
local json = require('src.lib.json')
local Data = { cache = {} }

function Data.read_json(path)
  if Data.cache[path] then return Data.cache[path] end
  local s = assert(love.filesystem.read(path), 'no se puede leer ' .. path)
  local v = json.decode(s)
  Data.cache[path] = v
  return v
end

function Data.load_lua(path)
  local chunk = assert(love.filesystem.load(path))
  return chunk()
end

return Data
