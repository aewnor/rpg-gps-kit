-- Protagonista: locomoción en 8 direcciones (sprite en 4), orientación, interacción y combate (fase 2).
local Collision = require('src.world.collision')

local Player = {}
local HANDS = { name = 'Mans', damage = 1, reach = 9, windup = 0.06, active = 0.08, recovery = 0.16, stamina_cost = 6 }
Player.__index = Player

local DIRS = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local ROW = { down = 0, up = 1, left = 2, right = 3 }
Player.DIRS = DIRS

function Player.new(x, y, level, cfg, sprite)
  local self = setmetatable({}, Player)
  self.body = { x = x, y = y, w = cfg.collider[1], h = cfg.collider[2], level = level or 0 }
  self.speed = cfg.speed
  self.facing = 'down'
  self.state = 'idle'
  self.t = 0
  self.anim = 0
  self.moving = false
  self.sprite = sprite
  self.stamina = cfg.stamina
  self.max_stamina = cfg.stamina
  self.stamina_regen = cfg.stamina_regen
  self.invuln = 0
  self.knock = { 0, 0 }
  self.attack_id = 0
  self.block_exhausted = false
  return self
end

-- dirección pedida (8 direcciones). La orientación del sprite sigue siendo una de las 4: se conserva la
-- actual si sigue pulsada; si no, manda el eje horizontal.
local function wanted_dir(self, act)
  local h = (act.right and 1 or 0) - (act.left and 1 or 0)
  local v = (act.down and 1 or 0) - (act.up and 1 or 0)
  if h == 0 and v == 0 then return nil end
  local face
  local cur = DIRS[self.facing]
  if cur[1] ~= 0 and cur[1] == h then face = self.facing
  elseif cur[2] ~= 0 and cur[2] == v then face = self.facing
  elseif h ~= 0 then face = h > 0 and 'right' or 'left'
  else face = v > 0 and 'down' or 'up' end
  return face, h, v
end

function Player:weapon(ctx) return ctx.state.equipment.weapon and ctx.items[ctx.state.equipment.weapon] end
function Player:shield(ctx) return ctx.state.equipment.shield and ctx.items[ctx.state.equipment.shield] end

