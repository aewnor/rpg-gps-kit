-- Vehículos del jugador: catálogo y física (aceleración, frenada, giro limitado, rozamiento, pendiente y
-- superficie). Lua puro salvo el dibujo: se prueba con luajit (tests/vehicles_cases.lua).
--
-- Física por paso (dt): la dirección pedida con las flechas (8 direcciones) es el rumbo objetivo; el rumbo
-- actual gira hacia él como mucho `handling` rad/s (parado o muy lento, gira en el sitio: fácil de manejar).
-- Pedir el sentido contrario frena (1,5 × aceleración). Sin teclas, rozamiento: v ← v·0,98 por paso de 1/60 s.
-- Velocidad máxima × superficie (pavimento 1, tierra, campo) × pendiente (subir frena, bajar acelera un poco).
-- Ningún vehículo sube escaleras (body.no_stairs) ni entra en interiores.
local Collision = require('src.world.collision')

local Vehicles = {}

-- max: px/s (andar = 64) · accel: px/s² · handling: rad/s · surface: factor en [natural, pavimento, tierra]
Vehicles.CATALOG = {
  bici = { name = 'Bicicleta de muntanya', max = 128, accel = 200, handling = 7.0, surface = { 0.7, 1, 0.9 },
           sheet = 'bike' },
  patinete = { name = 'Patinet elèctric', max = 150, accel = 300, handling = 8.0, surface = { 0.45, 1, 0.75 },
               sheet = 'patinete', min_level = 2 },
  scooter = { name = 'Scooter 125cc', max = 205, accel = 330, handling = 5.5, surface = { 0.45, 1, 0.7 },
              sheet = 'scooter', min_level = 3 },
  motocross = { name = 'Moto d\'enduro', max = 220, accel = 400, handling = 6.5, surface = { 0.92, 1, 1 },
                sheet = 'motocross', min_level = 4 },
  -- cavall de la hípica: no és al garatge (no és a ORDER); s'hi puja parlant amb un cavall (src/scenes/world_scene.lua)
  cavall = { name = 'Cavall', max = 140, accel = 240, handling = 6.5, surface = { 1, 0.85, 1 }, horse = true },
  cotxe = { name = 'Turisme compacte', max = 240, accel = 260, handling = 3.6, surface = { 0.4, 1, 0.65 },
            car = true, min_level = 6 },
}
Vehicles.ORDER = { 'bici', 'patinete', 'scooter', 'motocross', 'cotxe' }

local function angle_diff(a, b)
  local d = (b - a) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return d
end
Vehicles.angle_diff = angle_diff

function Vehicles.new_state(id, facing)
  local ang = ({ right = 0, down = math.pi / 2, left = math.pi, up = -math.pi / 2 })[facing or 'down'] or 0
  return { id = id, speed = 0, angle = ang }
end

-- dirección del sprite (4) a partir del rumbo
function Vehicles.facing(angle)
  local a = angle % (2 * math.pi)
  if a < math.pi / 4 or a >= 7 * math.pi / 4 then return 'right' end
  if a < 3 * math.pi / 4 then return 'down' end
  if a < 5 * math.pi / 4 then return 'left' end
  return 'up'
end

-- factor de pendiente: desnivel (m) entre la casilla actual y la de delante (4 m por casilla)
local function slope_factor(map, x, y, ang)
  if not map.height_at then return 1 end
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  local ax, ay = math.floor((x + math.cos(ang) * 16) / 16), math.floor((y + math.sin(ang) * 16) / 16)
  local h0 = map:height_at(tx, ty)
  local h1 = map:height_at(ax, ay)
  local grade = (h1 - h0) / 4
  return math.max(0.45, math.min(1.2, 1 - grade * 1.6))
end

local function surface_factor(v, map, x, y)
  if not map.height_at then return 1 end
  local _, surf = map:height_at(math.floor(x / 16), math.floor(y / 16))
  if surf == 1 then return v.surface[2] end
  if surf == 2 then return v.surface[3] end
  return v.surface[1]
end

-- ---------------------------------------------------------------- conducció guiada (2026-10-05, v2)
-- Anant per carretera o camí (asfalt o terra), la fletxa tria cap a on vols anar i el vehicle segueix la via que
-- va en aquella direcció (fins a 63° girada: amb «dreta», la carretera que tira cap a la dreta encara que pugi o
-- baixi), centrat a la calçada. A més, si hi ha algú davant (st.obs, el posa el món: peatons, personatges i
-- cotxes): esquiva els peatons si hi ha lloc i, si no, frena; darrere d'un cotxe, s'hi posa al darrere a la seva
-- velocitat. st.cap: velocitat màxima per aquest pas. st.assist = false ho apaga.
Vehicles.ASSIST_MAX = 1.1          -- rad (63°)
Vehicles.LOOK = 64                 -- px: fins on mira si té algú al davant
local function road_at(map, x, y, level)
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  if not map:in_bounds(tx, ty) then return -1 end
  if not Collision.walk_at(map:cell(tx, ty), level) then return -1 end
  local _, surf = map:height_at(tx, ty)
  return (surf == 1 or surf == 2) and 1 or 0
