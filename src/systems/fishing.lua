-- Pesca (2026-10-05): amb la Canya de pescar (te la dona en Quim, pescador del port, a la missió «La primera
-- pesca"), mirant l'aigua del mar o del port, Acció llança l'ham. Fases: cast (vola el suro) → wait (2-5 s) →
-- bite (picada: «!» durant 0,9 s, cal prémer Acció) → peix. Massa aviat o massa tard, s'escapa.
-- Cada espècie té nom, mida i lloc; de nit surten més calamars. Quadern: state.fish_log[id] = { n, best }.
-- La lògica pura (roll, log) es prova amb luajit (tests/fishing_cases.lua); la part de món fa servir love.*.
local Fishing = {}

-- where: 'mar' (platja i mar obert), 'port' (dins o vora el port), 'tots'
Fishing.FISH = {
  { id = 'sorell', name = 'Sorell', cm = { 15, 30 }, w = 22, where = 'tots' },
  { id = 'serra', name = 'Serrà', cm = { 12, 25 }, w = 18, where = 'tots' },
  { id = 'llissa', name = 'Llissa', cm = { 25, 50 }, w = 16, where = 'port' },
  { id = 'mabre', name = 'Mabre', cm = { 15, 30 }, w = 14, where = 'mar' },
  { id = 'sard', name = 'Sard', cm = { 18, 35 }, w = 12, where = 'tots' },
  { id = 'orada', name = 'Orada', cm = { 20, 45 }, w = 10, where = 'tots' },
  { id = 'moll', name = 'Moll', cm = { 12, 25 }, w = 9, where = 'mar' },
  { id = 'llobarro', name = 'Llobarro', cm = { 25, 60 }, w = 8, where = 'tots' },
  { id = 'calamar', name = 'Calamar', cm = { 15, 35 }, w = 5, where = 'tots', night = 4 },
  { id = 'cranc', name = 'Cranc', cm = { 6, 12 }, w = 6, where = 'port' },
  { id = 'pop', name = 'Pop', cm = { 30, 80 }, w = 3, where = 'port' },
  { id = 'tonyina', name = 'Tonyina petita', cm = { 50, 90 }, w = 1, where = 'mar' },
  { id = 'bota_vella', name = 'Bota vella', cm = { 25, 30 }, w = 5, where = 'tots', junk = true },
}
Fishing.BY_ID = {}
for _, f in ipairs(Fishing.FISH) do Fishing.BY_ID[f.id] = f end
Fishing.ROD = 'canya_pescar'
Fishing.PORT = { 1259 * 16, 1291 * 16, 70 * 16 }   -- centre i radi del Port de Roda de Berà (px)
Fishing.BITE_WINDOW = 0.9

-- tria un peix: spot 'mar' | 'port'; hour 0-23; rng(a, b) com love.math.random
function Fishing.roll(spot, hour, rng)
  local night = hour and (hour >= 21 or hour < 6)
  local pool, total = {}, 0
  for _, f in ipairs(Fishing.FISH) do
    if f.where == 'tots' or f.where == spot then
      local w = f.w * ((night and f.night) or 1)
      pool[#pool + 1] = { f, w }
      total = total + w
    end
  end
  local u = rng() * total
  for _, p in ipairs(pool) do
    u = u - p[2]
    if u <= 0 then
      local f = p[1]
      return f.id, rng(f.cm[1], f.cm[2])
    end
  end
  local f = pool[#pool][1]
  return f.id, f.cm[1]
end

-- apunta el peix al quadern; torna true si és una espècie nova
function Fishing.log(st, id, cm)
  st.fish_log = st.fish_log or {}
  local e = st.fish_log[id]
  local new = e == nil
  e = e or { n = 0, best = 0 }
  e.n = e.n + 1
  if cm > e.best then e.best = cm end
  st.fish_log[id] = e
  return new
end

function Fishing.species(st)
  local n = 0
  for id in pairs(st.fish_log or {}) do if Fishing.BY_ID[id] and not Fishing.BY_ID[id].junk then n = n + 1 end end
  return n
end

function Fishing.total_species()
  local n = 0
  for _, f in ipairs(Fishing.FISH) do if not f.junk then n = n + 1 end end
  return n
end

-- ---------------------------------------------------------------- al món
-- primera casella d'aigua (del mar o del port: no les piscines) davant del jugador, a 1-4 caselles
local function water_ahead(w)
  local pl = w.player
  local f = require('src.entities.player').DIRS[pl.facing]
  local r = w.game.renderer
  for d = 1, 4 do
    local x, y = pl.body.x + f[1] * 16 * d, pl.body.y - 2 + f[2] * 16 * d
    local tx, ty = math.floor(x / 16), math.floor(y / 16)
    local code = w.map:cell(tx, ty)
    if code and code % 4 == 2 then
      local g = w.map:tile_at('ground', tx, ty)
      if g and r and r.water and r.water[g] then return nil, 'pool' end
      return tx * 16 + 8, ty * 16 + 8
    end
  end
  return nil
end

function Fishing.try_start(w)
  local st = w.state
  if not (st.inventory or {})[Fishing.ROD] or not w.def.outdoor or w.player.vehicle or w.player.swimming then return false end
  local bx, by = water_ahead(w)
  if not bx then
    if by == 'pool' then w.hud:toast('A la piscina no hi ha peixos!', 2); return true end
    return false
  end
  local spot = (bx - Fishing.PORT[1]) ^ 2 + (by - Fishing.PORT[2]) ^ 2 < Fishing.PORT[3] ^ 2 and 'port' or 'mar'
  w.fishing = { phase = 'cast', t = 0, bx = bx, by = by, spot = spot, wait = 2 + love.math.random() * 3 }
  w.game.audio.play('swing')
  return true
end

local function finish(w, text)
  w.fishing = nil
  if text then w.hud:toast(text, 2.5) end
end

-- cada fotograma mentre es pesca (el jugador no es mou); pressed: accions d'aquest fotograma
function Fishing.update(w, dt, pressed)
  local f = w.fishing
  f.t = f.t + dt
  if pressed.cancel or pressed.attack then return finish(w, 'Has recollit la canya') end
  if f.phase == 'cast' then
    if f.t >= 0.45 then f.phase, f.t = 'wait', 0; w.game.audio.play('splash') end
  elseif f.phase == 'wait' then
    if pressed.confirm then return finish(w, 'Massa aviat! El peix s\'ha espantat') end
    if f.t >= f.wait then f.phase, f.t = 'bite', 0; w.game.audio.play('confirm') end
  elseif f.phase == 'bite' then
    if pressed.confirm then
      local hour = math.floor((w.state.clock or 600) / 60) % 24
      local id, cm = Fishing.roll(f.spot, hour, function(a, b)
        if a then return love.math.random(a, b) end
        return love.math.random()
      end)
      local def = Fishing.BY_ID[id]
      local St = require('src.state')
      St.give(w.state, id)
      local new = Fishing.log(w.state, id, cm)
      w.fishing = nil
      w.game.audio.play(def.junk and 'block' or 'chest')
      w.fx:preset('sparkle', f.bx, f.by - 4, 10)
      local pages = { def.junk and ('Has pescat... una ' .. def.name:lower() .. '! Algú l\'ha llençada al mar. Porta-la a la paperera.')
                      or ('Has pescat un ' .. def.name:lower() .. ' de ' .. cm .. ' cm!') }
      if new and not def.junk then
        pages[#pages + 1] = 'Espècie nova al quadern: ' .. Fishing.species(w.state) .. ' de ' .. Fishing.total_species() .. '.'
      end
      w.dialogue:show(nil, pages)
      local Town = require('src.systems.town')
      Town.event(w, 'event', { name = 'fish_caught' })
      if Fishing.species(w.state) >= 5 then Town.event(w, 'event', { name = 'fish_species_5' }) end
      return
    end
    if f.t >= Fishing.BITE_WINDOW then return finish(w, 'Oh! S\'ha escapat... Prem Acció quan surti «!»') end
  end
end

function Fishing.draw(w, ox, oy)
  local f = w.fishing
  if not f then return end
  local pl = w.player
  local f2 = require('src.entities.player').DIRS[pl.facing]
  local hx, hy = pl.body.x + f2[1] * 8 - ox, pl.body.y - 14 + f2[2] * 4 - oy   -- punta de la canya
  local k = f.phase == 'cast' and math.min(1, f.t / 0.45) or 1
  local bx = hx + (f.bx - ox - hx) * k
  local by = hy + (f.by - oy - hy) * k - math.sin(k * math.pi) * 18
  local bob = f.phase == 'wait' and math.sin(f.t * 5) * 1 or (f.phase == 'bite' and math.sin(f.t * 30) * 2 or 0)
  love.graphics.setColor(0.4, 0.28, 0.16, 1)
  love.graphics.setLineWidth(2)
  love.graphics.line(pl.body.x - ox, pl.body.y - 6 - oy, hx, hy)            -- canya
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.95, 0.95, 0.95, 0.8)
  love.graphics.line(hx, hy, bx, by + bob)                                   -- fil
  love.graphics.setColor(0.9, 0.2, 0.15, 1); love.graphics.rectangle('fill', math.floor(bx) - 1, math.floor(by + bob) - 2, 3, 2)
  love.graphics.setColor(1, 1, 1, 1); love.graphics.rectangle('fill', math.floor(bx) - 1, math.floor(by + bob), 3, 1)
  if f.phase ~= 'cast' then
    local r = 3 + (f.t * 6) % 6
    love.graphics.setColor(1, 1, 1, 0.5 - r / 20); love.graphics.circle('line', math.floor(bx), math.floor(by) + 2, r)
  end
  if f.phase == 'bite' then
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.rectangle('fill', pl.body.x - ox - 2, pl.body.y - oy - 38, 4, 9)
    love.graphics.rectangle('fill', pl.body.x - ox - 2, pl.body.y - oy - 27, 4, 3)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Fishing