-- ctx: { map, blockers, state, items, sfx }
function Player:update(dt, act, ctx)
  self.move_intent = false
  self.invuln = math.max(0, self.invuln - dt)
  self.t = self.t + dt
  if self.in_boat then return end   -- a la barca d'en Toni la mou src/systems/boat.lua
  self.blink_t = (self.blink_t or 0) + dt
  if (self.block_flash or 0) > 0 then self.block_flash = self.block_flash - dt end
  local pressed = act.pressed or {}

  if self.state == 'dead' then return end

  if self.state == 'hurt' then
    Collision.move(self.body, self.knock[1] * dt, self.knock[2] * dt, ctx.map, ctx.blockers)
    self.knock[1], self.knock[2] = self.knock[1] * 0.85, self.knock[2] * 0.85
    if self.t > 0.2 then self.state = 'idle'; self.t = 0 end
    return
  end

  local weapon = self:weapon(ctx)
  if self.state == 'attack' then
    -- es pot atacar caminant: més a poc a poc i sense girar-se (el cop va cap on mirava)
    if not self.vehicle then self:walk_step(act, ctx, dt, 0.8, true) end
    local w = self.attack_weapon
    if self.t >= w.windup + w.active + w.recovery then
      self.state = self.moving and 'walk' or 'idle'; self.t = 0
    end
    return
  end

  -- energía: se regenera si no se bloquea
  local shield = self:shield(ctx)
  local blocking = act.shield and shield and not self.block_exhausted and self.stamina > 0
  if blocking then
    self.stamina = math.max(0, self.stamina - shield.stamina_drain * dt)
    if self.stamina <= 0 then self.block_exhausted = true end
  else
    self.stamina = math.min(self.max_stamina, self.stamina + self.stamina_regen * dt)
    if self.block_exhausted and self.stamina >= 25 then self.block_exhausted = false end
  end

  if (pressed.attack or act.shield) and self.bike then self.bike = false end
  -- sense espasa (encara no has parlat amb l'Anna, l'agent forestal): una empenta amb les mans
  if pressed.attack and not weapon and not self.vehicle then
    weapon = HANDS
    if ctx.toast and not self.hands_told then
      self.hands_told = true
      ctx.toast('Sense espasa només pots empènyer. L\'Anna, l\'agent forestal, te\'n pot donar una.')
    end
  end
  if pressed.attack and weapon and self.stamina < weapon.stamina_cost and ctx.toast then ctx.toast('Estàs cansat: espera un moment', 1) end
  if pressed.attack and weapon and self.stamina >= weapon.stamina_cost then
    self.state = 'attack'
    self.t = 0
    self.attack_weapon = weapon
    self.attack_id = self.attack_id + 1
    self.stamina = self.stamina - weapon.stamina_cost
    if ctx.sfx then ctx.sfx('swing') end
    return
  end

  -- vehículo (src/systems/vehicles.lua): solo al aire libre; atacar o protegerse obliga a bajar
  if pressed.bike and ctx.outdoor then
    if self.vehicle then self:dismount()
    else
      local Vehicles = require('src.systems.vehicles')
      local id = ctx.state.vehicle or 'bici'
      local def = Vehicles.CATALOG[id]
      if def and (def.min_level or 1) > (ctx.state.char_level or 1) then
        if ctx.toast then ctx.toast('Requereix nivell ' .. def.min_level) end
      elseif def and (ctx.state.vehicles or { bici = true })[id] then
        self.vehicle = Vehicles.new_state(id, self.facing)
        self.body.no_stairs = true
      end
    end
    self.bike = self.vehicle ~= nil
    if ctx.sfx then ctx.sfx('confirm') end
  end
  if not ctx.outdoor or not self.bike then self:dismount() end
  local dir, h, v = wanted_dir(self, act)
  self.moving = false
  if self.vehicle then
    local Vehicles = require('src.systems.vehicles')
    local moved, bumped = Vehicles.update(self.vehicle, self.body, h or 0, v or 0, dt, ctx.map, ctx.blockers,
      1 + (ctx.state.train and ctx.state.train.agility or 0) * 0.02)
    self.moving = moved
    self.facing = Vehicles.facing(self.vehicle.angle)
    if moved then self.anim = self.anim + dt * math.min(2, self.vehicle.speed / 64) end
    if bumped and ctx.sfx then ctx.sfx('block') end
    self.state = self.moving and 'walk' or 'idle'
    return
  end
  self:walk_step(act, ctx, dt, blocking and 0.5 or 1, blocking)
  self.block_t = blocking and (self.block_t or 0) + dt or 0
  self.state = blocking and 'block' or (self.moving and 'walk' or 'idle')
end

-- un pas a peu: `k` multiplica la velocitat; amb `keep_facing` no es gira (protegint-se o atacant)
function Player:walk_step(act, ctx, dt, k, keep_facing)
  local dir, h, v = wanted_dir(self, act)
  self.moving = false
  if dir then
    self.move_intent = true
    if not keep_facing then self.facing = dir end
    self.diag = not keep_facing and require('src.paperdoll.diag').of(h, v) or nil   -- vista en diagonal
    -- agilidad (gimnàs): +2 % de velocidad por punto
    local agi = 1 + (ctx.state.train and ctx.state.train.agility or 0) * 0.02
    local sp = self.speed * k * agi * (self.swimming and 0.6 or 1)   -- nedant, més a poc a poc
    local kd = (h ~= 0 and v ~= 0) and 0.7071 or 1  -- en diagonal, misma velocidad
    local dx, dy = h * kd * sp * dt, v * kd * sp * dt
    local bx, by = self.body.x, self.body.y
    local mx, my = Collision.move(self.body, dx, dy, ctx.map, ctx.blockers)
    if (dx ~= 0 and not mx) or (dy ~= 0 and not my) then
      local ax, ay = Collision.slide_assist(self.body, dx, dy, ctx.map, ctx.blockers)
      if ax ~= 0 or ay ~= 0 then Collision.move(self.body, ax, ay, ctx.map, ctx.blockers) end
    end
    local distance=math.sqrt((self.body.x-bx)^2+(self.body.y-by)^2)
    self.moving = distance > .001
    self.anim = self.anim + distance/64
  else
    self.anim = 0
  end
end

function Player:dismount()
  self.vehicle = nil
  self.bike = false
  self.body.no_stairs = nil
end

