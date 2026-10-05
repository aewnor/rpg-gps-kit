-- Amics que t'acompanyen (2026-10-05). Un pas de missió amb `join = "<id amic>"` fa que aquell amic del perfil et
-- segueixi (també dins de coves i masmorres) fins a un pas amb `leave = true` o fins que s'acaba la missió.
-- Mentre et segueix t'ajuda:
--   · llança pedretes als enemics a prop (1 de mal; compta per als passos `event` ally_help / ally_help_3)
--   · si et queda poca vida, et posa una tireta (+2 mitjos cors, cada 40 s)
--   · nota els cofres amagats a prop i t'avisa amb un «!» (obrir-lo dispara l'esdeveniment ally_found); si
--     cal trobar un tresor i després d'una bona passejada no n'hi ha cap, en desenterra un de monedes
-- Estat desat: state.companion = { id, mission, helps }. Es dibuixa amb src/entities/follower.lua (com l'Olaf).
local C = {}

C.ASSIST_EVERY = 1.3     -- s entre pedretes
C.RANGE = 84             -- px des de l'amic fins a l'enemic
C.HEAL_EVERY = 40
C.SENSE = 6 * 16         -- px: cofres que nota
C.DIG_AFTER = 1600       -- px caminats junts sense cap cofre → en desenterra un (≈ 100 caselles)

local SAYS = { 'Som un gran equip!', 'On anem ara?', 'Quina aventura més xula!', 'Jo vigilo l\'esquena!',
               'Si veig alguna cosa amagada, t\'aviso.' }

local function entry(g, id)
  for _, fr in ipairs(g.friends or {}) do if fr.def and fr.def.id == id then return fr end end
end

-- crea el seguidor a l'escena (World.new i en unir-se)
function C.attach(w)
  local c = w.state.companion
  w.companion = nil
  if not c then return end
  local g = w.game
  local fr = entry(g, c.id)
  local spr = fr and g.sprites.chars[fr.sprite]
  if not spr then return end
  local f = require('src.entities.follower').new(fr.def.name, spr, w.player.body.x, w.player.body.y, 34)
  local map = w.map
  local Collision = require('src.world.collision')
  f.walkable = function(x, y)
    local tx, ty = math.floor(x / 16), math.floor(y / 16)
    return map:in_bounds(tx, ty) and Collision.walk_at(map:cell(tx, ty), 0)
  end
  f:place(w.player.body.x, w.player.body.y, w.player.facing)
  f.diag_ok = true                                   -- persona: també camina en diagonal
  w.companion = { f = f, name = fr.def.name, id = c.id, t = 1, heal_t = 0, stones = {}, pointed = {}, point = nil }
end

function C.join(w, id, mission)
  w.state.companion = { id = id, mission = mission, helps = 0 }
  C.attach(w)
  local cp = w.companion
  if cp then
    w.hud:toast(cp.name .. ' s\'uneix a l\'aventura!', 2.5)
    w.fx:preset('sparkle', cp.f.x, cp.f.y - 14, 8)
  end
end

function C.leave(w)
  local cp = w.companion
  if cp then w.hud:toast(cp.name .. ' torna cap a casa. Fins aviat!', 2.5) end
  w.state.companion = nil
  w.companion = nil
end

-- l'amic ha ajudat: per als passos `event` de les missions
local function helped(w)
  local c = w.state.companion
  if not c then return end
  c.helps = (c.helps or 0) + 1
  local Town = require('src.systems.town')
  Town.event(w, 'event', { name = 'ally_help' })
  if c.helps >= 3 then Town.event(w, 'event', { name = 'ally_help_3' }) end
end

function C.update(w, dt)
  local cp = w.companion
  if not cp then return end
  local st, pl = w.state, w.player
  local v = pl.vehicle
  cp.f:update(dt, pl.body.x, pl.body.y, v and 14 or 0)
  local fx, fy = cp.f.x, cp.f.y
  -- pedretes en vol
  for i = #cp.stones, 1, -1 do
    local s = cp.stones[i]
    s.t = s.t + dt
    if s.t >= s.dur then
      table.remove(cp.stones, i)
      local e = s.e
      if e.state ~= 'dead' then
        local res = e:damage(1, s.x0, s.y0, 90)
        w.fx:preset('sparkle', e.body.x, e.body.y - 8, 4)
        w:enemy_event(e, res == 'dead' and 'dead' or 'hit')
        helped(w)
      end
    end
  end
  -- llançar: l'enemic viu més proper a l'amic
  cp.t = cp.t - dt
  if cp.t <= 0 and not v then
    local best, bd
    for _, e in ipairs(w.enemies or {}) do
      if e.state ~= 'dead' and e.damage and not (e.kind and e.kind.boss) then
        local d = (e.body.x - fx) ^ 2 + (e.body.y - fy) ^ 2
        if d < C.RANGE * C.RANGE and (not bd or d < bd) then best, bd = e, d end
      end
    end
    if best then
      cp.t = C.ASSIST_EVERY
      cp.stones[#cp.stones + 1] = { e = best, x0 = fx, y0 = fy - 10, t = 0, dur = 0.3 }
      w.game.audio.play('swing')
      if math.abs(best.body.x - fx) > math.abs(best.body.y - fy) then cp.f.facing = best.body.x > fx and 'right' or 'left'
      else cp.f.facing = best.body.y > fy and 'down' or 'up' end
    else
      cp.t = 0.3
    end
  end
  -- tireta quan et queda poca vida
  cp.heal_t = math.max(0, cp.heal_t - dt)
  if cp.heal_t <= 0 and (st.hp or 0) > 0 and (st.hp or 0) <= math.max(2, (st.max_hp or 6) * 0.35) then
    cp.heal_t = C.HEAL_EVERY
    st.hp = math.min(st.max_hp or 6, st.hp + 2)
    w.hud:toast(cp.name .. ' et posa una tireta: +1 cor', 2.5)
    w.fx:preset('sparkle', pl.body.x, pl.body.y - 14, 6, { color = { 1, 0.6, 0.7 }, speed = 14 })
    w.game.audio.play('good')
  end
  -- cofres amagats a prop
  if cp.point then
    cp.point.t = cp.point.t - dt
    if cp.point.t <= 0 then cp.point = nil end
  end
  -- caçadors de tresors: si en una bona passejada no troben cap cofre, l'amic en desenterra un
  local Town = require('src.systems.town')
  local _, step = require('src.systems.missions').current(Town.defs(w.game), st)
  if step and step.type == 'event' and step.event == 'ally_found' then
    local lx, ly = cp.last_x or pl.body.x, cp.last_y or pl.body.y
    cp.walked = (cp.walked or 0) + math.min(8, math.sqrt((pl.body.x - lx) ^ 2 + (pl.body.y - ly) ^ 2))
    if cp.walked > C.DIG_AFTER and not cp.point then
      cp.walked = 0
      require('src.systems.rpg').earn(st, 8)
      w:popup('+8 mon.', 'coins')
      w.fx:preset('sparkle', fx, fy - 4, 10)
      w.game.audio.play('levelup')
      w.hud:toast(cp.name .. ': Aquí sota hi ha alguna cosa... Un tresor de monedes!', 3, true)
      Town.event(w, 'event', { name = 'ally_found' })
    end
  end
  cp.last_x, cp.last_y = pl.body.x, pl.body.y
  for _, c in ipairs(w.chests or {}) do
    local key = c.obj.props.flag
    if key and not cp.pointed[key] and not w.sstate.chests[key] then
      local cx, cy = c.rect.x + 8, c.rect.y + 8
      if (cx - fx) ^ 2 + (cy - fy) ^ 2 < C.SENSE * C.SENSE then
        cp.pointed[key] = true
        cp.point = { t = 4, x = cx, y = cy }
        w.hud:toast(cp.name .. ': Mira! Allà hi ha un cofre!', 3, true)
      end
    end
  end
end

-- s'ha obert un cofre: si l'havia trobat l'amic, compta
function C.on_chest(w, key)
  local cp = w.companion
  if cp and cp.pointed[key] then require('src.systems.town').event(w, 'event', { name = 'ally_found' }) end
end

function C.near(w, x, y, r)
  local cp = w.companion
  return cp and (cp.f.x - x) ^ 2 + (cp.f.y - 2 - y) ^ 2 < (r or 12) ^ 2
end

function C.talk(w)
  local cp = w.companion
  w.dialogue:show(cp.name, { SAYS[love.math.random(#SAYS)] })
end

-- add(y, fn): ordre de dibuix del món
function C.draw(w, add, ox, oy, shadow)
  local cp = w.companion
  if not cp then return end
  local pl = w.player
  if pl.vehicle and pl.vehicle.id == 'cotxe' then return end   -- en cotxe va a dins
  local f = cp.f
  add(f.y + 3.95, function()
    if shadow then shadow(f.x - ox, f.y + 3 - oy, 6, 2.2); love.graphics.setColor(1, 1, 1, 1) end
    f:draw(ox, oy)
    if cp.point and math.floor(cp.point.t * 4) % 2 == 0 then
      local x, y = math.floor(f.x - ox), math.floor(f.y - 30 - oy)
      love.graphics.setColor(1, 1, 1); love.graphics.rectangle('fill', x - 3, y - 6, 7, 10)
      love.graphics.setColor(0.85, 0.2, 0.2); love.graphics.rectangle('fill', x - 1, y - 4, 3, 4)
      love.graphics.rectangle('fill', x - 1, y + 1, 3, 2)
      love.graphics.setColor(1, 1, 1)
    end
  end)
  for _, s in ipairs(cp.stones) do
    local k = s.t / s.dur
    local x = s.x0 + (s.e.body.x - s.x0) * k
    local y = s.y0 + (s.e.body.y - 8 - s.y0) * k - math.sin(k * math.pi) * 10
    add(y + 20, function()
      love.graphics.setColor(0.45, 0.42, 0.40); love.graphics.rectangle('fill', math.floor(x - ox) - 1, math.floor(y - oy) - 1, 3, 3)
      love.graphics.setColor(1, 1, 1)
    end)
  end
end

return C
