-- Motor de missions «Coneix el teu poble» (aprenentatge espacial de Roda de Berà): data/missions.json.
--
-- Capítols progressius (navegació, família i amics, seguretat i civisme). Les missions de família es generen
-- a partir dels personatges del perfil (src/profile.lua): «Visita l'amiga», «Porta un encàrrec a casa
-- dels avis». Una missió activa alhora (es tria al Diari); el pas actiu dona l'objectiu de la brúixola.
-- El món avisa amb Missions.event(w, tipus, dades): talk, buy, bus, recycle, crosswalk, light, light_red,
-- i (fase 6) enter {scene}, have {item}, level {level}, defeat {target}, event {name}.
-- Fase 6: missions amb nivell mínim (min_level) i capítols que s'obren després d'un altre (after + unlock):
-- inicials (el poble) → intermèdies (encàrrecs, objectes i zones tancades) → l'èpica del Drac.
-- Lògica sense love.* (tests/missions_cases.lua); el món (src/scenes/world_scene.lua) resol les posicions.
local M = {}

M.CAT_COLOR = { nav = { 0.36, 0.62, 0.95 }, social = { 0.93, 0.52, 0.72 }, safety = { 0.45, 0.85, 0.45 },
                job = { 0.92, 0.80, 0.35 }, epic = { 0.95, 0.52, 0.25 } }
M.CAT_NAME = { nav = 'Orientació', social = 'Família i amics', safety = 'Seguretat i civisme', job = 'Encàrrecs',
               epic = 'Aventura' }

local function deep(v)
  if type(v) ~= 'table' then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = deep(x) end
  return o
end

-- {clau} → vars[clau]; la substitució per funció evita que un '%' d'un nom es llegeixi com a captura
local function fill(v, vars)
  if type(v) == 'string' then
    return (v:gsub('{([%w_]+)}', function(k) local r = vars[k]; if r ~= nil then return tostring(r) end end))
  elseif type(v) == 'table' then
    local o = {}
    for k, x in pairs(v) do o[k] = fill(x, vars) end
    return o
  end
  return v
end

