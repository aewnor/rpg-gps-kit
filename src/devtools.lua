-- Modos de desarrollo: --bench=SEG (recorrido automático y métricas), --test (escenario de
-- integración, ver tests/integration.lua) y --shot=archivo --at=tx,ty (captura de pantalla).
local Input = require('src.input')
local Path = require('src.world.pathfind')
local json = require('src.lib.json')

local Dev = {}
Dev.__index = Dev

function Dev.new(game, args)
  local self = setmetatable({ game = game, args = args, frames = {}, t = 0, n = 0 }, Dev)
  io.stdout:setvbuf('line')
  if args.test then love.window.setVSync(0) end
  game.args.bench = args.bench
  -- no tocar la partida real del usuario
  local Save = require('src.save')
  local mem = {}
  Save.fs = {
    read = function(n) return mem[n] end,
    write = function(n, d) mem[n] = d; return true end,
    exists = function(n) return mem[n] ~= nil end,
    remove = function(n) mem[n] = nil; return true end,
    rename = function(a, b) mem[b] = mem[a]; mem[a] = nil; return true end,
  }
  self.mem = mem
  require('src.profile').fs = Save.fs   -- perfils també en memòria (mai els reals de l'usuari)
  if not args.keephome then game.home, game.home_warning = nil, nil end
  game:new_game()
  game.transition = nil
  if args.simtime then game.state.sim_time = tonumber(args.simtime) end
  if args.scene then game:do_change({ scene = args.scene, spawn_name = 'spawn_entrance' }) end
  if args.equip then
    local State = require('src.state')
    for it in args.equip:gmatch('[%w_]+') do State.give(game.state, it); State.equip(game.state, game.items, it) end
  end
  if args.at then
    local tx, ty = args.at:match('(%d+),(%d+)')
    local b = game.scene.player.body
    b.x, b.y = tonumber(tx) * 16 + 8, tonumber(ty) * 16 + 8
  end
  if args.bench then self:init_bench(tonumber(args.bench) or 600) end
  if args.test then
    self.turbo = tonumber(args.turbo) or 8
    local chunk = assert(love.filesystem.load(type(args.test) == 'string' and args.test or 'tests/integration.lua'))
    self.test = coroutine.create(chunk())
    self.test_api = self:api()
  end
  return self
end

-- ---------------------------------------------------------------- conducción por waypoints
function Dev:drive_to(wps)
  self.wps, self.wi, self.stuck, self.last, self.dbg = wps, 1, 0, nil, 0
end

function Dev:drive_step(dt)
  local wps = self.wps
  Input.release_all()
  if not wps or self.wi > #wps then return true end
  local b = self.game.scene.player.body
  local w = wps[self.wi]
  local dx, dy = w[1] - b.x, w[2] - b.y
  if math.abs(dx) < 1.5 and math.abs(dy) < 1.5 then
    self.wi = self.wi + 1
    return self.wi > #wps
  end
  local axis_x = math.abs(dx) >= 1.5 and (math.abs(dx) >= math.abs(dy) or math.abs(dy) < 1.5)
  if self.stuck > 1.0 then axis_x = not axis_x end
  if self.stuck > 1.0 and not self.side_t and (axis_x and math.abs(dx) < 1.5 or not axis_x and math.abs(dy) < 1.5) then
    -- bloqueado en línea recta (p. ej. un coche parado delante): paso lateral de ½ s, alternando lado
    self.side_n = (self.side_n or 0) + 1
    self.side_t, self.side_key = 0.5, axis_x and (self.side_n % 2 == 0 and 'right' or 'left')
                                            or (self.side_n % 2 == 0 and 'down' or 'up')
  end
  if self.side_t then
    Input.hold(self.side_key, true)
    self.side_t = self.side_t - dt
    if self.side_t <= 0 then self.side_t = nil end
  elseif axis_x and math.abs(dx) >= 1.5 then Input.hold(dx > 0 and 'right' or 'left', true)
  elseif math.abs(dy) >= 1.5 then Input.hold(dy > 0 and 'down' or 'up', true)
  else Input.hold(dx > 0 and 'right' or 'left', true) end
  if os.getenv('DRIVE_DEBUG') and (self.dbg or 0) < 12 then
    self.dbg = (self.dbg or 0) + 1
    print(string.format('[drive] wi=%d/%d b=%.1f,%.1f w=%s,%s dx=%.1f dy=%.1f stuck=%.2f', self.wi, #wps, b.x, b.y, w[1], w[2], dx, dy, self.stuck))
  end
  local pos = b.x * 10000 + b.y
  if self.last and math.abs(pos - self.last) < 0.01 then self.stuck = self.stuck + dt else self.stuck = 0 end
  self.last = pos
  if self.stuck > 4 then self.wi = self.wi + 1; self.stuck = 0; self.skipped = (self.skipped or 0) + 1 end
  return false
end

function Dev:path_to(goal_fn)
  local sc = self.game.scene
  local b = sc.player.body
  -- celdas ocupadas por NPC, cofres, palancas y rejas cerradas (no por coches, que se mueven)
  local blocked = {}
  sc:rebuild_blockers()
  local W = sc.map.width
  local function mark(r) -- celda bloqueada si el collider centrado en ella toca el rectángulo
    for ty = math.floor(r.y / 16) - 1, math.floor((r.y + r.h) / 16) + 1 do
      for tx = math.floor(r.x / 16) - 1, math.floor((r.x + r.w) / 16) + 1 do
        local cx, cy = tx * 16 + 8, ty * 16 + 8
        if cx - 5 < r.x + r.w and cx + 5 > r.x and cy - 4 < r.y + r.h and cy + 4 > r.y then
          blocked[ty * W + tx] = true
        end
      end
    end
  end
  for _, n in ipairs(sc.npcs) do mark(n.blocker) end
  for _, c in ipairs(sc.chests) do mark(c.rect) end
  for _, l in ipairs(sc.levers) do mark(l.rect) end
  for _, g in ipairs(sc.gates) do if not sc:gate_open(g) then mark(g.rect) end end
  local tx, ty = math.floor(b.x / 16), math.floor(b.y / 16)
  blocked[ty * W + tx] = nil
  local p = Path.find(sc.map, { tx, ty, b.level }, function(x, y) return not blocked[y * W + x] and goal_fn(x, y) end,
    nil, blocked)
  return p and Path.waypoints(p)
end

-- ---------------------------------------------------------------- benchmark
function Dev:init_bench(seconds)
  self.duration = seconds
  local State = require('src.state')
  for _, it in ipairs({ 'sword_wood', 'shield_wood' }) do
    State.give(self.game.state, it); State.equip(self.game.state, self.game.items, it)
  end
  self.legs = { 'arc_de_bera', 'ermita_bera', 'roc_sant_gaieta', 'sant_bartomeu', 'pedrera_elies', 'cucurull',
                'mirador_morella', 'sant_bartomeu' }
  self.leg = 0
  self.samples = {}
  self.log = {}
  self.mode = 'bench'
  self.walked = 0
end

function Dev:next_leg()
  for _ = 1, #self.legs do
    self.leg = self.leg % #self.legs + 1
    local map = self.game.scene.map
    local o = map:object('poi', self.legs[self.leg])
    local gx, gy = math.floor(o.x / 16), math.floor(o.y / 16)
    -- destino: cualquier celda a ≤ 2 de la puerta (por si un NPC la ocupa)
    local wps = self:path_to(function(x, y) return math.abs(x - gx) + math.abs(y - gy) <= 2 end)
    self.tool_frame = true -- frame con búsqueda de ruta: es coste de la herramienta, no del juego
    if wps and #wps > 0 then
      self:drive_to(wps)
      self.legs_done = (self.legs_done or 0) + 1
      return
    end
    self.legs_failed = (self.legs_failed or 0) + 1
    print('[bench] sin ruta hacia ' .. self.legs[self.leg])
  end
  self:drive_to({})
end

local function read_file(p)
  local f = io.open(p, 'r')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end

function Dev:sys_metrics()
  local status = read_file('/proc/self/status') or ''
  local rss = tonumber(status:match('VmRSS:%s+(%d+)')) or 0
  local temp = tonumber(read_file('/sys/class/thermal/thermal_zone0/temp') or '') or 0
  local thr = ''
  local p = io.popen('vcgencmd get_throttled 2>/dev/null')
  if p then thr = p:read('*a') or ''; p:close() end
  return { rss_mib = rss / 1024, temp_c = temp / 1000, throttled = thr:match('0x%x+') or 'n/d' }
end

function Dev:record(ft)
  if self.mode ~= 'bench' then return end
  if self.tool_frame then
    self.tool_frame = false
    self.tool_frames = (self.tool_frames or 0) + 1
    return
  end
  self.samples[#self.samples + 1] = ft
end

function Dev:step(act, dt)
  self.t = self.t + dt
  if self.mode == 'bench' then
    -- combate activo: si hay un enemigo cerca, encararlo y atacar
    local sc = self.game.scene
    local b = sc.player.body
    for _, e in ipairs(sc.enemies) do
      if e.state ~= 'dead' and (e.body.x - b.x) ^ 2 + (e.body.y - b.y) ^ 2 < 26 ^ 2 then
        local dx, dy = e.body.x - b.x, e.body.y - b.y
        if math.abs(dx) > math.abs(dy) then sc.player.facing = dx > 0 and 'right' or 'left'
        else sc.player.facing = dy > 0 and 'down' or 'up' end
        Input.press('attack')
        self.attacks = (self.attacks or 0) + 1
        break
      end
    end
    if not self.wps or self:drive_step(dt) then self:next_leg() end
    if math.floor(self.t) % 30 == 0 and math.floor(self.t - dt) % 30 ~= 0 then
      local m = self:sys_metrics()
      m.t = math.floor(self.t)
      m.fps = love.timer.getFPS()
      m.p95_ms = self.game:p95() * 1000
      m.lua_mib = collectgarbage('count') / 1024
      m.chunks = self.game.scene.map.chunks.count
      local b = self.game.scene.player.body
      m.tile = { math.floor(b.x / 16), math.floor(b.y / 16) }
      self.log[#self.log + 1] = m
      print(string.format('[bench] t=%ds fps=%d p95=%.2fms rss=%.0fMiB temp=%.1f°C thr=%s tile=%d,%d',
        m.t, m.fps, m.p95_ms, m.rss_mib, m.temp_c, m.throttled, m.tile[1], m.tile[2]))
    end
    if self.t >= self.duration then self:finish_bench() end
  elseif self.test then
    if coroutine.status(self.test) == 'dead' then return end
    local ok, err = coroutine.resume(self.test, self.test_api, dt)
    if not ok then
      print('[test] ERROR: ' .. tostring(err))
      print(debug.traceback(self.test))
      love.event.quit(1)
    elseif coroutine.status(self.test) == 'dead' then
      print('[test] escenario completado')
      love.event.quit(self.failures and self.failures > 0 and 1 or 0)
    end
  elseif self.args.shot then
    self.n = self.n + 1
    if self.n == (tonumber(self.args.frames) or 30) then
      love.graphics.captureScreenshot(function(data)
        data:encode('png', 'shot.png')
        print('[shot] ' .. love.filesystem.getSaveDirectory() .. '/shot.png')
        love.event.quit(0)
      end)
    end
  end
end

function Dev:finish_bench()
  local s = {}
  for i, v in ipairs(self.samples) do s[i] = v end
  table.sort(s)
  local function pct(p) return s[math.max(1, math.floor(#s * p))] * 1000 end
  local long, streak, max_streak = 0, 0, 0
  for _, v in ipairs(self.samples) do
    if v > 1 / 30 then long = long + 1; streak = streak + 1; max_streak = math.max(max_streak, streak)
    else streak = 0 end
  end
  local total = 0
  for _, v in ipairs(self.samples) do total = total + v end
  local r = {
    duration_s = self.t, frames = #self.samples, renderer = { love.graphics.getRendererInfo() },
    work_ms = { mean = total / #self.samples * 1000, p50 = pct(0.5), p95 = pct(0.95), p99 = pct(0.99), max = s[#s] * 1000 },
    frames_over_33ms = long, longest_slow_streak = max_streak, dropped_backlogs = self.game.dropped,
    waypoints_skipped = self.skipped or 0, legs_started = self.legs_done or 0, legs_failed = self.legs_failed or 0,
    excluded_pathfinding_frames = self.tool_frames or 0, attacks = self.attacks or 0,
    deaths = self.deaths or 0, system = self:sys_metrics(),
    lua_mib = collectgarbage('count') / 1024, texture_mib = love.graphics.getStats().texturememory / 1048576,
    timeline = self.log,
  }
  local out = json.encode(r, true)
  love.filesystem.write('bench.json', out)
  print('[bench] RESULTADO ' .. json.encode({ p95 = r.work_ms.p95, p99 = r.work_ms.p99, max = r.work_ms.max,
    rss = r.system.rss_mib, temp = r.system.temp_c, thr = r.system.throttled }))
  print('[bench] ' .. love.filesystem.getSaveDirectory() .. '/bench.json')
  love.event.quit(0)
end

-- ---------------------------------------------------------------- API para tests de integración
function Dev:api()
  local dev, game = self, self.game
  local api = {}
  self.failures = 0
  function api.wait(frames)
    for _ = 1, frames or 1 do coroutine.yield() end
  end
  function api.check(cond, msg)
    if cond then print('[test] OK   ' .. msg)
    else print('[test] FAIL ' .. msg); dev.failures = dev.failures + 1 end
  end
  function api.press(action) Input.press(action); api.wait(2) end
  function api.scene() return game.scene end
  function api.state() return game.state end
  function api.player() return game.scene.player end
  function api.walk_to(goal_fn, timeout)
    for attempt = 1, 4 do
      local wps = dev:path_to(goal_fn)
      if not wps then print('[test] sin camino'); return false end
      dev:drive_to(wps)
      dev.skipped = 0
      local t = 0
      local done = false
      local sc0 = game.scene
      while not done and game.scene == sc0 and not game.transition do
        done = dev:drive_step(1 / 60)
        if done then break end
        coroutine.yield()
        if api.on_frame then api.on_frame() end
        t = t + 1 / 60
        if t > (timeout or 300) or (dev.skipped or 0) > 0 then break end
      end
      Input.release_all()
      api.wait(2)
      if game.scene ~= sc0 or game.transition then return true end
      local b = game.scene.player.body
      if goal_fn(math.floor(b.x / 16), math.floor(b.y / 16)) then return true end
      local w1 = wps[1] or {}
      print(string.format('[test] reintento %d desde (%d,%d) px=%.1f,%.1f lv=%d st=%s dlg=%s menu=%s wp1=%s,%s n=%d', attempt,
        math.floor(b.x / 16), math.floor(b.y / 16), b.x, b.y, b.level, game.scene.player.state, tostring(game.scene.dialogue.open),
        tostring(game.menu ~= nil), tostring(w1[1]), tostring(w1[2]), #wps))
      api.wait(60)
    end
    return false
  end
  -- ¿hay camino a pie desde el jugador? (sin moverse); devuelve los waypoints o nil
  function api.path_to(goal_fn) return dev:path_to(goal_fn) end
  function api.walk_next_to(x, y)
    local gx, gy = math.floor(x / 16), math.floor(y / 16)
    return api.walk_to(function(tx, ty) return math.abs(tx - gx) + math.abs(ty - gy) == 1 end)
  end
  function api.face(x, y)
    local b = game.scene.player.body
    local dx, dy = x - b.x, y - b.y
    if math.abs(dx) > math.abs(dy) then game.scene.player.facing = dx > 0 and 'right' or 'left'
    else game.scene.player.facing = dy > 0 and 'down' or 'up' end
  end
  function api.talk_through(max_pages)
    for _ = 1, (max_pages or 12) * 3 do
      if not game.scene.dialogue.open then return true end
      api.press('confirm')
      api.wait(3)
    end
    return not game.scene.dialogue.open
  end
  function api.teleport(tx, ty)
    local b = game.scene.player.body
    b.x, b.y, b.level = tx * 16 + 8, ty * 16 + 8, 0
  end
  function api.mem() return dev.mem end
  function api.game_dialogue(key) return (game.dialogue[key] or {}).name end
  return api
end

return Dev
