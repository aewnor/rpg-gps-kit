-- Temporadas (data/themes.json) y aspectos del protagonista (data/skins.json).
-- La temporada se activa sola por fecha ("auto") o se fija desde el menú; cambia adornos junto a las
-- puertas y farolas (los dibuja el renderer), luces de noche y el tinte nocturno.
local Data = require('src.data')

local Themes = {}

function Themes.load()
  local th = Data.read_json('data/themes.json').themes
  local sk = Data.read_json('data/skins.json').skins
  return th, sk
end

local function md(s)
  local m, d = s:match('(%d+)%-(%d+)')
  return tonumber(m) * 100 + tonumber(d)
end

-- tema activo: setting = 'auto' | 'none' | id; today = número MMDD (por defecto, la fecha del sistema)
function Themes.active(list, setting, today)
  setting = setting or 'auto'
  if setting == 'none' then return nil end
  for _, t in ipairs(list) do
    if setting == t.id then return t end
  end
  if setting ~= 'auto' then return nil end
  today = today or tonumber(os.date('%m%d'))
  for _, t in ipairs(list) do
    local a, b = md(t.from), md(t.to)
    if (a <= b and today >= a and today <= b) or (a > b and (today >= a or today <= b)) then return t end
  end
  return nil
end

-- tabla para el renderer: gid → adornos y luces (tiles = data/tiles.json .tiles)
function Themes.render_spec(theme, tiles)
  if not theme then return nil end
  local function gid(name) return tiles[name] and tiles[name].id + 1 end
  local spec = { decor = {}, lamp_decor = {}, glow = {} }
  for _, d in ipairs(theme.decor or {}) do
    if gid(d[1]) then spec.decor[#spec.decor + 1] = { gid(d[1]), d[2] } end
  end
  for _, d in ipairs(theme.lamp_decor or {}) do
    if gid(d[1]) then spec.lamp_decor[#spec.lamp_decor + 1] = { gid(d[1]), d[2] } end
  end
  for name, kind in pairs(theme.glow or {}) do
    if gid(name) then spec.glow[gid(name)] = kind end
  end
  return spec
end

-- azar determinista por celda (0..1), igual en todas las plataformas (sin operaciones de bits)
function Themes.cell_rand(x, y, salt)
  local v = (x * 7919 + y * 104729 + (salt or 0) * 1299709) % 1000003
  v = (v * 48271) % 2147483647
  return (v % 10000) / 10000
end

return Themes
