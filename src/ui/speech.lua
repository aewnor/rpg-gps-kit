-- Menús en veu alta (2026-10-05): a cada fotograma es pregunta al menú obert què hi ha seleccionat (menu:speech(),
-- que torna una clau i el text). Quan canvia, es diu tallant l'anterior: moure's per les opcions no fa cua.
-- En entrar en una pantalla nova es diu també el títol. Només si la veu llegeix «tot» (settings.tts.all).
local Speech = { last = nil }

function Speech.update(game)
  local Tts = require('src.tts')
  local m = game.menu
  if not (m and m.speech) then Speech.last, Speech.screen = nil, nil; return end
  local s = Tts.settings and Tts.settings.tts
  if not (s and s.all ~= false) then return end
  local ok, key, text, screen, title = pcall(m.speech, m)
  if not ok or not key or key == Speech.last then return end
  Speech.last = key
  if screen ~= Speech.screen and title and title ~= '' then text = title .. '. ' .. (text or '') end
  Speech.screen = screen
  if text and text ~= '' then Tts.say(text, true) end
end

return Speech
