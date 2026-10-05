-- Diari de missions (Quest Log): capítols amb les missions (fetes, activa, obertes, bloquejades), la
-- llista d'objectius de la triada i un mapa amb marques de colors (blau orientació, rosa família, verd
-- seguretat). Z activa la missió triada; Esc torna. S'obre des del menú de pausa o amb la tecla J.
local Missions = require('src.systems.missions')
local Town = require('src.systems.town')
local Z = require('src.ui.mapzoom')

local MAP_RECT = { x = 178, y = 20, w = 136, h = 136 }

local J = {}
J.__index = J

function J.new(game, back)
  local self = setmetatable({ game = game, sel = 1, t = 0, back = back }, J)
  self.rows = self:build_rows()
  local fx, fy = 0.5, 0.5
  if game.scene and game.scene.id == 'overworld' and game.scene.player then
    local m = game:get_map('overworld')
    fx, fy = game.scene.player.body.x / (m.width * 16), game.scene.player.body.y / (m.height * 16)
  end
  self.view = Z.new(fx, fy)
  self.btns = Z.buttons(MAP_RECT.x + MAP_RECT.w - 24, MAP_RECT.y + 2)
  -- començar a la missió activa
  for i, r in ipairs(self.rows) do if r.m and r.status == 'active' then self.sel = i end end
  if not self.rows[self.sel] or not self.rows[self.sel].m then self.sel = self:next_sel(self.sel, 1) end
  return self
end

