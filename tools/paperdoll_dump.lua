-- Vuelca en hexadecimal las hojas del paperdoll de Lua (src/paperdoll/) para comparar con Python:
--   luajit tools/paperdoll_dump.lua specs.json  → una línea por hoja: <id> <tipo> <w> <h> <hex RGBA>
package.path = './?.lua;./?/init.lua;' .. package.path
local json = require('src.lib.json')
local Chars = require('src.paperdoll.chars')
local Sheets = require('src.paperdoll.sheets')
local f = assert(io.open(arg[1])); local specs = json.decode(f:read('*a')); f:close()
local function hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
for _, it in ipairs(specs) do
  local out = { walk = Chars.sheet(it.spec) }
  if it.full then
    out.action = Sheets.action(it.spec); out.bike = Sheets.bike(it.spec)
    for _, v in ipairs({ 'patinete', 'scooter', 'motocross' }) do out[v] = Sheets.vehicle(it.spec, v) end
  end
  for kind, c in pairs(out) do print(it.id, kind, c.w, c.h, hex(c:bytes())) end
end