end
-- via seguida en aquest rumb, en caselles (de 8 en 8 px fins a 64 px endavant), mirant tot l'ample del vehicle
-- (centre i ±7 px): una farola, un arbre o un pal a la vora talla el recompte i resta (abans només es mirava el
-- centre i el vehicle anava fregant el que hi havia als costats). Mig punt per banda si a 32 px la via continua
-- a banda i banda (així es manté al mig).
local function road_score(map, x, y, ang, level)
  local c, s = math.cos(ang), math.sin(ang)
  local n = 0
  for k = 1, 8 do
    local px, py = x + c * 8 * k, y + s * 8 * k
    local r = road_at(map, px, py, level)
    if r < 0 or road_at(map, px - s * 7, py + c * 7, level) < 0 or road_at(map, px + s * 7, py - c * 7, level) < 0 then
      return n / 2 - (k <= 3 and 3 or 1)
    end
    if r == 0 then break end
    n = n + 1
  end
  n = n / 2
  if n >= 2 then
    for _, side in ipairs({ -1, 1 }) do
      if road_at(map, x + c * 32 - s * 14 * side, y + s * 32 + c * 14 * side, level) == 1 then n = n + 0.5 end
    end
  end
  return n
end
Vehicles.road_score = road_score

-- el més proper que hi ha davant en aquest rumb: distància i obstacle (o nil)
local function ahead(obs, x, y, ang, dist, wide)
  local c, s = math.cos(ang), math.sin(ang)
  local best, bd
  for _, o in ipairs(obs or {}) do
    local dx, dy = o.x - x, o.y - y
    local along = dx * c + dy * s
    local lat = math.abs(-dx * s + dy * c)
    if along > 2 and along < dist and lat < (o.r or 6) + (wide or 6) and (not bd or along < bd) then best, bd = o, along end
  end
  return bd, best
end
Vehicles.ahead = ahead

