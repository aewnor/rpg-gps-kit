-- Text en MAJÚSCULES (opció per a qui comença a llegir, 2026-10-05). Quan settings.upper és cert, tot el que el
-- joc escriu amb la font (love.graphics.print/printf i les mides de Font:getWidth/getWrap, perquè els salts de
-- línia es calculin amb el text en majúscules) passa a majúscules, també les lletres catalanes (à → À, ç → Ç…).
-- No toca les dades ni el que diu la veu. Lua pur llevat d'Upper.install.
local Upper = { on = false }

local MAP = { ['à'] = 'À', ['á'] = 'Á', ['è'] = 'È', ['é'] = 'É', ['í'] = 'Í', ['ï'] = 'Ï', ['ò'] = 'Ò', ['ó'] = 'Ó',
              ['ú'] = 'Ú', ['ü'] = 'Ü', ['ç'] = 'Ç', ['ñ'] = 'Ñ' }

function Upper.convert(s)
  if type(s) ~= 'string' then return s end
  s = s:upper()   -- ASCII
  return (s:gsub('\195[\160-\191]', function(c) return MAP[c] or c end))
end

-- text de print/printf: cadena o taula de colors { {r,g,b}, 'text', … }
local function conv(t)
  if not Upper.on then return t end
  if type(t) == 'string' then return Upper.convert(t) end
  if type(t) == 'table' then
    local o = {}
    for i, v in ipairs(t) do o[i] = type(v) == 'string' and Upper.convert(v) or v end
    return o
  end
  return t
end
Upper.conv = conv

local installed = false
function Upper.install(font)
  if installed or not (love and love.graphics) then return end
  installed = true
  local g = love.graphics
  local print0, printf0 = g.print, g.printf
  g.print = function(t, ...) return print0(conv(t), ...) end
  g.printf = function(t, ...) return printf0(conv(t), ...) end
  local mt = font and getmetatable(font)
  local idx = mt and mt.__index
  if type(idx) == 'table' then
    local gw, gr = idx.getWidth, idx.getWrap
    idx.getWidth = function(self, t) return gw(self, conv(t)) end
    idx.getWrap = function(self, t, w) return gr(self, conv(t), w) end
  end
end

return Upper
