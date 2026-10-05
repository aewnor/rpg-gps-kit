-- NPC: diálogo y paseo sencillo alrededor de su punto (sin pathfinding).
local Collision = require('src.world.collision')

local NPC = {}
NPC.__index = NPC

local DIRS = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local ROW = { down = 0, up = 1, left = 2, right = 3 }

function NPC.new(obj, sprite, seed)
  local self = setmetatable({}, NPC)
  self.name = obj.name
  self.props = obj.props
  self.home = { obj.x, obj.y }
  self.body = { x = obj.x, y = obj.y, w = 10, h = 8, level = 0 }
  self.facing = obj.props.facing or 'down'
  self.base_facing = self.facing
  self.sprite = sprite
  self.wander = (obj.props.wander or 0) * 16
  self.rng = love.math.newRandomGenerator(seed or 1)
  self.timer = self.rng:random() * 2
  self.blink_off = self.rng:random() * 3.7
  self.walk = nil
  self.anim = 0
  self.t = 0
  self.blocker = { x = 0, y = 0, w = 12, h = 10 }
  self.body.self_blocker = self.blocker
  self:sync_blocker()
  return self
end

function NPC:sync_blocker()
  self.blocker.x = self.body.x - 6
  self.blocker.y = self.body.y - 5
end

-- Clients amb carro: recorren el seu passadís i s'aturen a mirar els productes.
function NPC:update_cart(dt, ctx, talking, near)
  self.walk = nil
  if talking or near then return end
  self.timer = self.timer - dt
  if self.timer > 0 then return end
  local route = self.props.route
  self.route_index = self.route_index or 1
  local point = route[self.route_index]
  local tx, ty = point[1] * 16 + 8, point[2] * 16 + 8
  local dx, dy = tx - self.body.x, ty - self.body.y
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance < .5 then
    self.route_index = self.route_index % #route + 1
    self.timer = 1.2 + self.rng:random() * 1.8
    return
  end
  self:face(tx, ty)
  self.cart_facing = self.facing
  local step = math.min(distance, 18 * dt)
  local mx, my = dx / distance * step, dy / distance * step
  local d = DIRS[self.cart_facing]
  local cart = { x = self.body.x + d[1] * 11, y = self.body.y + d[2] * 11,
    w = 10, h = 10, level = 0, self_blocker = self.blocker }
  if not Collision.fits(cart, cart.x + mx, cart.y + my, ctx.map, ctx.blockers) then return end
  local bx, by = self.body.x, self.body.y
  Collision.move(self.body, mx, my, ctx.map, ctx.blockers)
  local travel = math.sqrt((self.body.x - bx)^2 + (self.body.y - by)^2)
  if travel > .001 then self.walk = self.facing; self.anim = self.anim + travel / 48 end
  self:sync_blocker()
end

-- Carro pixel art amb dues variants, orientat en el sentit de la marxa.
function NPC:draw_cart(ox, oy)
  local d = DIRS[self.cart_facing or self.base_facing]
  local x = math.floor(self.body.x + d[1] * 11) - ox
  local y = math.floor(self.body.y + d[2] * 11) - oy
  local g = love.graphics
  local r, green, b, a = g.getColor()
  g.setColor(.12,.15,.19,.3); g.rectangle('fill',x-6,y+2,13,5)
  g.setColor(.18,.23,.27,1)
  for _,wx in ipairs({-5,4}) do g.rectangle('fill',x+wx,y+3,2,3) end
  g.setColor(.62,.69,.71,1); g.rectangle('fill',x-6,y-6,12,10)
  g.setColor(.29,.36,.39,1); g.rectangle('fill',x-5,y-5,10,7)
  if self.props.cart == 'flatbed' then
    g.setColor(.69,.48,.23,1);g.rectangle('fill',x-5,y-4,10,5)
    g.setColor(.9,.74,.44,1);g.rectangle('fill',x-4,y-7,3,8)
    g.setColor(.34,.62,.35,1);g.rectangle('fill',x,y-5,4,5)
  else
    g.setColor(.8,.29,.2,1);g.rectangle('fill',x-4,y-4,3,3)
    g.setColor(.4,.66,.28,1);g.rectangle('fill',x,y-3,3,4)
    if self.props.cart_load ~= 0 then
      g.setColor(.92,.8,.44,1);g.rectangle('fill',x-3,y-1,3,3)
    end
    g.setColor(.72,.79,.8,1)
    for v=-3,3,3 do g.rectangle('fill',x+v,y-4,1,7) end
  end
  g.setColor(.19,.51,.43,1)
  if d[1] ~= 0 then g.rectangle('fill',x-d[1]*8,y-5,2,8)
  else g.rectangle('fill',x-5,y-d[2]*8,10,2) end
  g.setColor(r,green,b,a)
