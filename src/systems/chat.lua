-- Preguntes als veïns de les cases (2026-10-05): després de la frase del veí, surten tres preguntes per triar
-- («Com et dius?», «Què fas?», «Tens animals?»…) i «Adéu!». Cada resposta és fixa per a cada veí (la llavor és
-- el seu nom i la casa), així el mateix veí sempre té el mateix gat i el mateix menjar preferit. Sense IA.
local Chat = {}

local NAMES_F = { 'Marta', 'Laia', 'Núria', 'Carla', 'Anna', 'Júlia', 'Rosa', 'Montse', 'Elena', 'Clara' }
local NAMES_M = { 'Jordi', 'Pau', 'Marc', 'Joan', 'Pere', 'Albert', 'Xavi', 'Toni', 'Quim', 'Biel' }
local PETS = { 'Sí! Un gat taronja que es diu Mixa.', 'Tinc un peix vermell que neda en rodones.',
               'Un gos petit, el Brutus. Borda molt però és bo.', 'No, però m\'agradaria tenir un conill.',
               'Dos periquitos que canten cada matí.', 'Una tortuga que es diu Lenta. Ha, ha!' }
local FOOD = { 'Els macarrons amb tomàquet!', 'La truita de patates.', 'Les maduixes, mmm!',
               'El pa amb tomàquet i oli.', 'La sopa de la iaia.', 'Els cigrons... és broma, la xocolata!' }
local LIKES = { 'Llegir contes al sofà.', 'Anar en bici fins a la platja.', 'Ballar amb música ben alta.',
                'Fer pastissos.', 'Cuidar les plantes del balcó.', 'Jugar a pilota al parc.' }
local RIDDLES = { { 'Té barba i no és home, té dents i no menja. Què és?', 'L\'all!' },
                  { 'Quan més en treus, més gran es fa. Què és?', 'Un forat!' },
                  { 'Com més s\'asseca, més es mulla. Què és?', 'La tovallola!' },
                  { 'Blanc per dins, verd per fora. Si vols que t\'ho digui, espera. Què és?', 'La pera!' } }

local function pick(list, h) return list[h % #list + 1] end

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

-- el veí amb qui parles en una casa o pis (escena procedural) i no és un servei ni un personatge del perfil
function Chat.applies(w, n)
  local proc = w.state and w.state.proc
  return w.id and w.id:sub(1, 5) == 'proc_' and not (proc and proc.kind == 'shop') and not n.props.service
         and not n.props.friend and not n.props.parent and not tostring(n.props.sprite or ''):find('cat', 1, true)
end

local function questions(w, n)
  local g, st = w.game, w.state
  local key = (n.props.say_name or n.name or 'veí') .. '|' .. tostring(w.id) .. '|' .. tostring(n.body and math.floor(n.body.x) or 0)
  local h = hash(key)
  local voice = require('src.systems.town').sprite_voice(n.props.sprite)
  local name = voice == 'm' and pick(NAMES_M, h) or pick(NAMES_F, h)
  local own = tostring(n.props.say_name or ''):match("^[LE][al]%s(%u.*)$") or tostring(n.props.say_name or ''):match("^L'(%u.*)$")
  if own and not own:find(' ', 1, true) then name = own end   -- («La Laia» → Laia; «La veïna» no és un nom)
  local clock = math.floor(st.clock or 600) % 1440
  local hour = math.floor(clock / 60)
  local doing = hour < 10 and 'Esmorzo i després me\'n vaig a treballar.' or hour < 14 and 'Faig el dinar. Avui toca arròs!'
                or hour < 20 and 'Descanso una mica i després sortiré a passejar.' or 'Ja és tard: em preparo per anar a dormir.'
  local street
  local back = st.proc and st.proc.back
  if back then street = require('src.systems.streets').name_at(back.x, back.y, 80) end
  local riddle = pick(RIDDLES, math.floor(h / 7))
  local who = st.player_name or 'amic'
  return {
    { 'Com et dius?', { 'Em dic ' .. name .. '. I tu ets ' .. who .. ', oi? Quina alegria conèixer-te!' } },
    { 'Què fas?', { doing } },
    { 'Tens animals?', { pick(PETS, math.floor(h / 3)) } },
    { 'Quin és el teu menjar preferit?', { pick(FOOD, math.floor(h / 5)) } },
    { 'Què t\'agrada fer?', { pick(LIKES, math.floor(h / 11)) } },
    { 'On som?', { street and ('Vivim al ' .. street .. '. Quan surts, mira el cartell del carrer!')
                   or 'A casa meva! Quan surtis, mira el cartell del carrer.' } },
    { 'Saps una endevinalla?', { riddle[1], riddle[2] } },
    { 'Quina hora és?', { 'Són les ' .. require('src.systems.daylight').label(clock) .. '.' } },
  }
end

-- obre la llista de preguntes (3 a l'atzar de les que encara no has fet en aquesta conversa) i «Adéu!»
function Chat.open(w, n, done, asked)
  asked = asked or {}
  local all = questions(w, n)
  local left = {}
  for _, q in ipairs(all) do if not asked[q[1]] then left[#left + 1] = q end end
  local g = w.game
  local name = n.props.say_name or 'Veí'
  w.talking = nil   -- (amb la llista oberta el món és aturat; «Tornar» també tanca bé)
  local items = {}
  for _ = 1, math.min(3, #left) do
    local q = table.remove(left, love.math.random(#left))
    items[#items + 1] = { q[1], function()
      g:close_menu()
      asked[q[1]] = true
      w.talking = n
      w.dialogue:show(name, q[2], function() Chat.open(w, n, done, asked) end)
    end }
  end
  items[#items + 1] = { 'Adéu!', function() g:close_menu(); if done then done() end end }
  g:open_list(name .. ' · pregunta-li', items)
end

return Chat
