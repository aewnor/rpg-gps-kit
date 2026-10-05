-- Pruebas de colisión (luajit tests/collision_cases.lua desde la raíz del proyecto).
package.path = './?.lua;' .. package.path
local C = require('src.world.collision')

local fails = 0
local function check(cond, msg)
  print((cond and 'OK   ' or 'FAIL ') .. msg)
  if not cond then fails = fails + 1 end
end

-- mapa de prueba a partir de filas de caracteres
-- '.' suelo  '#' sólido  '~' agua  'H' autopista  'B' tablero (nivel 1 sobre suelo transitable)
-- 'b' tablero sobre autopista  'R' rampa de puente  'T' túnel bajo vía (sólido a nivel 0)  'r' rampa de túnel
local CODES = { ['.'] = 0, ['#'] = 1, ['~'] = 2, H = 3, B = 4, b = 7, R = 20, T = 9, r = 24 }
local function map_of(rows)
  local m = { rows = rows, width = #rows[1], height = #rows }
  function m:cell(tx, ty)
    if tx < 0 or ty < 0 or tx >= self.width or ty >= self.height then return 1 end
    return CODES[self.rows[ty + 1]:sub(tx + 1, tx + 1)]
  end
  return m
end
local function body(tx, ty, level)
  return { x = tx * 16 + 8, y = ty * 16 + 8, w = 10, h = 8, level = level or 0 }
end
local function walk(b, m, dx, dy, steps, blockers)
  for _ = 1, steps do C.move(b, dx, dy, m, blockers) end
end

-- 1. muro: no se atraviesa
local m = map_of({ '.....', '..#..', '.....' })
local b = body(0, 1)
walk(b, m, 0.8, 0, 200)
check(b.x + b.w / 2 <= 32 + 0.001, 'no atraviesa un muro (x=' .. b.x .. ')')

-- 2. esquina diagonal: dos sólidos en diagonal no dejan pasar
m = map_of({ '....', '.#..', '..#.', '....' })
b = body(1, 2)
walk(b, m, 0.8, -0.8, 200)
check(not (math.floor(b.x / 16) == 2 and math.floor(b.y / 16) == 1), 'no se cuela por una esquina diagonal')

-- 3. misma distancia a 30/60/120 FPS (paso fijo con subpasos)
local function dist_at(fps)
  local mm = map_of({ string.rep('.', 40) })
  local bb = body(0, 0)
  local dt = 1 / fps
  for _ = 1, fps * 2 do C.move(bb, 48 * dt, 0, mm) end
  return bb.x
end
local d30, d60, d120 = dist_at(30), dist_at(60), dist_at(120)
check(math.abs(d30 - d60) < 0.01 and math.abs(d60 - d120) < 0.01,
  string.format('misma velocidad a 30/60/120 FPS (%.2f %.2f %.2f)', d30, d60, d120))

-- 4. golpe rápido (knockback 160 px/s en un paso) no atraviesa un muro de 1 tile
m = map_of({ '.....#.....' })
b = body(3, 0)
C.move(b, 60, 0, m)
check(b.x + b.w / 2 <= 80 + 0.001, 'desplazamiento grande no atraviesa (x=' .. b.x .. ')')

-- 5. puente sobre autopista: se sube por la rampa y no se baja en medio
m = map_of({
  '.R.',
  '.b.',
  '.b.',
  '.R.',
})
-- columna 1: rampa (nivel 0+1), tablero sobre autopista, rampa
m = map_of({ '#.#', '#R#', '#b#', '#b#', '#R#', '#.#' })
b = body(1, 0)
walk(b, m, 0, 0.8, 140)
check(math.floor(b.y / 16) == 5 and b.level == 0, 'cruza el puente de punta a punta y baja a nivel 0 (fila ' ..
  math.floor(b.y / 16) .. ', nivel ' .. b.level .. ')')
b = body(1, 2, 0)
local ok = C.fits(b, b.x, b.y, m)
check(not ok, 'a nivel 0 la autopista bajo el puente no es transitable')

-- 6. paso inferior bajo vía: entrar por la rampa, pasar a nivel -1 y salir
m = map_of({ '#.#', '#r#', '#T#', '#T#', '#r#', '#.#' })
b = body(1, 0)
local seen_m1 = false
for _ = 1, 140 do C.move(b, 0, 0.8, m); if b.level == -1 then seen_m1 = true end end
check(seen_m1 and math.floor(b.y / 16) == 5 and b.level == 0, 'cruza el túnel (nivel -1) y sale a nivel 0')

-- 7. bajo un puente sobre suelo, a nivel 0 se pasa por debajo sin subir
m = map_of({ '.....', 'BBBBB', '.....' })
b = body(2, 0)
walk(b, m, 0, 0.8, 60)
check(math.floor(b.y / 16) == 2 and b.level == 0, 'pasar por debajo de un puente no cambia de nivel')
-- y estando arriba no se puede saltar del tablero al suelo (sin rampa)
b = body(2, 1, 1)
walk(b, m, 0, 0.8, 40)
check(math.floor(b.y / 16) == 1 and b.level == 1, 'desde el tablero no se baja fuera de las rampas')

-- 8. bloqueadores dinámicos: impiden entrar pero dejan salir a quien ya está dentro
m = map_of({ '..........' })
b = body(0, 0)
local blk = { x = 48, y = 0, w = 16, h = 16 }
walk(b, m, 0.8, 0, 100, { blk })
check(b.x + b.w / 2 <= 48 + 0.001, 'un bloqueador detiene la entrada')
b = body(3, 0)
walk(b, m, 0.8, 0, 60, { blk })
check(b.x > 64, 'quien está dentro de un bloqueador puede salir')

-- 9. regla de niveles igual a la de tools/walkgraph.py
check(C.step_level(20, 4, 0) == 1, 'salir de rampa de puente a tablero → nivel 1')
check(C.step_level(4, 20, 1) == 1, 'volver del tablero a la rampa conserva nivel 1')
check(C.step_level(20, 0, 1) == 0, 'salir de la rampa al suelo → nivel 0')
check(C.step_level(4, 0, 1) == nil, 'del tablero al suelo sin rampa → imposible')

print(fails == 0 and 'TODAS LAS PRUEBAS DE COLISIÓN OK' or (fails .. ' FALLOS'))
os.exit(fails == 0 and 0 or 1)
