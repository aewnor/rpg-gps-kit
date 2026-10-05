-- Convierte un interior en formato del editor (procgen.lua, casa de Nena…) en un Map en memoria,
-- sin pasar por tools/compile_maps.py. Misma regla de colisión que tools/zones.py build_interior:
-- tile sólido → 1, agua → 2, resto transitable; la salida y el punto de entrada siempre libres.
local Map = require('src.world.map')

local ProcMap = {}
local CHUNK = 32
local LAYERS = { { 'ground', 'ground' }, { 'detail', 'ground_detail' }, { 'structures', 'structures' },
                 { 'overhead', 'overhead' } }

-- componentes conexas a nivel 0 (4-vecinos), como walkgraph.components_fast
local function components(coll, w, h)
  local comp, n = {}, 0
  for i = 1, w * h do comp[i] = 0 end
  for s = 1, w * h do
    if coll[s] == 0 and comp[s] == 0 then
      n = n + 1
      comp[s] = n
      local q, head = { s }, 1
      while q[head] do
        local i = q[head]; head = head + 1
        local x, y = (i - 1) % w, math.floor((i - 1) / w)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and ny >= 0 and nx < w and ny < h then
            local j = ny * w + nx + 1
            if coll[j] == 0 and comp[j] == 0 then comp[j] = n; q[#q + 1] = j end
          end
        end
      end
    end
  end
  return comp
end

-- spec: { w, h, name, ground/detail/structures/overhead = nombres, objects, spawn }
-- tiles: data/tiles.json .tiles; back: { scene, x, y, level } adonde lleva la salida por defecto
-- Devuelve el Map y la lista de avisos.
function ProcMap.build(scene_id, spec, tiles, back, anim)
  local w, h = spec.w, spec.h
  local warns = {}
  local layers, coll = {}, {}
  for i = 1, w * h do coll[i] = 0 end
  for _, l in ipairs(LAYERS) do
    local names, arr, any = spec[l[1]] or {}, {}, false
    for i = 1, w * h do
      local nm = names[i]
      local id = 0
      if nm and nm ~= '' then
        local t = tiles[nm]
        if t then
          id = t.id + 1; any = true
          if l[1] ~= 'overhead' then
            if t.solid then coll[i] = 1 elseif t.water and coll[i] == 0 then coll[i] = 2 end
          end
        else
          warns[#warns + 1] = 'tile desconocido ' .. nm
        end
      end
      if l[1] == 'ground' and id == 0 then id = tiles.i_floor_wood_0.id + 1 end
      arr[i] = id
    end
    if any or l[1] == 'ground' then layers[l[2]] = arr end
  end
  local objects = {}
  local exit_seen
  for k, o in ipairs(spec.objects or {}) do
    local px, py = o.x * 16, o.y * 16
    local nm = scene_id .. '_' .. o.type .. '_' .. k
    if o.type == 'exit' then
      exit_seen = exit_seen or o
      coll[o.y * w + o.x + 1] = 0
      local p = { target_scene = o.target_scene or back.scene, target_spawn = o.target_spawn }
      if not o.target_scene or o.target_x then  -- vuelta a un punto concreto (fachada de origen)
        p.target_x, p.target_y = o.target_x or back.x, o.target_y or back.y
        p.target_level = o.target_level or back.level or 0
        p.target_facing = o.target_facing or back.facing
      end
      objects[#objects + 1] = { type = 'door', name = nm, x = px, y = py, w = 16, h = 16, props = p }
    elseif o.type == 'spawn' then
      objects[#objects + 1] = { type = 'spawn', name = o.name or nm, x = px + 8, y = py + 8, w = 0, h = 0,
                                props = { public = true } }
    elseif o.type == 'npc' then
      local say = o.say or { '...' }
      if type(say) == 'table' then say = table.concat(say, '|') end
      objects[#objects + 1] = { type = 'npc', name = nm, x = px + 8, y = py + 8, w = 0, h = 0,
        props = { sprite = o.sprite or 'npc_elder', facing = o.facing or 'down', say = say,
                  say_name = o.name or '', wander = o.wander or 0, ai = o.ai, persona = o.persona,
                  service = o.service, service_id = o.service_id, label = o.label, friend = o.friend,
                  parent = o.parent, owner = o.owner, cart = o.cart, route = o.route, cart_load = o.cart_load } }
    elseif o.type == 'arcade' then   -- màquina o aparell d'un minijoc (procgen.poi): el tile ja és sòlid
      local p = {}
      for k, v in pairs(o) do if k ~= 'type' and k ~= 'x' and k ~= 'y' then p[k] = v end end
      objects[#objects + 1] = { type = 'arcade', name = nm, x = px, y = py, w = 16, h = 16, props = p }
    elseif o.type == 'chest' then   -- cofre amb objecte fix (item) o per categoria (tier); flag: obert o no
      objects[#objects + 1] = { type = 'chest', name = nm, x = px, y = py, w = 16, h = 16,
                                props = { flag = o.flag or (scene_id .. '_chest_' .. k), item = o.item, tier = o.tier } }
    elseif o.type == 'parked_car' then   -- cotxe aparcat (casa del plànol: el pàrquing), el dibuixa el món
      objects[#objects + 1] = { type = 'parked_car', name = nm, x = px + 8, y = py + 8, w = 0, h = 0,
                                props = { color = o.color or 1, orient = o.orient or 'h' } }
    elseif o.type == 'display' then
      objects[#objects + 1] = { type = 'sign', name = nm, x = px + 8, y = py + 8, w = 0, h = 0,
        props = { display = true, section = o.section, service_id = o.service_id } }
    elseif o.type == 'sign' then
      coll[o.y * w + o.x + 1] = 1
      local say = o.say or { '...' }
      if type(say) == 'table' then say = table.concat(say, '|') end
      objects[#objects + 1] = { type = 'sign', name = nm, x = px + 8, y = py + 8, w = 0, h = 0,
                                props = { say = say, book = o.book } }   -- book: llibre a la prestatgeria (sense rètol)
    end
  end
  local sx, sy
  local first_spawn
  for _, o in ipairs(spec.objects or {}) do if o.type == 'spawn' then first_spawn = first_spawn or o end end
  if spec.spawn then sx, sy = spec.spawn[1], spec.spawn[2]
  elseif first_spawn then sx, sy = first_spawn.x, first_spawn.y
  elseif exit_seen then sx, sy = exit_seen.x, exit_seen.y - 1 end
  sx, sy = sx or math.floor(w / 2), sy or h - 2
  if coll[sy * w + sx + 1] ~= 0 then
    warns[#warns + 1] = 'punto de entrada bloqueado'
    coll[sy * w + sx + 1] = 0
  end
  objects[#objects + 1] = { type = 'spawn', name = 'spawn_in', x = sx * 16 + 8, y = sy * 16 + 8, w = 0, h = 0,
                            props = { public = true, facing = spec.spawn_facing } }
  local comp = components(coll, w, h)

  -- chunks ya construidos (los interiores caben en pocos)
  local built = {}
  local cxn, cyn = math.ceil(w / CHUNK), math.ceil(h / CHUNK)
  for cy = 0, cyn - 1 do
    for cx = 0, cxn - 1 do
      local cw, ch = math.min(CHUNK, w - cx * CHUNK), math.min(CHUNK, h - cy * CHUNK)
      local c = { w = cw, h = ch, coll = {}, comp = {} }
      for name, arr in pairs(layers) do c[name] = {} end
      for y = 0, ch - 1 do
        for x = 0, cw - 1 do
          local src = (cy * CHUNK + y) * w + cx * CHUNK + x + 1
          local dst = y * cw + x + 1
          for name, arr in pairs(layers) do c[name][dst] = arr[src] end
          c.coll[dst], c.comp[dst] = coll[src], comp[src]
        end
      end
      built[string.format('c_%d_%d.bin', cx, cy)] = c
    end
  end
  local index = { scene = scene_id, width = w, height = h, chunk = CHUNK, tile = 16, zones = {},
                  chunks_x = cxn, chunks_y = cyn, objects = objects, routes = {}, anim = anim or {},
                  props = { scene = scene_id, interior = true, name = spec.name or scene_id } }
  local dir = 'proc/' .. scene_id
  local m = Map.load(dir, function(p)
    if p == dir .. '/index.lua' then return index end
    error('no existe ' .. p)
  end, function(p)
    local c = built[p:match('[^/]+$')]
    -- copia: el renderer cuelga lienzos del chunk y lo libera al descargarlo
    local out = {}
    for k, v in pairs(assert(c, p)) do out[k] = v end
    return out
  end)
  m.generated = true
  return m, warns
end

return ProcMap
