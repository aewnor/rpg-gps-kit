-- Enemigos: senglar (patrulla y embiste) y ratpenat (vuelo ondulado). Datos de combate por tipo.
local Collision = require('src.world.collision')

local Enemy = {}
Enemy.__index = Enemy

Enemy.KINDS = {
  boar = { hp = 3, speed = 26, chase = 52, sight = 56, damage = 1, sprite = 'enemy_boar', xp = 25, coins = 3, lvl = 1 },
  bat = { hp = 1, speed = 30, chase = 40, sight = 64, damage = 1, sprite = 'enemy_bat', flying = true, xp = 10, coins = 1 },
  -- fauna salvaje de la montaña (src/systems/fauna.lua); lvl = nivel con el que están pensados (más nivel → algo más de vida)
  fox = { hp = 2, speed = 34, chase = 56, sight = 52, damage = 1, sprite = 'enemy_fox', xp = 14, coins = 1, shy = true, lvl = 1 },
  snake = { hp = 1, speed = 12, chase = 62, sight = 26, damage = 1, sprite = 'enemy_snake', xp = 12, coins = 0, lvl = 2 },
  wolf = { hp = 5, speed = 32, chase = 62, sight = 84, damage = 2, sprite = 'enemy_wolf', xp = 55, coins = 4, lvl = 4 },
  -- versiones de la mazmorra del Castell (más vida y daño)
  boar_dark = { hp = 6, speed = 30, chase = 58, sight = 64, damage = 2, sprite = 'enemy_boar', xp = 45, coins = 6 },
  bat_dark = { hp = 2, speed = 34, chase = 46, sight = 72, damage = 1, sprite = 'enemy_bat', flying = true, xp = 18, coins = 2 },
}

function Enemy.new(obj, sprite)
  local self = setmetatable({}, Enemy)
  local k = Enemy.KINDS[obj.props.kind or 'boar']
  self.kind = k
  self.name = obj.name
  self.room = obj.props.room
  self.sprite = sprite
  self.hp = k.hp + (obj.props.hp_bonus or 0)
  self.body = { x = obj.x, y = obj.y, w = 12, h = 8, level = 0 }
  self.home = { obj.x, obj.y }
  self.patrol = obj.props.patrol or 'h'
  self.range = (obj.props.range or 3) * 16
  self.dir = 1
  self.state = 'patrol'
  self.t = 0
  self.hurt_t = 0
  self.last_hit = -1
  self.knock = { 0, 0 }
  self.facing_left = true
  return self
end

function Enemy:box() return { x = self.body.x - 6, y = self.body.y - 10, w = 12, h = 14 } end

-- dany d'un encanteri o d'un altre projectil (src/systems/projectiles.lua); push: empenta extra (ràfaga)
function Enemy:damage(n, sx, sy, push)
  if self.state == 'dead' then return nil end
  self.last_dmg = n
  self.hp = self.hp - n
  self.hurt_t = 0.25
  self.enraged = true
  local dx, dy = self.body.x - sx, self.body.y - sy
  local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
  local k = push or 140
  self.knock = { dx / len * k, dy / len * k }
  if self.hp <= 0 then
    self.state = 'dead'
    self.t = 0
    return 'dead'
  end
  return 'hit'
end

local function overlap(a, b)
  return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end
Enemy.overlap = overlap

