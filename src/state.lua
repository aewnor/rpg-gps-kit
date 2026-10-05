-- Estado de la partida (lo que se guarda). Posiciones en píxeles lógicos del mundo.
local State = {}

function State.new(world)
  return require('src.systems.rpg').ensure({
    schema = 1,
    scene = 'overworld',
    x = 0, y = 0, level = 0, facing = 'down',
    hp = world.player.hp, max_hp = world.player.hp,
    flags = {},
    inventory = {},          -- id -> cantidad
    equipment = { weapon = nil, shield = nil },
    visited = {},            -- poi -> true
    scene_state = {},        -- escena -> { chests = {}, levers = {}, defeated = {} }
    play_time = 0,
    sim_time = 0,            -- reloj de simulación (trenes/coches); se congela en pausa
    clock = 540,             -- hora del día en minutos (ciclo día/noche); empieza a las 9:00
    skin = 'nena',          -- aspecto del protagonista (ver data/skins.json)
    stops = {},              -- paradas de bus descubiertas (viaje rápido)
    -- RPG (src/systems/rpg.lua): nivel, experiencia, monedas, equipo de 5 ranuras, vehículos
  })
end

function State.scene(st, name)
  st.scene_state[name] = st.scene_state[name] or { chests = {}, levers = {}, defeated = {} }
  return st.scene_state[name]
end

function State.has(st, item) return (st.inventory[item] or 0) > 0 end

function State.give(st, item, n)
  st.inventory[item] = (st.inventory[item] or 0) + (n or 1)
end

function State.take(st, item)
  if not State.has(st, item) then return false end
  st.inventory[item] = st.inventory[item] - 1
  if st.inventory[item] <= 0 then st.inventory[item] = nil end
  -- nunca dejar equipado algo que ya no se tiene
  for slot, id in pairs(st.equipment) do
    if id == item and not State.has(st, item) then st.equipment[slot] = nil end
  end
  return true
end

-- equipar sin duplicar: el objeto debe estar en el inventario y la ranura debe aceptar su tipo
function State.equip(st, items, item)
  local def = items[item]
  if not def or not State.has(st, item) then return false end
  local slot = require('src.systems.rpg').slot_of(def)
  if not slot then return false end
  st.equipment[slot] = item
  return true
end

function State.flag(st, f) return st.flags[f] == true end
function State.set(st, f, v) st.flags[f] = (v == nil) and true or v end

return State
