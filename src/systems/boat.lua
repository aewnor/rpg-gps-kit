-- La barca d'en Toni (Port de Roda de Berà): si li portes 3 petxines de la platja, et porta per mar des del
-- port fins al Roc de Sant Gaietà. La ruta es calcula sola per les caselles d'aigua (cerca en amplada), la barca
-- la segueix i el jugador baixa a la casella de terra més propera del final.
local State = require('src.state')
local Collision = require('src.world.collision')

local Boat = {}
local DIR_ROW = { down = 0, up = 1, left = 2, right = 3 }   -- files de les fulles de personatge
Boat.NPC = 'npc_toni_patro'
Boat.PRICE_ITEM, Boat.PRICE_N = 'petxina', 3
Boat.DEST = { 1182, 1306 }   -- aigua davant del Roc de Sant Gaietà (caselles)
Boat.DEST_LABEL = 'al Roc de Sant Gaietà'
Boat.SPEED = 150             -- px/s
Boat.BOX = 70                -- marge de la cerca al voltant de l'inici i el destí (caselles)

local function water(w, x, y) return w.map:in_bounds(x, y) and w.map:cell(x, y) % 4 == 2 end

local function nearest(w, tx, ty, pred, r)
  for d = 0, r or 10 do
    for dy = -d, d do
      for dx = -d, d do
        if math.max(math.abs(dx), math.abs(dy)) == d and pred(w, tx + dx, ty + dy) then return tx + dx, ty + dy end
      end
    end
  end
end

local function land(w, x, y) return w.map:in_bounds(x, y) and Collision.walk_at(w.map:cell(x, y), 0) end