-- caja de daño del ataque activo (o nil)
function Player:attack_box()
  if self.state ~= 'attack' then return nil end
  local w = self.attack_weapon
  if self.t < w.windup or self.t > w.windup + w.active then return nil end
  local x, y = self.body.x, self.body.y - 6
  local r = w.reach
  if self.facing == 'right' then return { x = x + 3, y = y - 8, w = r, h = 16 }, self.attack_id, w end
  if self.facing == 'left' then return { x = x - 3 - r, y = y - 8, w = r, h = 16 }, self.attack_id, w end
  if self.facing == 'down' then return { x = x - 8, y = y + 2, w = 16, h = r }, self.attack_id, w end
  -- cap amunt també toca el que està enganxat (com els altres costats, que comencen a 2-3 px del centre)
  return { x = x - 8, y = y - 10 - r, w = 16, h = r + 8 }, self.attack_id, w
end

function Player:hurtbox()
  return { x = self.body.x - 6, y = self.body.y - 18, w = 12, h = 22 }
end

-- ¿bloquea un golpe que viene desde (sx, sy)? cono frontal de `cone` grados
function Player:blocks_from(sx, sy, shield)
  if self.state ~= 'block' or not shield then return false end
  local dx, dy = sx - self.body.x, sy - (self.body.y - 6)
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.001 then return true end
  local f = DIRS[self.facing]
  local cos = (dx * f[1] + dy * f[2]) / len
  return cos >= math.cos(math.rad(shield.cone / 2))
end

-- devuelve true si el golpe hizo daño
-- unblockable: golpes que el escudo no para (coches)
function Player:hit(dmg, sx, sy, ctx, unblockable)
  if self.invuln > 0 or self.state == 'dead' then return false end
  if ctx and ctx.state and (ctx.state.ward_t or 0) > 0 then return false, 'ward' end   -- Escut màgic
  local shield = self:shield(ctx)
  local dx, dy = self.body.x - sx, self.body.y - sy
  local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
  if not unblockable and self:blocks_from(sx, sy, shield) and self.stamina >= shield.stamina_per_hit * 0.5 then
    self.stamina = math.max(0, self.stamina - shield.stamina_per_hit)
    if self.stamina <= 0 then self.block_exhausted = true end
    self.block_flash = 0.2
    Collision.move(self.body, dx / len * 6, dy / len * 6, ctx.map, ctx.blockers)
    if ctx.sfx then ctx.sfx('block') end
    return false, 'blocked'
  end
  dmg = require('src.systems.rpg').damage_taken(ctx.state, ctx.items, dmg)   -- la defensa resta
  ctx.state.hp = math.max(0, ctx.state.hp - dmg)
  self.invuln = unblockable and 1.2 or 0.6
  self.knock = { dx / len * 160, dy / len * 160 }
  self.state = ctx.state.hp <= 0 and 'dead' or 'hurt'
  self.t = 0
  if ctx.sfx then ctx.sfx('hurt') end
  return true
end

-- parpadeo: columna 5 de la hoja durante un instante cada pocos segundos (tools/chars.py)
local BLINK_EVERY, BLINK_LEN = 3.3, 0.13

-- sprites: la fulla on es dibuixarà; si té files en diagonal (src/paperdoll/diag.lua) i camina en diagonal, les fa servir
function Player:frame(sprites)
  local row = ROW[self.facing]
  if self.diag and self.moving and not self.vehicle and sprites and sprites.diag then
    row = require('src.paperdoll.diag').ROW[self.diag]
  end
  local col
  if self.state == 'walk' or self.state == 'block' and self.moving then
    col = math.floor(self.anim * 8) % 4
  else
    col = (self.blink_t or 0) % BLINK_EVERY < BLINK_LEN and 5 or 4
  end
  return row, col
end

-- paso con apoyo (columnas 0 y 2 del ciclo): el juego levanta polvo en ese instante
function Player:step_frame()
  if not self.moving then return nil end
  local col = self.bike and math.floor(self.anim * 8) % 2 * 2 or math.floor(self.anim * 8) % 4
  return col
end

local DIR_INDEX = { down = 0, up = 1, left = 2, right = 3 }

