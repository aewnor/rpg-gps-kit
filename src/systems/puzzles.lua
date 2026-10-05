-- Puzles de les masmorres (2026-10-05). Objectes del mapa:
--   block   {}                       bloc de pedra que s'empeny (en sortir i tornar a entrar, torna al seu lloc)
--   plate   {flag}                   placa de pressió: flag actiu mentre hi ha un bloc a sobre (el jugador no compta); quan
--                                    una reixa s'obre per primer cop queda resolta per sempre (solved_<nom de la reixa>)
--   rune    {group, order, n}        runa I-IV: tocar-les en ordre activa el flag `group` (si t'equivoques, s'apaguen)
--   brazier {flag}                   braser que s'encén amb la Bola de foc (flag permanent)
--   secret  {flag, say}             paret esquerdada: en tocar-la s'obre el passadís (flag permanent)
-- Les reixes (gate) poden demanar diversos flags (open_flag = "a,b") o una clau (open_key = item, key_flag).
local State = require('src.state')

local Puzzles = {}
local T = 16
local PUSH_TIME = 0.22
local SLIDE = 0.16

function Puzzles.init(w)
  w.puzzle = { blocks = {}, plates = {}, runes = {}, braziers = {}, secrets = {}, push_t = 0, progress = {} }
end

-- torna true si l'objecte és de puzle (i ja l'ha desat)
function Puzzles.load(w, o)
  local P = w.puzzle
  local t = o.type
  local tx, ty = math.floor(o.x / T), math.floor(o.y / T)
  if t == 'block' then
    P.blocks[#P.blocks + 1] = { name = o.name, tx = tx, ty = ty, rect = { x = tx * T + 1, y = ty * T + 1, w = 14, h = 14 } }
  elseif t == 'plate' then
    P.plates[#P.plates + 1] = { flag = o.props.flag, tx = tx, ty = ty }
  elseif t == 'rune' then
    P.runes[#P.runes + 1] = { group = o.props.group, order = o.props.order, n = o.props.n or o.props.order, tx = tx, ty = ty,
                              rect = { x = tx * T + 1, y = ty * T + 2, w = 14, h = 13 } }
  elseif t == 'brazier' then
    P.braziers[#P.braziers + 1] = { flag = o.props.flag, tx = tx, ty = ty, rect = { x = tx * T + 3, y = ty * T + 6, w = 10, h = 9 } }
    if State.flag(w.state, o.props.flag) then w.torches[#w.torches + 1] = { x = tx * T + 8, y = ty * T + 6 } end
  elseif t == 'secret' then
    P.secrets[#P.secrets + 1] = { flag = o.props.flag, say = o.props.say, tx = tx, ty = ty, rect = { x = tx * T, y = ty * T, w = T, h = T } }
  else
    return false
  end
  return true
end

local function block_at(P, tx, ty, except)
  for _, b in ipairs(P.blocks) do if b ~= except and b.tx == tx and b.ty == ty then return b end end
end

local function overlap(a, b) return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y end

-- ¿pot anar un bloc a (tx, ty)? terra transitable, sense un altre bloc ni res de dinàmic (reixes, cofres, NPC)
local function free_for_block(w, P, b, tx, ty)
  if not w.map:in_bounds(tx, ty) or w.map:cell(tx, ty) ~= 0 then return false end
  if block_at(P, tx, ty, b) then return false end
  local r = { x = tx * T + 1, y = ty * T + 1, w = 14, h = 14 }
  for _, g in ipairs(w.gates) do if not w:gate_open(g) and overlap(r, g.rect) then return false end end
  for _, c in ipairs(w.chests) do if overlap(r, c.rect) then return false end end
  for _, z in ipairs(P.braziers) do if overlap(r, z.rect) then return false end end
  for _, n in ipairs(P.runes) do if overlap(r, n.rect) then return false end end
  for _, e in ipairs(w.enemies) do if e.state ~= 'dead' and overlap(r, e:box()) then return false end end
  return true
end

local DIRV = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

function Puzzles.update(w, dt, act)
  local P = w.puzzle
  if not P then return end
  local st = w.state
  local pl = w.player
  -- lliscament dels blocs
  for _, b in ipairs(P.blocks) do
    if b.slide then
      b.slide.t = b.slide.t + dt
      if b.slide.t >= SLIDE then b.slide = nil end
    end
  end
  -- empènyer: caminant cap a un bloc que tens just al davant
  local d = DIRV[pl.facing]
  local want = act and ((pl.facing == 'left' and act.left) or (pl.facing == 'right' and act.right) or
                        (pl.facing == 'up' and act.up) or (pl.facing == 'down' and act.down))
  local front = { x = pl.body.x + d[1] * 10 - 3, y = pl.body.y - 2 + d[2] * 10 - 3, w = 6, h = 6 }
  local target
  if want and not pl.vehicle and pl.state ~= 'attack' then
    for _, b in ipairs(P.blocks) do if not b.slide and overlap(front, b.rect) then target = b end end
  end
  if target then
    P.push_t = P.push_t + dt
    if P.push_t >= PUSH_TIME then
      P.push_t = 0
      local nx, ny = target.tx + d[1], target.ty + d[2]
      if free_for_block(w, P, target, nx, ny) then
        target.slide = { fx = target.tx, fy = target.ty, t = 0 }
        target.tx, target.ty = nx, ny
        target.rect.x, target.rect.y = nx * T + 1, ny * T + 1
        w.game.audio.play('swing')
      else
        w.game.audio.play('block')
      end
    end
  else
    P.push_t = 0
  end
  -- plaques: només les prem un bloc (el jugador sol no pesa prou; si no, el puzle es resoldria trepitjant-la)
  for _, p in ipairs(P.plates) do
    local on = block_at(P, p.tx, p.ty) ~= nil
    if on and not p.on then w.game.audio.play('door') end
    p.on = on
    st.flags[p.flag] = on or nil
  end
  if #P.plates > 0 then   -- reixa oberta per plaques: queda resolta (encara que després es mogui el bloc)
    for _, g in ipairs(w.gates) do
      local of = g.obj.props.open_flag
      if of and not State.flag(st, 'solved_' .. tostring(w.id) .. '_' .. g.obj.name) then
        local all = true
        for f in tostring(of):gmatch('[^,]+') do if not State.flag(st, f) then all = false end end
        if all then State.set(st, 'solved_' .. tostring(w.id) .. '_' .. g.obj.name); w.hud:toast('La reixa s\'ha obert!', 2) end
      end
    end
  end
  -- brasers: la Bola de foc els encén
  for _, z in ipairs(P.braziers) do
    if not State.flag(st, z.flag) then
      for _, sh in ipairs(w.shots.list) do
        if sh.owner == 'player' and sh.kind == 'fire' and overlap({ x = sh.x - 3, y = sh.y - 3, w = 6, h = 6 }, z.rect) then
          State.set(st, z.flag)
          sh.life = 0
          w.torches[#w.torches + 1] = { x = z.tx * T + 8, y = z.ty * T + 6 }   -- il·lumina la sala fosca
          w.game.audio.play('spell')
          w.fx:preset('sparkle', z.tx * T + 8, z.ty * T + 4, 12)
          w.hud:toast('El braser s\'encén!', 1.5)
        end
      end
    end
  end
end

function Puzzles.blockers(w, b)
  local P = w.puzzle
  if not P then return end
  for _, k in ipairs(P.blocks) do b[#b + 1] = k.rect end
  for _, z in ipairs(P.braziers) do b[#b + 1] = z.rect end
  for _, n in ipairs(P.runes) do b[#b + 1] = n.rect end
  for _, s in ipairs(P.secrets) do if not State.flag(w.state, s.flag) then b[#b + 1] = s.rect end end
end

-- Acció davant d'una runa, d'una paret secreta o d'una reixa amb pany
function Puzzles.interact(w, fx, fy)
  local P = w.puzzle
  if not P then return false end
  local st = w.state
  local pt = { x = fx - 4, y = fy - 4, w = 8, h = 8 }
  for _, s in ipairs(P.secrets) do
    if overlap(pt, { x = s.rect.x - 2, y = s.rect.y - 2, w = 20, h = 20 }) and not State.flag(st, s.flag) then
      State.set(st, s.flag)
      w.game.audio.play('door')
      w.shaker:add(0.3)
      w.fx:preset('sparkle', s.tx * T + 8, s.ty * T + 6, 14)
      w:say_text(nil, s.say or 'La pedra de l\'estrella s\'enfonsa... i s\'obre un passadís secret!')
      return true
    end
  end
  for _, n in ipairs(P.runes) do
    if overlap(pt, { x = n.rect.x - 2, y = n.rect.y - 2, w = 18, h = 18 }) then
      if State.flag(st, n.group) then w.hud:toast('Les runes ja brillen totes', 1.5); return true end
      local prog = P.progress[n.group] or 0
      if n.lit then return true end
      if n.order == prog + 1 then
        n.lit = true
        P.progress[n.group] = prog + 1
        w.game.audio.play('confirm')
        local total = 0
        for _, r in ipairs(P.runes) do if r.group == n.group then total = total + 1 end end
        if prog + 1 == total then
          State.set(st, n.group)
          w.game.audio.play('levelup')
          w.shaker:add(0.25)
          w.hud:toast('Les runes brillen! S\'ha obert una reixa', 2.5)
        end
      else
        P.progress[n.group] = 0
        for _, r in ipairs(P.runes) do if r.group == n.group then r.lit = nil end end
        w.game.audio.play('block')
        w.hud:toast('Ordre equivocat: les runes s\'apaguen', 2)
      end
      return true
    end
  end
  for _, g in ipairs(w.gates) do
    local p = g.obj.props
    if p.open_key and not w:gate_open(g) and overlap({ x = fx - 6, y = fy - 6, w = 12, h = 12 }, g.rect) then
      if (st.inventory[p.open_key] or 0) > 0 then
        State.take(st, p.open_key)
        State.set(st, p.key_flag)
        w.game.audio.play('door')
        w.hud:toast('Clic! La clau obre la porta', 2)
      else
        local def = w.game.items[p.open_key]
        w.hud:toast('Tancada amb pany. Necessites: ' .. (def and def.name or p.open_key), 2.5)
      end
      return true
    end
  end
  return false
end

-- add(y, fn): ordre de dibuix del món; sheet = { img, quads } (puzzle.png: 1 bloc, 2-3 placa, 4-7 runes apagades,
-- 8-11 enceses, 12 braser apagat, 13-14 foc, 15 paret secreta)
function Puzzles.draw(w, add, sheet, ox, oy)
  local P = w.puzzle
  if not P or not sheet then return end
  local q = sheet.quads
  for _, p in ipairs(P.plates) do   -- les plaques van a terra: abans que tot el que hi ha a sobre
    add(p.ty * T - 8, function() love.graphics.draw(sheet.img, q[p.on and 3 or 2], p.tx * T - ox, p.ty * T - oy) end)
  end
  for _, b in ipairs(P.blocks) do
    local x, y = b.tx * T, b.ty * T
    if b.slide then
      local k = math.min(1, b.slide.t / SLIDE)
      x = (b.slide.fx + (b.tx - b.slide.fx) * k) * T
      y = (b.slide.fy + (b.ty - b.slide.fy) * k) * T
    end
    add(y + 15, function() love.graphics.draw(sheet.img, q[1], math.floor(x - ox), math.floor(y - oy)) end)
  end
  for _, n in ipairs(P.runes) do
    local lit = n.lit or State.flag(w.state, n.group)
    add(n.ty * T + 15, function() love.graphics.draw(sheet.img, q[(lit and 7 or 3) + (n.n or 1)], n.tx * T - ox, n.ty * T - oy) end)
  end
  local f = math.floor(love.timer.getTime() * 6) % 2
  for _, z in ipairs(P.braziers) do
    local on = State.flag(w.state, z.flag)
    add(z.ty * T + 15, function() love.graphics.draw(sheet.img, q[on and (13 + f) or 12], z.tx * T - ox, z.ty * T - oy) end)
  end
  for _, s in ipairs(P.secrets) do
    if not State.flag(w.state, s.flag) then
      add(s.ty * T + 15, function() love.graphics.draw(sheet.img, q[15], s.tx * T - ox, s.ty * T - oy) end)
    end
  end
end

return Puzzles