-- noms dels pares d'un personatge: Profile.parents_of(nil, f) ({pare, mare}) o f.parents; sense noms, «els pares de X»
function M.parents_text(f)
  local names = {}
  local ok, P = pcall(require, 'src.profile')
  local list = ok and type(P) == 'table' and P.parents_of and P.parents_of(nil, f) or f.parents
  if type(list) == 'table' then
    for _, p in ipairs({ list.pare or false, list.mare or false, list[1] or false, list[2] or false }) do
      local n = type(p) == 'table' and p.name or p
      if type(n) == 'string' and n ~= '' then names[#names + 1] = n end
    end
  end
  if #names == 0 then return 'els pares de ' .. f.name, names end
  return table.concat(names, ' i '), names
end

local function role_ok(t, role)
  if not t.roles then return true end
  for _, r in ipairs(t.roles) do if r == role then return true end end
  return false
end

local function friend_vars(f)
  local text, names = M.parents_text(f)
  return { name = f.name, id = f.id, role = f.role, parents = text, parent1 = names[1] or text, parent2 = names[2] or names[1] or text }
end

-- cadena principal «Reuneix la colla»: un cap de la colla per cada amic amb casa (fins a `max`); si en
-- falten, ajuden els veïns del poble (`fallback`). Cada un demana un favor i dona un fragment del mapa.
local function build_chain(cfg, friends, add)
  local keepers = {}
  for _, f in ipairs(friends) do
    if f.home and #keepers < (cfg.max or 6) then keepers[#keepers + 1] = { f = f } end
  end
  local fb = cfg.fallback or {}
  local i = 1
  while #keepers < (cfg.min or 3) and fb[i] do keepers[#keepers + 1] = { fb = fb[i] }; i = i + 1 end
  local places = cfg.places or {}
  for k, kp in ipairs(keepers) do
    local vars = kp.f and friend_vars(kp.f) or { name = kp.fb.name, id = kp.fb.id, role = 'veí', parents = kp.fb.name,
                                                 parent1 = kp.fb.name, parent2 = kp.fb.name }
    vars.who_target = kp.f and ('friend:' .. kp.f.id) or kp.fb.target
    vars.who = vars.name
    local pl = places[(k - 1) % math.max(1, #places) + 1] or { text = 'el poble', target = 'home' }
    vars.place, vars.place_target, vars.k, vars.n = pl.text, pl.target, k, #keepers
    local m = fill(deep(cfg.slot), vars)
    m.id = (cfg.id or 'colla') .. '_' .. vars.id
    m.friend = kp.f and kp.f.id or nil
    add(m, { 1, k })
  end
  if cfg.final and #keepers > 0 then
    local m = fill(deep(cfg.final), { n = #keepers })
    m.steps[1].count = #keepers
    m.id = (cfg.id or 'colla') .. '_final'
    add(m, { 1, 99 })
  end
  return #keepers
end

-- llista ordenada de missions (amb les de família del perfil): { chapters = {…}, by_id = {…}, order = {…} }
-- opts: { home = true si el jugador té casa al mapa } (les missions amb needs = 'home' només llavors)
-- Plantilles d'un capítol: templates (una per personatge, filtrades per `roles`), pair_templates (entre dos
-- personatges seguits, com a molt `pair_max`) i chain (cadena principal). `rank` agrupa l'ordre al diari.
function M.build(data, friends, opts)
  local out = { chapters = {}, by_id = {}, order = {}, by_chapter = {} }
  for ci, ch in ipairs(data.chapters) do
    local c = { id = ch.id, title = ch.title, unlock = ch.unlock or 0, after = ch.after, missions = {}, index = ci,
                parallel = ch.parallel or ch.id == 'familia' }
    local list, meta, seq = {}, {}, 0
    local function add(m, key)
      seq = seq + 1
      list[#list + 1] = m
      meta[m] = { key[1], key[2], key[3] or 0, seq }
    end
    for _, m in ipairs(deep(ch.missions or {})) do
      if m.needs ~= 'home' or (opts and opts.home) then add(m, { 9, 0 }) end
    end
    local tkeys = {}
    for key in pairs(ch.templates or {}) do tkeys[#tkeys + 1] = key end
    table.sort(tkeys)
    -- missions generades pels amics i avis del perfil (només si tenen casa al mapa)
    local homed = {}
    for fi, f in ipairs(friends or {}) do
      if f.home then
        homed[#homed + 1] = f
        for ti, key in ipairs(tkeys) do
          local t = ch.templates[key]
          if role_ok(t, f.role) then
            local m = fill(deep(t), friend_vars(f))
            m.roles = nil
            m.id = key .. '_' .. f.id
            m.friend = f.id
            add(m, { t.rank or 3, fi, ti })
          end
        end
      end
    end
    local pkeys = {}
    for key in pairs(ch.pair_templates or {}) do pkeys[#pkeys + 1] = key end
    table.sort(pkeys)
    for _, key in ipairs(pkeys) do
      local t = ch.pair_templates[key]
      for i = 1, math.min(ch.pair_max or 4, #homed - 1) do
        local a, b = homed[i], homed[i + 1]
        local vars = friend_vars(a)
        local vb = friend_vars(b)
        vars.name2, vars.id2, vars.parents2 = vb.name, vb.id, vb.parents
        local m = fill(deep(t), vars)
        m.id = key .. '_' .. a.id .. '_' .. b.id
        m.friend = a.id
        add(m, { t.rank or 4, i })
      end
    end
    if ch.chain then build_chain(ch.chain, friends or {}, add) end
    table.sort(list, function(a, b)
      local x, y = meta[a], meta[b]
      for i = 1, 4 do if x[i] ~= y[i] then return x[i] < y[i] end end
      return false
    end)
    for _, m in ipairs(list) do
      m.chapter = c
      c.missions[#c.missions + 1] = m
      out.by_id[m.id] = m
      out.order[#out.order + 1] = m
    end
    out.chapters[#out.chapters + 1] = c
    out.by_chapter[c.id] = c
  end
  return out
end

-- estat desat: st.quests = { active, done = {id = true}, step = {id = n}, count = {id = n} }
function M.state(st)
  st.quests = st.quests or {}
  local q = st.quests
  q.done = q.done or {}
  q.step = q.step or {}
  q.count = q.count or {}
  q.started = q.started or {}
  return q
end

local function chapter_done(defs, q, c)
  local n = 0
  for _, m in ipairs(c.missions) do if q.done[m.id] then n = n + 1 end end
  return n
end

-- per què està tancada: 'Nv 3' (nivell), 'capítol' o nil
function M.lock_reason(defs, st, m)
  local q = M.state(st)
  local c = m.chapter
  -- els capítols s'obren amb `unlock` missions fetes del capítol `after` (per defecte, el primer)
  local prev = c.after and defs.by_chapter[c.after] or defs.chapters[1]
  if c.index > 1 and prev ~= c and chapter_done(defs, q, prev) < c.unlock then return 'capítol' end
  if m.min_level and (st.char_level or 1) < m.min_level then return 'Nv ' .. m.min_level end
  return nil
end

-- 'done' | 'active' | 'open' | 'locked'
function M.status(defs, st, m)
  local q = M.state(st)
  if q.done[m.id] then return 'done' end
  if q.active == m.id then return 'active' end
  local c = m.chapter
  if M.lock_reason(defs, st, m) then return 'locked' end
  -- dins del capítol: la següent a la darrera feta (les de família, totes alhora)
  if m.chapter.parallel then return 'open' end
  for _, o in ipairs(c.missions) do
    if o == m then return 'open' end
    if not q.done[o.id] then return 'locked' end
  end
  return 'open'
end

function M.current(defs, st)
  local q = M.state(st)
  local m = q.active and defs.by_id[q.active]
  if not m then return nil end
  local i = q.step[m.id] or 1
  return m, m.steps[i], i
end

-- primera missió oberta (per activar-la sola en començar o en acabar-ne una)
function M.next_open(defs, st)
  for _, m in ipairs(defs.order) do
    if M.status(defs, st, m) == 'open' then return m end
  end
end

-- com a molt MAX_STARTED missions començades i sense acabar alhora (les noves s'han d'acabar o deixar enrere)
M.MAX_STARTED = 5
function M.started_open(defs, st)
  local q = M.state(st)
  local n = 0
  for id in pairs(q.started) do if defs.by_id[id] and not q.done[id] then n = n + 1 end end
  return n
end
function M.can_start(defs, st, id)
  local q = M.state(st)
  return q.started[id] or q.active == id or M.started_open(defs, st) < M.MAX_STARTED
end

-- activar: hooks(kind, ...) fa les coses del món (donar objectes, monedes, enviar l'Olaf al parc)
function M.activate(defs, st, id, hooks)
  local q = M.state(st)
  local m = defs.by_id[id]
  if not m or q.done[id] then return false end
  q.active = id
  q.step[id] = q.step[id] or 1
  if not q.started[id] then
    q.started[id] = true
    if hooks then
      if m.give then hooks('give', m.give) end
      if m.give_coins then hooks('coins', m.give_coins) end
      hooks('intro', m)
    end
  end
  if hooks then hooks('step', m, m.steps[q.step[id]]) end
  return true
end

-- avançar el pas actual; si era l'últim, missió completada (retorna 'done')
function M.advance(defs, st, hooks)
  local q = M.state(st)
  local m, s, i = M.current(defs, st)
  if not m then return nil end
  q.count[m.id] = nil
  if s.give and hooks then hooks('give', s.give) end   -- objecte que es rep en acabar el pas
  if s.say and hooks then hooks('say', s.say, s.who) end
  if s.join and hooks then hooks('join', s.join, m.id) end      -- un amic t'acompanya (src/systems/companion.lua)
  if s.leave and hooks then hooks('leave', m.id) end
  if s.family and hooks then hooks('family', s.family) end      -- 'out': els pares surten de casa; 'home': hi tornen
  if i < #m.steps then
    q.step[m.id] = i + 1
    if hooks then hooks('step', m, m.steps[i + 1]) end
    return 'step'
  end
  q.done[m.id] = true
  q.active = nil
  if hooks then hooks('done', m) end
  local nxt = M.next_open(defs, st)
  if nxt then M.activate(defs, st, nxt.id, hooks) end
  return 'done'
end

-- esdeveniment del món. data: { target = 'service:policia' | 'friend:f1', item, service, at_light } …
-- Retorna 'step' | 'done' | 'progress' | nil
function M.event(defs, st, kind, data, hooks)
  local m, s = M.current(defs, st)
  if not s then return nil end
  data = data or {}
  local q = M.state(st)
  local function counted(n)
    q.count[m.id] = (q.count[m.id] or 0) + (n or 1)
    if q.count[m.id] >= (s.count or 1) then return M.advance(defs, st, hooks) end
    if hooks then hooks('progress', m, s, q.count[m.id]) end
    return 'progress'
  end
  if s.type == 'talk' and kind == 'talk' and data.target == s.target then return M.advance(defs, st, hooks) end
  if s.type == 'deliver' and kind == 'talk' and data.target == s.target then
    if hooks and not hooks('has', s.item, s.count) then return nil end
    if hooks then hooks('take', s.item, s.count) end
    return M.advance(defs, st, hooks)
  end
  if s.type == 'buy' and kind == 'buy' then
    local okat = false
    for _, a in ipairs(s.at or {}) do if a == data.service then okat = true end end
    if not okat then return nil end
    q.bought = q.bought or {}
    q.bought[data.item] = true
    for _, it in ipairs(s.items) do if not q.bought[it] then return 'progress' end end
    q.bought = nil
    return M.advance(defs, st, hooks)
  end
  if (s.type == 'crosswalk' and kind == 'crosswalk') or (s.type == 'light' and kind == 'light') or
     (s.type == 'recycle' and kind == 'recycle') or (s.type == 'bus' and kind == 'bus') then
    return counted(data.n or 1)
  end
  if s.type == 'light' and kind == 'light_red' then
    if hooks then hooks('warn', 'Encara era vermell! Espera el ninotet verd.') end
    return nil
  end
  if (s.type == 'goto' or s.type == 'meet_olaf') and kind == 'arrive' then return M.advance(defs, st, hooks) end
  -- fase 6
  if s.type == 'enter' and kind == 'enter' and data.scene == s.scene then return M.advance(defs, st, hooks) end
  if s.type == 'have' and (kind == 'have' or kind == 'tick') and hooks and hooks('has', s.item, s.count) then
    return M.advance(defs, st, hooks)
  end
  if s.type == 'level' and (kind == 'level' or kind == 'tick') and (st.char_level or 1) >= (s.count or 1) then
    return M.advance(defs, st, hooks)
  end
  if s.type == 'defeat' and kind == 'defeat' and data.target == s.target then return M.advance(defs, st, hooks) end
  if s.type == 'event' and kind == 'event' and data.name == s.event then return M.advance(defs, st, hooks) end
  return nil
end

-- comprovacions que no depenen d'un esdeveniment (cada 0,25 s): tenir un objecte, haver arribat a un nivell
function M.tick(defs, st, hooks)
  local _, s = M.current(defs, st)
  if s and (s.type == 'have' or s.type == 'level') then return M.event(defs, st, 'tick', {}, hooks) end
end

-- percentatge de missions fetes (per al diari)
function M.progress(defs, st)
  local q = M.state(st)
  local n, d = 0, 0
  for _, m in ipairs(defs.order) do n = n + 1; if q.done[m.id] then d = d + 1 end end
  return d, n
end

return M
