-- Tráfico por carriles dirigidos: driving → yielding → stopped. IA a 10 Hz, movimiento a 60 Hz, reserva de
-- cruces y separación con el vehículo de delante. Nunca aparecen sobre el jugador.
--
-- Fase 4 («Smart Traffic»): además de coches circulan motos (scooter, enduro de la Policia Local) y
-- patinetes eléctricos, cada uno con su velocidad, aceleración y distancia de seguridad. Detección de
-- obstáculos genérica: el jugador, los peatones (src/systems/pedestrians.lua) y Olaf. Los pasos de cebra
-- saben si alguien espera o cruza (cw.waiting / cw.crossing) y los vehículos que llegan se paran si aún
-- pueden frenar. Un vehículo frenado más de 1,2 s por el jugador toca el claxon (self.events).
local Route = require('src.systems.route')

local Traffic = {}
Traffic.__index = Traffic

-- Semàfors (fase 5): un de cada tres passos de cebra dels carrers amb trànsit en té (tria fixa per posició).
-- L'OSM d'aquí no en porta cap: és una ubicació inventada i es diu així al joc. Cicle de LIGHT_CYCLE s: verd per
-- als cotxes, ambre, vermell (i verd per als vianants una mica després, perquè la cruïlla quedi buida).
Traffic.LIGHT_CYCLE = 22
local L_GREEN, L_AMBER = 10, 12.5          -- cotxes: verd [0, 10), ambre [10, 12.5), vermell la resta
local P_FROM, P_TO = 13.5, 21              -- vianants: verd [13.5, 21)

-- estat del semàfor d'un pas: 'green' | 'amber' | 'red' per als cotxes i true si els vianants poden passar
function Traffic.light_state(cw, clock)
  local t = ((clock or 0) + cw.light) % Traffic.LIGHT_CYCLE
  local car = t < L_GREEN and 'green' or (t < L_AMBER and 'amber' or 'red')
  return car, t >= P_FROM and t < P_TO, t
end

local LANE = 5          -- desplazamiento lateral del carril (px)
local AI_DT = 0.1

-- tipos de vehículo: velocidad (× cfg.speed), aceleración/frenada (px/s²), hueco (× cfg.gap) y caja (px)
Traffic.KINDS = {
  car = { speed = 1.0, accel = 60, brake = 120, gap = 1.0, w = 18, h = 12, hit = { 13, 10 } },
  moto = { speed = 1.15, accel = 90, brake = 150, gap = 0.7, w = 12, h = 8, hit = { 9, 8 } },
  police = { speed = 1.2, accel = 95, brake = 150, gap = 0.7, w = 12, h = 8, hit = { 9, 8 } },
  patinete = { speed = 0.55, accel = 50, brake = 110, gap = 0.6, w = 8, h = 6, hit = { 7, 7 } },
  -- vehicles grans (2026-10-05): es dibuixen com un cotxe amb el color fix de la fulla svc (world_scene draw_car);
  -- siren = llums d'emergència que parpellegen
  police_car = { speed = 1.15, accel = 70, brake = 130, gap = 1.0, w = 18, h = 12, hit = { 13, 10 }, car = true, color = 15, siren = 'police' },
  ambulance = { speed = 1.15, accel = 65, brake = 125, gap = 1.1, w = 18, h = 12, hit = { 13, 10 }, car = true, color = 16, siren = 'amb' },
  firetruck = { speed = 1.0, accel = 50, brake = 110, gap = 1.3, w = 18, h = 12, hit = { 14, 10 }, car = true, color = 17, siren = 'fire' },
  truck = { speed = 0.8, accel = 40, brake = 100, gap = 1.3, w = 18, h = 12, hit = { 14, 10 }, car = true, color = 18 },
  excavator = { speed = 0.45, accel = 30, brake = 90, gap = 1.3, w = 18, h = 12, hit = { 14, 10 }, car = true, color = 19 },
}
Traffic.KINDS.car.car = true
-- reparto: dos de cada tres son coches; el resto, motos, algún patinete y los vehículos de servicio y de obra
local MIX = { { 'car', 0.64 }, { 'moto', 0.76 }, { 'police', 0.80 }, { 'patinete', 0.87 }, { 'police_car', 0.90 },
              { 'ambulance', 0.92 }, { 'firetruck', 0.935 }, { 'truck', 0.98 }, { 'excavator', 1.0 } }

