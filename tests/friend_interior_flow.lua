-- Interiors de cases d'amics (love . --test=tests/friend_interior_flow.lua --mute):
-- pares amb el nom editat, terra del perfil només a la fusta, decoració per rol, tot accessible, interior estable
-- per amic i els avis sense pares.
return function(api)
  local game = api.scene().game
  local Collision = require('src.world.collision')
  local st = game.state
  local back = { scene = 'overworld', x = 100, y = 100, level = 0 }
  local function friend(id, role, kind, floor, door)
    return { id = id, name = 'Amic ' .. id, role = role, look = { age = role == 'avia' and 'elder' or 'child' },
             home = { door_x = door, door_y = 40 }, interior = { kind = kind, floor = floor, cat = true },
             parents = { pare = 'Ramon Test', mare = 'Montse Test' } }
  end
  for _, id in ipairs({ 'tx', 'ty', 'tg' }) do game.sprites.chars['friend_' .. id] = game.sprites.chars.npc_elder end

  local function visit(f, clock)
    st.day, st.clock = 3, clock
    local id = game:friend_interior(f, back)
    game.scene_manager:change(id, 'spawn_in')
    api.wait(40)
    return api.scene()
  end

  -- casa d'un amic: pares amb el nom editat, un dormitori amb les seves coses i la cuina amb rajola
  local f1 = friend('tx', 'amic', 'house', 'carpet', 60)
  local w = visit(f1, 12 * 60)
  api.check(w.id == 'friend_tx', 'entra a la casa de l\'amic (' .. tostring(w.id) .. ')')
  local seen = {}
  for _, n in ipairs(w.npcs) do if n.props.parent then seen[n.props.parent] = n end end
  api.check(seen.pare and seen.pare.props.say_name == 'Ramon Test' and seen.mare and seen.mare.props.say_name == 'Montse Test',
    'hi ha el pare i la mare amb el nom editat')
  local spec = game.generated[w.id].spec
  local carpet, wood, tile = 0, 0, 0
  for _, g in ipairs(spec.ground) do
    if g:match('^i_floor_carpet') then carpet = carpet + 1 elseif g:match('^i_floor_wood') then wood = wood + 1
    elseif g:match('^i_floor_tile') then tile = tile + 1 end
  end
  api.check(carpet > 0 and wood == 0, 'el terra del perfil substitueix la fusta (' .. carpet .. ' catifa)')
  api.check(tile > 0, 'la cuina i el bany conserven la rajola (' .. tile .. ')')
  local toys = 0
  for _, s in ipairs(spec.structures) do if s == 'i_toys' then toys = toys + 1 end end
  api.check(toys > 0, 'casa d\'un nen: joguines')
  -- accessibilitat i diàleg
  local m = w.map
  local pb = api.player().body
  local comp = m:component(math.floor(pb.x / 16), math.floor(pb.y / 16))
  local lost = 0
  for y = 0, m.height - 1 do for x = 0, m.width - 1 do
    if Collision.walk_at(m:cell(x, y), 0) and m:component(x, y) ~= comp then lost = lost + 1 end
  end end
  api.check(lost == 0, 'tot el que es camina és accessible des de l\'entrada (' .. lost .. ' aïllades)')
  local n = seen.mare
  pb.x, pb.y = n.body.x, n.body.y + 14
  api.player().facing = 'up'
  api.press('confirm'); api.wait(5)
  api.check(w.dialogue.open, 'parlar amb la mare de l\'amic obre un diàleg')
  for _ = 1, 8 do if w.dialogue.open then api.press('confirm'); api.wait(8) end end
  api.check(not w.dialogue.open, 'el diàleg es tanca')

  -- estable: mateix amic → mateix interior; un altre amic a la mateixa porta → un altre
  local sig = table.concat(spec.structures, ',')
  local w2 = visit(f1, 12 * 60)
  api.check(table.concat(game.generated[w2.id].spec.structures, ',') == sig, 'tornar a entrar dóna el mateix interior')
  local other = friend('ty', 'amic', 'house', 'wood', 60)
  local w3 = visit(other, 12 * 60)
  api.check(table.concat(game.generated[w3.id].spec.structures, ',') ~= sig, 'cada amic té un interior propi')

  -- de nit els pares dormen; els avis no en tenen i tenen butaques
  local wn = visit(f1, 23 * 60)
  local any = false
  for _, nn in ipairs(wn.npcs) do if nn.props.parent then any = true end end
  api.check(not any, 'de nit els pares no es veuen (dormen)')
  local gran = friend('tg', 'avia', 'house', 'wood', 90)
  local wg = visit(gran, 12 * 60)
  any = false
  for _, nn in ipairs(wg.npcs) do if nn.props.parent then any = true end end
  api.check(not any, 'els avis no tenen pares a casa')
  local arm = 0
  for _, s in ipairs(game.generated[wg.id].spec.structures) do if s == 'i_armchair' then arm = arm + 1 end end
  api.check(arm >= 2, 'casa d\'avis: butaques (' .. arm .. ')')

  -- bloc de pisos
  local blk = friend('tx', 'amic', 'block', 'tile', 70)
  local wp = visit(blk, 12 * 60)
  api.check(wp.id == 'friend_tx', 'el bloc s\'entra pel portal (' .. wp.id .. ')')
  game.scene_manager:change('friend_tx_p1_1', 'spawn_in')
  api.wait(40)
  local wb = api.scene()
  api.check(wb.id == 'friend_tx_p1_1', 'el pis de l\'amic al bloc (' .. wb.id .. ')')
  local pn = 0
  for _, nn in ipairs(wb.npcs) do if nn.props.parent then pn = pn + 1 end end
  api.check(pn == 2, 'al pis hi són els dos pares')
end
