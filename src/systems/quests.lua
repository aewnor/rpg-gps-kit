-- Diálogos condicionados por flags y acciones de misión (dar/quitar objetos, equipar, sellos).
local State = require('src.state')

local Quests = {}

function Quests.check(st, cond)
  for _, c in ipairs(cond or {}) do
    local neg = c:sub(1, 1) == '!'
    local f = neg and c:sub(2) or c
    local v = State.flag(st, f)
    if neg == v then return false end
  end
  return true
end

function Quests.remaining(st, pois)
  local n = 0
  for _, p in ipairs(pois) do if not st.visited[p] then n = n + 1 end end
  return n
end

-- devuelve {name, pages} y aplica las acciones de la variante elegida
function Quests.run(st, dialogue, items, key, pois)
  local d = dialogue[key]
  if not d then return { pages = { '...' } } end
  for _, v in ipairs(d.variants) do
    if Quests.check(st, v['if']) then
      local pages = {}
      for i, p in ipairs(v.pages) do
        pages[i] = p:gsub('{remaining}', tostring(Quests.remaining(st, pois)))
      end
      for _, it in ipairs(v.give or {}) do State.give(st, it) end
      for _, it in ipairs(v.take or {}) do State.take(st, it) end
      for _, it in ipairs(v.equip or {}) do State.equip(st, items, it) end
      for _, f in ipairs(v.set or {}) do State.set(st, f) end
      return { name = d.name, pages = pages, toast = v.toast, xp = v.xp, coins = v.coins }
    end
  end
  return { pages = { '...' } }
end

-- sello de un lugar visitado; devuelve texto de aviso o nil
function Quests.visit(st, poi, label, pois)
  if st.visited[poi] then return nil end
  st.visited[poi] = true
  State.set(st, 'visited_' .. poi)
  local done = 0
  for _, p in ipairs(pois) do if st.visited[p] then done = done + 1 end end
  if State.flag(st, 'has_notebook') and done == #pois and not State.flag(st, 'notebook_done') then
    State.set(st, 'notebook_done')
    return label .. ' · Quadern complet!', true
  end
  if State.flag(st, 'has_notebook') then
    return string.format('Segell: %s (%d/%d)', label, done, #pois)
  end
  return label
end

return Quests
