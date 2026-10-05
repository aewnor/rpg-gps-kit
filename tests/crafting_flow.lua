-- Creació d'objectes (love . --test=tests/crafting_flow.lua --mute): fusta dels arbres amb l'espasa (un cop per dia
-- per arbre), pedra de les roques, pell del llop, banc de taller a les cases i a la casa del jugador, i la missió
-- «El primer invent». Desa taller.png.
return function(api)
  local Crafting = require('src.systems.crafting')
  local Missions = require('src.systems.missions')
  local Town = require('src.systems.town')
  local State = require('src.state')
  local g = api.scene().game
  local w = api.scene()
  local st = api.state()
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  State.give(st, 'sword_wood'); st.equipment.weapon = 'sword_wood'
  st.stamina = 100
  local defs = Town.defs(g)
  local q = Missions.state(st)
  q.active = nil
  Missions.activate(defs, st, 'taller_primer', Town.hooks(w))
  api.wait(3); api.talk_through()
  -- elements a prop: arbres (tronc) i roques
  local b = api.player().body
  local px, py = math.floor(b.x / 16), math.floor(b.y / 16)
  local trees, rocks = {}, {}
  for r = 1, 40 do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local tx, ty = px + dx, py + dy
          local n = w:tile_name('structures', tx, ty) or ''
          local below = w.map:in_bounds(tx, ty + 1) and require('src.world.collision').walk_at(w.map:cell(tx, ty + 1), 0)
          if below then
            if n:match('^tree_.*_bot$') and #trees < 4 then trees[#trees + 1] = { tx, ty } end
            if n:match('^nature_rock_') and #rocks < 1 then rocks[#rocks + 1] = { tx, ty } end
          end
        end
      end
    end
    if #trees >= 4 and #rocks >= 1 then break end
  end
  api.check(#trees >= 3, 'hi ha arbres a prop (' .. #trees .. ')')
  local function hit(t)
    api.teleport(t[1], t[2] + 1); api.player().facing = 'up'; api.wait(4)
    st.stamina = 100
    api.press('attack'); api.wait(30)
  end
  hit(trees[1])
  api.check((st.inventory.fusta or 0) == 1, 'un cop d\'espasa a l\'arbre: +1 fusta')
  local Collision = require('src.world.collision')
  local t1 = trees[1]
  api.check((w:tile_name('structures', t1[1], t1[2]) or '') == '' and Collision.walk_at(w.map:cell(t1[1], t1[2]), 0),
    'l\'arbre tallat desapareix i s\'hi pot passar')
  api.check(not (w:tile_name('overhead', t1[1], t1[2] - 1) or ''):find('^tree_'), 'la copa també')
  hit(trees[1])
  api.check((st.inventory.fusta or 0) == 1, 'on era l\'arbre ja no en surt més fusta')
  -- en tornar a carregar el tros de mapa, segueix tallat; al cap de 3 dies torna a créixer
  local ch = w.map.chunks
  local cx, cy = math.floor(t1[1] / w.map.chunk), math.floor(t1[2] / w.map.chunk)
  ch.live[cy * 1024 + cx] = nil; ch.count = ch.count - 1
  api.check(Collision.walk_at(w.map:cell(t1[1], t1[2]), 0), 'recarregat el tros de mapa, l\'arbre segueix tallat')
  local day = st.day
  st.day = (st.day or 1) + 3
  ch.live[cy * 1024 + cx] = nil; ch.count = ch.count - 1
  api.check((w:tile_name('structures', t1[1], t1[2]) or ''):find('^tree_') ~= nil, 'al cap de tres dies l\'arbre torna a créixer')
  st.day = day
  hit(trees[2]); hit(trees[3])
  api.check((st.inventory.fusta or 0) == 3, 'tres arbres, tres trossos de fusta')
  local _, s = Missions.current(defs, st)
  api.check(s and s.event == 'crafted', 'la missió passa a «crea un objecte» (' .. tostring(s and s.event) .. ')')
  if rocks[1] then
    hit(rocks[1])
    api.check((st.inventory.pedra or 0) >= 1, 'de la roca surt pedra')
  end
  -- botí dels animals
  Crafting.drop(w, { kind = require('src.entities.enemy').KINDS.wolf })
  api.check((st.inventory.pell or 0) == 2, 'el llop deixa dues pells')
  -- bancs de taller
  local P = require('src.world.procgen')
  local found = 0
  for seed = 1, 20 do
    local spec = P.generate({ kind = 'house', seed = seed })
    for _, o in ipairs(spec.objects) do if o.game == 'taller' then found = found + 1 end end
  end
  api.check(found >= 15, 'les cases tenen banc de taller al menjador (' .. found .. '/20)')
  local spec = P.generate({ kind = 'house', seed = 3 })
  for i, v in ipairs(spec.structures) do if v == 'i_workbench' then spec.structures[i] = '' end end
  for i = #spec.objects, 1, -1 do if spec.objects[i].game == 'taller' then table.remove(spec.objects, i) end end
  api.check(Crafting.ensure_bench(spec) and not Crafting.ensure_bench(spec), 'a la casa del jugador se n\'hi posa un (i només un)')
  -- crear
  local recipe
  for _, r in ipairs(Crafting.data(g).recipes) do if r.item == 'sword_wood' then recipe = r end end
  local swords = st.inventory.sword_wood or 0
  Crafting.open(w)
  api.wait(5)
  local shot = function(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  shot('taller.png')
  local menu = g.menu
  local row
  for _, it in ipairs(menu and menu.list or {}) do
    local label = it[1] or it.label
    if type(label) == 'string' and label:find('Espasa de fusta', 1, true) then row = it end
  end
  api.check(row ~= nil, 'el banc de taller llista l\'espasa de fusta')
  if row then (row[2] or row.fn)() end
  api.wait(5); api.talk_through()
  api.check((st.inventory.sword_wood or 0) == swords + 1 and (st.inventory.fusta or 0) == 0, 'crea l\'espasa i gasta la fusta')
  api.check(q.done.taller_primer, 'missió «El primer invent» feta')
  g:close_menu()
  api.on_frame = nil
end
