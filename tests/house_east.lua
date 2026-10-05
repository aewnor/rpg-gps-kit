-- Casa privada con entrada por el este (tools/casa_privada.py --entrada este). Necesita una casa configurada
-- (tools/configure_home.py) y casa_privada.json en el directorio de datos de LÖVE:
--   love . --test=tests/house_east.lua --keephome --mute
return function(api)
  local Input = require('src.input')
  local sc = api.scene()
  local g = sc.game
  if not (g.home and g.house) then
    print('[test] (sin casa configurada: se omite)')
    return
  end
  api.check(g.house.entrance == 'este', 'la casa se ha generado con entrada por el este')
  local e = sc.house_east
  api.check(e ~= nil, 'el edificio de casa tiene entrada este')
  if not e then return end

  -- la puerta de la fachada sur ya no lleva a casa: avisa de que la entrada es al este
  local d = sc.house_door
  api.teleport(d[1], d[2] + 1)
  api.player().facing = 'up'
  api.press('confirm'); api.wait(5)
  api.check(api.scene() == sc and not g.transition, 'la puerta sur no entra en casa')

  -- empujar hacia el oeste contra la pared este → dentro de casa, mirando al oeste
  api.teleport(e.wx + 1, e.ty)
  Input.hold('left', true)
  for _ = 1, 90 do
    api.wait(1)
    if api.scene() ~= sc then break end
  end
  Input.release_all()
  api.wait(40)
  api.check(api.scene().id == g.house.entry, 'empujando al oeste se entra en casa (' .. tostring(api.scene().id) .. ')')
  api.check(api.player().facing == 'left', 'dentro, mirando al oeste')

  -- salir por la calle (este): de vuelta al exterior, en el lado este del edificio y mirando al este
  local inside = api.scene()
  Input.hold('right', true)
  for _ = 1, 240 do
    api.wait(1)
    if api.scene() ~= inside then break end
  end
  Input.release_all()
  api.wait(40)
  local b = api.player().body
  api.check(api.scene().id == 'overworld', 'saliendo por el este se vuelve afuera')
  api.check(math.floor(b.x / 16) == e.wx + 1 and math.floor(b.y / 16) == e.ty,
    string.format('reaparece en la entrada este (%d,%d)', math.floor(b.x / 16), math.floor(b.y / 16)))
  api.check(api.player().facing == 'right', 'mirando al este al salir')
end