local function follow_road(st, body, target, map, level)
  local near = road_at(map, body.x, body.y, level) == 1
  for _, d in ipairs({ { 16, 0 }, { -16, 0 }, { 0, 16 }, { 0, -16 } }) do
    if not near and road_at(map, body.x + d[1], body.y + d[2], level) == 1 then near = true end
  end
  if not near then return target end
  -- puntuació de 24 rumbs: la via de veritat és la que dona més recorregut (rs); un rumb només compta si és
  -- dins ±63° del que demanes, no fa mitja volta i va gairebé tan per via com la millor (si no, sortiries
  -- en diagonal per l'ample de la calçada: demanar «amunt» en un carrer horitzontal és voler sortir-ne)
  local cand, rs = {}, 0
  local function score(a)
    local sc = road_score(map, body.x, body.y, a, level)
    cand[#cand + 1] = { a, sc }
    if sc > rs and not (st.speed > 20 and math.abs(angle_diff(st.angle, a)) > 1.75) then rs = sc end
  end
  score(target)
  for k = 0, 23 do score(k * math.pi / 12) end
  local best, bv = target, nil
  for _, c in ipairs(cand) do
    local a, sc = c[1], c[2]
    local df = math.abs(angle_diff(target, a))
    local back = st.speed > 20 and math.abs(angle_diff(st.angle, a)) > 1.75
    if df <= Vehicles.ASSIST_MAX and not back and sc >= 3 and sc >= rs - 1 then
      local v = sc - df * 0.6 - math.abs(angle_diff(st.angle, a)) * 0.25
      if not bv or v > bv then best, bv = a, v end
    end
  end
  return best
end

-- per quines vies va cada vehicle (classes de data/roads.json)
Vehicles.LINES = { cotxe = { road = true }, scooter = { road = true, track = true },
                   motocross = { road = true, track = true, path = true } }
Vehicles.LANE = 5                  -- px a la dreta de l'eix (es circula per la dreta) a les carreteres de doble sentit
Vehicles.PURSUIT = 36              -- px: punt de l'eix al davant cap on s'apunta

-- punt a `dist` px seguint la línia li des del punt (x, y) del tram i, cap a dir (+1 endavant, -1 enrere); al final
-- de la via, continua per la que surti d'aquell extrem més cap a on demanes. Torna x, y, rumb i classe.
local function along(st, li, i, x, y, dir, dist, target, depth)
  local R = require('src.systems.roads')
  local l = R.line(li)
  local p = l.p
  local k = dir > 0 and i + 2 or i      -- següent vèrtex en aquest sentit
  local ang = 0
  while dist > 0 do
    if k < 1 or k > #p - 1 then break end
    local nx, ny = p[k], p[k + 1]
    local d = math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2)
    if d > 0 then ang = math.atan2(ny - y, nx - x) end
    if d >= dist then
      return x + (nx - x) * dist / d, y + (ny - y) * dist / d, ang, l.c, l.o, li
    end
    x, y, dist = nx, ny, dist - d
    k = k + 2 * dir
  end
  if dist > 0 and (depth or 0) < 2 then
    -- cruïlla al final de la via: la sortida més alineada amb la fletxa (mai la mateixa via enrere)
    local best, bd, bdir, bs
    for _, s in ipairs(R.near(x, y, 6, {})) do
      if s.li ~= li then
        for _, e in ipairs({ { s.x0, s.y0, 1, s.x1, s.y1 }, { s.x1, s.y1, -1, s.x0, s.y0 } }) do
          if (e[1] - x) ^ 2 + (e[2] - y) ^ 2 < 64 and not (s.o and e[3] < 0) then
            local a = math.atan2(e[5] - e[2], e[4] - e[1])
            local df = math.abs(angle_diff(target, a)) + math.abs(angle_diff(ang, a)) * 0.3
            if not bd or df < bd then best, bd, bdir, bs = s, df, e[3], e end
          end
        end
      end
    end
    if best then return along(st, best.li, best.i, bs[1], bs[2], bdir, dist, target, (depth or 0) + 1) end
  end
  return x, y, ang, l.c, l.o, li, dist   -- (dist > 0: la via s'acaba abans, sense continuació)
end

-- segueix l'eix de la via (st.lines: trams a prop, de src/systems/roads.lua) que va cap on demanes; nil si no n'hi ha
local function follow_lines(st, body, target)
  if not st.lines or #st.lines == 0 then return nil end
  local ok = Vehicles.LINES[st.id]
  local best, bv, bt, bdir
  for _, s in ipairs(st.lines) do
    if not ok or ok[s.c] then
      local dx, dy = s.x1 - s.x0, s.y1 - s.y0
      local l2 = dx * dx + dy * dy
      if l2 > 0 then
        local t = math.max(0, math.min(1, ((body.x - s.x0) * dx + (body.y - s.y0) * dy) / l2))
        local d = math.sqrt((s.x0 + dx * t - body.x) ^ 2 + (s.y0 + dy * t - body.y) ^ 2)
        if d < 30 then
          for _, dir in ipairs({ 1, -1 }) do
            if not (s.o and dir < 0 and st.id == 'cotxe') then
              local a = math.atan2(dy * dir, dx * dir)
              local df = math.abs(angle_diff(target, a))
              local back = st.speed > 20 and math.abs(angle_diff(st.angle, a)) > 1.75
              -- la via que ja segueixes, fins a 100° (un revolt tancat mentre mantens la fletxa)
              local max = (st.follow and st.follow[s.li]) and 1.75 or Vehicles.ASSIST_MAX
              if df <= max and not back then
                local v = df + d / 30 * 0.6 + math.abs(angle_diff(st.angle, a)) * 0.3
                if not bv or v < bv then best, bv, bt, bdir = s, v, t, dir end
              end
            end
          end
        end
      end
    end
  end
  if not best then st.follow = nil; return nil end
  local qx, qy = best.x0 + (best.x1 - best.x0) * bt, best.y0 + (best.y1 - best.y0) * bt
  local px, py, ang, cls, oneway, li2, rest = along(st, best.li, best.i, qx, qy, bdir, Vehicles.PURSUIT, target)
  -- final del camí (cul-de-sac, entrada d'un pàrquing o d'un camp): deixa de guiar i el vehicle va on demanes
  -- (abans apuntava al darrer punt de la via: girava en rodó o no et deixava sortir)
  if rest and rest > Vehicles.PURSUIT * 0.5 then st.follow = nil; return nil end
  -- revolt al davant: frena abans (a 70 px, quant gira la via respecte d'on va ara)
  local a0 = math.atan2((best.y1 - best.y0) * bdir, (best.x1 - best.x0) * bdir)
  local _, _, a2, _, _, li3 = along(st, best.li, best.i, qx, qy, bdir, 70, target)
  local turn = math.abs(angle_diff(a0, a2))
  if turn > 0.35 then st.cap = math.max(45, 200 * (1 - turn / 2.2)) end
  st.follow = { [best.li] = true, [li2 or best.li] = true, [li3 or best.li] = true }
  if cls == 'road' and not oneway then   -- carril de la dreta
    px, py = px - math.sin(ang) * Vehicles.LANE, py + math.cos(ang) * Vehicles.LANE
  end
  st.lane = { px, py }
  return math.atan2(py - body.y, px - body.x)
end
Vehicles.follow_lines = follow_lines

function Vehicles.assist(st, body, target, map)
  st.assisting, st.cap, st.yield = false, nil, nil
  if not (map and map.height_at and map.in_bounds and map.cell) then return target end
  local level = body.level or 0
  st.lane = nil
  -- primer l'eix de la via de veritat (data/roads.json); si no n'hi ha cap a prop, la superfície (asfalt/terra)
  local heading = follow_lines(st, body, target)
  if heading and road_score(map, body.x, body.y, heading, level) < -1 then
    heading = nil   -- l'eix passa per sobre d'un obstacle (un pal, un arbre): millor la superfície
  end
  heading = heading or follow_road(st, body, target, map, level)
  -- algú al davant
  local d, o = ahead(st.obs, body.x, body.y, heading, Vehicles.LOOK, 6)
  if o then
    local same = o.kind == 'car' and o.ang and math.cos(angle_diff(o.ang, heading)) > 0.5
    if same then
      -- darrere d'un cotxe que va cap al mateix lloc: a la seva velocitat, amb distància
      st.cap = math.min(st.cap or math.huge, math.max(0, (o.v or 0) * math.min(1.05, math.max(0, (d - 26) / 26))))
      st.yield = 'car'
    elseif d < 44 then
      -- peató, personatge o cotxe parat/en contra: esquivar si hi ha lloc a la via; si no, frenar
      local dodged
      for _, off in ipairs({ 0.35, -0.35, 0.6, -0.6 }) do
        local a = heading + off
        if not ahead(st.obs, body.x, body.y, a, 44, 7) and road_at(map, body.x + math.cos(a) * 16, body.y + math.sin(a) * 16, level) >= 0
            and road_at(map, body.x + math.cos(a) * 28, body.y + math.sin(a) * 28, level) >= 0 then
          heading, dodged = a, true
          break
        end
      end
      if not dodged then st.cap = math.min(st.cap or math.huge, math.max(0, (d - 16) * 3)); st.yield = o.kind or 'ped' end
    end
  end
  st.assisting = heading ~= target
  return heading
end

-- st: estado del vehículo (new_state); body: cuerpo del jugador; h, vv: −1/0/1 de las flechas
-- Devuelve: moving (bool), bumped (bool)
function Vehicles.update(st, body, h, vv, dt, map, blockers, boost)
  local v = Vehicles.CATALOG[st.id]
  local accel = v.accel * (boost or 1)
  local input = h ~= 0 or vv ~= 0
  st.skid = false     -- derrape (frenazo o curva cerrada rápida): el juego levanta polvo
  -- velocidad máxima aquí: superficie y pendiente (se recalcula cada paso)
  local vmax = v.max * (boost or 1) * surface_factor(v, map, body.x, body.y) * slope_factor(map, body.x, body.y, st.angle)
  if input then
    local target = math.atan2(vv, h)
    st.assisting = false
    if st.assist ~= false then target = Vehicles.assist(st, body, target, map) else st.cap = nil end
    if st.cap then vmax = math.min(vmax, st.cap) end
    local d = angle_diff(st.angle, target)
    if math.abs(d) > 2.6 and st.speed > 20 then          -- sentido contrario: frenar
      st.skid = st.speed > 60
      st.speed = math.max(0, st.speed - accel * 1.5 * dt)
    else
      if st.speed < 18 then st.angle = target               -- casi parado: gira en el sitio
      else
        local maxd = v.handling * dt
        st.angle = st.angle + math.max(-maxd, math.min(maxd, d))
      end
      -- acelerar hasta la máxima (en curva cerrada, menos: derrape)
      local k = 1 - math.min(0.6, math.abs(d) / math.pi)
      st.skid = st.speed > 80 and math.abs(d) > 0.6
      if st.speed < vmax then st.speed = math.min(vmax, st.speed + accel * k * dt) end
    end
  else
    st.speed = st.speed * (0.98 ^ (dt * 60))              -- rozamiento natural
    if st.speed < 4 then st.speed = 0 end
  end
  -- por encima de la máxima (al salir del asfalto, cuesta arriba): se pierde velocidad poco a poco
  if st.speed > vmax then st.speed = st.speed - (st.speed - vmax) * math.min(1, 4 * dt) end
  if input and st.cap and st.speed > st.cap then st.speed = math.max(st.cap, st.speed - accel * 2.5 * dt) end
  if st.speed <= 0 then return false, false end
  local dx, dy = math.cos(st.angle) * st.speed * dt, math.sin(st.angle) * st.speed * dt
  local mx, my = Collision.move(body, dx, dy, map, blockers)
  local bumped = (math.abs(dx) > 0.01 and not mx) or (math.abs(dy) > 0.01 and not my)
  if bumped then
    if not mx and not my then st.speed = st.speed * 0.3 else st.speed = st.speed * 0.85 end
  end
  return true, bumped and st.speed > 60
end

return Vehicles
