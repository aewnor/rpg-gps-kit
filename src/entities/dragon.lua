-- El Drac del cim (fase 6): enemic final al Cau del Drac. Vola (no xoca amb les parets) dins de l'arena, fa
-- boles de foc cap al jugador (es poden parar amb l'escut) i s'abraona de tant en tant. Amb menys de la meitat de
-- vida s'enfada: més ràpid i més boles. Mateixa interfície que src/entities/enemy.lua (update → 'hit' | 'dead',
-- box, damage, kind amb xp i monedes) perquè el món el tracti com un enemic més.
local Dragon = {}
Dragon.__index = Dragon

Dragon.KIND = { name = 'El Drac del cim', hp = 70, damage = 2, xp = 400, coins = 60, gems = 5, boss = true,
                sprite = 'dragon' }
Dragon.W, Dragon.H = 64, 48

function Dragon.new(obj, rng)
  local self = setmetatable({}, Dragon)
  self.kind = Dragon.KIND
  self.name = obj.name
  self.room = obj.props and obj.props.room
  self.flag = obj.props and obj.props.flag
  self.hp, self.max_hp = Dragon.KIND.hp, Dragon.KIND.hp
  self.body = { x = obj.x, y = obj.y, w = 40, h = 16, level = 0 }
  self.home = { obj.x, obj.y }
  self.state = 'sleep'      -- sleep → fight (→ dead)
  self.t, self.cool, self.hurt_t = 0, 2.0, 0
  self.mode, self.mode_t = 'hover', 0
  self.breath = 0
  self.last_hit = -1
  self.rng = rng or math.random
  return self
end

function Dragon:box() return { x = self.body.x - 20, y = self.body.y - 34, w = 40, h = 38 } end
function Dragon:enraged() return self.hp <= self.max_hp / 2 end

function Dragon:damage(n, sx, sy)
  if self.state == 'dead' then return nil end
  if self.state == 'sleep' then self.state = 'fight' end
  self.last_dmg = n
  self.hp = self.hp - n
  self.hurt_t = 0.2
  if self.hp <= 0 then
    self.hp = 0
    self.state = 'dead'
    self.t = 0
    return 'dead'
  end
  return 'hit'
end

local function aim(self, p, spread, n, speed, ctx)
  local dx, dy = p.body.x - self.body.x, (p.body.y - 8) - (self.body.y - 10)
  local base = math.atan2(dy, dx)
  for i = 1, n do
    local a = base + (i - (n + 1) / 2) * spread
    ctx.shoot({ x = self.body.x, y = self.body.y - 12, vx = math.cos(a) * speed, vy = math.sin(a) * speed,
                r = 5, dmg = self.kind.damage, owner = 'enemy', kind = 'dragonfire', life = 2.6 })
  end
  if ctx.sfx then ctx.sfx('fire', self.body.x, self.body.y) end
end

-- ctx: { player, shoot(o), sfx, state, items }
function Dragon:update(dt, ctx)
  self.t = self.t + dt
  if self.state == 'dead' then return end
  local p = ctx.player
  local res
  -- cops d'espasa
  local hb, id, weapon = p:attack_box()
  if hb and id ~= self.last_hit then
    local b = self:box()
    if hb.x < b.x + b.w and hb.x + hb.w > b.x and hb.y < b.y + b.h and hb.y + hb.h > b.y then
      self.last_hit = id
      local dmg = ctx.state and ctx.items and require('src.systems.rpg').damage_dealt(ctx.state, ctx.items, weapon)
                  or weapon.damage
      res = self:damage(dmg, p.body.x, p.body.y)
      if ctx.sfx then ctx.sfx('hit') end
      if res == 'dead' then return 'dead' end
    end
  end
  if self.hurt_t > 0 then self.hurt_t = self.hurt_t - dt end
  local dx, dy = p.body.x - self.body.x, p.body.y - self.body.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if self.state == 'sleep' then
    if dist < 120 then self.state = 'fight'; self.cool = 1.2; if ctx.sfx then ctx.sfx('roar') end end
    return res
  end
  local angry = self:enraged()
  if self.breath > 0 then self.breath = self.breath - dt end
  self.mode_t = self.mode_t + dt
  if self.mode == 'hover' then
    -- vol en forma de vuit al voltant del niu
    local tx = self.home[1] + math.sin(self.t * (angry and 0.9 or 0.6)) * 72
    local ty = self.home[2] + math.sin(self.t * (angry and 1.8 or 1.2)) * 22
    self.body.x = self.body.x + (tx - self.body.x) * math.min(1, dt * 2.5)
    self.body.y = self.body.y + (ty - self.body.y) * math.min(1, dt * 2.5)
    self.cool = self.cool - dt
    if self.cool <= 0 then
      if self.rng() < (angry and 0.35 or 0.25) and dist < 150 then
        self.mode, self.mode_t = 'swoop', 0
        self.swoop = { dx / math.max(dist, 1), dy / math.max(dist, 1) }
        if ctx.sfx then ctx.sfx('roar') end
      else
        self.breath = 0.45
        aim(self, p, angry and 0.26 or 0.3, angry and 5 or 3, angry and 120 or 95, ctx)
      end
      self.cool = angry and 1.5 or 2.3
    end
  elseif self.mode == 'swoop' then
    -- s'abraona cap on era el jugador i torna
    local sp = self.mode_t < 0.55 and 170 or -110
    self.body.x = self.body.x + self.swoop[1] * sp * dt
    self.body.y = self.body.y + self.swoop[2] * sp * dt
    if self.mode_t > 1.1 then self.mode = 'hover' end
  end
  -- dins de l'arena
  self.body.x = math.max(self.home[1] - 150, math.min(self.home[1] + 150, self.body.x))
  self.body.y = math.max(self.home[2] - 40, math.min(self.home[2] + 110, self.body.y))
  -- contacte
  local b = self:box()
  local hb2 = p:hurtbox()
  if b.x < hb2.x + hb2.w and b.x + b.w > hb2.x and b.y + 14 < hb2.y + hb2.h and b.y + b.h > hb2.y then
    p:hit(self.kind.damage + (self.mode == 'swoop' and 1 or 0), self.body.x, self.body.y, ctx)
  end
  return res
end

-- fotograma: 1–2 aletejant, 3 foc; +3 en blanc quan rep
function Dragon:frame()
  local f = self.breath > 0 and 3 or (math.floor(self.t * (self:enraged() and 7 or 5)) % 2 + 1)
  if not require('src.motion').reduced and self.hurt_t > 0 and math.floor(self.hurt_t * 12) % 2 == 0 then f = f + 3 end
  return f
end

function Dragon:draw(img, quads, ox, oy)
  if self.state == 'dead' then return end
  local x, y = math.floor(self.body.x + 0.5) - ox, math.floor(self.body.y + 0.5) - oy
  -- ombra a terra (vola una mica per sobre)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse('fill', x, y + 10, 18, 5)
  love.graphics.setColor(1, 1, 1, 1)
  local bob = require('src.motion').bob(self.t*5,2)
  love.graphics.draw(img, quads[self:frame()], x - 32, y - 44 + bob)
end

return Dragon
