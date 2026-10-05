-- Projectils (fase 6): boles de foc i ràfegues del jugador (encanteris, src/systems/magic.lua) i el foc del drac.
-- Una llista amb reutilització de taules (sense crear-ne de noves a cada tret) i col·lisions simples cercle–caixa.
-- Lua pur (sense love.*): es prova amb luajit (tests/combat6_cases.lua).
--   p = { x, y, vx, vy, r, dmg, owner = 'player' | 'enemy', kind = 'fire' | 'gust' | 'dragonfire', life, push,
--         pierce (travessa enemics: la ràfaga) }
local P = {}
P.__index = P

P.MAX = 48

function P.new() return setmetatable({ list = {}, pool = {}, events = {} }, P) end

function P:spawn(o)
  if #self.list >= P.MAX then return nil end
  local p = table.remove(self.pool) or {}
  for k in pairs(p) do p[k] = nil end
  for k, v in pairs(o) do p[k] = v end
  p.r = p.r or 4
  p.life = p.life or 1.5
  p.t = 0
  p.hit = p.pierce and {} or nil
  self.list[#self.list + 1] = p
  return p
end

local function overlap(p, b)
  local cx = math.max(b.x, math.min(p.x, b.x + b.w))
  local cy = math.max(b.y, math.min(p.y, b.y + b.h))
  return (p.x - cx) ^ 2 + (p.y - cy) ^ 2 <= p.r * p.r
end
P.overlap = overlap

local function event(self, kind, p, target)
  local e = self.events
  e[#e + 1] = { kind = kind, x = p.x, y = p.y, p_kind = p.kind, target = target, dmg = p.dmg }
end

-- solid(x, y) → true si hi ha paret; targets: entitats amb :box() i :damage(n, sx, sy) (enemics, el drac);
-- player: { hurtbox(), hit(dmg, sx, sy, ctx) }; ctx es passa a player:hit
function P:update(dt, solid, targets, player, ctx)
  local list = self.list
  local i = 1
  while i <= #list do
    local p = list[i]
    p.t = p.t + dt
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    local dead = p.t >= p.life
    if not dead and p.kind ~= 'dragonfire' and solid and solid(p.x, p.y) then
      dead = true
      event(self, 'wall', p)
    end
    if not dead and p.owner == 'player' then
      for _, e in ipairs(targets) do
        if e.state ~= 'dead' and not (p.hit and p.hit[e]) and overlap(p, e:box()) then
          local res = e:damage(p.dmg, p.x - p.vx * 0.05, p.y - p.vy * 0.05, p.push)
          if p.freeze and res ~= 'dead' then e.frozen_t = p.freeze end   -- raig de gel: queda congelat
          event(self, res == 'dead' and 'kill' or 'hit', p, e)
          if p.hit then p.hit[e] = true else dead = true; break end
        end
      end
    elseif not dead and p.owner == 'enemy' and player and overlap(p, player:hurtbox()) then
      local hurt, why = player:hit(p.dmg, p.x - p.vx * 0.1, p.y - p.vy * 0.1, ctx)
      local blocked = why == 'blocked' or why == 'ward'
      event(self, blocked and 'blocked' or (hurt and 'hurt' or 'miss'), p)
      dead = hurt or blocked
    end
    if dead then
      list[i] = list[#list]
      list[#list] = nil
      self.pool[#self.pool + 1] = p
    else
      i = i + 1
    end
  end
end

-- esdeveniments del darrer update (impactes) per als efectes; es buida en llegir-los
function P:take_events()
  local e = self.events
  self.events = {}
  return e
end

function P:clear()
  for i = #self.list, 1, -1 do self.pool[#self.pool + 1] = self.list[i]; self.list[i] = nil end
end

return P
