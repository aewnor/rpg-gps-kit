-- Màgia (fase 6): punts de màgia (MP), estadística Màgia i un arbre d'encanteris que s'obre per nivell.
-- Per fer encanteris cal portar equipat un arma amb «magic» (el Bastó màgic de la Cova de Roda).
-- Lua pur (sense love.*): es prova amb luajit (tests/combat6_cases.lua).
--
--   dany d'un encanteri = poder × màgia total / 10 (mínim 1);  màgia total = base + bonus de l'equip
--   MP: 10 al nivell 1, +3 per nivell; es recupera 1 MP cada 1,5 s
local Magic = {}

-- arbre: cada encanteri demana un nivell i, alguns, un altre encanteri abans
Magic.SPELLS = {
  { id = 'foc', name = 'Bola de foc', level = 2, mp = 4, power = 3, speed = 170,
    desc = 'Llança una bola de foc cap endavant.' },
  { id = 'rafaga', name = 'Ràfaga de vent', level = 3, mp = 6, power = 1, speed = 120, push = 260,
    desc = 'Un remolí que travessa i empeny els enemics.' },
  { id = 'cura', name = 'Curació', level = 4, mp = 8, heal = 4, desc = 'Recupera dos cors.' },
  { id = 'foc_triple', name = 'Pluja de foc', level = 6, mp = 10, power = 3, speed = 170, after = 'foc',
    desc = 'Tres boles de foc en ventall.' },
  -- encanteris de l'escola (2026-10-05): la mestra els ensenya a la Classe de màgia (st.learned_spells)
  { id = 'gel', name = 'Raig de gel', level = 2, mp = 5, power = 2, speed = 190, freeze = 2.5, school = true,
    desc = "Congela l'enemic uns segons." },
  { id = 'retorn', name = 'Retorn a la plaça', level = 2, mp = 6, teleport = true, school = true,
    desc = "Et porta volant a la Plaça de l'Església." },
  { id = 'llamp', name = 'Llamp', level = 3, mp = 7, power = 4, range = 150, school = true,
    desc = "Cau un llamp sobre l'enemic més proper." },
  { id = 'escut', name = 'Escut màgic', level = 4, mp = 8, ward = 8, school = true,
    desc = 'Durant 8 segons res no et fa mal.' },
}
Magic.BY_ID = {}
for _, s in ipairs(Magic.SPELLS) do Magic.BY_ID[s.id] = s end
Magic.REGEN_EVERY = 1.5

local DIRS = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

function Magic.has_staff(st, items)
  local w = items[st.equipment and st.equipment.weapon or '']
  return w ~= nil and (w.magic or 0) > 0
end

function Magic.total(st, items)
  local m = st.base and st.base.magic or 5
  for _, slot in ipairs({ 'weapon', 'shield', 'clothes', 'armor', 'helmet' }) do
    local d = items[st.equipment and st.equipment[slot] or '']
    if d then m = m + (d.magic or 0) end
  end
  return m
end

function Magic.unlocked(st, id)
  local s = Magic.BY_ID[id]
  if not s or (st.char_level or 1) < s.level then return false end
  if s.school and not (st.learned_spells or {})[id] then return false end
  return not s.after or Magic.unlocked(st, s.after)
end

-- encanteris que ja es poden fer (per a la roda de selecció)
function Magic.known(st)
  local out = {}
  for _, s in ipairs(Magic.SPELLS) do if Magic.unlocked(st, s.id) then out[#out + 1] = s end end
  return out
end

-- següent encanteri conegut (Q/E); torna el nou id
function Magic.next(st, step)
  local k = Magic.known(st)
  if #k == 0 then return nil end
  local cur = 1
  for i, s in ipairs(k) do if s.id == st.spell then cur = i end end
  cur = (cur - 1 + (step or 1)) % #k + 1
  st.spell = k[cur].id
  return st.spell
end

function Magic.damage(st, items, spell)
  return math.max(1, math.floor((spell.power or 1) * Magic.total(st, items) / 10 + 0.5))
end

-- ¿es pot fer? → true o false i el motiu (per al cartell)
function Magic.can_cast(st, items, id)
  local s = Magic.BY_ID[id or '']
  if not s then return false, 'Encara no saps cap encanteri' end
  if not Magic.has_staff(st, items) then return false, 'Necessites el Bastó màgic equipat' end
  if not Magic.unlocked(st, id) then return false, s.name .. ': nivell ' .. s.level end
  if (st.mp or 0) < s.mp then return false, 'Et falta màgia (' .. s.mp .. ' MP)' end
  if s.heal and st.hp >= st.max_hp then return false, 'Ja tens tota la vida' end
  if s.ward and (st.ward_t or 0) > 0 then return false, "L'escut encara dura" end
  return true
end

-- fa l'encanteri des de (x, y) cap a `facing`: gasta MP i torna { shots = {projectils}, heal = n }
function Magic.cast(st, items, id, x, y, facing)
  local ok, why = Magic.can_cast(st, items, id)
  if not ok then return nil, why end
  local s = Magic.BY_ID[id]
  st.mp = st.mp - s.mp
  local out = { spell = s, shots = {} }
  if s.heal then
    out.heal = math.min(s.heal, st.max_hp - st.hp)
    st.hp = st.hp + out.heal
    return out
  end
  if s.teleport then out.teleport = true; return out end
  if s.ward then st.ward_t = s.ward; out.ward = s.ward; return out end
  local d = DIRS[facing] or DIRS.down
  local dmg = Magic.damage(st, items, s)
  if s.range then out.bolt = { dmg = dmg, range = s.range }; return out end   -- el món tria l'objectiu
  local angles = id == 'foc_triple' and { -0.32, 0, 0.32 } or { 0 }
  for _, a in ipairs(angles) do
    local c, sn = math.cos(a), math.sin(a)
    local vx, vy = (d[1] * c - d[2] * sn) * s.speed, (d[1] * sn + d[2] * c) * s.speed
    out.shots[#out.shots + 1] = { x = x + d[1] * 10, y = y + d[2] * 10, vx = vx, vy = vy, dmg = dmg,
      owner = 'player', kind = id == 'rafaga' and 'gust' or s.freeze and 'ice' or 'fire', r = id == 'rafaga' and 8 or 5,
      life = id == 'rafaga' and 0.9 or 1.4, push = s.push, pierce = id == 'rafaga', freeze = s.freeze }
  end
  return out
end

-- recuperació de MP amb el temps
function Magic.regen(st, dt)
  if (st.ward_t or 0) > 0 then st.ward_t = math.max(0, st.ward_t - dt) end   -- l'escut màgic s'acaba
  if (st.mp or 0) >= (st.max_mp or 0) then st.mp_t = 0; return end
  st.mp_t = (st.mp_t or 0) + dt
  while st.mp_t >= Magic.REGEN_EVERY and st.mp < st.max_mp do
    st.mp_t = st.mp_t - Magic.REGEN_EVERY
    st.mp = st.mp + 1
  end
end

-- la mestra ensenya un encanteri de l'escola (Classe de màgia)
function Magic.learn(st, id)
  local s = Magic.BY_ID[id]
  if not s or not s.school then return false end
  st.learned_spells = st.learned_spells or {}
  st.learned_spells[id] = true
  if not st.spell or not Magic.unlocked(st, st.spell) then st.spell = Magic.unlocked(st, id) and id or st.spell end
  return true
end

return Magic
