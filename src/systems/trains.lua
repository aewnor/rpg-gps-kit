-- Trenes por corredor (fase 2). Estado = distancia `s` de la cabeza sobre la ruta, calculada de
-- forma analítica a partir del reloj de simulación: fuera de cámara no se simula vagón a vagón,
-- y al pausar/cargar no se acumulan trenes. Cada vagón se evalúa en s − offset.
-- Pasos a nivel: open → warning → closed → clearing → open. Nunca se cierra con el jugador dentro:
-- el tren frena antes del paso hasta que quede libre. Horarios ficticios.
-- Fase 4: las barreras bajan y suben animadas (cr.bar 0 = arriba … 1 = abajo), la campana suena mientras
-- avisan y el tren de alta velocidad (corredor rail_hs) pasa a 2,4× sin parar.
local Route = require('src.systems.route')

local Trains = {}
Trains.__index = Trains

local CAR_LEN = 48
local GAP = 2
local CONSISTS = {
  rail_hs = { kind = 'hs', cars = 4, decorative = true, speed = 2.4, nostop = true },
  rail_interior = { kind = 'rodalies', cars = 3 },
  rail_litoral = { kind = 'rodalies', cars = 3 },
}

function Trains.new(map, cfg)
  local self = setmetatable({ lines = {}, crossings = {}, cfg = cfg, delays = {}, horned = {} }, Trains)
  for _, r in ipairs(map.routes) do
    if r.type == 'route_train' then
      local route = Route.new(r)
      local c = { kind = 'rodalies', cars = 3 }
      local len = c.cars * (CAR_LEN + GAP)
      local travel = (route.length + len) / cfg.speed + #route.stops * cfg.stop
      -- el periodo debe dejar separación entre trenes del mismo sentido
      local period = math.max(cfg.period, (len + 64) / cfg.speed + cfg.stop)
      local corridor = r.props.corridor or r.name
      c = CONSISTS[corridor] or c
      len = c.cars * (CAR_LEN + GAP)
      local speed = cfg.speed * (c.speed or 1)
      local stop = c.nostop and 0 or cfg.stop
      travel = (route.length + len) / speed + #route.stops * stop
      self.lines[#self.lines + 1] = { route = route, consist = c, len = len, travel = travel, period = period,
                                      dirs = r.props.dirs or 'both', speed = speed, stop = stop }
    end
  end
  for _, o in ipairs(map.objects) do
    if o.type == 'level_crossing' then
      local cr = { x = o.x, y = o.y, lines = {}, state = 'open', t = 0, bar = 0, bell_t = 0,
                   area = { x = o.x - 28, y = o.y - 28, w = 56, h = 56 } }
      for _, l in ipairs(self.lines) do
        local s, d = l.route:project(o.x, o.y)
        if d < 48 then cr.lines[l] = s end
      end
      if next(cr.lines) then self.crossings[#self.crossings + 1] = cr end
    end
  end
  return self
end

-- distancia recorrida por la cabeza tras `e` segundos, con paradas
local function head_distance(line, e, dir, speed, stop)
  if e <= 0 then return nil end
  local stops = line.route.stops
  local s = speed * e
  local order = {}
  for i = 1, #stops do
    order[i] = dir > 0 and stops[i] or (line.route.length - stops[#stops - i + 1])
  end
  for _, st in ipairs(order) do
    local reach = st / speed
    if e < reach then break end
    if e < reach + stop then return st, true end
    e = e - stop
    s = speed * e
  end
  return s, false
end

-- trenes activos en el instante t: lista de {line, id, dir, head (s en coordenadas de ruta), dwell}
function Trains:active(t)
  local out = {}
  local cfg = self.cfg
  for li, l in ipairs(self.lines) do
    -- vía única: sentidos alternos cada medio periodo; vía doble: un sentido por vía
    local step = l.dirs == 'both' and l.period / 2 or l.period
    local offset = l.dirs == 'bwd' and l.period / 2 or 0
    local k1 = math.floor((t - offset) / step)
    local k0 = math.floor((t - offset - l.travel - 30) / step)
    for k = math.max(0, k0), k1 do
      local id = li * 100000 + k
      local dir
      if l.dirs == 'both' then dir = (k % 2 == 0) and 1 or -1
      else dir = l.dirs == 'fwd' and 1 or -1 end
      local e = t - offset - k * step - (self.delays[id] or 0)
      local d, dwell = head_distance(l, e, dir, l.speed, l.stop)
      if d and d - l.len < l.route.length then
        local head = dir > 0 and d or (l.route.length - d)
        out[#out + 1] = { line = l, id = id, dir = dir, head = head, dwell = dwell }
      end
    end
  end
  return out
end

local function overlap(a, b)
  return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

function Trains:update(dt, t, player, sfx)
  local trains = self:active(t)
  self.current = trains
  local pbox = player:hurtbox()
  for _, c in ipairs(self.crossings) do
    local eta_min, occupied = math.huge, false
    for _, tr in ipairs(trains) do
      local cs = c.lines[tr.line]
      if cs then
        local tail = tr.head - tr.dir * tr.line.len
        local ahead = (cs - tr.head) * tr.dir            -- >0 si el paso está delante de la cabeza
        local behind_tail = (cs - tail) * tr.dir
        if ahead <= 0 and behind_tail >= -4 then occupied = true end
        if ahead > 0 then
          local eta = ahead / tr.line.speed
          eta_min = math.min(eta_min, eta)
          -- protección: jugador dentro del paso y tren cerca → frenar antes del paso
          if overlap(pbox, c.area) and ahead < 96 then
            self.delays[tr.id] = (self.delays[tr.id] or 0) + dt
            c.holding = true
          end
        end
      end
    end
    local prev = c.state
    if occupied or eta_min < 3 then c.state = 'closed'
    elseif eta_min < 7 then c.state = (prev == 'closed') and 'closed' or 'warning'
    elseif prev == 'closed' then c.state = 'clearing'; c.t = 0
    elseif prev == 'clearing' then
      c.t = c.t + dt
      if c.t > 1.5 then c.state = 'open' end
    else c.state = 'open' end
    -- campana mientras avisa o está cerrado (cada 0,9 s; la escena atenúa según la distancia)
    if c.state == 'warning' or c.state == 'closed' then
      c.bell_t = c.bell_t - dt
      if c.bell_t <= 0 then c.bell_t = 0.9; if sfx then sfx('bell', c.x, c.y) end end
    else
      c.bell_t = 0
    end
    -- barreras: bajan en 1,5 s al cerrar y suben al despejar
    local target = c.state == 'closed' and 1 or 0
    if c.bar ~= target then
      if (c.bar == 0 or c.bar == 1) and sfx then sfx('barrier', c.x, c.y) end
      c.bar = target > c.bar and math.min(1, c.bar + dt / 1.5) or math.max(0, c.bar - dt / 1.5)
    end
    c.holding = false
  end
  -- olvidar trenes que ya han terminado (retrasos y bocinas): antes estas tablas crecían sin límite
  self.prune_t = (self.prune_t or 0) + dt
  if self.prune_t > 10 then
    self.prune_t = 0
    local live = {}
    for _, tr in ipairs(trains) do live[tr.id] = true end
    for id in pairs(self.horned) do if not live[id] then self.horned[id] = nil end end
    for id in pairs(self.delays) do if not live[id] then self.delays[id] = nil end end
  end
  -- bocina cuando un tren pasa cerca del jugador
  for _, tr in ipairs(trains) do
    local x, y = tr.line.route:at(tr.head)
    local near = (x - player.body.x) ^ 2 + (y - player.body.y) ^ 2 < 140 ^ 2
    if near and not self.horned[tr.id] and sfx then
      self.horned[tr.id] = true
      sfx('horn', x, y)
    end
  end
end

-- bloqueadores: barreras cerradas impiden ENTRAR en el paso (quien ya está dentro puede salir)
function Trains:blockers(out)
  for _, c in ipairs(self.crossings) do
    if c.state == 'closed' or c.state == 'warning' then out[#out + 1] = c.area end
  end
end

-- vagones a dibujar: {x, y, orient, reverse, kind, loco, level}
function Trains:cars(cam)
  local out = {}
  for _, tr in ipairs(self.current or {}) do
    local l = tr.line
    for i = 0, l.consist.cars - 1 do
      local s = tr.head - tr.dir * (i * (CAR_LEN + GAP) + CAR_LEN / 2)
      if s >= 0 and s <= l.route.length then
        local x, y, ang, level = l.route:at(s)
        if tr.dir < 0 then ang = ang + math.pi end
        if cam:visible(x - 24, y - 24, 48, 48, 32) then
          local o, rev = Route.orient(ang)
          out[#out + 1] = { x = x, y = y, orient = o, reverse = rev, kind = l.consist.kind,
                            loco = (i == 0), level = level, back = (i == l.consist.cars - 1) }
        end
      end
    end
  end
  return out
end

return Trains
