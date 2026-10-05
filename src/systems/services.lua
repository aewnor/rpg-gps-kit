-- Serveis del poble (data/services.json): cada servei és un personatge davant de l'edifici real.
--   townhall (Ajuntament): pagar multes i la missió «Ruta dels serveis»
--   police (Policia Local): cartera perduda, consells de seguretat i avís de multes
--   post (Correus): missions de missatgeria (portar un paquet a un altre servei)
--   doctor (CAP): revisió (cura gratis un cop al dia) i farmacioles
--   gym (Gimnàs): entrenar força (+atac) i agilitat (+velocitat)
--   shop / super: comprar (el Lidl té ofertes que canvien cada dia) i, als súpers, vendre col·leccionables
--   library (Biblioteca): endevinalles; amb 3 d'encertades, el Mapa antic (mostra els cofres al mapa)
--   casino (Casino Municipal): «Trivial de Roda», preguntes sobre el poble que donen monedes i gemmes
--   sports (Poliesportiu, Camp de futbol): curses contra rellotge
-- Fase 4: el Casino, el Gimnàs, el Poliesportiu i el Camp de futbol tenen interior («Entrar») amb minijocs
-- (src/minigames/): teatre i cinema, aparells al ritme, penals i circuit d'agilitat.
--   station (Estació): viatge ràpid en tren entre estacions conegudes
local Rpg = require('src.systems.rpg')

local Services = {}

local RIDDLES = {
  { 'Té dents i no menja, té barba i no és home.', { 'L\'all', 'La pinta', 'La serra' } },
  { 'Una senyora molt enrevessada, amb moltes faldilles i cap de cosida.', { 'La ceba', 'La col', 'La carxofa' } },
  { 'Blanca com la neu, negra com la pega; parla i no té boca, camina i no té peus.', { 'La carta', 'La pissarra', 'La gavina' } },
  { 'Té coll i no té cap, té braços i no té mans.', { 'La camisa', 'L\'ampolla', 'El penja-robes' } },
  { 'Sempre ve i mai no arriba.', { 'Demà', 'El tren', 'L\'hivern' } },
  { 'Com més s\'asseca, més mulla.', { 'La tovallola', 'El sol', 'La sorra' } },
  { 'Té quatre potes i no pot caminar.', { 'La taula', 'El gat', 'El cotxe' } },
  { 'Quan més en treus, més gran es fa.', { 'El forat', 'El pa', 'La lluna' } },
}

local TRIVIA = {
  { 'Quants anys té, més o menys, l\'Arc de Berà?', { 'Uns 2.000', 'Uns 200', 'Uns 50' } },
  { 'Quina via romana passava pel costat de l\'Arc de Berà?', { 'La Via Augusta', 'La Via Làctia', 'L\'AP-7' } },
  { 'Com es diu l\'església del centre de Roda?', { 'Sant Bartomeu', 'Sant Pere', 'Santa Maria' } },
  { 'Per quin camí vas vora el mar fins al Roc de Sant Gaietà?', { 'El Camí de Ronda', 'El Camí Ral', 'La Rambla' } },
  { 'Què hi ha dalt del Pujol de la Morella?', { 'Un mirador', 'Un port', 'Una platja' } },
  { 'Com es diuen les casetes de pedra sense morter dels camps?', { 'Barraques de pedra seca', 'Masies', 'Torres' } },
  { 'Quin mar banya Roda de Berà?', { 'El Mediterrani', 'El Cantàbric', 'El Bàltic' } },
  { 'De quin poble veí és el castell que hi ha a prop?', { 'Creixell', 'Cambrils', 'Reus' } },
}
-- en un altre lloc (tools/new_location.py), un trivial de coneixements generals per a nens
if not require('src.place').is_roda() then
  TRIVIA = {
    { 'Quantes potes té una aranya?', { 'Vuit', 'Sis', 'Quatre' } },
    { 'De quin color és el cel quan fa sol?', { 'Blau', 'Verd', 'Vermell' } },
    { 'Quin animal fa «mu»?', { 'La vaca', 'El gat', 'El gos' } },
    { 'On viuen els peixos?', { 'A l\'aigua', 'Als arbres', 'Sota terra' } },
    { 'Quants dies té una setmana?', { 'Set', 'Cinc', 'Deu' } },
    { 'Què necessiten les plantes per créixer?', { 'Aigua i sol', 'Xocolata', 'Música' } },
    { 'Quin és el planeta on vivim?', { 'La Terra', 'Mart', 'La Lluna' } },
    { 'Quina estació ve després de l\'estiu?', { 'La tardor', 'La primavera', 'L\'hivern' } },
  }
