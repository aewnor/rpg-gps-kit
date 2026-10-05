-- Creació d'objectes (2026-10-05): materials que es recullen colpejant arbres (fusta), matolls i canyís (fibra) i
-- roques (pedra i de vegades ferro) amb l'espasa, o que deixen els animals (pell del llop i la guineu, cuir del
-- senglar), i un banc de taller a les cases (procgen) i a la casa del jugador on es creen armes, escuts, roba i
-- eines amb receptes. Dades: data/crafting.json. Cada element del mapa dona material un cop per dia de joc.
local State = require('src.state')
local C = {}

function C.data(g)
  if not g.crafting then
    local ok, d = pcall(function() return require('src.lib.json').decode(love.filesystem.read('data/crafting.json')) end)
    g.crafting = ok and d or { gather = {}, drops = {}, recipes = {} }
  end
  return g.crafting
end

-- quin element recollible és la rajola `name` (o nil)
function C.kind_of(name)
  if not name then return nil end
  if name:sub(1, 5) == 'tree_' then return 'tree' end
  if name:sub(1, 5) == 'bush_' then return 'bush' end
  if name == 'nature_reeds' then return 'reeds' end
  if name:sub(1, 12) == 'nature_rock_' then return 'rock' end
  return nil
end

-- ¿hi ha prou materials? retorna true o la llista del que falta { {id, falten} }
function C.missing(st, recipe)
  local out = {}
  local ids = {}
  for id in pairs(recipe.needs or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local have = (st.inventory or {})[id] or 0
    if have < recipe.needs[id] then out[#out + 1] = { id, recipe.needs[id] - have } end
  end
  return #out == 0 and true or out
end

-- crea l'objecte: gasta els materials i el dona. true si s'ha pogut
function C.craft(st, recipe)
  if C.missing(st, recipe) ~= true then return false end
  for id, n in pairs(recipe.needs) do for _ = 1, n do State.take(st, id) end end
  State.give(st, recipe.item)
  st.crafted = (st.crafted or 0) + 1
  return true
end

-- «3 fusta, 1 fibra» (tot el que cal) o, amb missing = true, només el que falta
local function needs_text(g, st, recipe, missing)
  local short = C.data(g).short or {}
  local ids = {}
  for id in pairs(recipe.needs or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local parts = {}
  for _, id in ipairs(ids) do
    local n = recipe.needs[id]
    if missing then n = n - ((st.inventory or {})[id] or 0) end
    if n > 0 then parts[#parts + 1] = n .. ' ' .. (short[id] or (g.items[id] or {}).name or id) end
  end
  return table.concat(parts, ', ')
end

-- el banc de taller: llista de receptes (les que pots fer, primer)
function C.open(w)
  local g, st = w.game, w.state
  local list = {}
  for _, r in ipairs(C.data(g).recipes) do list[#list + 1] = r end
  table.sort(list, function(a, b)
    local ca, cb = C.missing(st, a) == true, C.missing(st, b) == true
    if ca ~= cb then return ca end
    return false
  end)
  local items = {}
  for _, r in ipairs(list) do
    local ok = C.missing(st, r) == true
    local name = (g.items[r.item] or {}).name or r.item
    local label = ok and (name .. ': ' .. needs_text(g, st, r)) or (name .. ': falta ' .. needs_text(g, st, r, true))
    items[#items + 1] = { label, function()
      if C.craft(st, r) then
        g:close_menu()
        g.audio.play('levelup')
        w.fx:preset('sparkle', w.player.body.x, w.player.body.y - 14, 10)
        w.hud:toast('Has creat: ' .. name .. '!', 2.5, true)
        require('src.systems.town').event(w, 'event', { name = 'crafted' })
      else
        g.audio.play('miss')
        w.hud:toast('Et falta: ' .. needs_text(g, st, r, true), 2.5)
      end
    end, sprite = (g.items[r.item] or {}).sprite }
  end
  items[#items + 1] = { 'Tancar', function() g:close_menu() end }
  g:open_list('Banc de taller', items)
end

-- ---------------------------------------------------------------- tallar i trencar
-- L'arbre tallat, la roca trencada o el matoll arrencat desapareixen del mapa i s'hi pot passar; tornen a sortir
-- al cap de REGROW dies de joc. Es desa a state.cut["x,y"] = { day, kind } i s'aplica a cada chunk que es carrega.
C.REGROW = { tree = 3, rock = 5, bush = 2, reeds = 2 }

local function idx(map, c, tx, ty) return (ty % map.chunk) * c.w + (tx % map.chunk) + 1 end

local function chunk_of(map, tx, ty)
  return map.chunks:get(math.floor(tx / map.chunk), math.floor(ty / map.chunk))
end

local function names(g)
  if not g.tile_names then
    g.tile_names = {}
    for name, t in pairs(g.tile_defs) do g.tile_names[t.id + 1] = name end
  end
  return g.tile_names
end

-- treu l'element de la casella (tx, ty) del chunk ja carregat `c` (i la copa o l'ombra si cal); torna els chunks tocats
local function clear(map, g, tx, ty, kind)
  local nm = names(g)
  local touched = {}
  local function set(layer, x, y, pred)
    if not map:in_bounds(x, y) then return end
    local c = chunk_of(map, x, y)
    local l = c[layer]
    local i = idx(map, c, x, y)
    if l and l[i] and l[i] ~= 0 and (not pred or pred(nm[l[i]] or '')) then
      l[i] = 0
      touched[c] = true
    end
  end
  if kind == 'reeds' then
    set('ground_detail', tx, ty)
  else
    set('structures', tx, ty)
    local c = chunk_of(map, tx, ty)
    local i = idx(map, c, tx, ty)
    local code = c.coll[i]
    if code and code % 4 ~= 0 then c.coll[i] = code - code % 4; touched[c] = true end   -- ja s'hi pot passar
    if kind == 'tree' then
      set('overhead', tx, ty - 1, function(n) return n:sub(1, 5) == 'tree_' end)
      for dy = -1, 1 do for dx = -1, 1 do
        set('ground_detail', tx + dx, ty + dy, function(n) return n:sub(1, 7) == 'sh_tree' end)
      end end
    end
  end
  return touched
end

local function refresh(touched)
  local R = require('src.world.renderer')
  for c in pairs(touched) do R.release(c) end   -- es tornarà a construir quan es vegi
end

-- en carregar un chunk: torna a aplicar-hi el que el jugador ha tallat (si encara no ha tornat a créixer)
function C.attach(w)
  if w.id ~= 'overworld' then return end
  local map, g, st = w.map, w.game, w.state
  local function apply(c)
    local cut = st.cut
    if not cut then return end
    local x0, y0 = c.cx * map.chunk, c.cy * map.chunk
    for key, v in pairs(cut) do
      local tx, ty = key:match('^(%-?%d+),(%-?%d+)$')
      tx, ty = tonumber(tx), tonumber(ty)
      if tx and tx >= x0 and ty >= y0 and tx < x0 + map.chunk and ty < y0 + map.chunk then
        if (st.day or 1) - (v.day or 0) >= (C.REGROW[v.kind] or 3) then cut[key] = nil   -- ha tornat a créixer
        else refresh(clear(map, g, tx, ty, v.kind)) end
      end
    end
  end
  map.chunks.on_load = apply
  for _, c in pairs(map.chunks.live) do apply(c) end
end

function C.cut(w, tx, ty, kind)
  local st = w.state
  st.cut = st.cut or {}
  st.cut[tx .. ',' .. ty] = { day = st.day or 1, kind = kind }
  refresh(clear(w.map, w.game, tx, ty, kind))
end

-- recollir: un cop d'espasa sobre un arbre, matoll, canyís o roca (que desapareix fins que torna a créixer)
function C.update(w)
  if not w.def.outdoor or w.id ~= 'overworld' then return end
  local pl = w.player
  local box, id = pl:attack_box()
  if not box or id == w.gather_swing then return end
  w.gather_swing = id
  local st = w.state
  local data = C.data(w.game).gather
  local x0, y0 = math.floor(box.x / 16), math.floor(box.y / 16)
  local x1, y1 = math.floor((box.x + box.w - 1) / 16), math.floor((box.y + box.h - 1) / 16)
  for ty = y0, y1 do
    for tx = x0, x1 do
      local kind = C.kind_of(w:tile_name('structures', tx, ty)) or C.kind_of(w:tile_name('overhead', tx, ty))
          or C.kind_of(w:tile_name('ground_detail', tx, ty))   -- (el canyís és al terra)
      local spec = kind and data[kind]
      if spec then
        if kind == 'tree' and (w:tile_name('structures', tx, ty) or ''):sub(-4) ~= '_bot' then ty = ty + 1 end   -- el tronc
        if st.gathered_day ~= (st.day or 1) then st.gathered, st.gathered_day = {}, st.day or 1 end
        st.gathered = st.gathered or {}
        local key = tx .. ',' .. ty
        local cx, cy = tx * 16 + 8, ty * 16 + 4
        if st.gathered[key] then
          w.hud:toast(kind == 'tree' and 'D\'aquest arbre ja n\'has tret fusta avui' or 'Aquí ja no en queda: torna demà', 1.5)
          return
        end
        st.gathered[key] = true
        C.cut(w, tx, ty, kind)                                       -- desapareix i s'hi pot passar
        State.give(st, spec.item)
        local msg = spec.say or ('+1 ' .. ((w.game.items[spec.item] or {}).name or spec.item))
        if spec.bonus and love.math.random() < (spec.bonus_p or 0) then
          State.give(st, spec.bonus)
          msg = msg .. ' i +1 ' .. ((w.game.items[spec.bonus] or {}).name or spec.bonus) .. '!'
        end
        w.hud:toast(msg, 1.5)
        w.game.audio.play(kind == 'rock' and 'block' or 'swing')
        local col = kind == 'rock' and { 0.7, 0.68, 0.64 } or (kind == 'tree' and { 0.45, 0.62, 0.28 } or { 0.55, 0.7, 0.3 })
        w:puff(cx, cy - (kind == 'tree' and 14 or 0), 8, col, 22, 0.6, 2)
        if w.shaker then w.shaker:add(0.1) end
        if spec.item == 'fusta' then
          st.wood_cut = (st.wood_cut or 0) + 1
          if st.wood_cut >= 3 then require('src.systems.town').event(w, 'event', { name = 'wood_3' }) end
        end
        return
      end
    end
  end
end

-- en vèncer un animal o enemic: materials (data/crafting.json drops)
function C.drop(w, e)
  local key
  for k, v in pairs(require('src.entities.enemy').KINDS) do if v == e.kind then key = k end end
  local list = key and C.data(w.game).drops[key]
  if not list then return end
  for _, d in ipairs(list) do
    if love.math.random() < d[2] then
      for _ = 1, d[3] or 1 do State.give(w.state, d[1]) end
      w.hud:toast('+' .. (d[3] or 1) .. ' ' .. ((w.game.items[d[1]] or {}).name or d[1]), 1.5)
    end
  end
end

-- casa del jugador (casa_privada.json, que no es toca): un banc de taller a la planta d'entrada si no en té.
-- spec = { w, h, ground, structures, objects } de procgen; busca una casella lliure arran de la paret de dalt
-- amb pas lliure a sota i als costats (no tapa cap passadís)
function C.ensure_bench(spec)
  if type(spec) ~= 'table' or type(spec.structures) ~= 'table' or not spec.w then return false end
  for _, o in ipairs(spec.objects or {}) do if o.type == 'arcade' and o.game == 'taller' then return false end end
  local w, h = spec.w, spec.h
  local function at(x, y) return spec.structures[y * w + x + 1] end
  local function free(x, y) return x > 0 and y > 0 and x < w - 1 and y < h - 1 and (at(x, y) or '') == '' end
  for y = 2, h - 3 do
    for x = 2, w - 3 do
      if free(x, y) and not free(x, y - 1) and free(x, y + 1) and free(x - 1, y) and free(x + 1, y)
          and free(x - 1, y + 1) and free(x + 1, y + 1) and free(x, y + 2) then
        spec.structures[y * w + x + 1] = 'i_workbench'
        spec.objects = spec.objects or {}
        table.insert(spec.objects, { type = 'arcade', x = x, y = y, game = 'taller', label = 'Banc de taller' })
        return true
      end
    end
  end
  return false
end

return C
