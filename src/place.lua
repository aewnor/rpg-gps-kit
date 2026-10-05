-- El lloc del joc (data/world.json, l'escriu tools/new_location.py): nom per als textos («Benvinguda a
-- l'Ajuntament de …») i si és el poble original (Roda de Berà: trivial i llibres amb la seva història).
local Place = {}
local cache

local function world()
  if cache then return cache end
  local ok, w = pcall(function() return require('src.data').read_json('data/world.json') end)
  cache = ok and type(w) == 'table' and w or {}
  return cache
end

function Place.name() return world().name or 'Roda de Berà' end
function Place.is_roda() return world().name == nil or world().name == 'Roda de Berà' end
-- «de Roda de Berà» / «d'Altafulla»
function Place.of()
  local n = Place.name()
  return (n:match('^[AEIOUÀÈÉÍÒÓÚaeiouàèéíòóú]') and 'd\'' or 'de ') .. n
end

return Place
