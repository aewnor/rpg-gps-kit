-- Perles del Drac (data/perles.json): set perles amagades a llocs reals del poble. Cada una dona un objecte
-- «Perla del Drac»; amb les set, el drac de Sant Jordi et regala l'Armadura del Drac (es veu al personatge).
-- Les posicions es calculen al vol: la casella transitable més propera al monument o a l'àrea indicats.
local State = require('src.state')
local Collision = require('src.world.collision')

local Perles = {}

local DATA
function Perles.data()
  if DATA == nil then
    DATA = false
    local txt = love.filesystem.read('data/perles.json')
    local ok, d = pcall(require('src.lib.json').decode, txt or '')
    if ok and type(d) == 'table' and type(d.perles) == 'table' then DATA = d end
  end
  return DATA or { perles = {} }
end

function Perles.total() return #Perles.data().perles end

function Perles.count(st)
  local n = 0
  for _, p in ipairs(Perles.data().perles) do if State.flag(st, p.id) then n = n + 1 end end
  return n
end

-- punt «poi» del monument (davant la porta, el posa tools/import_osm.py)
local function landmark_anchor(w, id)
  for _, o in ipairs(w.map.objects or {}) do
    if o.type == 'poi' and o.name == id then return math.floor(o.x / 16), math.floor(o.y / 16) end
  end
end

-- casella transitable (nivell 0) més propera, en espiral fins a 14 caselles
local function walkable_near(w, tx, ty)
  for r = 0, 14 do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local x, y = tx + dx, ty + dy
          if w.map:in_bounds(x, y) and Collision.walk_at(w.map:cell(x, y), 0) then return x, y end
        end
      end
    end
  end
end

-- posicions de les perles (només a l'exterior): { id, i, ax, ay (àncora en caselles), x, y quan es resol }.
-- La casella exacta es busca quan el tros del mapa ja és carregat (no força cap càrrega en entrar).
function Perles.setup(w)
  w.perles = {}
  if w.id ~= 'overworld' then return end
  for i, p in ipairs(Perles.data().perles) do
    local kind, arg = tostring(p.near):match('^(%w+):(.*)$')
    local tx, ty
    if kind == 'landmark' then
      tx, ty = landmark_anchor(w, arg)
    elseif kind == 'area' then
      local a = require('src.systems.streets').area(arg)
      if a then tx, ty = math.floor(a.cx / 16), math.floor(a.cy / 16) end
    end
    if tx then
      local off = p.offset or { 0, 0 }
      w.perles[#w.perles + 1] = { id = p.id, i = i, ax = tx + off[1], ay = ty + off[2], pista = p.pista }
    end
  end
end

local function resolve(w, p, force)
  if p.x or p.failed then return p.x ~= nil end
  local C = w.map.chunk or 32
  if not force and w.map.chunks.has and not w.map.chunks:has(math.floor(p.ax / C), math.floor(p.ay / C)) then return false end
  local x, y = walkable_near(w, p.ax, p.ay)
  if x then p.x, p.y = x * 16 + 8, y * 16 + 8 else p.failed = true end
  return x ~= nil
end
Perles.resolve = resolve

function Perles.update(w)
  if not w.perles or #w.perles == 0 then return end
  local st, b = w.state, w.player.body
  for _, p in ipairs(w.perles) do
    if not State.flag(st, p.id) and resolve(w, p) and math.abs(p.x - b.x) < 11 and math.abs(p.y - b.y) < 11 then
      State.set(st, p.id)
      State.give(st, 'perla_drac')
      local n, total = Perles.count(st), Perles.total()
      w.game.audio.play('chest')
      w:puff(p.x, p.y, 10, { 1, 0.7, 0.2 }, 30, 0.5, 1)
      if n >= total then
        local prize = Perles.data().premi or 'armadura_drac'
        if not State.has(st, prize) then State.give(st, prize) end
        State.equip(st, w.game.items, prize)
        State.set(st, 'perles_completes')
        w.hud:toast('Les ' .. total .. ' Perles del Drac! El drac et regala l\'Armadura del Drac', 5)
      else
        w.hud:toast('Perla del Drac ' .. n .. '/' .. total .. '!', 2.5)
      end
    end
  end
end

-- bola taronja brillant amb tantes estrelles vermelles com el seu número (com les del drac dels contes)
local STARS = {
  { { 0, 0 } }, { { -2, 0 }, { 2, 0 } }, { { -2, 1 }, { 2, 1 }, { 0, -2 } }, { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } },
  { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 }, { 0, 0 } }, { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 }, { -2, 0 }, { 2, 0 } },
  { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 }, { -2, 0 }, { 2, 0 }, { 0, 0 } },
}
function Perles.draw(w, ox, oy)
  if not w.perles then return end
  local lg = love.graphics
  local t = love.timer.getTime()
  for _, p in ipairs(w.perles) do
    if not State.flag(w.state, p.id) and p.x and w.cam:visible(p.x - 16, p.y - 24, 32, 40, 0) then
      local bob = math.floor(math.sin(t * 2.5 + p.i) * 2 + 0.5)
      local x, y = math.floor(p.x - ox), math.floor(p.y - oy) - 6 + bob
      local glow = 0.25 + 0.15 * math.sin(t * 4 + p.i)
      lg.setColor(1, 0.75, 0.25, glow); lg.circle('fill', x, y, 9)
      lg.setColor(0, 0, 0, 0.25); lg.ellipse('fill', x, math.floor(p.y - oy) + 2, 5, 2)
      lg.setColor(0.86, 0.45, 0.08); lg.circle('fill', x, y, 5.5)
      lg.setColor(1, 0.68, 0.18); lg.circle('fill', x, y, 4.5)
      lg.setColor(1, 0.92, 0.7); lg.rectangle('fill', x - 3, y - 4, 2, 2)
      lg.setColor(0.85, 0.1, 0.1)
      for _, s in ipairs(STARS[p.i] or STARS[1]) do lg.rectangle('fill', x + s[1], y + s[2], 1, 1) end
      if math.floor(t * 3 + p.i) % 4 == 0 then   -- espurna
        lg.setColor(1, 1, 0.85); lg.rectangle('fill', x + 5, y - 7, 1, 3); lg.rectangle('fill', x + 4, y - 6, 3, 1)
      end
    end
  end
  lg.setColor(1, 1, 1)
end

-- línies per al diari: quantes en tens i la pista de les que falten
function Perles.journal(st)
  local out = {}
  for _, p in ipairs(Perles.data().perles) do
    out[#out + 1] = { done = State.flag(st, p.id), pista = p.pista }
  end
  return out
end

return Perles