-- camí d'aigua (llista de punts en píxels) de (sx, sy) a (dx, dy), caselles; nil si no hi ha pas per mar
function Boat.route(w, sx, sy, dx, dy)
  local ax, ay = nearest(w, sx, sy, water, 8)
  local bx, by = nearest(w, dx, dy, water, 8)
  if not ax or not bx then return nil end
  local x0, y0 = math.min(ax, bx) - Boat.BOX, math.min(ay, by) - Boat.BOX
  local x1, y1 = math.max(ax, bx) + Boat.BOX, math.max(ay, by) + Boat.BOX
  local W = x1 - x0 + 1
  local function key(x, y) return (y - y0) * W + (x - x0) end
  local prev = { [key(ax, ay)] = -1 }
  local qx, qy, head = { ax }, { ay }, 1
  local found = false
  while head <= #qx do
    local x, y = qx[head], qy[head]; head = head + 1
    if x == bx and y == by then found = true; break end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 and prev[key(nx, ny)] == nil and water(w, nx, ny) then
        prev[key(nx, ny)] = key(x, y)
        qx[#qx + 1], qy[#qy + 1] = nx, ny
      end
    end
  end
  if not found then return nil end
  local cells = {}
  local k = key(bx, by)
  while k ~= -1 do
    cells[#cells + 1] = { k % W + x0, math.floor(k / W) + y0 }
    k = prev[k]
  end
  -- de l'inici al final, un punt de cada 4 caselles (la barca hi va en línia recta i sense escales)
  local pts = {}
  for i = #cells, 1, -1 do
    if i == #cells or i == 1 or (#cells - i) % 4 == 0 then
      pts[#pts + 1] = { cells[i][1] * 16 + 8, cells[i][2] * 16 + 8 }
    end
  end
  return pts
end

-- en parlar amb en Toni: true si ell s'encarrega de la conversa
function Boat.talk(w, n, after)
  local g = w.game
  local have = w.state.inventory[Boat.PRICE_ITEM] or 0
  if have >= Boat.PRICE_N then
    w.talking = nil
    n.facing = n.base_facing
    g:open_list('Barca d\'en Toni (' .. Boat.PRICE_N .. ' petxines)', {
      { 'Sí! Porta\'m al Roc de Sant Gaietà', function() g:close_menu(); Boat.start(w, n) end },
    })
    return true
  end
  if not State.flag(w.state, 'toni_barca_pista') then
    State.set(w.state, 'toni_barca_pista')
    w:say_text(n.props.say_name or 'En Toni, patró',
      'Si em portes ' .. Boat.PRICE_N .. ' petxines de la platja, et porto amb la meva barca fins al Roc de ' ..
      'Sant Gaietà!|Ara en tens ' .. have .. '. Les petxines brillen a la sorra, vora l\'aigua.', after)
    return true
  end
  return false
end

function Boat.start(w, n)
  local b = w.player.body
  local pts = Boat.route(w, math.floor(b.x / 16), math.floor(b.y / 16), Boat.DEST[1], Boat.DEST[2])
  if not pts or #pts < 2 then
    w.hud:toast('Avui el mar està massa mogut per sortir amb la barca', 2.5)
    return false
  end
  for _ = 1, Boat.PRICE_N do State.take(w.state, Boat.PRICE_ITEM) end
  local pl = w.player
  if pl.vehicle then pl.vehicle = nil end
  pl.in_boat = true
  b.level = 0
  n.hidden = true
  w.boat_ride = { pts = pts, i = 1, x = pts[1][1], y = pts[1][2], npc = n, ang = 0, t = 0 }
  b.x, b.y = pts[1][1], pts[1][2]
  w.game.audio.play('splash')
  w.hud:toast('Som-hi! Agafa\'t fort', 2)
  return true
end

-- avança la barca pel camí; en arribar, el jugador salta a terra
function Boat.update(w, dt)
  local r = w.boat_ride
  if not r then return end
  r.t = r.t + dt
  local step = Boat.SPEED * dt * math.min(1, r.t / 1.5)   -- arrenca a poc a poc
  while step > 0 and r.i < #r.pts do
    local p = r.pts[r.i + 1]
    local dx, dy = p[1] - r.x, p[2] - r.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= step then
      r.x, r.y, r.i, step = p[1], p[2], r.i + 1, step - d
    else
      r.x, r.y, step = r.x + dx / d * step, r.y + dy / d * step, 0
    end
    if d > 0.01 then r.ang = math.atan2(dy, dx) end
  end
  local pl = w.player
  pl.body.x, pl.body.y = r.x, r.y
  pl.facing = math.abs(math.cos(r.ang)) > math.abs(math.sin(r.ang)) and (math.cos(r.ang) > 0 and 'right' or 'left')
              or (math.sin(r.ang) > 0 and 'down' or 'up')
  r.wake = (r.wake or 0) - dt
  if r.wake <= 0 then
    r.wake = 0.12
    w:puff(r.x - math.cos(r.ang) * 12, r.y + 3 - math.sin(r.ang) * 6, 2, { 0.85, 0.95, 1 }, 10, 0.5, 2)
  end
  if r.i >= #r.pts then Boat.finish(w) end
end

function Boat.finish(w)
  local r = w.boat_ride
  w.boat_ride = nil
  local pl = w.player
  pl.in_boat = nil
  local tx, ty = nearest(w, math.floor(r.x / 16), math.floor(r.y / 16), land, 10)
  if tx then pl.body.x, pl.body.y = tx * 16 + 8, ty * 16 + 8 end
  if r.npc then r.npc.hidden = nil end   -- en Toni torna sol al port
  w.game.audio.play('splash')
  w.hud:toast('Has arribat ' .. Boat.DEST_LABEL .. '!', 2.5)
  State.set(w.state, 'volta_en_barca')
end

-- barca (casc blanc amb franja blava), en Toni al timó i el jugador de mig cos amunt
function Boat.draw(w, ox, oy)
  local r = w.boat_ride
  if not r then return end
  local g = w.game
  local lg = love.graphics
  local x, y = math.floor(r.x - ox), math.floor(r.y - oy)
  local horiz = math.abs(math.cos(r.ang)) >= math.abs(math.sin(r.ang))
  local bob = math.floor(math.sin(r.t * 4) + 0.5)
  local hw, hh = horiz and 16 or 9, horiz and 7 or 13
  lg.setColor(0.12, 0.3, 0.4, 0.5); lg.ellipse('fill', x, y + 4, hw + 3, hh * 0.6 + 2)
  -- persones (a dins de la barca: només de cintura amunt)
  local function person(sheet, quadf, px, py, facing)   -- el casc, dibuixat després, tapa les cames
    if not sheet then return end
    local row = DIR_ROW[facing] or 0
    lg.setColor(1, 1, 1)
    lg.draw(sheet, quadf(row, 4), px - 8, py - 20 + bob)
  end
  local back = horiz and { -8 * (math.cos(r.ang) > 0 and 1 or -1), 0 } or { 0, -6 * (math.sin(r.ang) > 0 and 1 or -1) }
  local front = { -back[1], -back[2] }
  local toni = r.npc and g.sprites.chars[r.npc.props.sprite]
  local pls = g.sprites.player
  local facing = w.player.facing
  local order = (back[2] < front[2]) and { 'toni', 'player' } or { 'player', 'toni' }
  for _, who in ipairs(order) do
    if who == 'toni' and toni then person(toni.sheet, toni.quad, x + back[1], y + back[2], facing)
    elseif who == 'player' and pls then person(pls.sheet, pls.quad, x + front[1] * 0.5, y + front[2] * 0.5, facing) end
  end
  -- casc per sobre de les cames
  lg.setColor(0.96, 0.95, 0.9)
  if horiz then
    local dir = math.cos(r.ang) > 0 and 1 or -1
    lg.polygon('fill', x - hw * dir, y - 2 + bob, x + (hw - 4) * dir, y - 2 + bob, x + (hw + 3) * dir, y - 5 + bob,
               x + hw * dir, y + 4 + bob, x - (hw - 2) * dir, y + 4 + bob)
    lg.setColor(0.2, 0.42, 0.7); lg.rectangle('fill', math.min(x - hw * dir, x + hw * dir), y + 1 + bob, hw * 2, 2)
  else   -- de cara o d'esquena: popa quadrada i proa en punta cap on va
    local dir = math.sin(r.ang) > 0 and 1 or -1
    local yb, yf = y - 6 * dir + bob, y + 7 * dir + bob
    lg.polygon('fill', x - hw, yb, x + hw, yb, x + hw - 1, yf - 3 * dir, x, yf + 4 * dir, x - hw + 1, yf - 3 * dir)
    lg.setColor(0.2, 0.42, 0.7); lg.rectangle('fill', x - hw, math.min(yb, yf) + 6, hw * 2, 2)
  end
  lg.setColor(0.45, 0.3, 0.18); lg.rectangle('fill', x - 2, y - 3 + bob, 4, 2)
  lg.setColor(1, 1, 1)
end

return Boat
