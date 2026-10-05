-- Gestor de sonido 8-bit (todo sintetizado: no hay archivos de audio en el paquete).
--
--  · Efectos: se sintetizan al arrancar (son cortos). Los que se solapan (pasos, monedas, golpes de ritmo)
--    tienen un pool de voces (Source:clone comparte el buffer): no se cortan entre sí.
--  · Música adaptativa (Audio.pick): día en el pueblo, noche tranquila con grillos, cuevas y cimas
--    misteriosas con viento, y un tema arcade en los minijuegos. Cambia con fundido cruzado.
--  · Rendimiento (Raspberry Pi): la música NO se sintetiza de golpe al arrancar. Se renderiza por trozos en
--    segundo plano (corrutina con presupuesto de ~3 ms por frame) y se guarda como WAV en el directorio de
--    datos (audio_cache/): a partir de la segunda partida se carga del disco al instante. Mientras una pista
--    no está lista, sigue sonando la anterior.
--  · Bucles: motor del vehículo (tono según la velocidad), retumbo del tren (volumen según la distancia),
--    grillos y viento (capas de ambiente).
local Audio = { sfx = {}, pools = {}, music = {}, loops = {}, current = nil, enabled = true, volume = 0.6,
                effects_volume = 1, music_volume = 0.45, jobs = {}, wanted = nil, ctx = {} }

local RATE = 22050
Audio.CACHE_VERSION = 3          -- súbelo si cambia una composición: invalida audio_cache/
Audio.BUDGET = 0.003             -- segundos de síntesis por frame

local function midi(n) return 440 * 2 ^ ((n - 69) / 12) end

local function osc(kind, phase)
  phase = phase % 1
  if kind == 'square' then return phase < 0.5 and 1 or -1 end
  if kind == 'pulse' then return phase < 0.25 and 1 or -1 end
  if kind == 'tri' then return 1 - 4 * math.abs(phase - 0.5) end
  if kind == 'saw' then return 2 * phase - 1 end
  return math.random() * 2 - 1 -- ruido
end

-- render de una lista de notas {t, dur, freq, kind, vol, slide, decay, vib = {rate, depth}, lp = 0..1}
-- kind 'lnoise': ruido filtrado (paso bajo, lp = suavizado). yield: función a la que ceder cada pocos miles
-- de muestras (render progresivo) o nil.
local function render_buf(len, notes, yield)
  local n = math.floor(len * RATE)
  local buf = {}
  for i = 1, n do buf[i] = 0 end
  local work = 0
  for _, nt in ipairs(notes) do
    local i0 = math.floor(nt.t * RATE) + 1
    local count = math.floor(nt.dur * RATE)
    local phase, lp = 0, 0
    local vib = nt.vib
    local alpha = nt.lp or 0.1
    for j = 0, count - 1 do
      local i = i0 + j
      if i > n then break end
      local p = j / count
      local f = nt.freq * (1 + (nt.slide or 0) * p)
      if vib then f = f * (1 + vib[2] * math.sin(6.2832 * vib[1] * j / RATE)) end
      phase = phase + f / RATE
      local env = math.min(1, j / (RATE * 0.005)) * (1 - p) ^ (nt.decay or 1)
      local v
      if nt.kind == 'lnoise' then lp = lp + ((math.random() * 2 - 1) - lp) * alpha; v = lp * 3
      else v = osc(nt.kind, phase) end
      buf[i] = buf[i] + v * env * nt.vol
    end
    work = work + count
    if yield and work > 6000 then work = 0; yield() end
  end
  return buf, n
end

local function to_sounddata(buf, n, yield)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 1, n do
    sd:setSample(i - 1, math.max(-1, math.min(1, buf[i])))
    if yield and i % 20000 == 0 then yield() end
  end
  return sd
end

local function render(len, notes) return to_sounddata(render_buf(len, notes)) end

-- buffer generado por una función f(i, t) → muestra (ambientes y motores)
local function gen(len, f)
  local n = math.floor(len * RATE)
  local buf = {}
  for i = 1, n do buf[i] = f(i, (i - 1) / RATE) end
  return buf, n
end

-- generador pseudoaleatorio propio (las pistas salen iguales en cada máquina: la caché es estable)
local function lcg(seed)
  local s = seed
  return function()
    s = (s * 1103515245 + 12345) % 2147483648
    return s / 2147483648
  end
end

-- Volums locals: respecten la configuració del servidor fins que el jugador els canvia.
function Audio.configure(settings, config)
  local s,c=settings.audio,config or {}
  Audio.volume=s.custom and s.master or (c.volum or .6)
  Audio.music_volume=s.custom and s.music or (c.volum_musica or .45)
  Audio.effects_volume=s.effects
  for _,ch in pairs(Audio.music) do ch.src:setVolume(ch.vol*Audio.volume*Audio.music_volume) end
  for _,ch in pairs(Audio.loops) do ch.src:setVolume(ch.vol*Audio.volume*Audio.effects_volume) end
  -- Aturar els efectes que ja sonen quan es baixa a silenci.
  if Audio.volume*Audio.effects_volume==0 then
    for _,pool in pairs(Audio.pools) do for _,src in ipairs(pool.voices) do src:stop() end end
  end