end

local TIPS = {
  'Creua sempre pels passos de vianants: els cotxes s\'hi paren.',
  'Amb bici, patinet o moto, porta casc. Al Lidl en venen!',
  'De nit, els fars dels cotxes et veuen millor si vas per la vorera.',
  'Als passos a nivell, espera que la barrera pugi del tot.',
}

-- serveis que compten per a la «Ruta dels serveis» de l'Ajuntament
Services.ROUTE = { 'policia', 'correus', 'metge', 'gimnas', 'poliesportiu', 'bonpreu', 'lidl', 'biblioteca', 'casino',
                   'estacio_roda_de_mar' }

-- barreja determinista (les respostes no surten sempre al mateix lloc)
local function shuffled(list, seed)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  local s = seed
  for i = #out, 2, -1 do
    s = (s * 1103515245 + 12345) % 2147483648
    local j = s % i + 1
    out[i], out[j] = out[j], out[i]
  end
  return out
end

local function day(st) return st.day or 1 end

function Services.stock(sv, st)
  if not sv.rotating then return sv.stock end
  -- ofertes de la setmana: 4 articles del catàleg que canvien cada dia de joc
  local out = shuffled(sv.stock, day(st) * 7919 + #sv.stock)
  local list = {}
  for i = 1, 4 do
    local dup = false
    for _, f in ipairs(sv.fixed or {}) do if f == out[i] then dup = true end end
    if out[i] and not dup then list[#list + 1] = out[i] end
  end
  for k = #(sv.fixed or {}), 1, -1 do table.insert(list, 1, sv.fixed[k]) end   -- fruita, pa (i llanterna): cada dia
  return list
end

-- ---------------------------------------------------------------- obrir un servei
-- w: World; n: NPC del servei (n.props.service, service_id, label, say_name)
function Services.open(w, n)
  local st, g = w.state, w.game
  local p = n.props
  st.missions.route_seen = st.missions.route_seen or {}
  st.missions.route_seen[p.service_id] = true
  -- lliurament de Correus
  local del = st.missions.delivery
  if del and del.to == p.service_id and (st.inventory.paquet or 0) > 0 then
    st.inventory.paquet = nil
    st.missions.delivery = nil
    st.missions.delivered = (st.missions.delivered or 0) + 1
    w.dialogue:show(p.say_name, { 'Un paquet per a mi? Moltes gràcies!' }, function()
      w:reward(30, 8, 'Paquet lliurat')
    end)
    return
  end
  local spec = Services.spec(g, p.service_id) or {}
  local fn = Services[p.service]
  if fn then fn(w, n, spec) end
end

function Services.spec(g, id)
  if not g.services_spec then
    g.services_spec = {}
    for _, s in ipairs(require('src.data').read_json('data/services.json').services) do g.services_spec[s.id] = s end
  end
  return g.services_spec[id]
end

local function menu(w, title, items) w.game:open_list(title, items) end

-- interior del servei (procgen.poi): s'hi entra des del personatge de fora; en sortir es torna davant seu
local POI_KIND = { casino = 'casino', gimnas = 'gym', poliesportiu = 'sports', camp_futbol = 'football', escola = 'school',
                   bonpreu = 'super', lidl = 'super', lidl_platja = 'super', aldi = 'super', mercadona = 'super',
                   spar = 'super', supercor = 'super', leroy = 'diy',
                   -- edificis importants amb interior propi (2026-10-05)
                   biblioteca = 'library', ajuntament = 'townhall', metge = 'clinic', policia = 'police',
                   correus = 'post', estacio_roda_de_mar = 'station' }
-- mida de l'interior de cada botiga gran (src/world/procgen.lua P.store): com més gran la botiga real, més passadissos
local STORE_SIZE = { bonpreu = { 48, 32 }, lidl = { 46, 30 }, lidl_platja = { 42, 28 }, aldi = { 42, 28 },
                     mercadona = { 46, 30 }, spar = { 30, 22 }, supercor = { 32, 22 }, leroy = { 64, 40 } }
-- serveis d'un altre lloc (tools/make_services.py): l'interior es dedueix del kind de data/services.json
local KIND_POI = { super = 'super', shop = 'super', diy = 'diy', school = 'school', library = 'library',
                   townhall = 'townhall', doctor = 'clinic', police = 'police', post = 'post', station = 'station',
                   gym = 'gym', sports = 'sports', casino = 'casino', football = 'football' }
setmetatable(POI_KIND, { __index = function(t, id)
  local k = false
  local ok, d = pcall(function() return require('src.data').read_json('data/services.json') end)
  for _, sv in ipairs(ok and type(d) == 'table' and d.services or {}) do
    if sv.id == id then k = sv.poi or KIND_POI[sv.kind] or false end
  end
  rawset(t, id, k)
  return k
end })
Services.POI_KIND, Services.STORE_SIZE = POI_KIND, STORE_SIZE
-- entrar a l'interior propi d'un edifici (porta del monument o de la façana): si hi ha el personatge del servei a
-- fora, també hi és a dins
function Services.enter_poi(w, service_id, kind, back)
  local g = w.game
  local npc
  for _, n in ipairs(w.npcs or {}) do
    local p = n.props
    if p.service_id == service_id then
      npc = { sprite = p.sprite, name = p.say_name, service = p.service, service_id = p.service_id, label = p.label }
    end
  end
  g:close_menu()
  g.audio.play('door')
  g:change(g:poi_interior(service_id, kind, back, npc, STORE_SIZE[service_id]), 'spawn_in')
end

function Services.enter(w, n)
  local g, p = w.game, n.props
  local kind = POI_KIND[p.service_id]
  if not kind then return end
  g:close_menu()
  local back = { scene = w.id, x = n.body.x, y = n.body.y + 18, level = 0, facing = 'down' }
  local npc = { sprite = p.sprite, name = p.say_name, service = p.service, service_id = p.service_id, label = p.label }
  g.audio.play('door')
  g:change(g:poi_interior(p.service_id, kind, back, npc, STORE_SIZE[p.service_id]), 'spawn_in')
end

-- opció «Entrar» al principi del menú si som a fora i el servei té interior
local function with_enter(w, n, items, label)
  if w.def.outdoor and POI_KIND[n.props.service_id] then
    table.insert(items, 1, { label or 'Entrar', function() Services.enter(w, n) end })
  end
  return items
end
local function close(w) w.game:close_menu() end
local function say(w, n, pages, after) w.dialogue:show(n.props.say_name, pages, after) end

-- ---------------------------------------------------------------- comerç
local function buy(w, id, sv)
  local st, g = w.state, w.game
  local d = g.items[id]
  close(w)
  if d.kind == 'vehicle' then
    if st.vehicles[d.vehicle] then w.hud:toast('Ja tens: ' .. d.name, 2); return end
    if (d.min_level or 1) > st.char_level then w.hud:toast('Requereix nivell ' .. d.min_level, 2); return end
  end
  if not Rpg.pay(st, d.price) then w.hud:toast('No tens prou monedes (' .. d.price .. ')', 2); return end
  if d.kind == 'vehicle' then
    st.vehicles[d.vehicle] = true
    w.hud:toast('Nou vehicle: ' .. d.name .. '. Tria\'l al menú Personatge → Vehicles', 3)
  else
    st.inventory[id] = (st.inventory[id] or 0) + 1
    w.hud:toast('Comprat: ' .. d.name .. '  (-' .. d.price .. ')', 2)
  end
  w.game.audio.play('chest')
  -- missió «Fes la compra»
  if sv then require('src.systems.town').event(w, 'buy', { item = id, service = sv.id }) end
end

local function shop_items(w, sv)
  local items = {}
  for _, id in ipairs(Services.stock(sv, w.state) or {}) do
    local d = w.game.items[id]
    if d and d.price then
      local lock = (d.min_level or 1) > w.state.char_level and (' Nv' .. d.min_level) or ''
      items[#items + 1] = { string.format('%s  %d%s', d.name, d.price, lock), function() buy(w, id, sv) end, sprite=d.sprite }
    end
  end
  return items
end

-- Comprar des d'una prestatgeria conserva preus, estoc rotatiu i missions del comerç.
function Services.display(w, p)
  local section = require('src.systems.store_sections')[p.section] or { text = p.section }
  local sv = Services.spec(w.game, p.service_id)
  local available, entries = {}, {}
  for _, id in ipairs(sv and Services.stock(sv, w.state) or {}) do available[id] = true end
  for _, id in ipairs(section.items or {}) do
    local d = w.game.items[id]
    if available[id] and d and d.price then
      local item_id = id
      entries[#entries + 1] = { string.format('%s  %d mon.', d.name, d.price),
        function() buy(w, item_id, sv) end, sprite = d.sprite }
    end
  end
  entries[#entries + 1] = { 'Examinar la secció', function()
    close(w); w.dialogue:show(p.section, { section.text })
  end }
  entries[#entries + 1] = { 'Tornar', function() close(w) end }
  menu(w, p.section .. ' · ' .. w.state.coins .. ' mon.', entries)
end

function Services.shop(w, n, sv)
  local title = sv.label .. (sv.rotating and ' (ofertes)' or '') .. ' · ' .. w.state.coins .. ' mon.'
  menu(w, title, with_enter(w, n, shop_items(w, sv), 'Entrar a la botiga'))
end

function Services.super(w, n, sv)
  local items = shop_items(w, sv)
  items[#items + 1] = { 'Vendre col·leccionables', function() Services.sell(w) end }
  menu(w, sv.label .. ' · ' .. w.state.coins .. ' mon.', with_enter(w, n, items, 'Entrar al súper'))
end

function Services.sell(w)
  local st, g = w.state, w.game
  local total = 0
  for id, n in pairs(st.inventory) do
    local d = g.items[id]
    if type(d) == 'table' and d.kind == 'collectible' then
      if d.gem then st.gems = (st.gems or 0) + n else total = total + (d.sell or 1) * n end
      st.inventory[id] = nil
    end
  end
  close(w)
  Rpg.earn(st, total)
  w.hud:toast(total > 0 and ('Venut! +' .. total .. ' monedes') or 'No tens res per vendre', 2)
end

-- ---------------------------------------------------------------- salut i entrenament
function Services.doctor(w, n, sv)
  local st = w.state
  menu(w, sv.label, {
    { 'Revisió (gratis, un cop al dia)', function()
      close(w)
      if st.missions.doctor_day == day(st) then say(w, n, { 'Avui ja t\'he mirat. Torna demà!' }); return end
      st.missions.doctor_day = day(st)
      st.hp = st.max_hp
      say(w, n, { 'A veure... cor fort i cames àgils. Ja estàs com nou!' })
      w.game.audio.play('chest')
    end },
    { 'Botiquí gratuït (un cop al dia)', function()
      close(w)
      if require('src.systems.rest').free_kit(w, 'metge') then
        say(w, n, { 'Té un botiquí per a les emergències.' }); w.game.audio.play('chest')
      else say(w, n, { 'Avui ja te\'n vaig donar un. Torna demà!' }) end
    end },
    { 'Comprar botiquí  10 mon.', function() buy(w, 'botiqui') end },
    { 'Comprar farmaciola  15 mon.', function() buy(w, 'farmaciola') end },
  })
end

function Services.restaurant(w, n, sv)
  require('src.systems.rest').restaurant(w, n, sv)
end

function Services.gym(w, n, sv)
  local st = w.state
  local function cost(k) return 10 * (st.train[k] + 1) end
  local function train(k, label)
    close(w)
    if st.train[k] >= 10 then say(w, n, { 'Ja estàs al màxim! Ets un crack.' }); return end
    if not Rpg.pay(st, cost(k)) then w.hud:toast('No tens prou monedes (' .. cost(k) .. ')', 2); return end
    st.train[k] = st.train[k] + 1
    w:reward(10, 0, label .. ' +1')
  end
  menu(w, 'Gimnàs · ' .. st.coins .. ' mon.', with_enter(w, n, {
    { string.format('Força +1 atac  %d  [%d/10]', cost('strength'), st.train.strength),
      function() train('strength', 'Força') end },
    { string.format('Agilitat +2%% vel.  %d  [%d/10]', cost('agility'), st.train.agility),
      function() train('agility', 'Agilitat') end },
  }, 'Entrar al gimnàs (aparells)'))
end

-- ---------------------------------------------------------------- administració
function Services.townhall(w, n, sv)
  local st = w.state
  local items = {}
  if st.fines > 0 then
    items[#items + 1] = { 'Pagar multes  ' .. st.fines .. ' mon.', function()
      close(w)
      if Rpg.pay(st, st.fines) then st.fines = 0; say(w, n, { 'Multes pagades. Gràcies, i compte amb els cotxes!' })
      else w.hud:toast('No tens prou monedes', 2) end
    end }
  end
  local seen = st.missions.route_seen or {}
  local done = 0
  for _, id in ipairs(Services.ROUTE) do if seen[id] then done = done + 1 end end
  if not st.missions.route_done then
    items[#items + 1] = { string.format('Missió: Ruta dels serveis  (%d/%d)', done, #Services.ROUTE), function()
      close(w)
      if done >= #Services.ROUTE then
        st.missions.route_done = true
        st.inventory.samarreta_roda = (st.inventory.samarreta_roda or 0) + 1
        say(w, n, { 'Has parlat amb tots els serveis del poble! Ara ja saps on és tot.',
                    'Té, la samarreta oficial ' .. require('src.place').of() .. '.' }, function() w:reward(80, 20, 'Missió completada') end)
      else
        local missing = {}
        for _, id in ipairs(Services.ROUTE) do
          if not seen[id] then missing[#missing + 1] = (Services.spec(w.game, id) or { label = id }).label end
        end
        say(w, n, { 'Visita tots els serveis del poble i parla amb ells.', 'Et falten: ' .. table.concat(missing, ', ') .. '.' })
      end
    end }
  end
  items[#items + 1] = { 'Parlar', function()
    close(w)
    say(w, n, { 'Benvinguda a l\'Ajuntament ' .. require('src.place').of() .. '!', 'Si necessites alguna cosa, aquí ens tens.' })
  end }
  menu(w, sv.label, items)
end

function Services.police(w, n, sv)
  local st = w.state
  local m = st.missions
  local items = {}
  if (st.inventory.cartera or 0) > 0 then
    items[#items + 1] = { 'Tornar la cartera trobada', function()
      close(w)
      st.inventory.cartera = nil
      m.wallet = 'done'
      say(w, n, { 'La cartera de la senyora Rosa! Quina honradesa, moltes gràcies.' }, function()
        w:reward(40, 15, 'Cartera retornada')
        require('src.systems.town').event(w, 'event', { name = 'wallet_returned' })
      end)
    end }
  elseif not m.wallet then
    items[#items + 1] = { 'Hi ha alguna feina?', function()
      close(w)
      local spot = w:random_stop()
      if not spot then say(w, n, { 'Avui tot està tranquil.' }); return end
      m.wallet = { x = spot.x + 12, y = spot.y + 10, label = spot.label }
      require('src.systems.town').event(w, 'event', { name = 'wallet_started' })
      say(w, n, { 'La senyora Rosa ha perdut la cartera.', 'Diu que potser se li va caure a la parada de bus ' ..
        spot.label .. '. Si la trobes, porta-la aquí!' })
    end }
  end
  if st.fines > 0 then
    items[#items + 1] = { 'Les meves multes', function()
      close(w); say(w, n, { 'Tens ' .. st.fines .. ' monedes de multa per creuar malament.', 'Pots pagar-les a l\'Ajuntament.' })
    end }
  end
  items[#items + 1] = { 'Un consell', function()
    close(w); say(w, n, { TIPS[love.math.random(#TIPS)] })
  end }
  items[#items + 1] = { 'Botiquí gratuït (un cop al dia)', function()
    close(w)
    if require('src.systems.rest').free_kit(w, 'policia') then
      say(w, n, { 'A la comissaria sempre en tenim: aquest botiquí és teu.' }); w.game.audio.play('chest')
    else say(w, n, { 'Avui ja te\'n vaig donar un. Torna demà!' }) end
  end }
  menu(w, sv.label, items)
end

function Services.post(w, n, sv)
  local st = w.state
  local m = st.missions
  if m.delivery then
    say(w, n, { 'Encara tens un paquet per portar a: ' .. m.delivery.label .. '.' })
    return
  end
  menu(w, sv.label .. '  ·  lliuraments: ' .. (m.delivered or 0), {
    { 'Portar un paquet', function()
      close(w)
      local opts = {}
      for _, id in ipairs(Services.ROUTE) do if id ~= 'correus' then opts[#opts + 1] = id end end
      local to = opts[((m.delivered or 0) * 3 + day(st)) % #opts + 1]
      local spec = Services.spec(w.game, to)
      m.delivery = { to = to, label = spec.label }
      st.inventory.paquet = 1
      say(w, n, { 'Aquest paquet és per a: ' .. spec.label .. '.', 'Porta-l\'hi i parla amb qui hi treballa.' })
    end },
  })
end

-- ---------------------------------------------------------------- cultura i oci
local function quiz(w, n, title, bank, key, per_day, on_right, on_end)
  local st = w.state
  local m = st.missions
  m[key] = m[key] or {}
  local q
  if per_day then
    if m[key .. '_day'] == day(st) and (m[key .. '_n'] or 0) >= 3 then
      say(w, n, { 'Per avui ja n\'hi ha prou. Torna demà!' }); return
    end
    if m[key .. '_day'] ~= day(st) then m[key .. '_day'], m[key .. '_n'] = day(st), 0 end
    q = bank[((day(st) * 3 + m[key .. '_n']) % #bank) + 1]
    m[key .. '_n'] = m[key .. '_n'] + 1
  else
    for i, item in ipairs(bank) do if not m[key][i] then q = item; m.current = i; break end end
    if not q then say(w, n, { 'Ja les has encertat totes! Quin cap més ben moblat.' }); return end
  end
  local answers = shuffled(q[2], #q[1] + day(st))
  local items = {}
  for _, a in ipairs(answers) do
    items[#items + 1] = { a, function()
      close(w)
      if a == q[2][1] then
        if not per_day then m[key][m.current] = true end
        say(w, n, { 'Correcte!' }, function() on_right(); if on_end then on_end() end end)
      else
        say(w, n, { 'No... Era: ' .. q[2][1] .. '.' }, on_end)
      end
    end }
  end
  w.dialogue:show(n.props.say_name, { q[1] }, function() menu(w, title, items) end)
end

function Services.library(w, n, sv)
  local st = w.state
  quiz(w, n, 'Endevinalla', RIDDLES, 'riddles', false, function()
    local solved = 0
    for _ in pairs(st.missions.riddles) do solved = solved + 1 end
    w:reward(20, 0, 'Endevinalla')
    if solved >= 3 and not st.inventory.mapa_antic then
      st.inventory.mapa_antic = 1
      w.hud:toast('Has rebut: Mapa antic (mostra els cofres al mapa)', 3)
    end
  end)
end

function Services.casino(w, n, sv)
  local st = w.state
  local function trivia()
    close(w)
    quiz(w, n, 'Trivial', TRIVIA, 'trivia', true, function()
      w:reward(10, 4, 'Resposta correcta')
      if st.missions.trivia_n == 3 then st.gems = (st.gems or 0) + 1; w.hud:toast('+1 gemma!', 2) end
    end)
  end
  menu(w, sv.label, with_enter(w, n, {
    { 'Carta del restaurant', function() menu(w, 'Carta del Casino', shop_items(w, sv)) end },
    { 'Trivial', trivia },
    { 'Parlar', function()
      close(w)
      say(w, n, { 'Benvinguda! El Casino és un restaurant i una sala de teatre i cinema.',
        'Al menjador pots demanar menjar. A la sala, els dos faristols obren el teatre i el curt.',
        'Les obres i la carta són recreacions per al joc, no la programació real del local.' })
    end },
  }, 'Entrar al restaurant i teatre/cine'))
end

function Services.sports(w, n, sv)
  if w.race then say(w, n, { 'Ja estàs fent una cursa! Corre!' }); return end
  local items = {
    { 'Parlar', function()
      close(w)
      say(w, n, { 'Aquí entrenen els equips del poble.', 'A dins hi ha la porteria per als penals' ..
        (n.props.service_id == 'poliesportiu' and ' i el circuit d\'agilitat.' or '.') })
    end },
  }
  if w.def.outdoor then table.insert(items, 1, { 'Cursa contra rellotge', function() close(w); w:start_race(n) end }) end
  menu(w, sv.label, with_enter(w, n, items, n.props.service_id == 'camp_futbol' and 'Entrar al camp (penals)' or
    'Entrar (penals i circuit)'))
end

-- ---------------------------------------------------------------- escola (la mestra)
local LESSON = {
  { 'Per on s\'ha de creuar el carrer?', { 'Pel pas de vianants', 'Per on vulguis', 'Entre dos cotxes' } },
  { 'A quin contenidor va el paper?', { 'Al blau', 'Al groc', 'Al verd' } },
  { 'Qui t\'ajuda si et trobes malament?', { 'La metgessa, al centre de salut', 'El caixer del súper', 'El gat' } },
  { 'Si trobes una cartera al carrer, on la portes?', { 'A la Policia Local', 'Me la quedo', 'A la paperera' } },
  { 'Què vol dir el ninotet vermell del semàfor?', { 'Que cal esperar', 'Que es pot passar corrent', 'Res' } },
}

-- Classe de màgia (2026-10-05): cada encanteri de l'escola s'aprèn responent bé una pregunta de la mestra
local MAGIC_LESSON = {
  gel = { 'A quina temperatura es glaça l\'aigua?', { 'A 0 graus', 'A 100 graus', 'A 50 graus' } },
  retorn = { 'Quin edifici hi ha a la Plaça de l\'Església?', { 'L\'església de Sant Bartomeu', 'El castell', 'L\'estació' } },
  llamp = { 'En una tempesta, què arriba primer?', { 'La llum del llamp', 'El soroll del tro', 'Arriben alhora' } },
  escut = { 'Què et protegeix el cap quan vas en bici?', { 'El casc', 'La gorra', 'Les ulleres de sol' } },
}

function Services.magic_class(w, n)
  local Magic = require('src.systems.magic')
  local st = w.state
  local items = {}
  for _, sp in ipairs(Magic.SPELLS) do
    if sp.school and MAGIC_LESSON[sp.id] then
      local learned = (st.learned_spells or {})[sp.id]
      local label = sp.name .. (learned and '  ✓' or ((st.char_level or 1) < sp.level and ('  (nivell ' .. sp.level .. ')') or ''))
      items[#items + 1] = { label, function()
        close(w)
        if learned then say(w, n, { sp.name .. ': ' .. sp.desc, 'Ja el saps fer! Tria\'l amb Q/E i llança\'l amb V.' }); return end
        if (st.char_level or 1) < sp.level then
          say(w, n, { 'Aquest encanteri és per a exploradors de nivell ' .. sp.level .. '.', 'Torna quan siguis més gran!' }); return
        end
        local q = MAGIC_LESSON[sp.id]
        local answers = shuffled(q[2], #q[1] + day(st))
        local opts = {}
        for _, a in ipairs(answers) do
          opts[#opts + 1] = { a, function()
            close(w)
            if a == q[2][1] then
              Magic.learn(st, sp.id)
              w.game.audio.play('levelup')
              w.fx:preset('levelup', w.player.body.x, w.player.body.y - 10, 12)
              say(w, n, { 'Molt bé! Ara saps fer ' .. sp.name .. ': ' .. sp.desc,
                          Magic.has_staff(st, w.game.items) and 'Tria\'l amb Q/E i llança\'l amb V.' or
                          'Recorda: per fer màgia cal portar el Bastó màgic de la Cova de Roda.' })
            else
              say(w, n, { 'Gairebé! La resposta era: ' .. q[2][1] .. '.', 'Torna-ho a provar quan vulguis.' })
            end
          end }
        end
        w.dialogue:show(n.props.say_name, { 'Lliçó de ' .. sp.name .. '.', q[1] }, function() menu(w, 'Classe de màgia', opts) end)
      end }
    end
  end
  menu(w, 'Classe de màgia', items)
end

function Services.school(w, n, sv)
  local st = w.state
  menu(w, sv.label, with_enter(w, n, {
    { 'Classe de màgia', function() close(w); Services.magic_class(w, n) end },
    { 'Lliçó: coneix el poble', function()
      close(w)
      quiz(w, n, 'Lliçó de la mestra', LESSON, 'lesson', true, function() w:reward(12, 2, 'Resposta correcta') end)
    end },
    { 'Botiquí de l\'escola (un cop al dia)', function()
      close(w)
      if require('src.systems.rest').free_kit(w, 'escola') then
        say(w, n, { 'Tenim un botiquí a l\'aula per als ensurts. Té!' }); w.game.audio.play('chest')
      else say(w, n, { 'Avui ja te\'n vaig donar un. Torna demà!' }) end
    end },
    { 'Parlar', function()
      close(w)
      say(w, n, { 'Hola, ' .. (st.player_name or 'bonica criatura') .. '! Sóc la mestra de l'escola.',
                  'Conèixer el poble és important: on és el CAP, la Policia Local, la biblioteca...' })
    end },
  }, 'Entrar a l\'aula'))
end

-- ---------------------------------------------------------------- pesca (en Quim, pescador del port)
function Services.fisher(w, n, sv)
  local Fishing = require('src.systems.fishing')
  local st = w.state
  local has_rod = (st.inventory or {})[Fishing.ROD]
  menu(w, sv.label, {
    { 'Consells de pesca', function()
      close(w)
      say(w, n, has_rod and { 'Posa\'t mirant el mar o l\'aigua del port i prem Acció per llançar.',
                              'Quan el suro faci «!», prem Acció de seguida. Si t\'afanyes massa, el peix s\'espanta!',
                              'Al port hi ha llisses, crancs i pops; a la platja, mabres i molls. De nit, calamars.' }
                         or { 'Sense canya no es pot pescar, criatura.', 'Si vols, et puc ensenyar: parla amb mi i començarem.' })
    end },
    { 'Quadern de peixos (' .. Fishing.species(st) .. '/' .. Fishing.total_species() .. ')', function()
      close(w)
      local lines = {}
      for _, f in ipairs(Fishing.FISH) do
        local e = (st.fish_log or {})[f.id]
        if not f.junk then lines[#lines + 1] = e and (f.name .. ': ' .. e.n .. ' (rècord ' .. e.best .. ' cm)') or '???' end
      end
      local pages, cur = {}, {}
      for i, l in ipairs(lines) do
        cur[#cur + 1] = l
        if #cur == 4 or i == #lines then pages[#pages + 1] = table.concat(cur, '\n'); cur = {} end
      end
      say(w, n, pages)
    end },
    { 'Vendre el peix', function()
      close(w)
      local total, n_f = 0, 0
      for id, k in pairs(st.inventory) do
        local d = w.game.items[id]
        if type(d) == 'table' and d.fish and not Fishing.BY_ID[id].junk then
          total = total + (d.sell or 1) * k; n_f = n_f + k; st.inventory[id] = nil
        end
      end
      if n_f == 0 then say(w, n, { 'No portes cap peix. Au, a pescar!' }); return end
      require('src.systems.rpg').earn(st, total)
      w.game.audio.play('coin')
      say(w, n, { 'Mmm, quin peix més fresc! Te\'n dono ' .. total .. ' monedes.' })
    end },
    { 'Parlar', function()
      close(w)
      say(w, n, { 'Sóc en Quim. Fa cinquanta anys que pesco en aquest port.',
                  'El mar s\'ha de respectar: el peix petit es torna a l\'aigua i la brossa, a la paperera.' })
    end },
  })
end

function Services.station(w, n, sv)
  w:station_menu(n)
end

return Services