function Traffic.new(map, cfg, rng)
  local self = setmetatable({ cars = {}, routes = {}, zones = {}, cfg = cfg, rng = rng, ai_t = 0, events = {},
                              obstacles = {}, map = map }, Traffic)
  for _, r in ipairs(map.routes) do
    if r.type == 'route_car' then self.routes[#self.routes + 1] = Route.new(r) end
  end
  self:find_junctions(map)
  self:link_routes()
  return self
end

-- Xarxa (fase 6): els vehicles no desapareixen al final del carrer. Per a cada extrem de ruta, les rutes
-- que hi passen a menys de LINK px (continuar pel carrer següent); per a cada cruïlla, les rutes que la
-- travessen (girar). Sense enllaç: mitja volta.
local LINK = 28
function Traffic:link_routes()
  -- extrems a la vora del mapa (o fora): entrades i sortides del bucle (fora de la vista del jugador)
  local W, H = (self.map and self.map.width or 1600) * 16, (self.map and self.map.height or 1600) * 16
  self.entrances = {}
  for _, r in ipairs(self.routes) do
    r.edge = {}
    if r.name ~= 'road_ap7' then
      for e = 0, 1 do
        local ex, ey = r:at(e == 0 and 0 or r.length)
        if ex < 48 or ey < 48 or ex > W - 48 or ey > H - 48 then
          r.edge[e] = true
          self.entrances[#self.entrances + 1] = { route = r, s = e == 0 and 0 or r.length, e = e }
        end
      end
    end
  end
  for _, r in ipairs(self.routes) do
    r.links = { [0] = {}, [1] = {} }
    if r.name ~= 'road_ap7' then
      for e = 0, 1 do
        local ex, ey = r:at(e == 0 and 0 or r.length)
        for _, o in ipairs(self.routes) do
          if o ~= r and o.name ~= 'road_ap7' then
            local s, d = o:project(ex, ey)
            if d < LINK then r.links[e][#r.links[e] + 1] = { route = o, s = s } end
          end
        end
      end
    end
  end
  for _, z in ipairs(self.zones) do
    z.through = {}
    for _, o in ipairs(self.routes) do
      if o.name ~= 'road_ap7' then
        local s, d = o:project(z.x, z.y)
        if d < z.r then z.through[#z.through + 1] = { route = o, s = s } end
      end
    end
  end
  self.nodes = self:find_crossings()
end

-- cruïlles reals entre rutes (on dues rutes es toquen): graella de segments de 64 px; es calcula un cop
-- per mapa (map._traffic_nodes) perquè tornar a l'exterior no costi res
function Traffic:find_crossings()
  local map = self.map
  if map and map._traffic_nodes then
    -- les rutes són objectes nous a cada escena: tornar a lligar per nom
    local by = {}
    for _, r in ipairs(self.routes) do by[r.name] = r end
    local out = {}
    for _, n in ipairs(map._traffic_nodes) do
      local t = {}
      for _, th in ipairs(n.through) do if by[th.name] then t[#t + 1] = { route = by[th.name], s = th.s } end end
      out[#out + 1] = { x = n.x, y = n.y, r = 18, through = t }
    end
    return out
  end
  local CELL = 64
  local grid = {}
  for ri, r in ipairs(self.routes) do
    if r.name ~= 'road_ap7' then
      for i = 1, #r.pts - 1 do
        local a, b = r.pts[i], r.pts[i + 1]
        for cy = math.floor(math.min(a[2], b[2]) / CELL), math.floor(math.max(a[2], b[2]) / CELL) do
          for cx = math.floor(math.min(a[1], b[1]) / CELL), math.floor(math.max(a[1], b[1]) / CELL) do
            local k = cy * 100000 + cx
            grid[k] = grid[k] or {}
            local cell = grid[k]
            cell[#cell + 1] = { ri, i }
          end
        end
      end
    end
  end
  local nodes = {}
  local function near_node(x, y)
    for _, n in ipairs(nodes) do if (n.x - x) ^ 2 + (n.y - y) ^ 2 < 24 ^ 2 then return n end end
  end
  -- intersecció de segments (o extrems a menys de 10 px: carrers que s'acaben en un altre)
  local function cross(ax, ay, bx, by, cx, cy, dx, dy)
    local rx, ry, sx, sy = bx - ax, by - ay, dx - cx, dy - cy
    local den = rx * sy - ry * sx
    if math.abs(den) < 1e-9 then return nil end
    local t = ((cx - ax) * sy - (cy - ay) * sx) / den
    local u = ((cx - ax) * ry - (cy - ay) * rx) / den
    if t >= -0.02 and t <= 1.02 and u >= -0.02 and u <= 1.02 then return t, u end
  end
  local seen = {}
  for k, cell in pairs(grid) do
    for i1 = 1, #cell do
      for i2 = i1 + 1, #cell do
        local s1, s2 = cell[i1], cell[i2]
        if s1[1] ~= s2[1] then
          local key = s1[1] .. ':' .. s1[2] .. '/' .. s2[1] .. ':' .. s2[2]
          if not seen[key] then
            seen[key] = true
            local r1, r2 = self.routes[s1[1]], self.routes[s2[1]]
            local a, b = r1.pts[s1[2]], r1.pts[s1[2] + 1]
            local c, d = r2.pts[s2[2]], r2.pts[s2[2] + 1]
            local t, u = cross(a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2])
            if t then
              local x, y = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
              local n = near_node(x, y)
              if not n then
                n = { x = x, y = y, r = 18, through = {} }
                nodes[#nodes + 1] = n
              end
              local function add(route, sv)
                for _, th in ipairs(n.through) do if th.route == route then return end end
                n.through[#n.through + 1] = { route = route, s = sv }
              end
              local l1 = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
              local l2 = math.sqrt((d[1] - c[1]) ^ 2 + (d[2] - c[2]) ^ 2)
              add(r1, r1.cum[s1[2]] + l1 * math.max(0, math.min(1, t)))
              add(r2, r2.cum[s2[2]] + l2 * math.max(0, math.min(1, u)))
            end
          end
        end
      end
    end
  end
  if map then
    map._traffic_nodes = {}
    for _, n in ipairs(nodes) do
      local t = {}
      for _, th in ipairs(n.through) do t[#t + 1] = { name = th.route.name, s = th.s } end
      map._traffic_nodes[#map._traffic_nodes + 1] = { x = n.x, y = n.y, through = t }
    end
  end
  return nodes
end

-- passar el vehicle a una altra ruta (a la distància s) en el sentit que s'allunya del punt d'entrada
function Traffic:move_to(c, route, s, from_s)
  local old = c.route
  if old.cars then
    for i, o in ipairs(old.cars) do if o == c then table.remove(old.cars, i); break end end
  end
  route.cars = route.cars or {}
  route.cars[#route.cars + 1] = c
  c.route, c.s = route, math.max(0, math.min(route.length, s))
  if c.s < 8 then c.dir = 1
  elseif c.s > route.length - 8 then c.dir = -1
  else c.dir = (self.rng:random() < 0.5) and 1 or -1 end
  for _, z in ipairs(self.zones) do if z.owner == c then z.owner = nil end end
end

-- en entrar a una cruïlla, a vegades gira cap a una altra de les rutes que la travessen
function Traffic:maybe_turn(c, x, y)
  for _, z in ipairs(self.nodes) do
    if z.through and #z.through > 1 and (x - z.x) ^ 2 + (y - z.y) ^ 2 < (z.r * 0.6) ^ 2 then
      if c.turned ~= z then
        c.turned = z
        if self.rng:random() < 0.35 then
          local opts = {}
          for _, t in ipairs(z.through) do if t.route ~= c.route then opts[#opts + 1] = t end end
          if #opts > 0 then
            local t = opts[math.floor(self.rng:random() * #opts) + 1]
            self:move_to(c, t.route, t.s)
            c.turns = (c.turns or 0) + 1
          end
        end
      end
      return
    end
  end
  c.turned = nil
end

-- cruces: precalculados por tools/import_osm.py (objetos 'junction'). Pasos de cebra: dirección de la calle
-- (de la ruta más cercana) para saber por dónde cruzan los peatones.
function Traffic:find_junctions(map)
  self.crosswalks = {}
  for _, o in ipairs(map.objects) do
    if o.type == 'junction' then
      self.zones[#self.zones + 1] = { x = o.x, y = o.y, r = o.props.r or 22, owner = nil }
    elseif o.type == 'crosswalk' then  -- pasos de peatones (tools/decorate_map.py)
      local cw = { x = o.x, y = o.y, r = o.props.r or 16, waiting = 0, crossing = 0 }
      local best = 40
      for _, r in ipairs(self.routes) do
        local s, d = r:project(o.x, o.y)
        if d < best then
          best = d
          local _, _, ang, level = r:at(s)
          cw.ang, cw.level, cw.route = ang, level, r.name
        end
      end
      local h = math.floor(o.x / 16) * 7 + math.floor(o.y / 16) * 13
      if cw.route and cw.route ~= 'road_ap7' and (cw.level or 0) == 0 and h % 3 == 0 then
        cw.light = h % Traffic.LIGHT_CYCLE   -- desfasament
      end
      self.crosswalks[#self.crosswalks + 1] = cw
    end
  end
end

function Traffic.kind_of(c) return Traffic.KINDS[c.kind or 'car'] end

function Traffic:spawn(player_x, player_y)
  local colors = 14   -- 4 clàssics + 8 models car2 + 2 furgonetes van2 (world_scene draw_car)
  for _, r in ipairs(self.routes) do
    -- densidad según la longitud de la ruta (un vehículo cada ~600 px y sentido)
    local n = (self.cfg.count or {})[r.name] or math.max(2, math.floor(r.length / 600))
    for k = 1, n do
      local dir = (k % 2 == 0) and -1 or 1
      local s = (k - 0.5) / n * r.length
      local x, y = r:at(s)
      if (x - player_x) ^ 2 + (y - player_y) ^ 2 < 96 ^ 2 then s = (s + r.length / 2) % r.length end
      local decorative = r.name == 'road_ap7'
      local kind = 'car'
      if not decorative then
        local u = self.rng:random()
        for _, m in ipairs(MIX) do if u <= m[2] then kind = m[1]; break end end
      end
      local car = { route = r, dir = dir, s = s, v = 0, state = 'driving', kind = kind,
                    color = Traffic.KINDS[kind].color or self.rng:random(1, colors), variant = self.rng:random(1, 2), zone = nil,
                    decorative = decorative }
      self.cars[#self.cars + 1] = car
      r.cars = r.cars or {}
      r.cars[#r.cars + 1] = car
    end
  end
end

-- posición en el carril (desplazada a la derecha del sentido de marcha)
function Traffic.pos(car)
  local x, y, ang, level = car.route:at(car.s)
  if car.dir < 0 then ang = ang + math.pi end
  local nx, ny = -math.sin(ang), math.cos(ang)
  return x + nx * LANE, y + ny * LANE, ang, level
end

local function ahead_point(car, d)
  local r = car.route
  local s = math.max(0, math.min(r.length, car.s + car.dir * d))
  local x, y = r:at(s)
  return x, y
end

-- obstáculos de este paso: { {x, y, who}, … } (el jugador siempre es el primero)
function Traffic:think(player, others)
  local obs = self.obstacles
  for i = #obs, 1, -1 do obs[i] = nil end
  obs[1] = { x = player.body.x, y = player.body.y, who = 'player', level = player.body.level or 0 }
  for _, o in ipairs(others or {}) do obs[#obs + 1] = o end
  for _, c in ipairs(self.cars) do
    if not c.decorative then self:think_car(c, player) end
  end
end

-- distancia de frenada a la velocidad actual (v² / 2a) + margen
function Traffic.stop_dist(c)
  local k = Traffic.kind_of(c)
  return c.v * c.v / (2 * k.brake) + 6
end

function Traffic:think_car(c, player)
  self.clock = self.clock or 0
  local k = Traffic.kind_of(c)
  local state = 'driving'
  local blocked_by_player = false
  -- vehículo de delante en el mismo carril
  local gap = self.cfg.gap * k.gap
  for _, o in ipairs(c.route.cars) do
    if o ~= c and o.dir == c.dir then
      local ds = (o.s - c.s) * c.dir
      if ds > 0 and ds < gap then
        state = ds < gap * 0.6 and 'stopped' or 'yielding'
      end
    end
  end
  -- obstáculos en el carril (jugador, peatones): distancia a lo largo del carril y desplazamiento lateral.
  -- Si le da tiempo a frenar (distancia de frenada), se para; si se le cruzan muy cerca, solo frena un poco
  -- y puede haber atropello.
  local x, y, ang, level = Traffic.pos(c)
  local hx, hy = math.cos(ang), math.sin(ang)
  local stop_d = Traffic.stop_dist(c)
  for _, ob in ipairs(self.obstacles) do
    if (ob.level or 0) == (level or 0) then
      local dx, dy = ob.x - x, ob.y - y
      local ds = dx * hx + dy * hy              -- por delante (+) o por detrás (−)
      local lat = math.abs(dx * hy - dy * hx)   -- separación lateral
      if ds > 0 and ds < 64 and lat < 11 then
        local want = ds > stop_d + 6 and 'stopped' or 'yielding'
        if state ~= 'stopped' then state = want end
        if ob.who == 'player' then blocked_by_player = true end
      end
    end
  end
  if (c.hit_t or 0) > 0 then state = 'stopped' end
  -- paso de peatones con alguien encima o esperando: se para si aún puede frenar antes de la cebra
  local px, py = player.body.x, player.body.y
  for _, cw in ipairs(self.crosswalks) do
    local dcw = (cw.x - x) ^ 2 + (cw.y - y) ^ 2
    if dcw < 70 ^ 2 then
      local player_on = (cw.x - px) ^ 2 + (cw.y - py) ^ 2 < cw.r ^ 2
      local busy = player_on or cw.crossing > 0 or cw.waiting > 0
      -- semàfor en ambre o vermell: s'atura a la línia si encara hi és a temps
      if cw.light and Traffic.light_state(cw, self.clock) ~= 'green' then busy = true end
      if busy then
        for _, d in ipairs({ 18, 34, 50 }) do
          local ax, ay = ahead_point(c, d)
          if (ax - cw.x) ^ 2 + (ay - cw.y) ^ 2 < (cw.r + 6) ^ 2 then
            -- con alguien cruzando se para siempre; si solo esperan, solo si le da tiempo a frenar
            if player_on or cw.crossing > 0 or d >= stop_d then
              state = 'stopped'
              if player_on then blocked_by_player = true end
            end
          end
        end
      end
    end
  end
  -- reserva de cruces
  local ax, ay = ahead_point(c, 30)
  for _, z in ipairs(self.zones) do
    local far = (x - z.x) ^ 2 + (y - z.y) ^ 2 > 90 ^ 2 and z.owner ~= c
    if not far then
      local inside = (x - z.x) ^ 2 + (y - z.y) ^ 2 < z.r ^ 2
      local coming = (ax - z.x) ^ 2 + (ay - z.y) ^ 2 < z.r ^ 2
      if z.owner == c and not inside and not coming then z.owner = nil end
      -- una reserva que dura demasiado (vehículo detenido por otro motivo) caduca: evita bloqueos
      if z.owner and z.owner ~= c and self.clock - (z.since or 0) > 4 then z.owner = nil end
      if coming and z.owner ~= c then
        if z.owner == nil then z.owner = c; z.since = self.clock else state = 'stopped' end
      end
    end
  end
  -- claxon: más de 1,2 s frenado por culpa del jugador (como mucho uno cada 6 s por vehículo)
  if blocked_by_player and state ~= 'driving' then
    c.wait_player = (c.wait_player or 0) + AI_DT
    if c.wait_player > 1.2 and self.clock - (c.honked or -99) > 6 then
      c.honked = self.clock
      self.events[#self.events + 1] = { type = 'horn', x = x, y = y, kind = c.kind }
    end
  else
    c.wait_player = 0
  end
  c.state = state
end

function Traffic:update(dt, player, others)
  self.clock = (self.clock or 0) + dt
  self.ai_t = self.ai_t + dt
  if self.ai_t >= AI_DT then
    self.ai_t = self.ai_t - AI_DT
    self:think(player, others)
  end
  for _, c in ipairs(self.cars) do
    local k = Traffic.kind_of(c)
    if c.hit_t then c.hit_t = math.max(0, c.hit_t - dt) end
    local vmax = c.decorative and self.cfg.speed * 1.6 or self.cfg.speed * k.speed
    if c.decorative then c.state = 'driving' end
    local target = c.state == 'driving' and vmax or c.state == 'yielding' and vmax * 0.4 or 0
    if c.v < target then c.v = math.min(target, c.v + k.accel * dt) else c.v = math.max(target, c.v - k.brake * dt) end
    c.s = c.s + c.dir * c.v * dt
    -- final de la ruta: continua pel carrer enllaçat; sense enllaç, mitja volta (l'AP-7 decorativa torna
    -- a començar). Ja no desapareixen ni apareixen de cop.
    if c.s > c.route.length or c.s < 0 then
      local e = c.s > c.route.length and 1 or 0
      if c.decorative then
        c.s = c.dir > 0 and 0 or c.route.length
      else
        local links = c.route.links and c.route.links[e] or {}
        if c.route.edge and c.route.edge[e] and #self.entrances > 1 then
          -- surt del mapa: torna a entrar per una altra entrada (bucle d'entrada i sortida)
          local en
          for _ = 1, 4 do
            en = self.entrances[math.floor(self.rng:random() * #self.entrances) + 1]
            if not (en.route == c.route and en.e == e) then break end
          end
          self:move_to(c, en.route, en.s)
          c.loops = (c.loops or 0) + 1
        elseif #links > 0 then
          local l = links[math.floor(self.rng:random() * #links) + 1]
          self:move_to(c, l.route, l.s)
          c.turns = (c.turns or 0) + 1
        else
          c.s = math.max(0, math.min(c.route.length, c.s))
          c.dir = -c.dir
          c.v = c.v * 0.3                         -- frena per fer la mitja volta
          c.uturns = (c.uturns or 0) + 1
        end
      end
    elseif not c.decorative and c.v > 5 then
      c.turn_t = (c.turn_t or 0) - dt
      if c.turn_t <= 0 then
        c.turn_t = 0.2
        local x, y = c.route:at(c.s)
        self:maybe_turn(c, x, y)
      end
    end
  end
end

-- eventos pendientes (claxon…): la escena los consume
function Traffic:take_events()
  local ev = self.events
  self.events = {}
  return ev
end

-- vehículo en marcha que alcanza al jugador (mismo nivel): devuelve el vehículo y su posición, o nil
function Traffic:hit_test(player)
  local b = player.body
  for _, c in ipairs(self.cars) do
    if not c.decorative and c.v > 20 then
      local x, y, _, level = Traffic.pos(c)
      local hb = Traffic.kind_of(c).hit
      if level == (b.level or 0) and math.abs(x - b.x) < hb[1] and math.abs(y - b.y) < hb[2] then
        c.hit_t = 1.2
        return c, x, y
      end
    end
  end
end

-- rectángulos bloqueantes para el jugador (solo vehículos a nivel 0)
function Traffic:blockers(out)
  for _, c in ipairs(self.cars) do
    local x, y, _, level = Traffic.pos(c)
    if level == 0 and not c.decorative then
      local k = Traffic.kind_of(c)
      c.blocker = c.blocker or {}
      c.blocker.x, c.blocker.y, c.blocker.w, c.blocker.h = x - k.w / 2, y - k.h / 2, k.w, k.h
      out[#out + 1] = c.blocker
    end
  end
end

return Traffic
