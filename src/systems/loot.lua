-- Botín de cofres por categoría (data/loot.json): madera, hierro, plata y legendario.
-- Lua puro (tests/rpg_cases.lua). La tirada es determinista por cofre: la semilla sale del nombre del cofre,
-- así el mismo cofre da siempre lo mismo (y no se puede «repetir tirada» cargando la partida).
local Loot = {}

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

local function rng(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(n)   -- entero en [1, n]
    s = (s * 48271) % 2147483647
    return s % n + 1
  end
end

-- tables: data/loot.json; tier: 'wood' | 'iron' | 'silver' | 'legend'; key: identificador del cofre
function Loot.roll(tables, tier, key)
  local t = tables[tier] or tables.wood
  local r = rng(hash(tier .. ':' .. key))
  local out = { items = {}, coins = 0, xp = t.xp or 0, label = t.label }
  for _, id in ipairs(t.always or {}) do out.items[#out.items + 1] = id end
  local pool = {}
  for _, e in ipairs(t.table) do pool[#pool + 1] = { e[1], e[2] } end
  for _ = 1, t.rolls or 1 do
    local total = 0
    for _, e in ipairs(pool) do total = total + e[2] end
    if total <= 0 then break end
    local k = r(total)
    for i, e in ipairs(pool) do
      k = k - e[2]
      if k <= 0 then
        out.items[#out.items + 1] = e[1]
        table.remove(pool, i)   -- sin repetir objeto en el mismo cofre
        break
      end
    end
  end
  local lo, hi = t.coins[1], t.coins[2]
  out.coins = lo + r(hi - lo + 1) - 1
  return out
end

-- aplica el botín al estado; los planos desbloquean su vehículo. Devuelve los nombres para el diálogo.
function Loot.apply(st, items, res)
  local names = {}
  for _, id in ipairs(res.items) do
    local d = items[id]
    if d and d.kind == 'blueprint' then
      st.vehicles = st.vehicles or {}
      st.vehicles[d.vehicle] = true
    elseif d and d.gem then
      st.gems = (st.gems or 0) + 1
    end
    if d and not d.gem then st.inventory[id] = (st.inventory[id] or 0) + 1 end
    names[#names + 1] = d and d.name or id
  end
  st.coins = (st.coins or 0) + res.coins
  return names
end

return Loot