-- ctx: { map, blockers, player, sfx, state, items }
function Enemy:update(dt, ctx)
  if self.state == 'dead' then
    self.t = self.t + dt
    return
  end
  self.t = self.t + dt
  local p = ctx.player
  local hit_now = false
  -- recibir golpe de espada: un único daño por identificador de ataque
  local hb, id, weapon = p:attack_box()
  if hb and id ~= self.last_hit and overlap(hb, self:box()) then
    self.last_hit = id
    -- el ataque total (nivel, fuerza y equipo) multiplica el daño del arma (src/systems/rpg.lua)
    self.last_dmg = ctx.state and ctx.items and require('src.systems.rpg').damage_dealt(ctx.state, ctx.items, weapon)
                    or weapon.damage
    self.hp = self.hp - self.last_dmg
    self.hurt_t = 0.25
    self.enraged = true
    local dx, dy = self.body.x - p.body.x, self.body.y - p.body.y
    local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
    self.knock = { dx / len * 140, dy / len * 140 }
    if ctx.sfx then ctx.sfx('hit') end
    if self.hp <= 0 then
      self.state = 'dead'
      self.t = 0
      return 'dead'
    end
    hit_now = true
  end
  if (self.frozen_t or 0) > 0 then   -- congelat (Raig de gel): ni es mou ni mossega
    self.frozen_t = self.frozen_t - dt
    return hit_now and 'hit' or nil
  end
  if self.hurt_t > 0 then
    self.hurt_t = self.hurt_t - dt
    Collision.move(self.body, self.knock[1] * dt, self.knock[2] * dt, ctx.map, ctx.blockers)
    self.knock[1], self.knock[2] = self.knock[1] * 0.8, self.knock[2] * 0.8
    return hit_now and 'hit' or nil
  end
  local dx, dy = p.body.x - self.body.x, p.body.y - self.body.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local k = self.kind
  local vx, vy = 0, 0
  -- (dist > 0.5: encima del jugador la dirección no está definida; antes daba NaN y el enemigo se quedaba
  -- congelado sobre el jugador, pegándole sin parar)
  if dist < k.sight and dist > 0.5 and p.state ~= 'dead' then
    -- los tímidos (zorro) huyen del jugador y solo muerden si los hieren (enraged)
    local sgn = (k.shy and not self.enraged) and -1 or 1
    self.state = sgn < 0 and 'flee' or 'chase'
    vx, vy = sgn * dx / dist * k.chase, sgn * dy / dist * k.chase
  else
    self.state = 'patrol'
    if self.patrol == 'h' then
      vx = self.dir * k.speed
      if (self.body.x - self.home[1]) * self.dir > self.range then self.dir = -self.dir end
    else
      vy = self.dir * k.speed
      if (self.body.y - self.home[2]) * self.dir > self.range then self.dir = -self.dir end
    end
    if k.flying then vy = vy + math.sin(self.t * 4) * 18 end
  end
  if vx ~= 0 then self.facing_left = vx < 0 end
  local mx, my = Collision.move(self.body, vx * dt, vy * dt, ctx.map, ctx.blockers)
  if self.state == 'patrol' and ((vx ~= 0 and not mx) or (self.patrol == 'v' and vy ~= 0 and not my)) then
    self.dir = -self.dir
  end
  -- daño por contacto (un tímido que huye no muerde)
  if self.state ~= 'flee' and overlap(self:box(), p:hurtbox()) then
    local hurt, why = p:hit(k.damage, self.body.x, self.body.y, ctx)
    if why == 'blocked' then
      self.hurt_t = 0.2
      self.knock = { -dx / math.max(dist, 1) * 120, -dy / math.max(dist, 1) * 120 }
    end
  end
end

function Enemy:draw(sheet, quads, ox, oy)
  if self.state == 'dead' then return end   -- la nube de polvo la pone world_scene
  local f = math.floor(self.t * ((self.state == 'chase' or self.state == 'flee') and 10 or 6)) % 2 + 1
  if not require('src.motion').reduced and self.hurt_t > 0 and math.floor(self.hurt_t * 12) % 2 == 0 then f = f + 2 end
  local x = math.floor(self.body.x + 0.5) - ox
  local y = math.floor(self.body.y + 4 - 16 + 0.5) - oy
  local sx = self.facing_left and 1 or -1
  local motion=require('src.motion')
  local lift=self.kind.flying and motion.bob(self.t*7,2) or 0
  local squash=(not motion.reduced and self.hurt_t>0) and .88 or 1
  local frozen = (self.frozen_t or 0) > 0
  if frozen then love.graphics.setColor(0.62, 0.86, 1, 1) end   -- congelat: blavós i quiet
  love.graphics.draw(sheet, quads[frozen and 1 or f], x, y+16-lift, 0, sx, squash, 8, 16)
  if frozen then love.graphics.setColor(1, 1, 1, 1) end
end

return Enemy