end

-- ---------------------------------------------------------------- efectos
local function sfx_defs()
  local d = {
    talk = { 0.04, { { t = 0, dur = 0.035, freq = 880, kind = 'square', vol = 0.15 } } },
    confirm = { 0.12, { { t = 0, dur = 0.05, freq = 988, kind = 'square', vol = 0.2 },
                        { t = 0.05, dur = 0.07, freq = 1319, kind = 'square', vol = 0.2 } } },
    swing = { 0.12, { { t = 0, dur = 0.12, freq = 1200, kind = 'noise', vol = 0.25, decay = 2 } } },
    hit = { 0.15, { { t = 0, dur = 0.15, freq = 180, kind = 'square', vol = 0.35, slide = -0.6, decay = 2 },
                    { t = 0, dur = 0.06, freq = 1, kind = 'noise', vol = 0.3 } } },
    hurt = { 0.25, { { t = 0, dur = 0.25, freq = 440, kind = 'saw', vol = 0.3, slide = -0.7 } } },
    block = { 0.12, { { t = 0, dur = 0.12, freq = 1568, kind = 'pulse', vol = 0.25, decay = 3 },
                      { t = 0, dur = 0.12, freq = 2093, kind = 'square', vol = 0.12, decay = 3 } } },
    -- cofre: arpegio y una lluvia de destellos agudos
    chest = { 0.75, { { t = 0, dur = 0.1, freq = midi(72), kind = 'square', vol = 0.2 },
                      { t = 0.1, dur = 0.1, freq = midi(76), kind = 'square', vol = 0.2 },
                      { t = 0.2, dur = 0.1, freq = midi(79), kind = 'square', vol = 0.2 },
                      { t = 0.3, dur = 0.15, freq = midi(84), kind = 'square', vol = 0.2 },
                      { t = 0.42, dur = 0.08, freq = midi(96), kind = 'tri', vol = 0.12, decay = 2 },
                      { t = 0.5, dur = 0.08, freq = midi(100), kind = 'tri', vol = 0.1, decay = 2 },
                      { t = 0.58, dur = 0.12, freq = midi(103), kind = 'tri', vol = 0.08, decay = 2 } } },
    stamp = { 0.25, { { t = 0, dur = 0.08, freq = midi(79), kind = 'square', vol = 0.2 },
                      { t = 0.1, dur = 0.15, freq = midi(86), kind = 'square', vol = 0.2 } } },
    bell = { 0.9, (function()
      local n = {}
      for i = 0, 3 do n[#n + 1] = { t = i * 0.22, dur = 0.2, freq = (i % 2 == 0) and 1760 or 1480,
                                    kind = 'tri', vol = 0.25, decay = 2 } end
      return n
    end)() },
    -- piscina: capbussó en entrar i braçada suau en nedar
    splash = { 0.45, { { t = 0, dur = 0.4, freq = 1, kind = 'noise', vol = 0.3, decay = 2.5 },
                       { t = 0, dur = 0.2, freq = 520, kind = 'tri', vol = 0.12, slide = -0.6, decay = 2 } } },
    -- tro: retruny greu que s'apaga a poc a poc
    thunder = { 2.2, { { t = 0, dur = 0.25, freq = 1, kind = 'noise', vol = 0.35, decay = 1.5 },
                       { t = 0.1, dur = 2.0, freq = 1, kind = 'noise', vol = 0.28, decay = 1.2 },
                       { t = 0, dur = 1.8, freq = 55, kind = 'tri', vol = 0.25, slide = -0.4, decay = 1.3 } } },
    -- renill del cavall (clàxon a cavall)
    neigh = { 0.75, { { t = 0, dur = 0.7, freq = 980, kind = 'saw', vol = 0.16, slide = -0.45, decay = 1.4 },
                      { t = 0.02, dur = 0.6, freq = 1460, kind = 'square', vol = 0.05, slide = -0.5, decay = 2 } } },
    swim = { 0.3, { { t = 0, dur = 0.28, freq = 1, kind = 'noise', vol = 0.12, decay = 3 } } },
    -- campanes de Sant Bartomeu (toc de les hores): ding-dong greu amb ressonància
    campana = { 2.6, { { t = 0, dur = 1.2, freq = 392, kind = 'tri', vol = 0.24, decay = 1.3 },
                       { t = 0, dur = 1.0, freq = 784, kind = 'tri', vol = 0.06, decay = 2 },
                       { t = 1.15, dur = 1.4, freq = 330, kind = 'tri', vol = 0.22, decay = 1.2 },
                       { t = 1.15, dur = 1.1, freq = 660, kind = 'tri', vol = 0.05, decay = 2 } } },
    horn = { 0.7, { { t = 0, dur = 0.65, freq = 311, kind = 'saw', vol = 0.18 },
                    { t = 0, dur = 0.65, freq = 392, kind = 'saw', vol = 0.15 } } },
    door = { 0.2, { { t = 0, dur = 0.2, freq = 220, kind = 'tri', vol = 0.3, slide = 0.5 } } },
    -- fase 6: encanteris i el drac
    spell = { 0.3, { { t = 0, dur = 0.28, freq = 660, kind = 'tri', vol = 0.22, slide = 1.2, vib = { 12, 0.03 } },
                     { t = 0, dur = 0.2, freq = 1, kind = 'noise', vol = 0.1, decay = 2 } } },
    heal = { 0.5, { { t = 0, dur = 0.12, freq = midi(79), kind = 'tri', vol = 0.2 },
                    { t = 0.12, dur = 0.12, freq = midi(84), kind = 'tri', vol = 0.2 },
                    { t = 0.24, dur = 0.25, freq = midi(88), kind = 'tri', vol = 0.2, decay = 2 } } },
    fire = { 0.35, { { t = 0, dur = 0.35, freq = 1, kind = 'lnoise', lp = 0.25, vol = 0.3, decay = 1.5 },
                     { t = 0, dur = 0.2, freq = 120, kind = 'saw', vol = 0.12, slide = -0.5 } } },
    roar = { 0.8, { { t = 0, dur = 0.75, freq = 92, kind = 'saw', vol = 0.3, slide = -0.35, vib = { 18, 0.08 } },
                    { t = 0, dur = 0.7, freq = 1, kind = 'lnoise', lp = 0.12, vol = 0.25, decay = 1.2 } } },
    -- subir de nivel: fanfarria
    levelup = { 0.9, { { t = 0, dur = 0.09, freq = midi(72), kind = 'square', vol = 0.18 },
                       { t = 0.09, dur = 0.09, freq = midi(76), kind = 'square', vol = 0.18 },
                       { t = 0.18, dur = 0.09, freq = midi(79), kind = 'square', vol = 0.18 },
                       { t = 0.27, dur = 0.5, freq = midi(84), kind = 'square', vol = 0.2, vib = { 7, 0.012 } },
                       { t = 0.27, dur = 0.5, freq = midi(76), kind = 'pulse', vol = 0.1 },
                       { t = 0, dur = 0.8, freq = midi(48), kind = 'tri', vol = 0.25 } } },
    coin = { 0.25, { { t = 0, dur = 0.06, freq = midi(83), kind = 'square', vol = 0.16 },
                     { t = 0.06, dur = 0.18, freq = midi(88), kind = 'square', vol = 0.16, decay = 2 } } },
    -- Olaf: maullido (sube y baja, con vibrato) y ronroneo
    meow = { 0.5, { { t = 0, dur = 0.16, freq = 620, kind = 'tri', vol = 0.3, slide = 0.6, vib = { 9, 0.03 } },
                    { t = 0.15, dur = 0.32, freq = 990, kind = 'tri', vol = 0.3, slide = -0.45, decay = 1.5,
                      vib = { 7, 0.04 } },
                    { t = 0.02, dur = 0.4, freq = 1980, kind = 'square', vol = 0.03, slide = -0.3, decay = 2 } } },
    purr = { 0.7, (function()
      local n = {}
      for i = 0, 15 do n[#n + 1] = { t = i * 0.042, dur = 0.03, freq = 1, kind = 'lnoise', lp = 0.05, vol = 0.22 } end
      return n
    end)() },
    -- pasos según el suelo
    step_asphalt = { 0.04, { { t = 0, dur = 0.03, freq = 1, kind = 'noise', vol = 0.12, decay = 3 },
                             { t = 0, dur = 0.02, freq = 140, kind = 'tri', vol = 0.12, decay = 2 } } },
    step_grass = { 0.07, { { t = 0, dur = 0.06, freq = 1, kind = 'lnoise', lp = 0.35, vol = 0.07, decay = 1.5 } } },
    step_dirt = { 0.06, { { t = 0, dur = 0.05, freq = 1, kind = 'lnoise', lp = 0.18, vol = 0.09, decay = 2 },
                          { t = 0, dur = 0.02, freq = 90, kind = 'tri', vol = 0.1 } } },
    step_sand = { 0.09, { { t = 0, dur = 0.08, freq = 1, kind = 'lnoise', lp = 0.5, vol = 0.05 } } },
    step_wood = { 0.05, { { t = 0, dur = 0.04, freq = 190, kind = 'tri', vol = 0.18, slide = -0.3, decay = 2 },
                          { t = 0, dur = 0.01, freq = 1, kind = 'noise', vol = 0.05 } } },
    -- vehículos
    horn_car = { 0.4, { { t = 0, dur = 0.36, freq = 415, kind = 'square', vol = 0.12 },
                        { t = 0, dur = 0.36, freq = 523, kind = 'square', vol = 0.1 } } },
    horn_moto = { 0.3, { { t = 0, dur = 0.26, freq = 660, kind = 'pulse', vol = 0.12 } } },
    horn_bell = { 0.5, { { t = 0, dur = 0.18, freq = 2349, kind = 'tri', vol = 0.18, decay = 2 },
                         { t = 0.2, dur = 0.28, freq = 2349, kind = 'tri', vol = 0.18, decay = 2 } } },
    skid = { 0.35, { { t = 0, dur = 0.35, freq = 1, kind = 'lnoise', lp = 0.6, vol = 0.08, decay = 1.2 } } },
    -- minijuegos
    kick = { 0.18, { { t = 0, dur = 0.12, freq = 120, kind = 'tri', vol = 0.4, slide = -0.6 },
                     { t = 0, dur = 0.05, freq = 1, kind = 'noise', vol = 0.2, decay = 2 } } },
    whistle = { 0.55, { { t = 0, dur = 0.5, freq = 2800, kind = 'square', vol = 0.07, vib = { 28, 0.03 } } } },
    cheer = { 1.2, { { t = 0, dur = 1.2, freq = 1, kind = 'lnoise', lp = 0.45, vol = 0.12, decay = 0.6 },
                     { t = 0.05, dur = 0.9, freq = 1, kind = 'lnoise', lp = 0.25, vol = 0.08 } } },
    beat = { 0.06, { { t = 0, dur = 0.05, freq = 880, kind = 'tri', vol = 0.18, decay = 2 } } },
    good = { 0.1, { { t = 0, dur = 0.08, freq = midi(84), kind = 'square', vol = 0.13, decay = 2 } } },
    perfect = { 0.14, { { t = 0, dur = 0.05, freq = midi(88), kind = 'square', vol = 0.13 },
                        { t = 0.05, dur = 0.08, freq = midi(93), kind = 'square', vol = 0.13, decay = 2 } } },
    miss = { 0.16, { { t = 0, dur = 0.15, freq = 110, kind = 'square', vol = 0.12, slide = -0.2 } } },
    reel = { 0.03, { { t = 0, dur = 0.02, freq = 1500, kind = 'pulse', vol = 0.08 } } },
    stop = { 0.1, { { t = 0, dur = 0.08, freq = 330, kind = 'square', vol = 0.15, decay = 2 } } },
    win = { 0.8, { { t = 0, dur = 0.1, freq = midi(79), kind = 'square', vol = 0.15 },
                   { t = 0.1, dur = 0.1, freq = midi(84), kind = 'square', vol = 0.15 },
                   { t = 0.2, dur = 0.1, freq = midi(88), kind = 'square', vol = 0.15 },
                   { t = 0.3, dur = 0.45, freq = midi(91), kind = 'square', vol = 0.15, vib = { 8, 0.01 } } } },
    lose = { 0.5, { { t = 0, dur = 0.2, freq = midi(67), kind = 'tri', vol = 0.2 },
                    { t = 0.2, dur = 0.3, freq = midi(62), kind = 'tri', vol = 0.2, slide = -0.05 } } },
    barrier = { 0.5, { { t = 0, dur = 0.45, freq = 180, kind = 'saw', vol = 0.06, slide = 0.3, vib = { 18, 0.05 } } } },
  }
  return d
end

-- voces por efecto: los que se repiten rápido se pueden solapar
local VOICES = { step_asphalt = 3, step_grass = 3, step_dirt = 3, step_sand = 3, step_wood = 3, coin = 3, beat = 3,
                 good = 2, perfect = 2, miss = 2, reel = 2, hit = 2, talk = 2, spark = 2, kick = 2, horn_car = 2 }

-- ---------------------------------------------------------------- música
-- día: D-G-A-D / Bm-G-A-D a 112 ppm, bajo en triángulo y melodía en pulso
local function day_song()
  local bpm, notes = 112, {}
  local e = 60 / bpm / 2 -- corchea
  local chords = { { 50, 54, 57 }, { 55, 59, 62 }, { 57, 61, 64 }, { 50, 54, 57 },
                   { 47, 50, 54 }, { 55, 59, 62 }, { 57, 61, 64 }, { 50, 54, 57 } }
  local melody = {
    { 74, 0, 76, 78, 81, 0, 78, 76 }, { 74, 0, 71, 74, 79, 0, 78, 76 },
    { 76, 0, 78, 79, 81, 0, 79, 78 }, { 76, 74, 73, 74, 0, 0, 0, 0 },
    { 78, 0, 79, 81, 83, 0, 81, 79 }, { 79, 0, 78, 76, 74, 0, 71, 74 },
    { 76, 0, 78, 79, 81, 79, 78, 76 }, { 74, 0, 0, 69, 74, 0, 0, 0 },
  }
  for bar = 0, 15 do
    local ch = chords[bar % 8 + 1]
    for i = 0, 7 do
      local t = (bar * 8 + i) * e
      notes[#notes + 1] = { t = t, dur = e * 0.9, freq = midi(ch[1] - 12 + ((i % 2 == 1) and 12 or 0)),
                            kind = 'tri', vol = 0.22 }
      if i % 2 == 0 then
        notes[#notes + 1] = { t = t, dur = e * 0.6, freq = midi(ch[(i / 2) % 3 + 1] + 12), kind = 'pulse', vol = 0.05 }
      end
      if i % 4 == 2 then notes[#notes + 1] = { t = t, dur = 0.03, freq = 1, kind = 'noise', vol = 0.04 } end
      local m = melody[bar % 8 + 1][i + 1]
      if m > 0 then
        notes[#notes + 1] = { t = t, dur = e * 1.6, freq = midi(m + (bar >= 8 and 12 or 0)), kind = 'square',
                              vol = bar >= 8 and 0.05 or 0.08, decay = 0.6 }
      end
    end
  end
  return 16 * 8 * e, notes
end

-- noche: Fmaj7-Dm7-B♭maj7-C a 72 ppm, arpegios suaves de triángulo y una nana escasa
local function night_song()
  local notes, e = {}, 60 / 72 / 2
  local chords = { { 53, 57, 60, 64 }, { 50, 53, 57, 60 }, { 46, 50, 53, 57 }, { 48, 52, 55, 60 } }
  local mel = { { 72, 0, 0, 0, 69, 0, 0, 0 }, { 69, 0, 0, 0, 65, 0, 67, 0 }, { 65, 0, 0, 0, 62, 0, 0, 0 },
                { 64, 0, 0, 0, 0, 0, 0, 0 } }
  for bar = 0, 7 do
    local ch = chords[bar % 4 + 1]
    notes[#notes + 1] = { t = bar * 8 * e, dur = 8 * e, freq = midi(ch[1] - 12), kind = 'tri', vol = 0.18, decay = 0.4 }
    for i = 0, 7 do
      local t = (bar * 8 + i) * e
      local up = { 1, 2, 3, 4, 3, 2, 3, 2 }
      notes[#notes + 1] = { t = t, dur = e * 1.8, freq = midi(ch[up[i + 1]] + 12), kind = 'tri', vol = 0.07, decay = 1.5 }
      local m = mel[bar % 4 + 1][i + 1]
      if m > 0 and bar >= 4 then
        notes[#notes + 1] = { t = t, dur = e * 3.5, freq = midi(m + 12), kind = 'pulse', vol = 0.035, decay = 1.2,
                              vib = { 5, 0.006 } }
      end
    end
  end
  return 8 * 8 * e, notes
end

-- cuevas: arpegio menor lento con bajo profundo
local function cave_song()
  local notes, e = {}, 0.3
  local arp = { 57, 60, 64, 60, 55, 59, 62, 59, 53, 57, 60, 57, 52, 56, 59, 56 }
  for rep = 0, 1 do
    for i, n in ipairs(arp) do
      local t = (rep * #arp + i - 1) * e
      notes[#notes + 1] = { t = t, dur = e * 1.8, freq = midi(n), kind = 'tri', vol = 0.18, decay = 1.5 }
      if i % 4 == 1 then
        notes[#notes + 1] = { t = t, dur = e * 4, freq = midi(n - 24), kind = 'tri', vol = 0.2 }
      end
    end
  end
  -- gotas lejanas
  local r = lcg(77)
  for _ = 1, 10 do
    notes[#notes + 1] = { t = r() * 9, dur = 0.12, freq = 1800 + r() * 900, kind = 'tri', vol = 0.05, slide = -0.4, decay = 3 }
  end
  return 2 * #arp * e, notes
end

-- cimas: dórico de re, notas largas con eco y campanas lejanas (misterioso, con aire)
local function peaks_song()
  local notes, e = {}, 0.35
  local pads = { { 50, 57 }, { 48, 55 }, { 53, 60 }, { 50, 57 }, { 46, 53 }, { 48, 55 }, { 45, 52 }, { 50, 57 } }
  local bells = { 74, 0, 0, 77, 0, 72, 0, 0, 69, 0, 0, 0, 71, 0, 74, 0 }
  for bar = 0, 7 do
    local p = pads[bar + 1]
    notes[#notes + 1] = { t = bar * 8 * e, dur = 8 * e, freq = midi(p[1] - 12), kind = 'tri', vol = 0.17, decay = 0.3 }
    notes[#notes + 1] = { t = bar * 8 * e, dur = 8 * e, freq = midi(p[2]), kind = 'tri', vol = 0.06, decay = 0.3,
                          vib = { 3, 0.004 } }
    for i = 0, 1 do
      local b = bells[(bar * 2 + i) % #bells + 1]
      if b > 0 then
        local t = (bar * 8 + i * 4) * e
        notes[#notes + 1] = { t = t, dur = 1.2, freq = midi(b), kind = 'tri', vol = 0.1, decay = 2.5 }
        notes[#notes + 1] = { t = t + 3 * e, dur = 1.0, freq = midi(b), kind = 'tri', vol = 0.04, decay = 2.5 }  -- eco
      end
    end
  end
  return 8 * 8 * e, notes
end

-- minijuegos: C-Am-F-G a 150 ppm, bajo saltarín y charles
local function arcade_song()
  local notes, e = {}, 60 / 150 / 2
  local chords = { { 48, 52, 55 }, { 45, 48, 52 }, { 41, 45, 48 }, { 43, 47, 50 } }
  local mel = { { 72, 76, 79, 76, 72, 0, 74, 76 }, { 72, 69, 72, 76, 74, 0, 72, 69 },
                { 69, 72, 77, 72, 69, 0, 72, 74 }, { 71, 74, 79, 77, 74, 0, 71, 74 } }
  for bar = 0, 7 do
    local ch = chords[bar % 4 + 1]
    for i = 0, 7 do
      local t = (bar * 8 + i) * e
      notes[#notes + 1] = { t = t, dur = e * 0.8, freq = midi(ch[1] - 12 + (i % 2) * 12), kind = 'square', vol = 0.09 }
      notes[#notes + 1] = { t = t, dur = 0.02, freq = 1, kind = 'noise', vol = i % 2 == 1 and 0.06 or 0.03 }
      local m = mel[bar % 4 + 1][i + 1]
      if m > 0 then
        notes[#notes + 1] = { t = t, dur = e * 0.9, freq = midi(m + (bar >= 4 and 12 or 0)), kind = 'pulse', vol = 0.08 }
      end
    end
  end
  return 8 * 8 * e, notes
end

local SONGS = { day = day_song, night = night_song, cave = cave_song, peaks = peaks_song, arcade = arcade_song }
for id, song in pairs(require('src.music_extra')) do SONGS[id] = song end
Audio.SONGS = SONGS

-- ---------------------------------------------------------------- bucles (ambiente, motor, tren)
local LOOPS = {
  crickets = function()
    local r = lcg(5)
    local chirps = {}
    for v = 0, 1 do    -- dos grillos con ritmos distintos
      local t = r() * 0.3
      while t < 2.8 do
        for k = 0, 2 do chirps[#chirps + 1] = { t + k * 0.055, 4100 + v * 600 } end
        t = t + 0.55 + v * 0.27 + r() * 0.2
      end
    end
    local n = math.floor(3.0 * RATE)
    local buf = {}
    for i = 1, n do buf[i] = 0 end
    for _, c in ipairs(chirps) do      -- cada chirrido escribe solo su ventana (barato al arrancar)
      local i0, len = math.floor(c[1] * RATE), math.floor(0.03 * RATE)
      for j = 0, len - 1 do
        local i = i0 + j + 1
        if i <= n then buf[i] = buf[i] + math.sin(6.2832 * c[2] * (i - 1) / RATE) * (1 - j / len) * 0.12 end
      end
    end
    return buf, n
  end,
  wind = function()
    local lp, lp2 = 0, 0
    return gen(4.0, function(i, t)
      local gust = 0.55 + 0.45 * math.sin(6.2832 * t / 4.0)
      lp = lp + ((math.random() * 2 - 1) - lp) * (0.02 + 0.03 * gust)
      lp2 = lp2 + (lp - lp2) * 0.2
      return lp2 * 2.2 * gust * 0.5
    end)
  end,
  rain = function()   -- pluja: soroll filtrat amb gotes que piquen
    local lp, hp = 0, 0
    local r = lcg(9)
    return gen(3.0, function(i, t)
      local w = math.random() * 2 - 1
      lp = lp + (w - lp) * 0.35
      hp = lp - hp * 0.6
      local drop = (r() < 0.0009) and (math.random() * 2 - 1) * 0.5 or 0
      return hp * 0.22 + drop
    end)
  end,
  rumble = function()   -- rodadura grave y el «ta-tac» de las juntas de la vía
    local lp = 0
    return gen(1.0, function(i, t)
      lp = lp + ((math.random() * 2 - 1) - lp) * 0.03
      local clack = 0
      local ph = t % 0.25
      if ph < 0.02 then clack = (1 - ph / 0.02) * 0.35 * (math.random() * 2 - 1) end
      return lp * 1.6 + clack + 0.08 * math.sin(6.2832 * 50 * t)
    end)
  end,
  engine_moto = function()
    return gen(0.2, function(i, t)
      local p = (t * 100) % 1
      return (2 * p - 1) * 0.16 + (((t * 50) % 1) < 0.3 and 0.08 or -0.08) + (math.random() * 2 - 1) * 0.02
    end)
  end,
  engine_car = function()
    return gen(0.2, function(i, t)
      local p = (t * 70) % 1
      return (1 - 4 * math.abs(p - 0.5)) * 0.22 + (((t * 35) % 1) < 0.5 and 0.05 or -0.05)
    end)
  end,
  engine_e = function()
    return gen(0.2, function(i, t)
      return (1 - 4 * math.abs((t * 500) % 1 - 0.5)) * 0.07 + (1 - 4 * math.abs((t * 1000) % 1 - 0.5)) * 0.03
    end)
  end,
}

-- ---------------------------------------------------------------- caché en disco
local function cache_path(name) return string.format('audio_cache/v%d_%s.wav', Audio.CACHE_VERSION, name) end

local function u32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256,
                                         math.floor(n / 16777216) % 256) end
local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end

local function save_wav(name, sd)
  pcall(function()
    local pcm = sd:getString()
    local hdr = 'RIFF' .. u32(36 + #pcm) .. 'WAVEfmt ' .. u32(16) .. u16(1) .. u16(1) .. u32(RATE) .. u32(RATE * 2)
                .. u16(2) .. u16(16) .. 'data' .. u32(#pcm)
    love.filesystem.createDirectory('audio_cache')
    love.filesystem.write(cache_path(name), hdr .. pcm)
  end)
end

local function load_wav(name)
  if not love.filesystem.getInfo(cache_path(name)) then return nil end
  local ok, sd = pcall(love.sound.newSoundData, cache_path(name))
  return ok and sd or nil
end

-- ---------------------------------------------------------------- arranque
local function make_music_source(name, sd)
  local src = love.audio.newSource(sd, 'static')
  src:setLooping(true)
  src:setVolume(0)
  Audio.music[name] = { src = src, vol = 0, target = 0 }
end

-- pista de música: de la caché si existe; si no, a la cola de síntesis en segundo plano
function Audio.request(name)
  if Audio.music[name] or Audio.jobs[name] or not SONGS[name] then return end
  local sd = load_wav(name)
  if sd then make_music_source(name, sd); return end
  local co = coroutine.create(function()
    local len, notes = SONGS[name]()
    local buf, n = render_buf(len, notes, coroutine.yield)
    local data = to_sounddata(buf, n, coroutine.yield)
    return data
  end)
  Audio.jobs[name] = co
  Audio.queue = Audio.queue or {}
  table.insert(Audio.queue, name)
end

function Audio.init()
  local ok, err = pcall(function()
    for name, def in pairs(sfx_defs()) do
      local src = love.audio.newSource(render(def[1], def[2]), 'static')
      Audio.sfx[name] = src
      local pool = { src }
      for _ = 2, VOICES[name] or 1 do pool[#pool + 1] = src:clone() end
      Audio.pools[name] = { voices = pool, next = 1 }
    end
    for name, f in pairs(LOOPS) do
      local src = love.audio.newSource(to_sounddata(f()), 'static')
      src:setLooping(true)
      Audio.loops[name] = { src = src, vol = 0, target = 0 }
    end
  end)
  Audio.enabled = ok
  if not ok then print('audio desactivat: ' .. tostring(err)) end
  -- la de día primero (es la del título); el resto se prepara en segundo plano en este orden
  for _, n in ipairs({ 'day', 'night', 'cave', 'peaks', 'arcade' }) do Audio.request(n) end
end

-- síntesis pendiente: avanza la corrutina hasta agotar el presupuesto de este frame
function Audio.work(budget)
  local q = Audio.queue
  if not q or #q == 0 then return end
  local t0 = love.timer.getTime()
  -- la pista que se quiere oír ya pasa delante
  if Audio.wanted and Audio.jobs[Audio.wanted] then
    for i, n in ipairs(q) do if n == Audio.wanted and i > 1 then table.remove(q, i); table.insert(q, 1, n) end end
  end
  while #q > 0 and love.timer.getTime() - t0 < (budget or Audio.BUDGET) do
    local name = q[1]
    local co = Audio.jobs[name]
    local ok, res = coroutine.resume(co)
    if not ok then
      print('audio: ' .. tostring(res)); table.remove(q, 1); Audio.jobs[name] = nil
    elseif coroutine.status(co) == 'dead' then
      table.remove(q, 1); Audio.jobs[name] = nil
      make_music_source(name, res)
      save_wav(name, res)
    end
  end
end

-- termina toda la síntesis pendiente ya (tests, benchmark)
function Audio.finish_all()
  while Audio.queue and #Audio.queue > 0 do Audio.work(10) end
end

-- ---------------------------------------------------------------- efectos
-- opts: { vol = 0..1, pitch = factor }
function Audio.play(name, opts)
  if not Audio.enabled then return end
  local pool = Audio.pools[name]
  if not pool then return end
  local voices = pool.voices
  local s
  for _, v in ipairs(voices) do if not v:isPlaying() then s = v; break end end
  if not s then s = voices[pool.next]; pool.next = pool.next % #voices + 1 end
  s:stop()
  s:setVolume(Audio.volume * Audio.effects_volume * (opts and opts.vol or 1))
  s:setPitch(opts and opts.pitch or 1)
  s:play()
end

local STEP_PITCH = { 0.92, 1.0, 1.08, 0.96, 1.04 }
local step_i = 0
function Audio.step(surface)
  step_i = step_i % #STEP_PITCH + 1
  Audio.play('step_' .. (surface or 'asphalt'), { vol = 0.55, pitch = STEP_PITCH[step_i] })
end

-- ---------------------------------------------------------------- música adaptativa
-- ctx: { scene = 'overworld'|'cave'… (música de la escena), outdoor, clock (minutos), height (m), minigame }
-- Devuelve la pista y las capas de ambiente { crickets = vol, wind = vol }.
Audio.PEAK_IN, Audio.PEAK_OUT = 70, 55   -- metros: histéresis para no alternar en el límite
function Audio.pick(ctx, prev)
  if ctx.minigame == 'none' then return nil, {} end      -- minijoc amb el seu propi ritme
  if ctx.minigame then return 'arcade', {} end
  local radio = require('src.systems.radio')
  if radio.valid(ctx.radio) then return ctx.radio, {} end
  if ctx.swimming then return 'swim', {} end
  if ctx.outdoor and ctx.vehicle == 'bici' then return 'bike', {} end
  if ctx.outdoor and ctx.vehicle == 'cavall' then return 'horse', {} end
  if ctx.scene == 'cave' then return 'cave', {} end
  if ctx.outdoor then
    local c = ctx.clock or 540
    local night = c < 7 * 60 or c >= 21 * 60
    local h = ctx.height or 0
    local high = h >= Audio.PEAK_IN or (prev == 'peaks' and h >= Audio.PEAK_OUT)
    if high then return 'peaks', { wind = 0.55, crickets = night and 0.25 or nil } end
    if night then return 'night', { crickets = 0.5, wind = 0.12 } end
    return 'day', {}
  end
  return 'day', {}
end

function Audio.set_context(ctx) Audio.ctx = ctx end

-- compatibilidad: la escena pide su música de base ('overworld' o 'cave')
function Audio.music_play(name)
  Audio.ctx = Audio.ctx or {}
  Audio.ctx.scene = name
end

local FADE = 0.7   -- volumen por segundo
local function fade(ch, dt, scale)
  if ch.vol < ch.target then ch.vol = math.min(ch.target, ch.vol + FADE * dt)
  elseif ch.vol > ch.target then ch.vol = math.max(ch.target, ch.vol - FADE * dt) end
  if ch.vol > 0 then
    ch.src:setVolume(ch.vol * scale)
    if not ch.src:isPlaying() and not Audio.paused then ch.src:play() end
  elseif ch.src:isPlaying() then
    ch.src:stop()
  end
end

function Audio.update(dt)
  if not Audio.enabled then return end
  Audio.work()
  if Audio.paused then return end
  local track, amb = Audio.pick(Audio.ctx or {}, Audio.current)
  Audio.wanted = track
  if track then Audio.request(track) end
  if track == nil then Audio.current = nil
  elseif Audio.music[track] then Audio.current = track end
  for name, ch in pairs(Audio.music) do
    ch.target = (name == Audio.current) and 1 or 0
    fade(ch, dt, Audio.music_volume * Audio.volume)
  end
  local wx = (Audio.ctx and Audio.ctx.outdoor and Audio.ctx.weather) or {}   -- capes del temps (src/systems/weather.lua)
  for _, n in ipairs({ 'crickets', 'wind', 'rain' }) do
    local ch = Audio.loops[n]
    if ch then ch.target = math.max(amb[n] or 0, wx[n] or 0); fade(ch, dt, Audio.volume * Audio.effects_volume) end
  end
  -- motor y tren: se fijan cada paso desde la escena; si nadie los fija, se apagan
  for _, n in ipairs({ 'rumble', 'engine_moto', 'engine_car', 'engine_e' }) do
    local ch = Audio.loops[n]
    if ch then
      ch.target = ch.set or 0
      ch.set = nil
      ch.vol = ch.target   -- sin fundido: siguen a la velocidad al momento
      if ch.vol > 0.01 then
        ch.src:setVolume(ch.vol * Audio.volume * Audio.effects_volume)
        ch.src:setPitch(ch.pitch or 1)
        if not ch.src:isPlaying() then ch.src:play() end
      elseif ch.src:isPlaying() then ch.src:stop() end
    end
  end
end

-- motor del vehículo: kind 'moto' | 'car' | 'e' (eléctrico); ratio = velocidad / máxima
function Audio.engine(kind, ratio)
  if not Audio.enabled or not kind then return end
  local ch = Audio.loops['engine_' .. kind]
  if not ch then return end
  ch.set = 0.25 + 0.35 * math.min(1, ratio)
  ch.pitch = 0.7 + 1.1 * math.min(1.2, ratio)
end

-- tren cerca: r = 0..1
function Audio.rumble(r)
  if not Audio.enabled then return end
  local ch = Audio.loops.rumble
  if ch and r > 0 then ch.set = math.max(ch.set or 0, r * 0.7); ch.pitch = 0.9 + r * 0.2 end
end

function Audio.pause(on)
  if not Audio.enabled then return end
  Audio.paused = on
  for _, group in ipairs({ Audio.music, Audio.loops }) do
    for _, ch in pairs(group) do
      if on then ch.src:pause() elseif ch.vol > 0 then ch.src:play() end
    end
  end
end

return Audio
