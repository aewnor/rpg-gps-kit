-- Interior procedural en JSON (formato del editor): luajit tools/procgen_cli.lua <house|shop|block> <semilla>
-- Lo usa el editor (POST /api/procgen); el juego llama a src/world/procgen.lua directamente.
package.path = arg[0]:gsub('tools/procgen_cli%.lua$', '') .. '?.lua;' .. package.path
local P = require('src.world.procgen')
local json = require('src.lib.json')
local kind, seed = arg[1] or 'house', tonumber(arg[2]) or os.time()
if kind ~= 'house' and kind ~= 'shop' and kind ~= 'block' then io.stderr:write('tipo desconocido\n'); os.exit(2) end
local s = P.generate({ kind = kind, seed = seed })
s.height = {}
for i = 1, s.w * s.h do s.height[i] = 0 end
s.seed = seed
io.write(json.encode(s))
