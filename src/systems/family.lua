-- Pare i mare del jugador a la casa del perfil, i pares dels amics a les seves cases.
--   · casa del jugador (game.house, plantes en ordre): rutines senzilles (cuina, sofà, despatx, llit), A* entre
--     plantes per l'escala, de nit dormen al costat del llit (es veuen, amb «Zzz») i parlen amb diàlegs propis.
--     Sempre són a casa, preferint la planta de l'entrada, llevat que una missió els faci sortir (pas amb
--     family = 'out' → state.family_out; family = 'home' hi torna)
--   · llit i nevera de la casa: Rest.sleep(w) / Rest.eat(w) de src/systems/rest.lua si existeix; si no, un
--     recanvi simple (cura i, en dormir, passen 8 h)
--   · pares dels amics: friend_interior els hi posa com a NPC estàtics (props.parent, props.owner = id de l'amic)
-- La part pura (slot, scan, lines) no depèn de LÖVE: tests/family_cases.lua
local Schedule = require('src.systems.schedule')

local Family = {}

local WALK = 34              -- px/s
local ROLES = { 'pare', 'mare' }
Family.ROLES = ROLES

-- ---------------------------------------------------------------- horari
local function hm(h, m) return h * 60 + (m or 0) end

-- on és cada un segons l'hora: 'bed' | 'kitchen' | 'sofa' | 'office'
function Family.slot(role, clock, day)
  local c = (clock or 600) % 1440
  local we = Schedule.weekend(day)
  if c < hm(7) or c >= hm(22, 30) then return 'bed' end
  if c < hm(8, 30) then return 'kitchen' end
  if c < hm(13, 30) then
    if role == 'pare' then return we and 'sofa' or 'office' end
    return c < hm(10, 30) and 'kitchen' or 'sofa'
  end
  if c < hm(15) then return 'kitchen' end
  if c < hm(17) then
    if role == 'pare' and not we then return 'office' end
    return 'sofa'
  end
  if c < hm(19, 30) then return role == 'pare' and 'sofa' or 'kitchen' end
  if c < hm(21) then return 'kitchen' end
  return 'sofa'
end

-- amb l'estat de la partida: 'out' si una missió els ha fet sortir de casa
function Family.slot_for(st, role)
  if st.family_out then return 'out' end
  return Family.slot(role, st.clock, st.day)
end

-- ---------------------------------------------------------------- cerca de punts a la planta
local DIRS = { { 0, 1, 'up' }, { 0, -1, 'down' }, { 1, 0, 'left' }, { -1, 0, 'right' } }   -- veí → cap on mira

local KINDS = {
  kitchen = { 'i_stove', 'i_counter', 'i_sink' },
  fridge = { 'i_fridge' },
  sofa = { 'i_sofa', 'i_armchair' },
  bed = { 'i_bed_b', 'i_bed', 'i_bed_t' },
}

-- spec = planta en format procgen (ground/structures amb noms); defs = data/tiles.json .tiles
-- → { kitchen = { {x,y,face}… }, fridge, sofa, office, bed } (cel·les lliures al costat del mobiliari, en ordre fix)
function Family.scan(spec, defs)
  local W, H = spec.w, spec.h
  local function sname(x, y) return spec.structures[y * W + x + 1] or '' end
  local function free(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return false end
    local n = sname(x, y)
    if n ~= '' and defs[n] and defs[n].solid then return false end
    local g = defs[spec.ground[y * W + x + 1] or '']
    if g and (g.solid or g.water) then return false end
    return true
  end
  local out = {}
  local function beside(names, into)
    local want = {}
    for _, n in ipairs(names) do want[n] = true end
    local seen = {}
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if want[sname(x, y)] then
          for _, d in ipairs(DIRS) do
            local cx, cy = x + d[1], y + d[2]
            local k = cy * W + cx
            if not seen[k] and free(cx, cy) then
              seen[k] = true
              into[#into + 1] = { x = cx, y = cy, face = d[3] }
              break
            end
          end
        end
      end
    end
  end
  for kind, names in pairs(KINDS) do
    out[kind] = {}
    for _, n in ipairs(names) do beside({ n }, out[kind]) end
  end
  -- despatx: la cadira vora l'escriptori (seu) i, si no, un costat lliure de l'escriptori
  out.office = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if sname(x, y) == 'i_desk' then
        for _, d in ipairs(DIRS) do
          local cx, cy = x + d[1], y + d[2]
          if sname(cx, cy) == 'i_chair' and free(cx, cy) then
            out.office[#out.office + 1] = { x = cx, y = cy, face = d[3] }
          end
        end
      end
    end
  end
  if #out.office == 0 then beside({ 'i_desk' }, out.office) end
  return out
end

-- ---------------------------------------------------------------- textos (català)
local function pick(list, i) return list[(i - 1) % #list + 1] end

local SCHOOL = {
  'Com ha anat l\'escola? Has après alguna cosa nova?',
  'Has fet els deures? Si vols, et dono un cop de mà.',
  'Què heu fet avui a classe? M\'ho expliques?',
  'I els teus amics i amigues? Us ho passeu bé a l\'escola?',
}
local SCOLD = {
  'Recorda recollir la teva habitació: sempre és un caos!',
  'No arribis tard a casa, que ens preocupem.',
  'Amb la bici i el patinet, a poc a poc i amb casc, d\'acord?',
  'Menys pantalles i més jugar fora, que fa bon dia.',
}
local ENCOURAGE = {
  'Estic molt %s de tu, %s!',
  'Si t\'esforces, pots aconseguir tot el que et proposis.',
  'Has fet molt bona feina últimament. Segueix així!',
  'Ser valent i amable val més que cap nota.',
}
local DOING = {
  kitchen = { 'Estic preparant alguna cosa bona. Tens gana?', 'Ajuda\'m a parar la taula, va.' },
  sofa = { 'Estic descansant una estona al sofà.', 'Seu amb mi un moment, que fa dies que no parlem.' },
  office = { 'Tinc feina al despatx, però per a tu sempre tinc un minut.', 'Estic acabant uns papers.' },
}

-- diàleg d'un pare/mare del jugador. ctx = { name, role, slot, clock, hp, max_hp, scares, talks, we }
function Family.lines(ctx)
  local name = (ctx.name and ctx.name ~= '') and ctx.name or 'maco'
  local proud = ctx.role == 'mare' and 'orgullosa' or 'orgullós'
  local c = (ctx.clock or 600) % 1440
  local lines = { 'Hola, ' .. name .. '!' }
  local k = ctx.talks or 1
  if ctx.max_hp and ctx.hp and ctx.hp < ctx.max_hp * 0.5 then
    lines[#lines + 1] = 'Tens mala cara, ' .. name .. '. Menja alguna cosa de la nevera i descansa una estona.'
  elseif c >= hm(21, 30) or c < hm(6) then
    lines[#lines + 1] = 'És molt tard! Posa\'t el pijama i a dormir al llit, que demà hi ha feina.'
  elseif (ctx.scares or 0) > 0 and k % 3 == 0 then
    lines[#lines + 1] = 'M\'han dit que has anat massa de pressa amb el vehicle. A poc a poc, d\'acord?'
  elseif not ctx.we and c >= hm(7) and c < hm(9) then
    lines[#lines + 1] = 'Vinga, que arribaràs tard a l\'escola! Has esmorzat?'
  else
    local m = (k - 1) % 4
    if m == 0 then lines[#lines + 1] = pick(SCHOOL, k)
    elseif m == 1 then
      local e = pick(ENCOURAGE, k)
      lines[#lines + 1] = e:find('%%s') and string.format(e, proud, name) or e
    elseif m == 2 then lines[#lines + 1] = pick(SCOLD, k)
    else lines[#lines + 1] = pick(SCHOOL, k + 1) end
  end
  local d = DOING[ctx.slot]
  if d then lines[#lines + 1] = pick(d, k) end
  return lines
end

-- diàleg dels pares d'un amic. ctx = { name (jugador), friend (nom), role, here (l'amic és a casa) }
function Family.friend_lines(ctx)
  local name = (ctx.name and ctx.name ~= '') and ctx.name or 'maco'
  local lines = { 'Hola, ' .. name .. '! Passa, passa, ets benvingut a casa.' }
  if ctx.here then
    lines[#lines + 1] = ctx.friend .. ' és per aquí. Segur que té ganes de jugar amb tu!'
  else
    lines[#lines + 1] = ctx.friend .. ' ara no hi és. Potser és a l\'escola o al parc.'
  end
  if ctx.talks and ctx.talks % 2 == 0 then
    lines[#lines + 1] = ctx.role == 'mare' and 'Vols una mica de fruita? A casa sempre en tenim.' or 'Cuida\'t molt, i no corris pel carrer!'
  end
  return lines
end

-- ---------------------------------------------------------------- aspecte dels pares
-- v: variant (nombre) per als pares d'un amic: canvien cabell, color i roba; sense v, els pares del jugador
-- skin: pell (per defecte la de l'avatar del perfil)
local function look_for(g, role, v, skin)
  local Looks = require('src.paperdoll.looks')
  local av = g.profile and g.profile.avatar
  local l = Looks.default(role == 'pare' and 'nen' or 'nena')
  Looks.preset_age(l, 'adult')
  l.skin = skin or (type(av) == 'table' and tonumber(av.skin)) or 2
  l.acc = {}
  v = v or 0
  if role == 'pare' then
    l.hair, l.hair_color, l.outfit, l.top, l.bottom, l.shoes = 'short', 2 + v % 3, 'pants', ({ 2, 4, 6, 9 })[v % 4 + 1], 8, 8
    l.acc.beard = v % 2 == 1   -- (el pare del jugador, v = 0, sense barba)
  else
    l.hair, l.hair_color, l.outfit, l.top, l.bottom, l.shoes = (v % 2 == 0) and 'long' or 'short', 1 + v % 4, 'dress',
      ({ 10, 3, 7, 11 })[v % 4 + 1], 10, 8
  end
  return Looks.build(Looks.sanitize(l))
end

local function names(g)
  local ok, Profile = pcall(require, 'src.profile')
  local p = ok and Profile.parents_of(g.profile) or {}
  return { pare = p.pare or 'Pare', mare = p.mare or 'Mare' }
end
Family.names = names

-- ---------------------------------------------------------------- pla de la casa
local function floor_index(H, id)
  for i, f in ipairs(H.floors or {}) do if f == id then return i end end
end

function Family.applies(g, scene_id)
  return g.house ~= nil and g.house.floors ~= nil and floor_index(g.house, scene_id) ~= nil
end

-- cel·la de referència d'una planta (el seu primer spawn) i component connex
local function reference(g, floor)
  local spec = g.generated[floor].spec
  for _, o in ipairs(spec.objects or {}) do
    if o.type == 'spawn' then return o.x, o.y end
  end
end

-- pla: per a cada tipus (kitchen, sofa…) la planta i les cel·les lliures i connectades; es calcula una vegada
function Family.plan(g)
  local H = g.house
  if not H or not H.floors then return nil end
  if H.family_plan then return H.family_plan end
  local per = {}
  for _, f in ipairs(H.floors) do
    local gen = g.generated and g.generated[f]
    if gen then
      local map = g:get_map(f)
      local sc = Family.scan(gen.spec, g.tile_defs)
      local rx, ry = reference(g, f)
      local comp = rx and map:component(rx, ry) or 0
      for kind, list in pairs(sc) do
        local ok = {}
        for _, c in ipairs(list) do
          if comp ~= 0 and map:component(c.x, c.y) == comp then ok[#ok + 1] = c end
        end
        sc[kind] = ok
      end
      per[f] = sc
    end
  end
  local plan = {}
  local function choose(kind, entry_first)
    -- primer la planta preferida (la de l'entrada o no); després les altres
    local pref, rest = {}, {}
    for _, f in ipairs(H.floors) do
      if (f == H.entry) == entry_first then pref[#pref + 1] = f else rest[#rest + 1] = f end
    end
    for _, group in ipairs({ pref, rest }) do
      for _, f in ipairs(group) do
        if per[f] and #per[f][kind] > 0 then return { floor = f, cells = per[f][kind] } end
      end
    end
  end
  plan.kitchen = choose('kitchen', true)
  plan.fridge = choose('fridge', true) or plan.kitchen
  plan.sofa = choose('sofa', true) or plan.kitchen
  plan.office = choose('office', true) or plan.sofa   -- (a la planta de l'entrada si n'hi ha: es veuen en entrar)
  plan.bed = choose('bed', false)
  H.family_plan = plan
  return plan
end

-- on ha de ser un rol en aquest moment: { floor, x, y, face } (cel·les)
function Family.target(plan, role, slot)
  if slot == 'out' then return nil end   -- fora de casa (missió)
  local e = plan[slot] or plan.sofa or plan.kitchen
  if not e then return nil end
  local cells = e.cells
  local i
  if role == 'mare' then i = 1
  elseif slot == 'sofa' then i = math.min(#cells, 3)
  else i = math.min(#cells, 2) end
  if slot == 'bed' and role == 'pare' and #cells >= 2 then i = math.max(2, math.floor(#cells / 2)) end
  local c = cells[i] or cells[1]
  return { floor = e.floor, x = c.x, y = c.y, face = c.face }
end

local function hop(H, cur, tgt)
  if cur == tgt then return nil end
  if cur == H.entry then return tgt end
  return H.entry
end

local function stair_cell(g, floor, to)
  for _, o in ipairs(g.generated[floor].spec.objects or {}) do
    if o.type == 'exit' and o.target_scene == to then return o.x, o.y end
  end
end

local function arrival_cell(g, floor, from)
  local spec = g.generated[floor].spec
  for _, o in ipairs(spec.objects or {}) do
    if o.type == 'spawn' and o.name == 'from_' .. from then return o.x, o.y end
  end
  local x, y = reference(g, floor)
  return x, y
end

-- de nit dormen al costat del llit: es veuen, amb una bafarada «Zzz…» (no s'amaguen: una nena de 5 anys els busca)
function Family.sleep(n, on)
  n.asleep = on or nil
  if on then n.bubble = { text = 'Zzz...', t = 1e9 } elseif n.bubble and n.bubble.text == 'Zzz...' then n.bubble = nil end
end

-- ---------------------------------------------------------------- escena
function Family.attach(w)
  local g, st = w.game, w.state
  if not Family.applies(g, w.id) then return end
  local plan = Family.plan(g)
  if not plan or not plan.kitchen then return end
  local NPC = require('src.entities.npc')
  local nm = names(g)
  g.house.family_where = g.house.family_where or {}
  local F = { npc = {}, rt = {}, last_clock = st.clock or 600, t = 0, tick = 0, plan = plan,
             rng = love.math.newRandomGenerator(g.house.entry:len() * 31 + 7) }
  w.family = F
  for i, role in ipairs(ROLES) do
    local key = 'parent_' .. role
    g.sprites.chars[key] = g.sprites.chars[key] or look_for(g, role)
    local obj = { name = key, x = 0, y = 0, props = { sprite = key, say_name = nm[role], parent = role, owner = 'player',
                                                      facing = 'down', wander = 0, say = '...' } }
    local n = NPC.new(obj, g.sprites.chars[key], 300 + i)
    n.routine = { kind = 'family', place = 'home' }
    local slot = Family.slot_for(st, role)
    local tgt = Family.target(plan, role, slot)
    F.rt[role] = { slot = slot, target = tgt }
    if tgt and tgt.floor == w.id then
      n.body.x, n.body.y = tgt.x * 16 + 8, tgt.y * 16 + 8
      n.facing, n.base_facing = tgt.face, tgt.face
      n.hidden = false; Family.sleep(n, slot == 'bed')
      g.house.family_where[role] = w.id
    else
      n.hidden = true
      n.body.x, n.body.y = 0, 0
      if tgt then g.house.family_where[role] = tgt.floor end
    end
    n:sync_blocker()
    F.npc[role] = n
    w.npcs[#w.npcs + 1] = n
  end
end

local function go(w, F, role, n, gx, gy, dt)
  local AStar = require('src.world.astar')
  local rt = F.rt[role]
  F.walk = F.walk or AStar.walker(w.map)
  local pb = w.player.body
  if (pb.x - n.body.x) ^ 2 + (pb.y - n.body.y) ^ 2 < 11 ^ 2 then n.walk = nil; return false end   -- no encavalcar
  if not rt.path or rt.wp > #rt.path or rt.goal_x ~= gx or rt.goal_y ~= gy then
    if w.town.path_budget <= 0 then return false end
    w.town.path_budget = w.town.path_budget - 1
    local sx, sy = math.floor(n.body.x / 16), math.floor(n.body.y / 16)
    local path = AStar.find(F.walk, sx, sy, gx, gy, 800)
    rt.path = AStar.waypoints(path)
    local last = path[#path]
    if #rt.path == 0 or last[1] ~= gx or last[2] ~= gy then
      rt.path = { { gx * 16 + 8, gy * 16 + 8 } }
    else
      rt.path[#rt.path + 1] = { gx * 16 + 8, gy * 16 + 8 }
    end
    rt.wp, rt.goal_x, rt.goal_y = 1, gx, gy
  end
  local p = rt.path[rt.wp]
  local dx, dy = p[1] - n.body.x, p[2] - n.body.y
  local d = math.sqrt(dx * dx + dy * dy)
  local step = WALK * dt
  if d <= step then
    n.body.x, n.body.y = p[1], p[2]
    rt.wp = rt.wp + 1
  else
    n.body.x, n.body.y = n.body.x + dx / d * step, n.body.y + dy / d * step
  end
  if math.abs(dx) > math.abs(dy) then n.facing = dx > 0 and 'right' or 'left' else n.facing = dy > 0 and 'down' or 'up' end
  n.walk = n.facing
  n.anim = (n.anim or 0) + dt
  n:sync_blocker()
  return true
end

-- un altre racó del mateix lloc (mateixa planta) on fer l'activitat
local function pick_sub(plan, slot, tgt, rng)
  local lists = { plan[slot] }
  if slot == 'kitchen' then lists[2] = plan.fridge end
  local cands = {}
  for _, e in ipairs(lists) do
    if e.floor == tgt.floor then
      for i, c in ipairs(e.cells) do if i <= 6 and not (c.x == tgt.x and c.y == tgt.y) then cands[#cands + 1] = c end end
    end
  end
  if #cands == 0 then return nil end
  return cands[rng:random(1, #cands)]
end

function Family.update(w, dt)
  local F = w.family
  if not F then return end
  local g, st = w.game, w.state
  local H = g.house
  local clock = st.clock or 600
  local jumped = math.abs(((clock - F.last_clock + 720) % 1440) - 720) > 20
  F.last_clock = clock
  F.tick = F.tick - dt
  local rechoose = F.tick <= 0 or jumped
  if rechoose then F.tick = 1 end
  for _, role in ipairs(ROLES) do
    local n, rt = F.npc[role], F.rt[role]
    if rechoose then
      local slot = Family.slot_for(st, role)
      if slot ~= rt.slot or jumped then
        rt.slot, rt.target, rt.path, rt.sub, rt.alt_t = slot, Family.target(F.plan, role, slot), nil, nil, nil
        if jumped then rt.snap = true end
      end
    end
    local tgt = rt.target
    local where = H.family_where[role]
    if not tgt then n.hidden = true; Family.sleep(n, false) end   -- fora de casa
    if tgt then
      if where ~= w.id then
        -- no és a aquesta planta: hi arriba si li toca estar-hi (per l'escala, o directe si ha saltat l'hora)
        if tgt.floor == w.id then
          local x, y
          if rt.snap or not floor_index(H, where or '') then x, y = tgt.x, tgt.y
          else x, y = arrival_cell(g, w.id, where) end
          if x then
            n.body.x, n.body.y = x * 16 + 8, y * 16 + 8
            n.hidden, n.walk, rt.path = false, nil, nil
            n:sync_blocker()
            H.family_where[role] = w.id
            where = w.id
          end
        else
          H.family_where[role] = tgt.floor
        end
      end
      if H.family_where[role] == w.id then
        if rt.snap then
          rt.snap, rt.path, n.walk = nil, nil, nil
          if tgt.floor == w.id then
            n.body.x, n.body.y = tgt.x * 16 + 8, tgt.y * 16 + 8
            n.facing, n.base_facing = tgt.face, tgt.face
            n.hidden = false; Family.sleep(n, rt.slot == 'bed')
            n:sync_blocker()
          else
            n.hidden = true
            H.family_where[role] = tgt.floor
          end
        end
        local eff = (rt.sub and tgt.floor == w.id) and rt.sub or tgt
        local gx, gy, leaving
        if tgt.floor == w.id then gx, gy = eff.x, eff.y
        else
          local nxt = hop(H, w.id, tgt.floor)
          gx, gy = stair_cell(g, w.id, nxt)
          leaving = nxt
          if not gx then H.family_where[role] = tgt.floor; n.hidden = true end   -- sense escala: salta
        end
        if gx and H.family_where[role] == w.id and w.talking ~= n then
          local at = (n.body.x - (gx * 16 + 8)) ^ 2 + (n.body.y - (gy * 16 + 8)) ^ 2 < 5 ^ 2
          if at then
            n.walk = nil
            if leaving then
              n.hidden = true
              H.family_where[role] = leaving
            else
              n.hidden = false; Family.sleep(n, rt.slot == 'bed')
              n.facing, n.base_facing = eff.face, eff.face
              -- l'interior no fa passar el temps: de tant en tant canvien de racó (cuina ↔ nevera, sofà…)
              rt.alt_t = (rt.alt_t or (8 + F.rng:random() * 10)) - dt
              if rt.alt_t <= 0 and not n.hidden then
                rt.alt_t = nil
                rt.sub = pick_sub(F.plan, rt.slot, tgt, F.rng)
              end
            end
          else
            if n.hidden then n.hidden = false end
            go(w, F, role, n, gx, gy, dt)
          end
        end
      end
    end
  end
end

-- pares d'un amic o familiar (no dels avis) com a objectes npc d'un interior de procgen: a la cuina, al sofà o al
-- despatx segons l'hora; de nit dormen (no apareixen). Llegeixen els noms editats a f.parents.
-- → llista d'objectes { type = 'npc', … } perquè Game:friend_interior els afegeixi al spec
function Family.friend_parents(g, spec, f, st)
  if not f or f.role == 'avi' or f.role == 'avia' then return {} end
  local Profile = require('src.profile')
  local nm = Profile.parents_of(nil, f)
  local sc = Family.scan(spec, g.tile_defs or {})
  local seed = 0
  for i = 1, #tostring(f.id) do seed = seed + tostring(f.id):byte(i) * i end
  local out, used = {}, {}
  for i, role in ipairs(ROLES) do
    local slot = Family.slot(role, st and st.clock, st and st.day)
    if slot ~= 'bed' then
      if slot == 'office' then slot = 'sofa' end
      local list = sc[slot]
      if not list or #list == 0 then list = sc.sofa end
      if not list or #list == 0 then list = sc.kitchen end
      local c
      for k = 0, (list and #list or 0) - 1 do
        local cand = list[(seed + i + k) % #list + 1]
        if not used[cand.y * spec.w + cand.x] then c = cand; break end
      end
      if c then
        used[c.y * spec.w + c.x] = true
        local key = 'fparent_' .. role .. '_' .. tostring(f.id)
        if g.sprites and g.sprites.chars and not g.sprites.chars[key] then
          g.sprites.chars[key] = look_for(g, role, seed + i, f.look and tonumber(f.look.skin))
        end
        out[#out + 1] = { type = 'npc', x = c.x, y = c.y, sprite = key, name = nm[role],
                          say = { '...' }, facing = c.face, wander = 0, parent = role, owner = f.id }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- converses
function Family.talk(w, n)
  local p = n.props
  local st, g = w.state, w.game
  n.talks = (n.talks or 0) + 1
  local lines
  if p.owner == 'player' then
    local rt = w.family and w.family.rt[p.parent]
    lines = Family.lines({ name = st.player_name, role = p.parent, slot = rt and rt.slot, clock = st.clock,
                           hp = st.hp, max_hp = st.max_hp, scares = st.scares, talks = n.talks,
                           we = Schedule.weekend(st.day) })
    w.dialogue:show(p.say_name .. (p.parent == 'mare' and ' (mare)' or ' (pare)'), lines)
    require('src.systems.town').event(w, 'event', { name = 'parent_' .. p.parent })
    return true
  end
  local f = require('src.systems.town').friend(g, p.owner) or {}
  local here = false
  for _, o in ipairs(w.npcs) do if o.props.friend == p.owner and not o.hidden then here = true end end
  lines = Family.friend_lines({ name = st.player_name, friend = f.name or 'El teu amic', role = p.parent,
                                here = here, talks = n.talks })
  w.dialogue:show(p.say_name .. (p.parent == 'mare' and ' (mare)' or ' (pare)'), lines)
  return true
end

-- ---------------------------------------------------------------- llit i nevera
local function rest_mod()
  local ok, R = pcall(require, 'src.systems.rest')
  return ok and type(R) == 'table' and R or nil
end

local function ahead(w, fx, fy)
  local F = w.family
  if not F and not Family.applies(w.game, w.id) then return nil end
  local spec = w.game.generated[w.id].spec
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  if tx < 0 or ty < 0 or tx >= spec.w or ty >= spec.h then return nil end
  local n = spec.structures[ty * spec.w + tx + 1] or ''
  if n == 'i_bed_t' or n == 'i_bed_b' or n == 'i_bed' then return 'bed' end
  if n == 'i_fridge' then return 'fridge' end
end

function Family.can_interact(w, fx, fy) return ahead(w, fx, fy) ~= nil end

function Family.interact(w, fx, fy)
  local kind = ahead(w, fx, fy)
  if not kind then return false end
  local st = w.state
  local R = rest_mod()
  if kind == 'bed' then
    if R and R.sleep then R.sleep(w); return true end
    -- recanvi: dormir 8 h cura i restableix
    st.hp, st.mp = st.max_hp or st.hp, st.max_mp or st.mp
    local c = (st.clock or 600) + 480
    if c >= 1440 then st.day = (st.day or 1) + 1 end
    st.clock = c % 1440
    w.hud:toast('Has dormit 8 hores: vida i energia al màxim', 3)
    return true
  end
  if R and R.eat then R.eat(w); return true end
  local now = (st.day or 1) * 1440 + (st.clock or 600)
  if st.family_fed and now - st.family_fed < 120 then
    w.hud:toast('Ja has menjat fa poc', 2)
    return true
  end
  st.family_fed = now
  if st.max_hp then st.hp = math.min(st.max_hp, (st.hp or 0) + math.ceil(st.max_hp * 0.35)) end
  if st.max_mp then st.mp = math.min(st.max_mp, (st.mp or 0) + math.ceil(st.max_mp * 0.35)) end
  w.hud:toast('Has menjat alguna cosa de la nevera', 2.5)
  return true
end

return Family
