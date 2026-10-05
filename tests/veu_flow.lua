-- Veu i majúscules per a qui encara no llegeix (love . --test=tests/veu_flow.lua --mute): els menús es llegeixen
-- en moure's (tallant l'anterior), els avisos també, els homes parlen amb veu d'home i el text pot anar en
-- MAJÚSCULES. Desa majuscules.png.
return function(api)
  local Tts = require('src.tts')
  local S = require('src.settings')
  local Upper = require('src.ui.upper')
  local Input = require('src.input')
  local g = api.scene().game
  api.talk_through()
  local backend = Tts.backend
  Tts.backend = 'web'      -- (a les proves no hi ha veu: així queda l'historial)
  local function last() return Tts.history[#Tts.history] or '' end
  -- menú de pausa
  g:open_menu(); api.wait(12)
  api.check(last():find('Pausa', 1, true) ~= nil, 'en obrir el menú, diu el títol i l\'opció (' .. last() .. ')')
  local before = last()
  api.press('down'); api.wait(12)
  api.check(last() ~= before and not last():find('Pausa', 1, true), 'en baixar, diu la nova opció sola (' .. last() .. ')')
  g:close_menu(); api.wait(2)
  -- avisos
  g.scene.hud:toast('Has trobat una poma!', 2)
  api.wait(1)
  api.check(last() == 'Has trobat una poma!', 'els avisos també es llegeixen')
  -- veu d'home i de dona
  local d = g.scene.dialogue
  d:show('En Jordi', { 'Hola, bon dia!' }); api.wait(1)
  api.check(Tts.last_voice == 'm', 'en Jordi parla amb veu d\'home')
  d.open = false
  d:show('La Carme', { 'Hola, maca!' }); api.wait(1)
  api.check(Tts.last_voice == 'f', 'la Carme, amb veu de dona')
  d.open = false
  -- majúscules
  local old = S.get().upper
  S.get().upper, Upper.on = true, true
  api.check(g.font:getWidth('plaça') == g.font:getWidth('PLAÇA'), 'en majúscules, les mides es calculen amb el text en majúscules')
  d:show('La Carme', { 'Hola! Vols venir a la plaça a jugar amb l\'àvia?' }); api.wait(60)
  api.check(d:reading_char() ~= nil and d:reading_char() > 3, 'la paraula que es llegeix es ressalta (caràcter ' .. tostring(d:reading_char()) .. ')')
  Tts.event({ type = 'tts_word', id = Tts.seq, i = 20, n = 46 })
  local c = d:reading_char()
  api.check(c and c >= 18 and c <= 24, 'amb els avisos del navegador, va sincronitzat (' .. tostring(c) .. ')')
  local done = false
  love.graphics.captureScreenshot(function(img) img:encode('png', 'majuscules.png'); done = true end)
  for _ = 1, 60 do if done then break end; api.wait(1) end
  d.open = false
  S.get().upper, Upper.on = old, old and true or false
  -- opcions: hi ha els dos interruptors
  g:open_options(false); api.wait(2)
  local has_up, has_all = false, false
  for _, it in ipairs(g.menu.list) do
    if tostring(it[1]):find('MAJÚSCULES') then has_up = true end
    if tostring(it[1]):find('Llegir%-ho tot') then has_all = true end
  end
  api.check(has_up and has_all, 'a Opcions hi ha «TEXT EN MAJÚSCULES» i «Llegir-ho tot»')
  g:close_menu()
  Tts.backend = backend
  Input.release_all()
end
