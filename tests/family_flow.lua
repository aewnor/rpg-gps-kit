-- Pare i mare a la casa del jugador (love . --test=tests/family_flow.lua --keephome --mute):
-- apareixen amb nom, segueixen l'horari (cuina/sofà/despatx), dormen de nit (es veuen, amb «Zzz»), canvien de
-- planta per l'escala, parlen i el llit i la nevera funcionen.
return function(api)
  local game = api.scene().game
  if not game.house or not game.house.floors then print('[test] SKIP família: no hi ha casa_privada.json'); return end
  local Family = require('src.systems.family')
  local Profile = require('src.profile')
  local st = game.state
  st.day, st.clock = 2, 12 * 60   -- dimarts, migdia
  game:change(game.house.entry, 'spawn_in')
  api.wait(60)
  local w = api.scene()
  api.check(w.id == game.house.entry and w.family ~= nil, 'a la casa hi ha família (' .. tostring(w.id) .. ')')
  if not w.family then return end

  local names = Profile.parents_of(game.profile)
  local seen = {}
  for _, n in ipairs(w.npcs) do
    if n.props.parent then seen[n.props.parent] = n; api.check(n.props.say_name == names[n.props.parent], 'el pare/la mare porta el seu nom') end
  end
  api.check(seen.pare and seen.mare, 'hi ha pare i mare')

  -- migdia: tots dos a la cuina, visibles i sobre una cel·la lliure
  local function cell_free(n)
    return require('src.world.collision').walk_at(w.map:cell(math.floor(n.body.x / 16), math.floor(n.body.y / 16)), 0)
  end
  for _, role in ipairs(Family.ROLES) do
    local n = seen[role]
    local tgt = Family.target(w.family.plan, role, Family.slot(role, st.clock, st.day))
    api.check(n.hidden == (tgt.floor ~= w.id), role .. ' és visible només si li toca ser aquí (' .. tgt.floor .. ')')
    if not n.hidden then api.check(cell_free(n), role .. ' no està encastat a la paret') end
  end

  -- converses amb diàleg propi
  local n = seen.mare
  local pb = api.player().body
  pb.x, pb.y = n.body.x, n.body.y + 14
  api.player().facing = 'up'
  api.press('confirm'); api.wait(5)
  api.check(w.dialogue.open, 'parlar amb la mare obre un diàleg')
  for _ = 1, 8 do if w.dialogue.open then api.press('confirm'); api.wait(8) end end
  api.check(not w.dialogue.open, 'el diàleg es tanca')

  -- de nit: dormen (amagats); el rellotge salta i les rutines s'ajusten sense quedar-se encastades
  st.clock = 23 * 60
  api.wait(40)
  for _, role in ipairs(Family.ROLES) do
    local tgt = Family.target(w.family.plan, role, 'bed')
    local where = game.house.family_where[role]
    api.check(tgt ~= nil and where == tgt.floor, role .. ' dorm a la planta del llit (' .. tostring(where) .. ')')
  end
  for _, role in ipairs(Family.ROLES) do
    api.check(seen[role].hidden, role .. ' no es veu: dorm al llit o és a una altra planta')
  end

  -- al matí tornen a baixar a la cuina caminant per l'escala
  st.clock = 7 * 60 + 30
  api.wait(60)
  local kitchen = Family.target(w.family.plan, 'mare', 'kitchen')
  api.check(game.house.family_where.mare == kitchen.floor, 'al matí la mare és a la cuina (' .. tostring(game.house.family_where.mare) .. ')')

  -- a les 13:30 el pare puja del despatx pel replà i camina fins a la cuina (sense salts)
  -- (l'interior no fa avançar el rellotge: el movem a mà, sense salts de més de 20 min)
  st.day, st.clock = 2, 13 * 60 + 29
  api.wait(30)
  st.clock = 13 * 60 + 31
  local tgt = Family.target(w.family.plan, 'pare', 'kitchen')
  local px, py = tgt.x * 16 + 8, tgt.y * 16 + 8
  local far0 = false
  for _ = 1, 90 do   -- (el despatx pot ser a la mateixa planta, lluny: casa de 80 caselles)
    api.wait(15)
    local n = seen.pare
    if not n.hidden and (n.body.x - px) ^ 2 + (n.body.y - py) ^ 2 > 24 ^ 2 then far0 = true end
    if not n.hidden and (n.body.x - px) ^ 2 + (n.body.y - py) ^ 2 < 5 ^ 2 then break end
  end
  local n = seen.pare
  api.check(far0, 'el pare apareix lluny de la cuina (arriba per l\'escala)')
  api.check(not n.hidden and (n.body.x - px) ^ 2 + (n.body.y - py) ^ 2 < 8 ^ 2, 'el pare arriba caminant a la cuina')

  -- nevera i llit (recanvi si no hi ha Rest)
  local spec = game.generated[w.id].spec
  local function find(name)
    for y = 0, spec.h - 1 do for x = 0, spec.w - 1 do
      if spec.structures[y * spec.w + x + 1] == name then return x, y end
    end end
  end
  local fx, fy = find('i_fridge')
  if fx then
    st.hp = 1; st.family_fed = nil
    api.check(Family.can_interact(w, fx * 16 + 8, fy * 16 + 8), 'la nevera és interactuable')
    api.check(Family.interact(w, fx * 16 + 8, fy * 16 + 8) and (st.hp > 1 or not st.max_hp), 'la nevera cura')
  end

  -- dormir (Rest.sleep, si existeix) salta 8 h: els pares s'han de recol·locar segons la nova hora (no quedar amagats)
  local Rest_ok, Rest = pcall(require, 'src.systems.rest')
  if Rest_ok and Rest.sleep then
    st.day, st.clock = 2, 10 * 60
    api.wait(30)
    Rest.sleep(w)
    for _ = 1, 40 do if not w.rest_fx then break end api.wait(15) end
    api.wait(60)
    api.check(not w.rest_fx, 'ha acabat de dormir')
    api.check(st.clock >= 17 * 60 and st.clock < 19 * 60, 'han passat 8 h (' .. math.floor(st.clock) .. ')')
    for _, role in ipairs(Family.ROLES) do
      local slot = Family.slot(role, st.clock, st.day)
      local tgt = Family.target(w.family.plan, role, slot)
      api.check(seen[role].hidden == (tgt.floor ~= w.id), role .. ' es recol·loca després de dormir (' .. slot .. ')')
    end
  end

  -- de nit no s'amaguen: a la planta del llit es veuen, amb «Zzz»; i surten de casa només si una missió ho diu
  st.clock = 23 * 60 + 30
  local plan = w.family.plan
  local bedf = plan.bed and plan.bed.floor
  if bedf then
    game:change(bedf, 'spawn_in')
    api.wait(60)
    local w2 = api.scene()
    local vis = 0
    for _, n2 in ipairs(w2.npcs) do if n2.props.parent and not n2.hidden and n2.asleep then vis = vis + 1 end end
    api.check(vis == 2, 'de nit, el pare i la mare dormen i es veuen (' .. vis .. ')')
    st.family_out = true
    api.wait(90)
    local out = 0
    for _, n2 in ipairs(w2.npcs) do if n2.props.parent and n2.hidden then out = out + 1 end end
    api.check(out == 2, 'amb una missió que els fa sortir, no són a casa')
    st.family_out = nil
  end
end
