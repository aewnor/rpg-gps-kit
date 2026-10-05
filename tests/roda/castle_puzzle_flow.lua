-- Puzles de la Masmorra del Castell (love . --test=tests/castle_puzzle_flow.lua --mute): el bloc fins a la placa
-- obre la reixa del cofre llegendari i la paret secreta amaga un cofre de plata. Desa castell_puzle.png.
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
  st.char_level = math.max(st.char_level or 1, 3)
  local ow = api.scene()
  local door
  for _, d in ipairs(ow.doors) do if d.obj.props.target_scene == 'masmorra_castell' then door = d end end
  api.check(door ~= nil, 'hi ha la porta de la masmorra')
  if not door then return end
  api.player().body.x, api.player().body.y = door.rect.x + 16, door.rect.y + 8 + 20; api.wait(5)
  api.player().body.y = door.rect.y + 8
  for _ = 1, 120 do if api.scene() ~= ow and not g.transition then break end; api.wait(1) end
  for _ = 1, 120 do if not g.transition then break end; api.wait(1) end
  api.wait(10)
  local dun = api.scene()
  api.check(dun.id == 'masmorra_castell', 'dins la masmorra (' .. tostring(dun.id) .. ')')
  if dun.id ~= 'masmorra_castell' then return end
  st.ward_t = 9999
  local function gate(name) for _, gt in ipairs(dun.gates) do if gt.obj.name == name then return gt end end end
  local reixa = gate('reixa_tresor')
  local bl, pla = dun.puzzle.blocks[1], dun.puzzle.plates[1]
  api.check(reixa and bl and pla and bl.ty == pla.ty and bl.tx < pla.tx, 'bloc i placa a la mateixa fila')
  api.check(not dun:gate_open(reixa), 'la reixa del tresor és tancada')
  for _, e in ipairs(dun.enemies) do e.state = 'dead' end   -- un enemic al davant del bloc l'atura
  -- trepitjar la placa no n'hi ha prou
  api.teleport(pla.tx, pla.ty); api.wait(5)
  api.check(not dun:gate_open(reixa), 'el jugador sol no prem la placa')
  for _ = 1, 12 do
    if bl.tx == pla.tx then break end
    api.teleport(bl.tx - 1, bl.ty); api.player().facing = 'right'; api.wait(2)
    local before = bl.tx
    Input.hold('right', true)
    for _ = 1, 40 do if bl.tx ~= before then break end; api.wait(1) end
    Input.release_all(); api.wait(12)
    if bl.tx == before then break end
  end
  api.wait(3)
  api.check(bl.tx == pla.tx and dun:gate_open(reixa), 'amb el bloc a la placa, la reixa s\'obre')
  shot('castell_puzle.png')
  -- el cofre llegendari, ara accessible pel nínxol
  local leg
  for _, c in ipairs(dun.chests) do if c.obj.props.tier == 'legend' then leg = c end end
  api.teleport(math.floor(leg.rect.x / 16), math.floor(leg.rect.y / 16) + 1); api.player().facing = 'up'; api.wait(3)
  api.press('confirm'); api.wait(5); api.talk_through()
  api.check(dun.sstate.chests[leg.obj.props.flag], 'el cofre llegendari s\'obre')
  -- paret secreta
  local s = dun.puzzle.secrets[1]
  api.check(s ~= nil, 'hi ha una paret secreta')
  if s then
    api.teleport(s.tx, s.ty + 1); api.player().facing = 'up'; api.wait(3)
    api.press('confirm'); api.wait(5); api.talk_through()
    api.check(State.flag(st, 'masmorra_secret'), 'la paret secreta s\'enfonsa')
    api.teleport(s.tx, s.ty); api.player().facing = 'up'; api.wait(3)
    api.press('confirm'); api.wait(5); api.talk_through()
    api.check(dun.sstate.chests.cofre_masmorra_amagat, 'el cofre amagat s\'obre')
  end
  st.ward_t = 0
  api.on_frame = nil
end
