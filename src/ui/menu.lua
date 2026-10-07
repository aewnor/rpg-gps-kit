-- Menús: título, pausa, quadern, mapa y controles. Navegación con arriba/abajo/confirmar/cancelar.
local Menu = {}
Menu.__index = Menu

function Menu.new(game, screen)
  local self = setmetatable({ game = game, screen = screen or 'pause', sel = 1 }, Menu)
  return self
end

function Menu:items()
  local g = self.game
  if self.screen == 'list' then
    local it = {}
    for _, e in ipairs(self.list) do it[#it + 1] = e end
    it[#it + 1] = { 'Tornar', function() if self.from_title then g:to_title() else g:close_menu() end end }
    return it
  end
  if self.screen == 'title' then
    local it = {}
    -- perfils (src/ui/profiles.lua): 5 ranures amb avatar, casa i amics; la partida sense perfil continua
    it[#it + 1] = { 'Jugar (perfils)', function() g:open_profiles() end }
    if g:has_save() then it[#it + 1] = { 'Continuar sense perfil', function() g:continue_game() end } end
    it[#it + 1] = { 'Partida ràpida', function() g:new_game() end }
    it[#it + 1] = { 'Opcions (so i veu)', function() g:open_audio_options(true) end }
    it[#it + 1] = { 'Controls', function() self.screen = 'controls'; self.back = 'title' end }
    if love.system.getOS() ~= 'Web' then it[#it + 1] = { 'Sortir', function() love.event.quit() end } end
    return it
  end
  return {
    { 'Continuar', function() g:close_menu() end },
    { 'Desar partida', function() g:save_game(true) end },
    { 'Personatge i equip', function() self.screen = 'character'; self.back = 'pause' end },
    { 'Esperar (passar el temps)', function() self:open_wait() end },
    { 'Diari de missions', function() g:open_journal(true) end },
    { 'Quadern de llocs', function() self.screen = 'notebook'; self.back = 'pause' end },
    { 'Aspecte', function() self:open_skins() end },
    { 'Opcions (so i veu)', function() g:open_audio_options(false) end },
    { 'Temporada', function() self:open_seasons() end },
    { 'Mapa', function() self.screen = 'map'; self.back = 'pause' end },
    { 'Controls', function() self.screen = 'controls'; self.back = 'pause' end },
    { 'Desar i tornar al títol', function() if g:save_game(false) then g:to_title() end end },
  }
end

-- ------------------------------------------------------------ personatge: equip, inventari, vehicles
local Rpg = require('src.systems.rpg')

local function count_str(n) return (n and n > 1) and (' ×' .. n) or '' end

function Menu:open_actions()
  local g = self.game
  g:open_list('Personatge', {
    { 'Canviar l\'equip', function() self:open_slots() end },
    { 'Màgia (encanteris)', function() self:open_spells() end },
    { 'Inventari', function() self:open_inventory() end },
    { 'Vehicles', function() self:open_vehicles() end },
    { 'Saltar (desencallar-me)', function()   -- src/systems/unstuck.lua: a la casella lliure més propera
      local w = g.scene
      if not (w and w.player) then return end
      local d = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[w.player.facing] or { 0, 0 }
      g:close_menu()
      require('src.systems.unstuck').jump(w, d[1], d[2])
    end },
    { 'Ràdio de butxaca', function() require('src.systems.radio').open(g) end },
  })
end

-- «Esperar»: fa passar el temps (src/systems/rest.lua Rest.wait), p. ex. si la missió és en un lloc tancat de nit
function Menu:open_wait()
  local g = self.game
  local w, st = g.scene, g.state
  if not (w and st and w.player) then return end
  local Daylight = require('src.systems.daylight')
  local function go(minutes)
    g:close_menu()
    require('src.systems.rest').wait(w, minutes)
  end
  local c = math.floor(st.clock or 600) % 1440
  local items = {}
  local closed = w.town and w.town.closed
  if closed and closed.wait and closed.wait > 0 then
    items[#items + 1] = { 'Fins que obri (' .. Daylight.label(closed.at) .. ')',
                          function() go(closed.wait) end }
  end
  items[#items + 1] = { 'Una hora', function() go(60) end }
  items[#items + 1] = { 'Tres hores', function() go(180) end }
  items[#items + 1] = { 'Fins al matí (8:00)', function() go((480 - c) % 1440) end }
  items[#items + 1] = { 'Fins a la nit (21:00)', function() go((1260 - c) % 1440) end }
  g:open_list('Esperar · ara són les ' .. Daylight.label(c), items)
end

-- arbre d'encanteris (src/systems/magic.lua): els coneguts es poden triar; els altres diuen el nivell que cal
function Menu:open_spells()
  local g, st = self.game, self.game.state
  local Magic = require('src.systems.magic')
  local staff = Magic.has_staff(st, g.items)
  local items = {}
  for _, sp in ipairs(Magic.SPELLS) do
    local known = Magic.unlocked(st, sp.id)
    local label = (st.spell == sp.id and known and '> ' or '') .. sp.name ..
        (known and ('  ' .. sp.mp .. ' MP') or ('  (nivell ' .. sp.level .. (sp.after and ', després de ' ..
        Magic.BY_ID[sp.after].name or '') .. ')'))
    items[#items + 1] = { label, function()
      if known then
        st.spell = sp.id
        g.hud:toast(sp.name .. ': ' .. sp.desc .. (staff and '' or ' (cal el Bastó màgic)'), 3)
      else
        g.hud:toast('Encara no: puja fins al nivell ' .. sp.level .. '.', 2)
      end
      g:close_menu()
    end }
  end
  g:open_list(staff and 'Màgia · V per llançar, Q/E per canviar' or 'Màgia · cal el Bastó màgic (Cova de Roda)', items)
end

function Menu:open_slots()
  local g, st = self.game, self.game.state
  local items = {}
  for _, slot in ipairs(Rpg.SLOTS) do
    local cur = g.items[st.equipment[slot] or '']
    items[#items + 1] = { Rpg.SLOT_NAME[slot] .. ': ' .. (cur and cur.name or '—'), function() self:open_slot(slot) end }
  end
  g:open_list('Equip', items)
end

function Menu:open_slot(slot)
  local g, st = self.game, self.game.state
  local items = {}
  for id, n in pairs(st.inventory) do
    local d = g.items[id]
    if type(d) == 'table' and Rpg.fits(d, slot) then
      local lock = (d.min_level or 1) > st.char_level and ('  [Nv' .. d.min_level .. ']') or ''
      local stat = (d.attack and ('  At+' .. d.attack) or '') .. (d.defense and ('  Df+' .. d.defense) or '')
      items[#items + 1] = { (st.equipment[slot] == id and '> ' or '  ') .. d.name .. stat .. lock, function()
        local ok, why = Rpg.equip(st, g.items, id, slot)
        g:close_menu()
        g.hud:toast(ok and ('Equipat: ' .. d.name) or why, 2)
      end, sprite=d.sprite }
    end
  end
  table.sort(items, function(a, b) return a[1] < b[1] end)
  if st.equipment[slot] then
    items[#items + 1] = { 'Treure-ho', function() Rpg.unequip(st, slot); g:close_menu() end }
  end
  if #items == 0 then items[1] = { '(No tens res per a aquesta ranura)', function() g:close_menu() end } end
  g:open_list(Rpg.SLOT_NAME[slot], items)
end

function Menu:open_inventory()
  local g, st = self.game, self.game.state
  local items = {}
  for id, n in pairs(st.inventory) do
    local d = g.items[id]
    if type(d) == 'table' then
      local label = d.name .. count_str(n)
      if d.kind == 'food' then
        items[#items + 1] = { label .. '  (fer servir)', function()
          local msg = Rpg.use(st, g.items, id, g.scene and g.scene.player)
          g:close_menu()
          if msg then g.hud:toast(msg, 2) end
        end }
      else
        items[#items + 1] = { label, function() g:close_menu() end }
      end
      if items[#items] then items[#items].sprite=d.sprite end
    end
  end
  table.sort(items, function(a, b) return a[1] < b[1] end)
  if #items == 0 then items[1] = { '(Inventari buit)', function() g:close_menu() end } end
  g:open_list('Inventari  ·  ' .. st.coins .. ' monedes  ·  ' .. (st.gems or 0) .. ' gemmes', items)
end

function Menu:open_vehicles()
  local g, st = self.game, self.game.state
  local Vehicles = require('src.systems.vehicles')
  local items = {}
  for _, id in ipairs(Vehicles.ORDER) do
    local v = Vehicles.CATALOG[id]
    if st.vehicles[id] then
      local lock = (v.min_level or 1) > st.char_level and ('  [Nv' .. v.min_level .. ']') or ''
      items[#items + 1] = { (st.vehicle == id and '> ' or '  ') .. v.name .. lock, function()
        g:close_menu()
        if (v.min_level or 1) > st.char_level then g.hud:toast('Requereix nivell ' .. v.min_level, 2); return end
        st.vehicle = id
        g.hud:toast('Vehicle: ' .. v.name .. ' (tecla B)', 2)
      end }
    end
  end
  g:open_list('Vehicles', items)
end

function Menu:open_skins()
  local g = self.game
  local items = {}
  if g.profile then   -- l'avatar del perfil (paperdoll)
    items[1] = { ((g.state.skin == 'avatar') and '> ' or '  ') .. 'El meu avatar (' .. g.profile.name .. ')', function()
      g:apply_skin('avatar'); g:close_menu(); g.hud:toast('Aspecte: el teu avatar', 2)
    end }
  end
  for _, sk in ipairs(g.skins) do
    local mark = (g.state.skin or 'default') == sk.id and '> ' or '  '
    items[#items + 1] = { mark .. sk.name, function() g:apply_skin(sk.id); g:close_menu(); g.hud:toast('Aspecte: ' .. sk.name, 2) end }
  end
  g:open_list('Aspecte del personatge', items)
end

function Menu:open_seasons()
  local g = self.game
  local cur = g.state.theme or 'auto'
  local auto = require('src.themes').active(g.themes, 'auto')
  local opts = { { 'auto', 'Automàtica (' .. (auto and auto.name or 'cap') .. ')' } }
  for _, t in ipairs(g.themes) do opts[#opts + 1] = { t.id, t.name } end
  opts[#opts + 1] = { 'none', 'Cap' }
  local items = {}
  for _, o in ipairs(opts) do
    items[#items + 1] = { (cur == o[1] and '> ' or '  ') .. o[2], function()
      g:apply_theme(o[1]); g:close_menu()
      g.hud:toast(g.theme and (g.theme.welcome or g.theme.name) or 'Sense temporada', 3)
    end }
  end
  g:open_list('Temporada', items)
end

-- pantalla del mapa: punt de mira, botons de marca i d'amics, missatge i ajuda
function Menu:draw_map_extras()
  local g, v = self.game, self:map_view()
  local lg = love.graphics
  lg.setColor(1, 1, 1, 0.85)   -- punt de mira (on va la marca amb Z)
  lg.rectangle('fill', 159, 113, 2, 5); lg.rectangle('fill', 159, 122, 2, 5)
  lg.rectangle('fill', 153, 119, 5, 2); lg.rectangle('fill', 162, 119, 5, 2)
  for _, name in ipairs({ 'mark', 'friends' }) do
    local r = v.btns[name]
    lg.setColor(0.12, 0.10, 0.14, 0.88); lg.rectangle('fill', r.x, r.y, r.w, r.h)
    lg.setColor(0.96, 0.94, 0.89); lg.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    if name == 'mark' then
      lg.setColor(0.93, 0.33, 0.36); lg.polygon('fill', cx - 4, cy - 2, cx + 4, cy - 2, cx, cy + 7)
      lg.circle('fill', cx, cy - 3, 5); lg.setColor(1, 1, 1); lg.circle('fill', cx, cy - 3, 2)
    else
      lg.setColor(0.93, 0.52, 0.72); lg.polygon('fill', cx - 7, cy, cx, cy - 7, cx + 7, cy)
      lg.rectangle('fill', cx - 5, cy, 10, 7); lg.setColor(0.12, 0.10, 0.14); lg.rectangle('fill', cx - 1, cy + 3, 3, 4)
    end
  end
  local places = require('src.systems.marker').places(g)
  if self.map_place and places[self.map_place] then   -- llista ràpida: on som de la volta per les cases
    local y, pw = 6, 60
    for _, p in ipairs(places) do pw = math.max(pw, g.font:getWidth('> ' .. p.label) + 10) end
    lg.setColor(0.12, 0.10, 0.14, 0.82); lg.rectangle('fill', 4, 4, math.min(pw, 280), 6 + #places * 14)
    for i, p in ipairs(places) do
      lg.setColor(i == self.map_place and { 0.93, 0.52, 0.72 } or { 0.96, 0.94, 0.89 })
      lg.print((i == self.map_place and '> ' or '  ') .. p.label, 8, y); y = y + 14
    end
  end
  if (self.map_msg_t or 0) > 0 and self.map_msg then
    local tw = g.font:getWidth(self.map_msg)
    lg.setColor(0.12, 0.10, 0.14, 0.9); lg.rectangle('fill', 160 - tw / 2 - 6, 196, tw + 12, 18, 4)
    lg.setColor(1, 1, 1); lg.print(self.map_msg, 160 - tw / 2, 198)
  end
  lg.setColor(0.12, 0.10, 0.14, 0.8); lg.rectangle('fill', 0, 222, 320, 18)
  lg.setColor(0.96, 0.94, 0.89)
  lg.print('Z marca · X amics · +/- zoom · Esc', 6, 224)
  lg.setColor(1, 1, 1)
end

-- vista con zoom del mapa M: se crea al entrar y centrada en el jugador
function Menu:map_view()
  local Z = require('src.ui.mapzoom')
  if not self.mapview then
    local g = self.game
    local fx, fy = 0.5, 0.5
    if g.scene and g.scene.id == 'overworld' and g.scene.player then
      local m = g:get_map('overworld')
      local b = g.scene.player.body
      fx, fy = b.x / (m.width * 16), b.y / (m.height * 16)
    end
    self.mapview = Z.new(fx, fy)
    self.mapview.btns = Z.buttons(292, 6)
    -- marca al centre i casa dels amics (src/systems/marker.lua)
    self.mapview.btns.mark = { x = 292, y = 70, w = 22, h = 22 }
    self.mapview.btns.friends = { x = 292, y = 96, w = 22, h = 22 }
  end
  return self.mapview
end

function Menu:map_rect()
  local mm = self.game.sprites.minimap
  return { x = 0, y = 0, w = 320, h = 240 }, 232 * (mm and mm:getWidth() / mm:getHeight() or 1)
end

-- clic o toque: botones + / − y, con zoom, centrar el mapa en el punto tocado
function Menu:pointer(x, y)
  if self.screen ~= 'map' then return end
  local Z = require('src.ui.mapzoom')
  local v = self:map_view()
  local hit = Z.hit(v.btns, x, y)
  if hit == 'mark' then self:map_mark(); return end
  if hit == 'friends' then self:map_next_place(); return end
  if hit then require('src.input').press(hit); return end
  local rect, base = self:map_rect()
  v.fx, v.fy = Z.unpos(v, rect, base, x, y)
  if v.i == 1 then Z.step(v, 2) end   -- tocar el mapa sencer hi apropa la vista
end

-- Z / botó 📍: posa (o treu) la marca al centre de la vista
function Menu:map_mark()
  local g, v = self.game, self:map_view()
  local Marker = require('src.systems.marker')
  local m = g:get_map('overworld')
  local x, y = v.fx * m.width * 16, v.fy * m.height * 16
  local cur = Marker.get(g.state)
  local Z = require('src.ui.mapzoom')
  local _, base = self:map_rect()
  local near = cur and math.abs(cur.x - x) * Z.size(v, base) / (m.width * 16) < 6
                   and math.abs(cur.y - y) * Z.size(v, base) / (m.height * 16) < 6
  if near then
    Marker.clear(g.state); self.map_msg = 'Marca treta'
  else
    local place = self.map_place and Marker.places(g)[self.map_place]
    if place and math.abs(place.x - x) < 24 and math.abs(place.y - y) < 24 then
      Marker.set(g.state, place.x, place.y, place.label)
    else
      local St = require('src.systems.streets')
      Marker.set(g.state, x, y, St.name_at(x, y, 64) or 'Marca')
    end
    self.map_msg = 'Marca: ' .. g.state.marker.label
  end
  self.map_msg_t = 2.5
  g.audio.play('confirm')
end

-- X / botó 🏠: centra la vista a casa i després a la casa de cada amic, i hi posa la marca
function Menu:map_next_place()
  local g, v = self.game, self:map_view()
  local Marker = require('src.systems.marker')
  local places = Marker.places(g)
  if #places == 0 then self.map_msg, self.map_msg_t = 'Encara no hi ha cases d\'amics', 2.5; return end
  self.map_place = (self.map_place or 0) % #places + 1
  local p = places[self.map_place]
  local m = g:get_map('overworld')
  v.fx, v.fy = p.x / (m.width * 16), p.y / (m.height * 16)
  if v.i < 3 then v.i = 3 end
  Marker.set(g.state, p.x, p.y, p.label)
  self.map_msg, self.map_msg_t = 'Marca: ' .. p.label, 2.5
  g.audio.play('talk')
end

-- què es diu en veu alta (src/ui/speech.lua): clau, text, pantalla i títol
local SCREEN_NAME = { title = require('src.place').name(), pause = 'Pausa', map = 'Mapa', notebook = 'Quadern de llocs',
                      controls = 'Controls', character = 'Personatge' }
function Menu:speech()
  local sc = self.screen
  if sc == 'map' or sc == 'notebook' or sc == 'controls' or sc == 'character' then
    return sc, SCREEN_NAME[sc], sc
  end
  local items = self:items()
  local it = items and items[self.sel]
  if not it then return nil end
  local title = sc == 'list' and self.title or SCREEN_NAME[sc]
  local label = tostring(it[1]):gsub('<', ''):gsub('>', '')
  return sc .. '|' .. tostring(self.title) .. '|' .. self.sel .. '|' .. label, label, sc .. '|' .. tostring(self.title), title
end

function Menu:update(dt, pressed, act)
  if self.screen ~= 'map' then self.mapview, self.map_place = nil, nil end
  if self.screen == 'character' then
    if pressed.confirm then self.game.audio.play('confirm'); self:open_actions(); return end
    if pressed.cancel or pressed.pause then
      self.screen = self.back or 'pause'; self.back = nil
      self.game.audio.play('talk')
    end
    return
  end
  if self.screen == 'map' then
    local rect, base = self:map_rect()
    require('src.ui.mapzoom').update(self:map_view(), rect, base, dt, pressed, act)
    self.map_msg_t = math.max(0, (self.map_msg_t or 0) - dt)
    if pressed.confirm then self:map_mark(); return end
    if pressed.attack then self:map_next_place(); return end
  end
  if self.screen == 'notebook' or self.screen == 'map' or self.screen == 'controls' then
    if pressed.confirm or pressed.cancel or pressed.pause or pressed.map then
      if self.back then self.screen = self.back; self.back = nil
      else self.game:close_menu() end
      self.game.audio.play('talk')
    end
    return
  end
  local items = self:items()
  if self.screen == 'list' and (pressed.cancel or pressed.pause) then
    if self.from_title then self.game:to_title() else self.game:close_menu() end
    return
  end
  if pressed.up then self.sel = (self.sel - 2) % #items + 1; self.game.audio.play('talk') end
  if pressed.down then self.sel = self.sel % #items + 1; self.game.audio.play('talk') end
  if items[self.sel].adjust and (pressed.left or pressed.right) then
    items[self.sel].adjust(pressed.left and -.1 or .1);return
  end
  if pressed.confirm then
    self.game.audio.play('confirm')
    items[self.sel][2]()
  elseif (pressed.cancel or pressed.pause) and self.screen == 'pause' then
    self.game:close_menu()
  end
end

local function panel(x, y, w, h)
  love.graphics.setColor(0.12, 0.10, 0.14, 0.94)
  love.graphics.rectangle('fill', x, y, w, h)
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.rectangle('line', x + 1.5, y + 1.5, w - 3, h - 3)
  love.graphics.setColor(1, 1, 1)
end

-- text que no cap a l'amplada: l'opció triada es desplaça (marquesina) i les altres s'escurcen amb «…»
-- (abans sortien del recuadre, sobretot en majúscules)
local function fit_print(font, text, x, y, maxw, moving)
  local tw = font:getWidth(text)
  if tw <= maxw then love.graphics.print(text, x, y); return end
  if moving and not require('src.motion').reduced then
    local off = (love.timer.getTime() * 24) % (tw + 30)
    love.graphics.push('all')
    love.graphics.intersectScissor(x, y - 2, maxw, 20)
    love.graphics.print(text, x - off, y)
    love.graphics.print(text, x - off + tw + 30, y)
    love.graphics.pop()
    return
  end
  local cut = text
  while #cut > 1 and font:getWidth(cut .. '…') > maxw do
    cut = cut:sub(1, -2)
    while #cut > 0 and cut:byte(-1) >= 128 and cut:byte(-1) < 192 do cut = cut:sub(1, -2) end   -- (UTF-8)
    if #cut > 0 and cut:byte(-1) >= 192 then cut = cut:sub(1, -2) end
  end
  love.graphics.print(cut .. '…', x, y)
end
Menu.fit_print = fit_print

function Menu:draw()
  local g = self.game
  if self.screen == 'title' then
    love.graphics.setColor(0.33, 0.78, 0.76); love.graphics.rectangle('fill', 0, 0, 320, 240)
    love.graphics.setColor(0.18, 0.62, 0.69); love.graphics.rectangle('fill', 0, 150, 320, 90)
    love.graphics.setColor(0.95, 0.88, 0.67); love.graphics.rectangle('fill', 0, 140, 320, 14)
    love.graphics.setColor(1, 1, 1)
    if g.sprites.landmarks.landmark_arc_de_bera then
      love.graphics.draw(g.sprites.landmarks.landmark_arc_de_bera, 236, 78)
    end
    love.graphics.setColor(0.12, 0.10, 0.14)
    love.graphics.print('RODA DE BERÀ', 26, 30, 0, 2, 2)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('RODA DE BERÀ', 24, 28, 0, 2, 2)
    love.graphics.print('Una aventura pel poble', 26, 64)
  end
  if self.screen == 'title' or self.screen == 'pause' then
    local items = self:items()
    local x, y, w = self.screen == 'title' and 24 or 90, self.screen == 'title' and 92 or 6, 190
    local rh = 20
    if self.screen == 'pause' then   -- el menú de pausa té moltes opcions: tan ample com calgui (fins a 300)
      w = 200
      for _, it in ipairs(items) do w = math.max(w, g.font:getWidth(it[1]) + 24) end
      w = math.min(300, w); x = math.floor(160 - w / 2); rh = 18
    end
    if self.screen == 'title' then rh = 19; y = 84 end
    panel(x, y, w, #items * rh + 12)
    for i, it in ipairs(items) do
      if i == self.sel then
        love.graphics.setColor(0.84, 0.42, 0.29)
        love.graphics.rectangle('fill', x + 4, y + 4 + (i - 1) * rh, w - 8, rh - 1)
        love.graphics.setColor(1, 1, 1)
      end
      fit_print(g.font, it[1], x + 12, y + 5 + (i - 1) * rh, w - 20, i == self.sel)
    end
    if self.screen == 'title' then
      love.graphics.setColor(0.12, 0.10, 0.14)
      love.graphics.print('Mapa © OpenStreetMap', 160, 222)
      love.graphics.setColor(1, 1, 1)
      if g.warning then
        panel(8, 196, 304, 24)
        love.graphics.print(g.warning, 14, 200)
      end
    end
  elseif self.screen == 'list' then
    -- lista con desplazamiento (viaje en bus, aspecto…): 8 filas visibles
    local items = self:items()
    local rows = math.min(8, #items)
    local top = math.max(1, math.min(self.sel - 3, #items - rows + 1))
    panel(30, 20, 260, rows * 20 + 34)
    love.graphics.setScissor(34, 20, 252, rows * 20 + 34)   -- ningún texto sale del panel
    love.graphics.setColor(0.9, 0.74, 0.42)
    fit_print(g.font, self.title or '', 42, 26, 236, true)
    love.graphics.setColor(1, 1, 1)
    for i = top, top + rows - 1 do
      local y = 46 + (i - top) * 20
      if i == self.sel then
        love.graphics.setColor(0.84, 0.42, 0.29)
        love.graphics.rectangle('fill', 34, y - 2, 252, 19)
        love.graphics.setColor(1, 1, 1)
      end
      local icon=items[i].sprite and g:special_sprite(items[i].sprite)
      if icon then love.graphics.draw(icon,39,y-1) end
      fit_print(g.font, items[i][1], icon and 59 or 44, y, icon and 222 or 236, i == self.sel)
    end
    love.graphics.setScissor()
    if top > 1 then love.graphics.print('^', 274, 44) end
    if top + rows - 1 < #items then love.graphics.print('v', 274, 46 + (rows - 1) * 20) end
  elseif self.screen == 'notebook' then
    panel(16, 12, 288, 216)
    love.graphics.print('Quadern de llocs', 28, 18)
    local st = g.state
    for i, p in ipairs(g.world.pois) do
      local o = g:get_map('overworld'):object('poi', p)
      local label = o and o.props.label or p
      local y = 40 + (i - 1) * 21
      local got = st.visited[p]
      love.graphics.setColor(got and { 0.84, 0.42, 0.29 } or { 0.5, 0.48, 0.45 })
      love.graphics.rectangle(got and 'fill' or 'line', 28, y + 2, 12, 12)
      love.graphics.setColor(1, 1, 1)
      fit_print(g.font, label, 48, y, 250)
    end
    if not st.flags.has_notebook then
      love.graphics.setColor(0.8, 0.78, 0.7)
      love.graphics.print('(La Carme del forn té el quadern)', 28, 210)
      love.graphics.setColor(1, 1, 1)
    end
  elseif self.screen == 'character' then
    self:draw_character()
  elseif self.screen == 'map' then
    g:draw_minimap(self:map_view())
    self:draw_map_extras()
  elseif self.screen == 'controls' then
    panel(16, 20, 288, 200)
    local lines = {
      'Fletxes / WASD: caminar', 'Z / Intro / Espai: parlar, llegir', 'X: atacar (amb espasa)',
      'C / Maj.: protegir-se (escut)', 'V: encanteri · Q / E: canviar-lo', 'B: bici · H: clàxon',
      'M / Tab: mapa · J: diari de missions', 'Esc / P: menú', 'Comandament: creu, A, X, LB, Y', 'Mapa © OpenStreetMap',
    }
    for i, l in ipairs(lines) do fit_print(g.font, l, 28, 26 + (i - 1) * 18, 268) end
  end
end

function Menu:draw_character()
  local g, st = self.game, self.game.state
  local s = Rpg.stats(st, g.items)
  panel(16, 12, 288, 216)
  love.graphics.setColor(0.9, 0.74, 0.42)
  love.graphics.print('Nivell ' .. st.char_level, 28, 18)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(string.format('XP %d / %d', st.xp, st.next_xp), 120, 18)
  love.graphics.setColor(0.25, 0.22, 0.28); love.graphics.rectangle('fill', 28, 37, 264, 4)
  love.graphics.setColor(0.89, 0.72, 0.40); love.graphics.rectangle('fill', 28, 37, 264 * math.min(1, st.xp / st.next_xp), 4)
  love.graphics.setColor(1, 1, 1)
  local lines = {
    string.format('Vida  %d/%d cors', math.ceil(st.hp / 2), st.max_hp / 2),
    string.format('Atac  %d  (+%d equip)', s.total_attack, s.bonus_attack),
    string.format('Defensa  %d  (+%d equip)', s.total_defense, s.bonus_defense),
    string.format('Màgia  %d   MP %d/%d', s.magic, st.mp or 0, st.max_mp or 0),
    string.format('Monedes %d   Gemmes %d', st.coins, st.gems or 0),
  }
  -- entrenament del Gimnàs: força, agilitat i resistència (0..10), a la dreta en una línia pròpia
  local tr = st.train or {}
  for i, l in ipairs(lines) do fit_print(g.font, l, 28, 44 + (i - 1) * 15, 264) end
  love.graphics.setColor(0.70, 0.66, 0.60)
  fit_print(g.font, string.format('Força %d · Agilitat %d · Resist. %d', tr.strength or 0, tr.agility or 0, tr.resistance or 0), 28, 44 + #lines * 15, 264)
  love.graphics.setColor(1, 1, 1)
  for i, slot in ipairs(Rpg.SLOTS) do
    local d = g.items[st.equipment[slot] or '']
    love.graphics.setColor(0.7, 0.66, 0.6)
    local ny = 138 + (i - 1) * 13
    fit_print(g.font, Rpg.SLOT_NAME[slot], 28, ny, 108)
    love.graphics.setColor(1, 1, 1)
    fit_print(g.font, d and d.name or '—', 140, ny, 152)
  end
  love.graphics.setColor(0.8, 0.78, 0.7)
  fit_print(g.font, 'Z: equip, màgia, inventari i vehicles', 28, 206, 264, true)
  love.graphics.setColor(1, 1, 1)
end

return Menu
