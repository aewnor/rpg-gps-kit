-- Granges al sud de l'autopista (2026-10-05). tools/decorate_map.py (farms) hi posa corrals de fusta
-- ('farm_pen': rectangle on es mouen els animals i `animals` = "ruc:2,cavall:1"), gallines soltes a la vora de la
-- casa (`loose`) i el pagès ('farmer'). Rucs, cavalls, porcs, ovelles i gallines passegen, s'aturen a menjar i,
-- si els dones pinso (te'l dona el pagès un cop al dia) o una poma, mengen contents; les gallines a vegades
-- ponen un ou. Esdeveniments de missió: farm_pinso, animal_fed, animals_3 (tres espècies) i egg.
-- Fulles: sprites/farm_<espècie>.png (4 fotogrames mirant a l'esquerra: quiet, camina, camina, menja).
local State = require('src.state')
local Collision = require('src.world.collision')
local Farm = {}

Farm.SPECIES = {
  ruc = { name = 'El ruc', w = 24, h = 20, speed = 10, sound = 'I-aaa! I-aaa!', likes = { pinso = true, poma = true } },
  cavall = { name = 'El cavall', w = 24, h = 20, speed = 13, sound = 'Hiiii! (mou la crinera, content)',
             likes = { pinso = true, poma = true } },
  porc = { name = 'El porc', w = 24, h = 20, speed = 9, sound = 'Oinc, oinc, oinc!', likes = { pinso = true, poma = true } },
  ovella = { name = 'L\'ovella', w = 24, h = 20, speed = 8, sound = 'Beeee!', likes = { pinso = true } },
  gallina = { name = 'La gallina', w = 16, h = 16, speed = 16, sound = 'Coc, coc, cocorocó!', likes = { pinso = true },
              egg = 0.5 },
}
Farm.PINSO_DAY = 5           -- grapats de pinso que dona el pagès cada dia
Farm.FED_TIME = 90           -- s que un animal està tip
local ACTIVE = 640           -- px: més lluny del jugador no es mouen

local function hash(n)
  n = (n * 1664525 + 1013904223) % 4294967296
  n = (n * 1664525 + 1013904223) % 4294967296
  return n / 4294967296
end

local function walkable(w, x, y)
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  return w.map:in_bounds(tx, ty) and Collision.walk_at(w.map:cell(tx, ty), 0)
end

-- un punt del corral on pot anar (les gallines soltes, només on es pot caminar)
local function spot_in(w, a, r)
  for k = 1, 12 do
    local x = a.pen.x + 4 + r(k) * math.max(1, a.pen.w - 8)
    local y = a.pen.y + 6 + r(k + 50) * math.max(1, a.pen.h - 8)
    if not a.loose or walkable(w, x, y) then return x, y end
  end
  return a.x, a.y
end

function Farm.attach(w)
  if w.id ~= 'overworld' then return end
  local F = { animals = {}, rng = love.math.newRandomGenerator(os.time()) }
  w.farm = F
  local seed = 0
  for _, o in ipairs(w.map:objects_of('farm_pen')) do
    local p = o.props or {}
    local pen = { x = o.x, y = o.y, w = p.w or 64, h = p.h or 48 }
    for kind, n in tostring(p.animals or ''):gmatch('(%a+):(%d+)') do
      if Farm.SPECIES[kind] then
        for _ = 1, tonumber(n) do
          seed = seed + 1
          local s0 = seed
          local a = { kind = kind, pen = pen, loose = p.loose, farm = p.farm, state = 'idle', anim = 0,
                      t = 1 + hash(s0) * 3, left = hash(s0 + 7) < 0.5, fed = 0 }
          a.x, a.y = pen.x + pen.w / 2, pen.y + pen.h / 2
          a.x, a.y = spot_in(w, a, function(k) return hash(s0 * 31 + k) end)
          F.animals[#F.animals + 1] = a
        end
      end
    end
  end
  local NPC = require('src.entities.npc')
  local spr = w.game.sprites.chars.npc_gardener
  for _, o in ipairs(w.map:objects_of('farmer')) do
    if spr then
      local farm = (o.props or {}).farm or 'la granja'
      local obj = { name = 'pages_' .. tostring((o.props or {}).n or 1), x = o.x, y = o.y,
                    props = { sprite = 'npc_gardener', say_name = 'El pagès · ' .. farm, farmer = farm, facing = 'down',
                              wander = 0 } }
      w.npcs[#w.npcs + 1] = NPC.new(obj, spr, #w.npcs + 600)
    end
  end
end

function Farm.update(w, dt)
  local F = w.farm
  if not F then return end
  local pb = w.player.body
  local rng = F.rng
  for _, a in ipairs(F.animals) do
    a.fed = math.max(0, a.fed - dt)
    if (a.x - pb.x) ^ 2 + (a.y - pb.y) ^ 2 < ACTIVE * ACTIVE then
      local sp = Farm.SPECIES[a.kind]
      a.t = a.t - dt
      if a.state == 'walk' then
        local dx, dy = a.tx - a.x, a.ty - a.y
        local d = math.sqrt(dx * dx + dy * dy)
        local step = sp.speed * dt
        if d <= step or a.t <= 0 then
          a.state, a.t = rng:random() < 0.45 and 'eat' or 'idle', 1.5 + rng:random() * 3
        else
          local nx, ny = a.x + dx / d * step, a.y + dy / d * step
          if a.loose and not walkable(w, nx, ny) then a.state, a.t = 'idle', 1
          else a.x, a.y = nx, ny end
          a.left = dx < 0
          a.anim = a.anim + dt
        end
      elseif a.t <= 0 then
        if rng:random() < 0.6 then
          a.tx, a.ty = spot_in(w, a, function() return rng:random() end)
          a.state, a.t = 'walk', 6
        else
          a.state, a.t = rng:random() < 0.5 and 'eat' or 'idle', 1.5 + rng:random() * 3
        end
      end
    end
  end
end

local function nearest(w, fx, fy)
  local F = w.farm
  if not F then return nil end
  local best, bd = nil, 18 * 18
  for _, a in ipairs(F.animals) do
    local d = (a.x - fx) ^ 2 + (a.y - 6 - fy) ^ 2
    if d < bd then best, bd = a, d end
  end
  return best
end

function Farm.can_interact(w, fx, fy) return nearest(w, fx, fy) ~= nil end

local function rnd(w) return w.farm and w.farm.rng:random() or math.random() end

-- donar menjar (pinso o una poma) a l'animal que tens davant
function Farm.interact(w, fx, fy)
  local a = nearest(w, fx, fy)
  if not a then return false end
  local st, g = w.state, w.game
  local sp = Farm.SPECIES[a.kind]
  local Town = require('src.systems.town')
  if a.fed > 0 then
    w.hud:toast(sp.name .. ' ja ha menjat. Està tip i content!', 2)
    return true
  end
  local food
  for _, id in ipairs({ 'pinso', 'poma' }) do
    if sp.likes[id] and (st.inventory[id] or 0) > 0 then food = id; break end
  end
  if not food then
    w.hud:toast(sp.name .. ' et mira amb gana. Demana pinso al pagès!', 2.5)
    w.fx:preset('sparkle', a.x, a.y - 12, 3, { color = { 1, 0.6, 0.7 }, speed = 10 })
    return true
  end
  State.take(st, food)
  a.fed, a.state, a.t = Farm.FED_TIME, 'eat', 3
  a.left = w.player.body.x < a.x
  w.fx:preset('sparkle', a.x, a.y - 14, 8, { color = { 1, 0.45, 0.55 }, speed = 14 })
  g.audio.play('good')
  w.dialogue:show(sp.name, { sp.sound, food == 'poma' and 'Una poma! Quina festa!' or 'Ñam, ñam... quin pinso més bo!' })
  st.farm_fed = st.farm_fed or {}
  st.farm_fed[a.kind] = true
  Town.event(w, 'event', { name = 'animal_fed' })
  local n = 0
  for _ in pairs(st.farm_fed) do n = n + 1 end
  if n >= 3 then Town.event(w, 'event', { name = 'animals_3' }) end
  if sp.egg and (not st.farm_egg or rnd(w) < sp.egg) then
    st.farm_egg = true
    State.give(st, 'ou')
    w.hud:toast('La gallina ha post un ou! (+1 Ou de gallina)', 3, true)
    Town.event(w, 'event', { name = 'egg' })
  end
  return true
end

-- el pagès: pinso un cop per dia de joc
function Farm.talk(w, n)
  local st = w.state
  local name = n.props.say_name
  if st.pinso_day ~= (st.day or 1) then
    st.pinso_day = st.day or 1
    for _ = 1, Farm.PINSO_DAY do State.give(st, 'pinso') end
    w.dialogue:show(name, { 'Bon dia! Benvingut a ' .. n.props.farmer .. '.',
      'Té, ' .. Farm.PINSO_DAY .. ' grapats de pinso. Posa\'t davant d\'un animal i prem Acció per donar-li menjar.',
      'Les gallines, si estan contentes, ponen ous!' })
    w.hud:toast('+' .. Farm.PINSO_DAY .. ' Pinso', 2)
  else
    w.dialogue:show(name, { 'Avui ja t\'he donat pinso. Torna demà, que els animals sempre tenen gana!' })
  end
  require('src.systems.town').event(w, 'event', { name = 'farm_pinso' })
  return true
end

-- add(y, fn): ordre de dibuix del món
function Farm.draw(w, add, ox, oy, shadow)
  local F = w.farm
  if not F then return end
  local sprites = w.game.sprites
  for _, a in ipairs(F.animals) do
    local sp = Farm.SPECIES[a.kind]
    local sh = sprites['farm_' .. a.kind]
    if sh and w.cam:visible(a.x - sp.w, a.y - sp.h - 4, sp.w * 2, sp.h + 8) then
      add(a.y, function()
        if shadow then shadow(a.x - ox, a.y - oy, sp.w / 3, 2, 0.25); love.graphics.setColor(1, 1, 1, 1) end
        local fr = 1
        if a.state == 'walk' then fr = 2 + math.floor(a.anim * 6) % 2
        elseif a.state == 'eat' then fr = (math.floor(love.timer.getTime() * 3) % 2 == 0) and 4 or 1 end
        local x, y = math.floor(a.x + 0.5) - ox, math.floor(a.y + 0.5) - oy
        local sx = a.left and 1 or -1
        love.graphics.draw(sh.img, sh.quads[fr], x + (a.left and -sp.w / 2 or sp.w / 2), y - sp.h + 2, 0, sx, 1)
      end)
    end
  end
end

return Farm
