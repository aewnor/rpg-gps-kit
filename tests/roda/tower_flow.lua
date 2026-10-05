-- Les profunditats del Cucurull resoltes de cap a cap (love . --test=tests/tower_flow.lua --mute): la paret de
-- l'estrella, blocs a les plaques, runes en ordre, la clau, la porta amb pany, els brasers i l'amulet.
-- Desa torre_secret.png, torre_blocs.png, torre_runes.png i torre_tresor.png.
return function(api)
  local Input = require('src.input')
  local State = require('src.state')
  local g = api.scene().game
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local st = api.state()
  st.char_level = math.max(st.char_level or 1, 4)

  -- 1) la paret secreta al peu de la torre
  local w = api.scene()
  local door
  for _, d in ipairs(w.doors) do if d.obj.props.target_scene == 'torre_cucurull' then door = d end end
  api.check(door ~= nil, 'hi ha la porta secreta del Cucurull')
  if not door then return end
  local dx, dy = math.floor(door.rect.x / 16), math.floor(door.rect.y / 16)
  api.teleport(dx, dy + 1)
  api.player().facing = 'up'
  api.wait(5)
  Input.hold('up', true); api.wait(20); Input.release_all()
  api.check(api.scene() == w, 'abans de trobar l\'estrella, la paret no deixa passar')
  api.teleport(dx, dy + 2); api.player().facing = 'up'; api.wait(3)   -- un pas enrere: el cap no tapa la paret
  shot('torre_secret.png')
  api.teleport(dx, dy + 1); api.player().facing = 'up'; api.wait(3)
  api.press('confirm'); api.wait(5); api.talk_through()
  api.check(State.flag(st, 'cucurull_secret'), 'tocant la pedra de l\'estrella s\'obre el passadís')
  Input.hold('up', true)
  for _ = 1, 120 do if api.scene() ~= w and not g.transition then break end; api.wait(1) end
  Input.release_all()
  for _ = 1, 120 do if not g.transition then break end; api.wait(1) end
  api.wait(10)
  local t = api.scene()
  api.check(t.id == 'torre_cucurull', 'has entrat a les profunditats del Cucurull (' .. tostring(t.id) .. ')')
  if t.id ~= 'torre_cucurull' then return end
  st.ward_t = 9999   -- els enemics no han d'aturar la prova

  local function block(name)
    for _, b in ipairs(t.puzzle.blocks) do if b.name == name then return b end end
  end
  -- empeny `b` cap a `dir` fins que arribi a (tx, ty)
  local OPP = { left = { 1, 0 }, right = { -1, 0 }, up = { 0, 1 }, down = { 0, -1 } }
  local function push(name, dir, tx, ty)
    local b = block(name)
    for _ = 1, 12 do
      if (b.tx == tx and b.ty == ty) then break end
      api.teleport(b.tx + OPP[dir][1], b.ty + OPP[dir][2])
      api.player().facing = dir
      api.wait(2)
      local before = b.tx * 100 + b.ty
      Input.hold(dir, true)
      for _ = 1, 40 do if b.tx * 100 + b.ty ~= before then break end; api.wait(1) end
      Input.release_all()
      api.wait(12)
      if b.tx * 100 + b.ty == before then break end
    end
    return b.tx == tx and b.ty == ty
  end
  local function gate(name) for _, gt in ipairs(t.gates) do if gt.obj.name == name then return gt end end end

  -- 2) sala A: un bloc a la placa
  api.check(not t:gate_open(gate('reixa_a')), 'la primera reixa és tancada')
  api.check(push('bloc_a', 'right', 22, 34) and push('bloc_a', 'up', 22, 32), 'el bloc arriba a la placa')
  api.wait(3)
  api.check(t:gate_open(gate('reixa_a')), 'amb el bloc a la placa, la reixa s\'obre')
  shot('torre_blocs.png')
  -- 3) sala B: dos blocs a dues plaques
  local ok1 = push('bloc_b1', 'left', 11, 23) and push('bloc_b1', 'up', 11, 19)
  api.check(ok1 and not t:gate_open(gate('reixa_b')), 'amb una sola placa, la segona reixa encara és tancada')
  local ok2 = push('bloc_b2', 'right', 28, 23) and push('bloc_b2', 'up', 28, 19)
  api.wait(3)
  api.check(ok2 and t:gate_open(gate('reixa_b')), 'amb les dues plaques, s\'obre')
  -- 4) sala C: runes en ordre (primer s'equivoca)
  local function touch(n)
    for _, r in ipairs(t.puzzle.runes) do
      if r.n == n then api.teleport(r.tx, r.ty + 1); api.player().facing = 'up'; api.wait(2); api.press('confirm'); api.wait(3); api.talk_through() end
    end
  end
  touch(2)
  api.check((t.puzzle.progress.cucurull_runes or 0) == 0, 'si comences per la II, les runes s\'apaguen')
  touch(1); touch(2); touch(3)
  shot('torre_runes.png')
  touch(4)
  api.check(State.flag(st, 'cucurull_runes') and t:gate_open(gate('reixa_c')), 'I, II, III, IV: la reixa s\'obre')
  -- 5) sala D: la clau
  api.teleport(37, 8); api.player().facing = 'up'; api.wait(2); api.press('confirm'); api.wait(5); api.talk_through()
  api.check((st.inventory.clau_torre or 0) == 1, 'tens la Clau de la torre')
  -- 6) la porta amb pany
  api.check(not t:gate_open(gate('porta_tresor')), 'la porta del tresor és tancada')
  api.teleport(28, 2); api.player().facing = 'right'; api.wait(2); api.press('confirm'); api.wait(5); api.talk_through()
  api.check(t:gate_open(gate('porta_tresor')) and (st.inventory.clau_torre or 0) == 0, 'la clau obre la porta (i es gasta)')
  -- 7) els brasers amb la Bola de foc
  State.give(st, 'baston_magic'); st.equipment.weapon = 'baston_magic'
  st.max_mp, st.mp, st.spell = 40, 40, 'foc'
  for _, bx in ipairs({ 14, 25 }) do
    api.teleport(bx, 5); api.player().facing = 'up'; api.wait(2)
    t:cast_spell()
    api.wait(40)
  end
  api.check(State.flag(st, 'cucurull_braser_a') and State.flag(st, 'cucurull_braser_b'), 'la Bola de foc encén els dos brasers')
  api.check(t:gate_open(gate('reixa_alcova')), 'amb els dos brasers encesos, s\'obre l\'alcova')
  -- 8) el tresor
  api.teleport(36, 3); api.player().facing = 'up'; api.wait(2); api.press('confirm'); api.wait(5); api.talk_through()
  api.check((st.inventory.amulet_cucurull or 0) == 1, 'has trobat l\'Amulet del Cucurull')
  shot('torre_tresor.png')
  st.ward_t = 0
  api.on_frame = nil
end
