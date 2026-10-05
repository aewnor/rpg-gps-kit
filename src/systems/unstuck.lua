-- Salt per desencallar-se (2026-10-05). Si el jugador queda atrapat (no es pot moure cap a cap costat, o fa estona
-- que empeny sense avançar en un pont, rampa o nivell que no és el del carrer), fa un salt curt fins a la casella
-- lliure més propera que estigui enllaçada amb la resta del món (la mateixa component que el punt d'aparició).
-- També es pot fer a mà des del menú (Accions > Saltar).
local Collision = require('src.world.collision')

local U = { AUTO_ALL = 0.8, AUTO_PUSH = 2.5, RADIUS = 12, DUR = 0.45 }

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- component de referència: la del punt d'aparició públic (a fora) o la de qualsevol punt d'entrada (a dins)
local function main_comp(w)
  local m = w.map
  local names = { w.game.world and w.game.world.start_spawn, 'spawn_in', 'spawn_entrance' }
  for _, n in ipairs(names) do
    local o = n and m:object('spawn', n)
    if o then
      local c = m:component(math.floor(o.x / 16), math.floor(o.y / 16))
      if c and c ~= 0 then return c end
    end
  end
  for _, o in ipairs(m:objects_of('spawn')) do
    local c = m:component(math.floor(o.x / 16), math.floor(o.y / 16))
    if c and c ~= 0 then return c end
  end
end

-- quantes direccions deixen moure's 3 px
function U.free_dirs(w)
  local b = w.player.body
  local n = 0
  for _, d in ipairs(DIRS) do
    if Collision.fits(b, b.x + d[1] * 3, b.y + d[2] * 3, w.map, w.blockers) then n = n + 1 end
  end
  return n
end

-- casella on aterrar: la més propera (amb preferència per la direcció dx, dy) transitable a nivell 0, de la
-- component principal i on hi cap el cos. Torna x, y en píxels (centre) o nil.
function U.find(w, dx, dy)
  local b, m = w.player.body, w.map
  local comp = main_comp(w)
  local tx0, ty0 = math.floor(b.x / 16), math.floor(b.y / 16)
  local best, bs
  local probe = { x = 0, y = 0, w = b.w, h = b.h, level = 0 }
  for r = 1, U.RADIUS do
    for ty = ty0 - r, ty0 + r do
      for tx = tx0 - r, tx0 + r do
        if math.max(math.abs(tx - tx0), math.abs(ty - ty0)) == r and m:in_bounds(tx, ty) then
          local code = m:cell(tx, ty)
          if Collision.walk_at(code, 0) and (not comp or m:component(tx, ty) == comp) then
            probe.x, probe.y = tx * 16 + 8, ty * 16 + 8
            if Collision.fits(probe, probe.x, probe.y, m, w.blockers) then
              local ddx, ddy = tx - tx0, ty - ty0
              local dist = math.sqrt(ddx * ddx + ddy * ddy)
              -- cap on empenyies: fins a 2 caselles de premi; enrere, penalització
              local along = (dx or 0) * ddx + (dy or 0) * ddy
              local score = dist - (along > 0 and math.min(2, along * 0.6) or 0) + (along < 0 and 1.5 or 0)
              if not bs or score < bs then best, bs = { probe.x, probe.y }, score end
            end
          end
        end
      end
    end
    if best and r >= 2 then break end   -- ja n'hi ha a prop (es mira un anell més per triar la direcció)
  end
  if best then return best[1], best[2] end
end

function U.jump(w, dx, dy)
  local p = w.player
  if p.jump then return true end
  local x, y = U.find(w, dx, dy)
  if not x then
    w.hud:toast('No trobo cap lloc per saltar. Prova el Mapa > Viatjar.', 3)
    return false
  end
  if p.vehicle then p:dismount() end
  p.jump = { x0 = p.body.x, y0 = p.body.y, x1 = x, y1 = y, t = 0 }
  p.stuck_t, p.push_t = 0, 0
  if w.game.audio then w.game.audio.play('confirm') end
  w.hud:toast('Hop! Salt per desencallar-te.', 1.5)
  return true
end

-- cada pas (World:update, després del jugador). h, v: fletxes. Torna true mentre salta (el jugador no es mou).
function U.update(w, dt, h, v)
  local p = w.player
  local j = p.jump
  if j then
    j.t = j.t + dt
    local k = math.min(1, j.t / U.DUR)
    p.body.x, p.body.y = j.x0 + (j.x1 - j.x0) * k, j.y0 + (j.y1 - j.y0) * k
    p.jump_z = math.sin(k * math.pi) * 14
    if k >= 1 then
      p.body.level = 0
      p.jump, p.jump_z = nil, nil
      if w.fx then w.fx:preset('sparkle', p.body.x, p.body.y + 4, 6, { color = { 1, 1, 0.8 }, speed = 12 }) end
    end
    return true
  end
  local pushing = (h or 0) ~= 0 or (v or 0) ~= 0
  local moved = p.last_x and ((p.body.x - p.last_x) ^ 2 + (p.body.y - p.last_y) ^ 2) > 0.04
  p.last_x, p.last_y = p.body.x, p.body.y
  if not pushing or moved or w.fishing or w.boat_ride or p.in_boat or p.swimming then
    p.stuck_t, p.push_t = 0, 0
    return false
  end
  p.push_t = (p.push_t or 0) + dt
  if U.free_dirs(w) == 0 then p.stuck_t = (p.stuck_t or 0) + dt else p.stuck_t = 0 end
  local off_street = (p.body.level or 0) ~= 0
  if not off_street then
    local code = w.map:cell(math.floor(p.body.x / 16), math.floor(p.body.y / 16))
    off_street = Collision.is_ramp(code) or not Collision.walk_at(code, 0)
  end
  if p.stuck_t >= U.AUTO_ALL or (off_street and p.push_t >= U.AUTO_PUSH) then
    U.jump(w, h, v)
  end
  return false
end

return U