-- fila diagonal del vehicle segons el rumb (0 avall-esquerra, 1 avall-dreta, 2 amunt-esquerra, 3 amunt-dreta) o nil
-- si va gairebé recte (a menys de 22,5° d'una direcció principal)
function Player.vehicle_diag(angle)
  local a = (angle or 0) % (2 * math.pi)
  local oct = math.floor((a + math.pi / 8) / (math.pi / 4)) % 8   -- 0 dreta, 1 avall-dreta, 2 avall, 3 avall-esquerra…
  return ({ [1] = 1, [3] = 0, [5] = 2, [7] = 3 })[oct]
end
local SLASH_OFF = { down = { 0, 18 }, up = { 0, -10 }, left = { -13, 6 }, right = { 13, 6 } }

-- espurna en parar un cop amb l'escut (block_flash el posa Player:hit)
function Player:draw_block_flash(cx, cy)
  local fl = self.block_flash or 0
  if fl <= 0 then return end
  local a = fl / 0.2
  love.graphics.setColor(1, 1, 0.8, a)
  love.graphics.circle('line', cx, cy, 4 + (1 - a) * 8)
  for i = 0, 5 do
    local an = i * math.pi / 3 + (1 - a)
    love.graphics.rectangle('fill', math.floor(cx + math.cos(an) * (5 + (1 - a) * 9)), math.floor(cy + math.sin(an) * (5 + (1 - a) * 9)), 1, 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Player:draw(sprites, ox, oy)
  if self.in_boat then return end   -- el dibuixa la barca (src/systems/boat.lua)
  if not require('src.motion').reduced and self.invuln > 0 and math.floor(self.invuln * 12) % 2 == 0 then return end
  local x = math.floor(self.body.x - 8 + 0.5) - ox
  local y = math.floor(self.body.y + self.body.h / 2 - 24 + 0.5 - (self.jump_z or 0)) - oy   -- (jump_z: salt)
  local di = DIR_INDEX[self.facing]
  if self.state == 'attack' and self.attack_weapon and sprites.weapon then
    local w=self.attack_weapon
    local motion=require('src.motion')
    local swing=motion.attack(self.t,w)
    local dir=DIRS[self.facing]
    local lunge=motion.reduced and 0 or math.max(0,swing)*2
    love.graphics.draw(sprites.sheet,sprites.quad(ROW[self.facing],4),x+dir[1]*lunge,y+dir[2]*lunge)
    local angle=({down=math.pi,up=0,left=-math.pi/2,right=math.pi/2})[self.facing]+swing
    local hx,hy=x+8+dir[1]*7,y+15+dir[2]*6
    if not motion.reduced and self.t>=w.windup and self.t<w.windup+w.active then
      love.graphics.setColor(w.magic and .45 or 1,.85,1,.45)
      love.graphics.arc('line','open',hx,hy,math.min(16,w.reach),angle-math.pi/2-.8,angle-math.pi/2)
      love.graphics.setColor(1,1,1,1)
    end
    love.graphics.draw(sprites.weapon,hx,hy,angle,1,1,7,14)
    return
  end
  if self.state == 'attack' and self.attack_weapon then
    local w = self.attack_weapon
    local ph = self.t < w.windup and 0 or (self.t < w.windup + w.active and 1 or 2)
    love.graphics.draw(sprites.action, sprites.action_quads[di * 3 + ph + 1], x - 8, y - 6)
    -- estela del golpe (slash.png: abajo, arriba, izquierda, derecha) durante la fase activa y al recuperar
    if sprites.slash and ph >= 1 then
      local k = ph == 1 and 1 or math.max(0, 1 - (self.t - w.windup - w.active) / w.recovery)
      local off = SLASH_OFF[self.facing]
      love.graphics.setColor(1, 1, 1, k)
      love.graphics.draw(sprites.slash, sprites.slash_quads[di + 1], x + off[1], y + off[2])
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end
  if self.state == 'block' and sprites.shield then
    local row,col=self:frame()
    local dir=DIRS[self.facing]
    -- l'escut puja del costat cap al davant en 0,12 s (i fa un petit retrocés en parar un cop)
    local k = require('src.motion').reduced and 1 or math.min(1, (self.block_t or 1) / 0.12)
    k = 1 - (1 - k) * (1 - k)
    local recoil = (self.block_flash or 0) > 0 and 2 or 0
    local sx = x + dir[2] * 6 * (1 - k) + dir[1] * (7 * k - recoil)
    local sy = y + 12 - 4 * k + dir[2] * (4 * k - recoil)
    if self.facing == 'up' then
      love.graphics.draw(sprites.shield, sx, sy)
      love.graphics.draw(sprites.sheet,sprites.quad(row,col),x,y)
    else
      love.graphics.draw(sprites.sheet,sprites.quad(row,col),x,y)
      love.graphics.draw(sprites.shield, sx, sy)
    end
    self:draw_block_flash(sx + 6, sy + 6)
    return
  end
  if self.state == 'block' then
    love.graphics.draw(sprites.action, sprites.action_quads[12 + di + 1], x - 8, y - 7)
    local dir = DIRS[self.facing]
    self:draw_block_flash(x + 8 + dir[1] * 9, y + 14 + dir[2] * 7)
    return
  end
  if self.vehicle then
    local id = self.vehicle.id
    if id == 'cotxe' and sprites.car then   -- en coche: el coche del jugador, orientado en 8 direcciones
      sprites.car(self.body.x, self.body.y, self.vehicle.angle)
      return
    end
    local sh = sprites.vehicles and sprites.vehicles[self.vehicle.skin or id]
    if not sh and id == 'cavall' and sprites.horse then
      -- aspecte sense fulla de genets (partida ràpida): el cavall de la hípica i el personatge assegut a sobre
      local himg = sprites.horse(self.vehicle.skin)
      if himg then
        local left = self.facing == 'left'
        local bob = self.moving and (math.floor(self.anim * 8) % 2) or 0
        -- primer el personatge (més amunt) i després el cavall, que li tapa les cames
        love.graphics.draw(sprites.sheet, sprites.quad(DIR_INDEX[self.facing], 4), x, y - 7 - bob)
        if sprites.helmet then love.graphics.draw(sprites.helmet, sprites.helmet_quads[4 + di + 1], x, y - 7 - bob) end
        love.graphics.draw(himg, x + 8 + (left and 12 or -12), y + 10 - bob, 0, left and -1 or 1, 1)
        return
      end
    end
    local diag_sh = sh and sh.diag or (not sh and sprites.bike_diag) or nil
    sh = sh or { img = sprites.bike, quads = sprites.bike_quads }
    local f = self.moving and (math.floor(self.anim * 8) % 2) or 0
    local ride=self.moving and require('src.motion').bob(self.anim*12,.6) or 0
    -- en diagonal (rumb entre dues direccions), la fulla de tres quarts (src/paperdoll/sheets.lua S.diag)
    local dg = diag_sh and Player.vehicle_diag(self.vehicle.angle)
    if dg then
      local horse = id == 'cavall'
      love.graphics.draw(diag_sh.img, diag_sh.quads[dg * 2 + f + 1], x - 8, y - 4 + ride)
      if sprites.helmet then   -- cap de perfil (avall) o d'esquena (amunt), com el genet
        local hd = dg <= 1 and (dg == 0 and 2 or 3) or 1
        love.graphics.draw(sprites.helmet, sprites.helmet_quads[hd + 1], x + (horse and (dg <= 1 and 1 or 0) or 0),
          y - 4 + ride + (horse and -2 or 2) + (dg >= 2 and 0 or 0))
      end
      return
    end
    love.graphics.draw(sh.img, sh.quads[di * 2 + f + 1], x - 8, y - 4+ride)
    if sprites.helmet then   -- el cap del ciclista és al mateix lloc que el del personatge, desplaçat
      local side = self.facing == 'left' or self.facing == 'right'
      love.graphics.draw(sprites.helmet, sprites.helmet_quads[di + 1], x, y - 4 + ride + (side and 2 or 0) + f * 0)
    end
    return
  end
  local row, col = self:frame(sprites)
  if self.swimming then
    -- a la piscina: només cap i espatlles fora de l'aigua, amb onades al voltant
    local q = sprites.quad(row, col)
    local qx, qy, qw, qh = q:getViewport()
    local sw, sh = sprites.sheet:getDimensions()
    self.swim_quad = self.swim_quad or love.graphics.newQuad(0, 0, 1, 1, sw, sh)
    self.swim_quad:setViewport(qx, qy, qw, 13, sw, sh)
    local bob = require('src.motion').bob(self.anim*6,1)
    love.graphics.draw(sprites.sheet, self.swim_quad, x, y + 8 + bob)
    love.graphics.setColor(0.85, 0.95, 1, 0.8)
    local r = require('src.motion').reduced and 8 or 7 + math.floor((self.anim * 4) % 3)
    love.graphics.ellipse('line', x + 8, y + 21, r, r * 0.35)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local breath=not self.moving and require('src.motion').bob((self.blink_t or 0)*1.7,.55) or 0
  love.graphics.draw(sprites.sheet, sprites.quad(row, col), x, y+24, 0, 1, (24-breath)/24, 0, 24)
end

return Player