end

function NPC:update(dt, ctx, talking)
  self.t = self.t + dt
  local p = ctx.player
  local near = p and (p.body.x - self.body.x) ^ 2 + (p.body.y - self.body.y) ^ 2 < 40 ^ 2
  if self.props.cart and self.props.route then self:update_cart(dt, ctx, talking, near); return end
  if talking or self.wander == 0 or near then
    self.walk = nil
    -- miran al jugador cuando se acerca (y vuelven a su postura cuando se va)
    if not talking then
      local was_near = self.was_near
      self.was_near = near
      if near and (p.body.x - self.body.x) ^ 2 + (p.body.y - self.body.y) ^ 2 < 30 ^ 2 then self:face(p.body.x, p.body.y)
      elseif not near then
        if was_near then self.facing, self.glance = self.base_facing, nil end
        -- els que no es mouen, de tant en tant miren a banda i banda (semblen vius, no estàtues)
        self.glance = (self.glance or (3 + self.rng:random() * 5)) - dt
        if self.glance <= 0 then
          if self.facing == self.base_facing then
            local side = { down = { 'left', 'right' }, up = { 'left', 'right' }, left = { 'down', 'up' }, right = { 'down', 'up' } }
            local opts = side[self.base_facing] or { 'left', 'right' }
            self.facing = opts[self.rng:random(1, 2)]
            self.glance = 0.8 + self.rng:random() * 0.8
          else
            self.facing = self.base_facing
            self.glance = 3 + self.rng:random() * 6
          end
        end
      end
    end
    return
  end
  self.timer = self.timer - dt
  if self.walk then
    local d = DIRS[self.walk]
    local nx, ny = self.body.x + d[1] * 24 * dt, self.body.y + d[2] * 24 * dt
    if math.abs(nx - self.home[1]) > self.wander or math.abs(ny - self.home[2]) > self.wander then
      self.walk = nil
    else
      local bx,by=self.body.x,self.body.y
      local mx, my = Collision.move(self.body, d[1] * 24 * dt, d[2] * 24 * dt, ctx.map, ctx.blockers)
      if not (mx or my) then self.walk = nil end
      self.anim = self.anim + math.sqrt((self.body.x-bx)^2+(self.body.y-by)^2)/48
    end
    self:sync_blocker()
    if self.timer <= 0 then self.walk = nil; self.timer = 1 + self.rng:random() * 2 end
  elseif self.timer <= 0 then
    local dirs = { 'down', 'up', 'left', 'right' }
    self.walk = dirs[self.rng:random(1, 4)]
    self.diag = nil
    self.facing = self.walk
    self.timer = 0.5 + self.rng:random()
  end
end

function NPC:face(px, py)
  local dx, dy = px - self.body.x, py - self.body.y
  if math.abs(dx) > math.abs(dy) then self.facing = dx > 0 and 'right' or 'left'
  else self.facing = dy > 0 and 'down' or 'up' end
end

function NPC:draw(sprites, ox, oy)
  local cart_back = (self.cart_facing or self.base_facing) == 'up'
  if self.props.cart and cart_back then self:draw_cart(ox, oy) end
  local row = ROW[self.facing]
  if self.walk and self.diag and self.sprite.diag then row = require('src.paperdoll.diag').ROW[self.diag] end
  -- caminar (4 pasos) o reposo con parpadeo de vez en cuando (desfasado por personaje)
  local col = self.walk and (math.floor(self.anim * 6) % 4) or
      (((self.t + self.blink_off) % 3.7) < 0.13 and 5 or 4)
  local x = math.floor(self.body.x - 8 + 0.5) - ox
  local height = self.sprite.height or 24
  local y = math.floor(self.body.y + 4 - height + 0.5) - oy
  local breathe=not self.walk and require('src.motion').bob((self.t+self.blink_off)*1.7,.55) or 0
  local flip = self.sprite.side_facing and self.facing == 'right'
  love.graphics.draw(self.sprite.sheet, self.sprite.quad(row, col), x + (flip and 16 or 0), y+height,
    0, flip and -1 or 1, (height-breathe)/height, 0, height)
  if self.props.cart and not cart_back then self:draw_cart(ox, oy) end
end

return NPC
