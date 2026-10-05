-- Sistema RPG: nivel, experiencia, monedas, cinco ranuras de equipo y estadísticas.
-- Lua puro (sin love.*): se prueba con luajit (tests/rpg_cases.lua).
--
-- Estadísticas (escala del diseño: ataque 10, defensa 5 al empezar; +3 / +2 por nivel):
--   ataque total  = ataque base + entrenamiento de fuerza + bonus del equipo
--   defensa total = defensa base + bonus del equipo
--   daño al enemigo  = arma.damage × ataque total / 10   (mínimo 1)
--   daño recibido    = golpe − ⌊defensa total / 10⌋      (mínimo 1; en medios corazones)
-- La vida sigue en medios corazones (state.hp / state.max_hp): cada nivel suma un corazón (hasta 12).
-- Fase 6: cada nivel también sube la Magia (+2) y los puntos de magia, MP (+3); src/systems/magic.lua.
local Rpg = {}

Rpg.SLOTS = { 'weapon', 'shield', 'clothes', 'armor', 'helmet' }
Rpg.SLOT_NAME = { weapon = 'Arma', shield = 'Escut', clothes = 'Roba', armor = 'Armadura', helmet = 'Casc' }
Rpg.BASE = { attack = 10, defense = 5, magic = 5, mp = 10 }
Rpg.PER_LEVEL = { attack = 3, defense = 2, hp = 2, magic = 2, mp = 3 }
Rpg.MAX_MP = 40
Rpg.MAX_HP = 24
Rpg.FIRST_XP = 100

-- completa una partida (nueva o guardada con una versión anterior) con los campos del RPG
function Rpg.ensure(st)
  st.char_level = st.char_level or 1
  st.xp = st.xp or 0
  st.next_xp = st.next_xp or Rpg.FIRST_XP
  st.coins = st.coins or 0
  st.gems = st.gems or 0
  st.base = st.base or { attack = Rpg.BASE.attack + Rpg.PER_LEVEL.attack * (st.char_level - 1),
                         defense = Rpg.BASE.defense + Rpg.PER_LEVEL.defense * (st.char_level - 1) }
  st.base.magic = st.base.magic or (Rpg.BASE.magic + Rpg.PER_LEVEL.magic * (st.char_level - 1))
  st.max_mp = st.max_mp or math.min(Rpg.MAX_MP, Rpg.BASE.mp + Rpg.PER_LEVEL.mp * (st.char_level - 1))
  st.mp = st.mp or st.max_mp
  st.spell = st.spell or 'foc'
  st.train = st.train or { strength = 0, agility = 0 }
  st.train.resistance = st.train.resistance or 0   -- fase 4: bici estàtica del Gimnàs (+1 defensa per punt)
  st.equipment = st.equipment or {}
  st.fines = st.fines or 0
  st.vehicles = st.vehicles or { bici = true }
  st.vehicle = st.vehicle or 'bici'
  st.missions = st.missions or {}
  return st
end

local function slot_of(def)
  if not def then return nil end
  for _, s in ipairs(Rpg.SLOTS) do if def.kind == s then return s end end
  return nil
end
Rpg.slot_of = slot_of

-- estadísticas totales (equivalente a recalculateStats del diseño)
function Rpg.stats(st, items)
  local atk = (st.base and st.base.attack or Rpg.BASE.attack) + (st.train and st.train.strength or 0)
  local def = (st.base and st.base.defense or Rpg.BASE.defense) + (st.train and st.train.resistance or 0)
  local bonus_atk, bonus_def = 0, 0
  for _, s in ipairs(Rpg.SLOTS) do
    local d = items[st.equipment[s] or '']
    if d then
      bonus_atk = bonus_atk + (d.attack or 0)
      bonus_def = bonus_def + (d.defense or 0)
    end
  end
  local mag = (st.base and st.base.magic or Rpg.BASE.magic)
  for _, s in ipairs(Rpg.SLOTS) do local d = items[st.equipment[s] or '']; if d then mag = mag + (d.magic or 0) end end
  return { attack = atk, defense = def, bonus_attack = bonus_atk, bonus_defense = bonus_def, magic = mag,
           total_attack = atk + bonus_atk, total_defense = def + bonus_def,
           agility = st.train and st.train.agility or 0, resistance = st.train and st.train.resistance or 0 }
end

-- equipar con requisito de nivel; sustituye lo que hubiera en la ranura. Devuelve ok, motivo
function Rpg.equip(st, items, id)
  local d = items[id]
  local slot = slot_of(d)
  if not slot then return false, 'no es pot equipar' end
  if (st.inventory[id] or 0) <= 0 then return false, 'no el tens' end
  if (d.min_level or 1) > st.char_level then return false, 'Requereix nivell ' .. d.min_level end
  st.equipment[slot] = id
  return true
end

function Rpg.unequip(st, slot) st.equipment[slot] = nil end

-- experiencia: devuelve el número de niveles subidos (puede ser más de uno)
function Rpg.add_xp(st, n)
  st.xp = st.xp + math.max(0, n or 0)
  local ups = 0
  while st.xp >= st.next_xp do
    st.xp = st.xp - st.next_xp
    st.next_xp = math.floor(st.next_xp * 1.5)
    st.char_level = st.char_level + 1
    st.base.attack = st.base.attack + Rpg.PER_LEVEL.attack
    st.base.defense = st.base.defense + Rpg.PER_LEVEL.defense
    st.max_hp = math.min(Rpg.MAX_HP, st.max_hp + Rpg.PER_LEVEL.hp)
    st.hp = st.max_hp
    if st.base.magic then st.base.magic = st.base.magic + Rpg.PER_LEVEL.magic end
    if st.max_mp then
      st.max_mp = math.min(Rpg.MAX_MP, st.max_mp + Rpg.PER_LEVEL.mp)
      st.mp = st.max_mp
    end
    ups = ups + 1
  end
  return ups
end

function Rpg.damage_dealt(st, items, weapon)
  local s = Rpg.stats(st, items)
  return math.max(1, math.floor((weapon.damage or 1) * s.total_attack / 10 + 0.5))
end

function Rpg.damage_taken(st, items, dmg)
  local s = Rpg.stats(st, items)
  return math.max(1, dmg - math.floor(s.total_defense / 10))
end

-- monedas
function Rpg.pay(st, n)
  if st.coins < n then return false end
  st.coins = st.coins - n
  return true
end

function Rpg.earn(st, n) st.coins = st.coins + math.max(0, n or 0) end

-- usar un consumible: cura (medios corazones) o energía; devuelve texto o nil
function Rpg.use(st, items, id, player)
  local d = items[id]
  if not d or d.kind ~= 'food' or (st.inventory[id] or 0) <= 0 then return nil end
  local heal = d.heal == 'full' and st.max_hp or (d.heal or 0)
  local mp = d.mp == 'full' and (st.max_mp or 0) or (d.mp or 0)
  local mp_room = mp > 0 and (st.mp or 0) < (st.max_mp or 0)
  if heal > 0 and st.hp >= st.max_hp and not d.stamina and not mp_room then return 'Ja tens tota la vida' end
  st.inventory[id] = st.inventory[id] - 1
  if st.inventory[id] <= 0 then st.inventory[id] = nil end
  st.hp = math.min(st.max_hp, st.hp + heal)
  if mp_room then st.mp = math.min(st.max_mp, (st.mp or 0) + mp) end
  if d.stamina and player then player.stamina = player.max_stamina end
  return d.name .. ': ' .. (d.use_text or 'Ja et trobes millor!')
end

return Rpg
