-- Pruebas del guardado (luajit tests/save_cases.lua).
package.path = './?.lua;' .. package.path
local Save = require('src.save')
local fails = 0
local function check(c, m) print((c and 'OK   ' or 'FAIL ') .. m); if not c then fails = fails + 1 end end

local mem = {}
local fail_rename = false
Save.fs = {
  read = function(n) return mem[n] end,
  write = function(n, d) mem[n] = d; return true end,
  exists = function(n) return mem[n] ~= nil end,
  remove = function(n) mem[n] = nil; return true end,
  rename = function(a, b) if fail_rename then return false end mem[b] = mem[a]; mem[a] = nil; return true end,
}
local function state(x)
  return { scene = 'overworld', x = x, y = 10, level = 0, facing = 'down', flags = { a = true },
           inventory = { postcard = 1 }, equipment = {}, visited = {}, scene_state = {}, hp = 6, max_hp = 6 }
end

check(Save.read() == nil, 'sin guardado: nil sin error')
check(Save.write(state(1)), 'primer guardado')
local s = Save.read()
check(s and s.x == 1 and s.schema == Save.SCHEMA and s.flags.a == true, 'se relee con esquema y datos')
check(mem['save.tmp'] == nil, 'no queda temporal tras guardar')
Save.write(state(2))
check(Save.read().x == 2 and mem['save.bak'] ~= nil, 'segundo guardado crea respaldo')
mem['save.json'] = '{"schema":1,'
local r, src, warn = Save.read()
check(r and r.x == 1 and src == 'backup' and warn, 'JSON corrupto → respaldo con aviso')
mem['save.json'] = '{"schema":99,"scene":"overworld","x":1,"y":1,"flags":{}}'
r, src = Save.read()
check(src == 'backup', 'esquema desconocido → respaldo')
mem['save.bak'] = 'basura'
r, src, warn = Save.read()
check(r == nil and warn ~= nil, 'ambos dañados → nil y aviso (nueva partida)')
mem = {}
Save.write(state(5))
fail_rename = true
local ok = Save.write(state(6))
fail_rename = false
check(not ok and Save.read().x == 5, 'si el reemplazo falla, el guardado anterior sigue intacto')
local bad = state(7); bad.x = nil
local ok2 = pcall(Save.write, bad)
check(Save.read().x == 5, 'un estado inválido no sustituye al guardado bueno')
print(fails == 0 and 'TODAS LAS PRUEBAS DE GUARDADO OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
