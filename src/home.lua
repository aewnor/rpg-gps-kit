-- Casa del jugador: configuración LOCAL (home.json en el directorio de datos de LÖVE), nunca en
-- el paquete ni en el repositorio. Sin configurar → spawn público; inválida → spawn público + aviso.
local json = require('src.lib.json')

local Home = { FILE = 'home.json' }

function Home.read()
  if not love.filesystem.getInfo(Home.FILE) then return { configured = false } end
  local ok, v = pcall(json.decode, love.filesystem.read(Home.FILE) or '')
  if not ok or type(v) ~= 'table' then
    return { configured = false, error = 'home.json no és JSON vàlid' }
  end
  return v
end

-- maps: tabla escena -> Map ya cargado o función que lo carga
function Home.resolve(cfg, get_map, public_spawn)
  if not cfg.configured then return nil, cfg.error end
  local scene = cfg.scene or 'overworld'
  local ok, map = pcall(get_map, scene)
  if not ok or not map then return nil, 'escena desconeguda: ' .. tostring(scene) end
  local tx, ty = tonumber(cfg.tile_x), tonumber(cfg.tile_y)
  if not tx or not ty then return nil, 'falten tile_x/tile_y' end
  if not map:in_bounds(tx, ty) then return nil, 'fora dels límits del mapa' end
  local code = map:cell(tx, ty)
  if code % 4 ~= 0 or code >= 32 then return nil, 'la casa cau en una cel·la bloquejada' end
  local sp = map:object('spawn', public_spawn)
  if sp then
    local a = map:component(tx, ty)
    local b = map:component(math.floor(sp.x / 16), math.floor(sp.y / 16))
    if a == 0 or a ~= b then return nil, 'la casa no té accés a peu des del centre' end
  end
  return { scene = scene, x = tx * 16 + 8, y = ty * 16 + 8, tx = tx, ty = ty }
end

return Home
