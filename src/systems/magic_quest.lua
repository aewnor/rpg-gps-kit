-- La màgia s'aprèn (2026-10-05): trobar el bastó no n'hi ha prou. Missions del capítol del drac, després
-- de «fons» (data/missions.json):
--   basto_que_es   ensenyar el bastó a la bibliotecària (et diu què és)
--   llibre_magia   buscar el Llibre de Màgia a les prestatgeries de la biblioteca (un llibre concret, cada dia un)
--   llibre_mestra  portar el llibre a la mestra de l'escola
--   pati_magia     tres proves d'encanteri al pati, a prop de la mestra
-- Fins aleshores el bastó pega però no fa encanteris (MQ.can_cast). Si el joc no té aquestes missions (un altre
-- poble del kit), no hi ha cap bloqueig.
local Missions = require('src.systems.missions')
local MQ = {}

MQ.STEPS = { basto_que_es = 1, llibre_magia = 2, llibre_mestra = 3, pati_magia = 4 }
local REASON = {
  "Encara no saps fer servir el bastó. Porta'l a la biblioteca perquè te'l mirin.",
  'Primer has de trobar el Llibre de Màgia a les prestatgeries de la biblioteca.',
  "Porta el Llibre de Màgia a la mestra de l'escola: ella t'ensenyarà.",
}

local function defs(w) return require('src.systems.town').defs(w.game) end

-- id de la missió de màgia activa (o nil)
function MQ.current(w)
  local d = defs(w)
  if not d then return nil end
  local m = Missions.current(d, w.state)
  return m and MQ.STEPS[m.id] and m.id or nil
end

function MQ.can_cast(w)
  local st = w.state
  if st.magic_ok then return true end
  local d = defs(w)
  if not (d and d.by_id and d.by_id.pati_magia) then return true end   -- (sense les missions: com abans)
  local q = Missions.state(st)
  if q.done.pati_magia then st.magic_ok = true; return true end
  local cur = MQ.current(w)
  if cur == 'pati_magia' then return true end                          -- les proves del pati
  local k = 1
  if q.done.llibre_mestra then k = 3 elseif q.done.llibre_magia then k = 3 elseif q.done.basto_que_es then k = 2 end
  return false, REASON[k]
end

-- llegir un llibre de la biblioteca: si busques el Llibre de Màgia, només un de les prestatgeries ho és
function MQ.on_book(w, s)
  if MQ.current(w) ~= 'llibre_magia' or not (w.id or ''):find('biblioteca', 1, true) then return false end
  local st = w.state
  local books = {}
  for _, o in ipairs(w.signs) do if o.props.book then books[#books + 1] = o end end
  if #books == 0 then return false end
  local pick = books[((st.day or 1) * 3) % #books + 1]
  if s ~= pick then
    w:say_text(nil, s.props.say, function()
      w.hud:toast('Aquest no és el Llibre de Màgia. Prova una altra prestatgeria!', 3, true)
    end)
    return true
  end
  require('src.state').give(st, 'llibre_magia')
  w.game.audio.play('levelup')
  w.fx:preset('sparkle', s.x, s.y - 8, 14, { color = { 0.6, 0.7, 1 }, speed = 20 })
  w.dialogue:show(nil, { 'Entre els llibres n\'hi ha un que brilla...', 'Has trobat el Llibre de Màgia!',
                         "Porta'l a la mestra de l'escola." })
  return true
end

-- cada encanteri llançat a prop de la mestra durant les proves del pati compta
function MQ.on_cast(w)
  if MQ.current(w) ~= 'pati_magia' then return end
  local pl = w.player.body
  for _, n in ipairs(w.npcs or {}) do
    if n.props.service_id == 'escola' and not n.hidden and (n.body.x - pl.x) ^ 2 + (n.body.y - pl.y) ^ 2 < (12 * 16) ^ 2 then
      require('src.systems.town').event(w, 'event', { name = 'magic_practice' })
      if not MQ.current(w) then
        w.state.magic_ok = true
        w.dialogue:show(n.props.say_name, { 'Ho has fet molt bé!', 'Ja saps fer màgia. Q i E canvien d\'encanteri.',
                                            'Ara ja pots venir a la Classe de màgia per aprendre\'n de nous.' })
      end
      return
    end
  end
  w.hud:toast('Les proves es fan al pati, a prop de la mestra', 2)
end

return MQ