function J:build_rows()
  local g = self.game
  local defs = Town.defs(g)
  local rows = {}
  for _, c in ipairs(defs.chapters) do
    local header = { header = c.title }
    rows[#rows + 1] = header
    local done = 0
    for _, m in ipairs(c.missions) do
      local stt = Missions.status(defs, g.state, m)
      if stt == 'done' then done = done + 1 end
      rows[#rows + 1] = { m = m, status = stt, why = stt == 'locked' and Missions.lock_reason(defs, g.state, m) or nil }
    end
    if #c.missions > 0 then header.header = string.format('%s  %d/%d', c.title, done, #c.missions) end
  end
  -- Perles del Drac (src/systems/perles.lua): una fila per perla amb la seva pista
  local Perles = require('src.systems.perles')
  local list = Perles.journal(g.state)
  if #list > 0 then
    rows[#rows + 1] = { header = string.format('Perles del Drac  %d/%d', Perles.count(g.state), #list) }
    for i, p in ipairs(list) do
      rows[#rows + 1] = { m = { id = 'perla_' .. i, title = 'Perla ' .. i .. (p.done and ' (trobada)' or ''), cat = 'epic',
                                steps = {}, pista = p.pista }, status = p.done and 'done' or 'hint', perla = true }
    end
  end
  return rows
end

function J:next_sel(i, d)
  for _ = 1, #self.rows do
    i = (i - 1 + d) % #self.rows + 1
    if self.rows[i].m then return i end
  end
  return i
end

-- salta a la primera missió del capítol següent (d = 1) o de l'anterior (d = -1)
function J:jump_chapter(d)
  local i = self.sel
  if d < 0 then
    while i > 1 and not self.rows[i].header do i = i - 1 end       -- capçalera del capítol actual
    i = i - 1
    while i > 1 and not self.rows[i].header do i = i - 1 end       -- capçalera de l'anterior
  else
    i = i + 1
    while i <= #self.rows and not self.rows[i].header do i = i + 1 end
  end
  if i < 1 or i > #self.rows or not self.rows[i].header then return end
  if self.rows[i + 1] and self.rows[i + 1].m then self.sel = i + 1 end
end

-- clic o toque: botones de zoom y, con zoom, centrar el mapa
function J:pointer(x, y)
  local hit = Z.hit(self.btns, x, y)
  if hit then require('src.input').press(hit); return end
  if self.view.i > 1 and x >= MAP_RECT.x and x <= MAP_RECT.x + MAP_RECT.w and y >= MAP_RECT.y and y <= MAP_RECT.y + MAP_RECT.h then
    self.view.fx, self.view.fy = Z.unpos(self.view, MAP_RECT, MAP_RECT.w, x, y)
  end
end

function J:update(dt, pressed, act)
  self.t = self.t + dt
  Z.update(self.view, MAP_RECT, MAP_RECT.w, dt, pressed, nil)   -- las flechas eligen misión; el mapa se centra tocándolo
  local g = self.game
  if pressed.up then self.sel = self:next_sel(self.sel, -1); g.audio.play('talk') end
  if pressed.down then self.sel = self:next_sel(self.sel, 1); g.audio.play('talk') end
  if self.view.i == 1 then
    if pressed.left then self:jump_chapter(-1); g.audio.play('talk') end
    if pressed.right then self:jump_chapter(1); g.audio.play('talk') end
  end
  if pressed.confirm then
    local r = self.rows[self.sel]
    if r and r.m and (r.status == 'open' or r.status == 'active') and
       not Missions.can_start(Town.defs(g), g.state, r.m.id) then
      g.audio.play('block')
      if g.scene and g.scene.hud then g.scene.hud:toast('Massa missions començades: acaba\'n alguna', 3, true) end
    elseif r and r.m and (r.status == 'open' or r.status == 'active') then
      local w = g.scene
      Missions.activate(Town.defs(g), g.state, r.m.id, w and Town.hooks(w) or nil)
      g.audio.play('confirm')
      g:close_menu()
      if w then w.hud:toast('Missió activa: ' .. r.m.title, 2.5) end
      return
    elseif r and r.status == 'locked' then
      g.audio.play('block')
    end
  end
  if pressed.cancel or pressed.pause or pressed.journal then
    g.audio.play('talk')
    if self.back then g:open_menu() else g:close_menu() end
  end
end

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- posició del pas actual d'una missió (o del primer pas si encara no s'ha començat)
local function mission_pos(g, m)
  local w = g.scene
  if not w then return nil end
  local q = Missions.state(g.state)
  local s = m.steps[q.step[m.id] or 1]
  if not s then return nil end
  local ok, p = pcall(Town.resolve, w, s.target)
  return ok and p or nil
end

function J:draw()
  local g = self.game
  local font = g.font
  local defs = Town.defs(g)
  col({ 0.12, 0.10, 0.14 }, 0.96); love.graphics.rectangle('fill', 0, 0, 320, 240)
  local done, total = Missions.progress(defs, g.state)
  col({ 0.9, 0.74, 0.42 }); love.graphics.print(string.format('Diari de missions  %d/%d', done, total), 8, 2)
  -- llista
  local view = 12
  local top = math.max(1, math.min(self.sel - 5, #self.rows - view + 1))
  love.graphics.setScissor(4, 20, 168, view * 17 + 2)
  for i = top, math.min(#self.rows, top + view - 1) do
    local r = self.rows[i]
    local y = 21 + (i - top) * 17
    if r.header then
      col({ 0.9, 0.74, 0.42 }); love.graphics.print(r.header, 8, y)
    else
      if i == self.sel then col({ 0.84, 0.42, 0.29 }); love.graphics.rectangle('fill', 4, y, 168, 16) end
      local c = Missions.CAT_COLOR[r.m.cat] or { 1, 1, 1 }
      local box = r.status == 'done' and 'fill' or 'line'
      col(r.status == 'locked' and { 0.4, 0.38, 0.36 } or c)
      love.graphics.rectangle(box, 10.5, y + 4.5, 7, 7)
      if r.status == 'active' and math.floor(self.t * 3) % 2 == 0 then love.graphics.rectangle('fill', 12, y + 6, 4, 4) end
      col(r.status == 'locked' and { 0.5, 0.48, 0.45 } or { 1, 1, 1 })
      love.graphics.print(r.status == 'locked' and (r.why and r.why ~= 'capítol' and (r.m.title .. '  (' .. r.why .. ')')
        or '(bloquejada)') or r.m.title, 22, y)
    end
  end
  love.graphics.setScissor()
  -- mapa amb marques
  local mx, my, mw = 178, 20, 136
  local mm = g.sprites.minimap
  col({ 0.2, 0.18, 0.22 }); love.graphics.rectangle('fill', mx, my, mw, mw)
  Z.clamp(self.view, MAP_RECT, mw)
  local S = Z.size(self.view, mw)
  local ox, oy = Z.pos(self.view, MAP_RECT, mw, 0, 0)
  love.graphics.setScissor(mx, my, mw, mw)
  if mm then love.graphics.setColor(1, 1, 1); love.graphics.draw(mm, ox, oy, 0, S / mm:getWidth(), S / mm:getHeight()) end
  local map = g:get_map('overworld')
  local k = S / (map.width * 16)
  local sel = self.rows[self.sel] and self.rows[self.sel].m
  for _, r in ipairs(self.rows) do
    if r.m and (r.status == 'open' or r.status == 'active') then
      local p = mission_pos(g, r.m)
      if p then
        local c = Missions.CAT_COLOR[r.m.cat]
        local big = r.m == sel
        local blink = big and math.floor(self.t * 4) % 2 == 0
        col({ 0.1, 0.08, 0.12 }); love.graphics.rectangle('fill', ox + p.x * k - (big and 4 or 3), oy + p.y * k - (big and 4 or 3), big and 8 or 6, big and 8 or 6)
        col(blink and { 1, 1, 1 } or c); love.graphics.rectangle('fill', ox + p.x * k - (big and 3 or 2), oy + p.y * k - (big and 3 or 2), big and 6 or 4, big and 6 or 4)
      end
    end
  end
  if g.scene and g.scene.id == 'overworld' then
    local b = g.scene.player.body
    love.graphics.setColor(1, 1, 1); love.graphics.circle('line', ox + b.x * k, oy + b.y * k, 3)
  end
  love.graphics.setScissor()
  Z.draw_buttons(self.view, self.btns, nil)
  -- detalls de la triada
  if sel and sel.pista then
    col(Missions.CAT_COLOR.epic or { 1, 0.6, 0.2 }); love.graphics.print('Pista', mx, 158)
    col({ 1, 1, 1 }); love.graphics.printf(sel.pista, mx, 174, mw, 'left')
  elseif sel then
    local q = Missions.state(g.state)
    local status = self.rows[self.sel].status
    local c = Missions.CAT_COLOR[sel.cat]
    col(c); love.graphics.print(Missions.CAT_NAME[sel.cat], mx, 158)
    local cur = q.step[sel.id] or 1
    for i, s in ipairs(sel.steps) do
      local y = 174 + (i - 1) * 16
      local ok = status == 'done' or i < cur
      col(ok and { 0.55, 0.92, 0.5 } or { 1, 1, 1 })
      love.graphics.setScissor(mx, y, mw, 16)
      local cnt = (i == cur and s.count and s.count > 1) and string.format(' %d/%d', q.count[sel.id] or 0, s.count) or ''
      love.graphics.print((ok and '[x] ' or '[ ] ') .. s.text .. cnt, mx, y)
      love.graphics.setScissor()
    end
  end
  col({ 0.62, 0.58, 0.54 })
  love.graphics.print('Z: activar · </>: capítol · +/-: zoom · Esc', 8, 222)
  love.graphics.setColor(1, 1, 1)
end

return J
