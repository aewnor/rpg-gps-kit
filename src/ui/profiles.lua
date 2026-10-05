-- Perfiles (Family & Friends Editor): pantalla de 5 ranuras, menú de cada perfil, editor de avatar y de
-- personajes (amigos, abuelos…), entrada de nombre (teclado o rejilla de letras con mando) y selector de
-- casas sobre el mapa real (vista general con el minimapa → vista de cerca con las puertas marcadas).
-- Todo se guarda en profiles/slot<N>/user_profile.json (src/profile.lua), nunca en el repositorio.
local Profile = require('src.profile')
local Looks = require('src.paperdoll.looks')
local Chars = require('src.paperdoll.chars')
local Canvas = require('src.paperdoll.canvas')
local Collision = require('src.world.collision')
local Z = require('src.ui.mapzoom')

local CLOSE_ZOOMS = { 0.5, 1, 2 }   -- zoom de la vista de cerca del selector de casa

local UI = {}
UI.__index = UI

local C = { bg = { 0.12, 0.10, 0.14 }, panel = { 0.18, 0.15, 0.20 }, edge = { 0.96, 0.94, 0.89 },
            sel = { 0.60, 0.25, 0.15 }, gold = { 0.9, 0.74, 0.42 }, dim = { 0.62, 0.58, 0.54 }, text = { 1, 1, 1 } }
local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function panel(x, y, w, h)
  col(C.bg, 0.95); love.graphics.rectangle('fill', x, y, w, h)
  col(C.edge); love.graphics.rectangle('line', x + 1.5, y + 1.5, w - 3, h - 3)
  love.graphics.setColor(1, 1, 1)
end

function UI.new(game)
  local self = setmetatable({ game = game, stack = {}, t = 0, rep = 0 }, UI)
  self.slots = Profile.list()
  self:push('slots')
  -- perfils creats en un altre aparell (src/sync.lua): quan arriben, es torna a llegir la llista
  local Sync = require('src.sync')
  Sync.on_change = function()   -- qualsevol baixada amb canvis (també la del canvi de jugador del hub)
    if game.menu == self then self.slots = Profile.list() end
  end
  Sync.pull(function(changed)
    if changed and game.menu == self then self.slots = Profile.list() end
  end, game.scene and game.slot or nil)
  return self
end

-- ---------------------------------------------------------------- pila de pantallas
function UI:push(kind, data)
  data = data or {}
  data.kind, data.sel = kind, data.sel or 1
  self.stack[#self.stack + 1] = data
  if kind == 'name' then love.keyboard.setTextInput(true) end
  return data
end

function UI:pop()
  local top = table.remove(self.stack)
  if top and top.kind == 'name' then love.keyboard.setTextInput(false) end
  if #self.stack == 0 then self.game:to_title() end
  return top
end

function UI:top() return self.stack[#self.stack] end

local function sfx(self, n) self.game.audio.play(n) end

-- ---------------------------------------------------------------- filas de cada pantalla
-- cada fila: { label, action = fn | nil, left = fn, right = fn, value = string }
function UI:rows(s)
  local g = self.game
  if s.kind == 'slots' then
    local rows = {}
    for i, e in ipairs(self.slots) do
      local label
      if e.error then
        label = tostring(i)..'. Perfil a recuperar'
      elseif e.exists then
        label = string.format('%d. %s', i, e.name)
        if e.has_save then label = label .. string.format('  Nv%d  %dh%02d', e.level, math.floor(e.play_time / 3600),
                                                              math.floor(e.play_time / 60) % 60) end
      else label = string.format('%d. (perfil buit: crear-ne un)', i) end
      rows[#rows + 1] = { label, action = function() self:open_slot(i) end }
    end
    rows[#rows + 1] = { 'Tornar', action = function() self:pop() end }
    return rows
  elseif s.kind == 'slot_menu' then
    local e = self.slots[s.slot]
    local p = s.profile
    local rows = {}
    rows[#rows + 1] = { e.has_save and 'Continuar la partida' or 'Començar a jugar', action = function()
      self:play(s.slot, p, e.has_save and 'continue' or 'new') end }
    if e.has_save then
      rows[#rows + 1] = { 'Partida nova (esborra la desada)', action = function()
        self:confirm('Segur? Es perdrà la partida desada d\'aquest perfil.', function() self:play(s.slot, p, 'new') end)
      end }
    end
    rows[#rows + 1] = { 'Avatar: ' .. p.name, action = function() self:edit_avatar(s) end }
    rows[#rows + 1] = { 'Casa: ' .. (p.home and (p.home.street or 'triada') or 'sense triar'), action = function()
      self:pick_place(p.home, 'On és casa teva?', function(h) p.home = h; return self:save(s) end)
    end }
    rows[#rows + 1] = { string.format('Amics i família (%d/%d)', #p.friends, Profile.MAX_FRIENDS), action = function()
      self:push('friends', { slot = s.slot, profile = p })
    end }
    rows[#rows + 1] = { 'Pares: ' .. Profile.parents_of(p).pare .. ' i ' .. Profile.parents_of(p).mare, action = function()
      p.parents = Profile.parents_of(p)
      self:push('parents', { owner = p, slot_state = s, who = p.name })
    end }
    rows[#rows + 1] = { 'Duplicar el perfil', action = function() self:duplicate(s) end }
    rows[#rows + 1] = { 'Esborrar el perfil', action = function()
      self:confirm('Esborrar el perfil ' .. p.name .. ' i la seva partida?', function()
        Profile.delete(s.slot); self.slots = Profile.list(); self:pop()
      end)
    end }
    rows[#rows + 1] = { 'Tornar', action = function() self:pop() end }
    return rows
  elseif s.kind == 'friends' then
    local p = s.profile
    local rows = {}
    for i, f in ipairs(p.friends) do
      local where = f.home and (f.home.street or 'casa triada') or 'sense casa'
      rows[#rows + 1] = { string.format('%s (%s) · %s', f.name, Profile.ROLE_NAMES[f.role], where), action = function()
        self:edit_friend(s, i)
      end }
    end
    if #p.friends < Profile.MAX_FRIENDS then
      rows[#rows + 1] = { '+ Afegir amic o familiar', action = function()
        local roles = {}
        for _, r in ipairs(Profile.ROLES) do
          roles[#roles + 1] = { Profile.ROLE_NAMES[r], action = function()
            self:pop()
            p.friends[#p.friends + 1] = Profile.new_friend(p, r)
            self:edit_friend(s, #p.friends, true)
          end }
        end
        roles[#roles + 1] = { 'Tornar', action = function() self:pop() end }
        self:push('choice', { title = 'Qui és?', items = roles })
      end }
    end
    rows[#rows + 1] = { 'Tornar', action = function() self:pop() end }
    return rows
  elseif s.kind == 'parents' then
    local o = s.owner
    local function ask(key, title)
      self:ask_name(title, o.parents[key], function(n)
        o.parents[key] = n
        if s.slot_state then self:save(s.slot_state) end
      end)
    end
    return {
      { 'Pare: ' .. o.parents.pare, action = function() ask('pare', 'Nom del pare') end },
      { 'Mare: ' .. o.parents.mare, action = function() ask('mare', 'Nom de la mare') end },
      { 'Tornar', action = function() self:pop() end },
    }
  elseif s.kind == 'choice' then
    return s.items
  elseif s.kind == 'editor' then
    return self:editor_rows(s)
  end
  return {}
end

-- ---------------------------------------------------------------- acciones
function UI:open_slot(i)
  local e = self.slots[i]
  if e.error then self.save_error=e.error; return end
  if e.exists then
    local p,warning=Profile.read(i)
    if not p then self.save_error=warning or 'No es pot llegir el perfil';return end
    self.notice=warning
    self:push('slot_menu', { slot = i, profile = p })
  else
    -- perfil nuevo: nombre → avatar → casa
    self:ask_name('Com et dius?', '', function(name)
      local p = Profile.new(name, 'nena')
      local ok,err=Profile.write(i,p)
      if not ok then self.save_error=err; return false end
      self.save_error=nil
      self.slots = Profile.list()
      local s = self:push('slot_menu', { slot = i, profile = p })
      self:edit_avatar(s, function()
        self:pick_place(nil, 'On és casa teva? (Esc: ara no)', function(h) p.home = h; return self:save(s) end)
      end)
    end)
  end
end

function UI:save(s)
  local ok,err=Profile.write(s.slot,s.profile)
  self.save_error=not ok and err or nil
  if ok then self.slots = Profile.list() end
  return ok
end

function UI:play(slot, p, mode)
  love.keyboard.setTextInput(false)
  Looks.clear_cache()
  self.game:start_profile(slot, p, mode)
end

-- copia el perfil a la primera ranura libre (con o sin la partida)
function UI:duplicate(s)
  if not Profile.free_slot() then
    self:flash('No hi ha cap ranura lliure: esborra\'n un perfil')
    sfx(self, 'block')
    return
  end
  local function go(with_save)
    local dst, err = Profile.duplicate(s.slot, with_save)
    self.slots = Profile.list()
    if dst then
      self:flash(string.format('Perfil duplicat a la ranura %d', dst))
      sfx(self, 'stamp')
    else
      self:flash(err or 'No s\'ha pogut duplicar')
      sfx(self, 'block')
    end
  end
  if self.slots[s.slot].has_save then
    self:push('choice', { title = 'Vols copiar també la partida desada?', items = {
      { 'Sí, copiar la partida', action = function() self:pop(); go(true) end },
      { 'No, només el perfil', action = function() self:pop(); go(false) end },
      { 'Tornar', action = function() self:pop() end },
    } })
  else
    go(false)
  end
end

function UI:flash(text) self.flash_text, self.flash_t = text, 3.5 end

function UI:confirm(text, yes)
  self:push('choice', { title = text, items = {
    { 'Sí', action = function() self:pop(); yes() end },
    { 'No', action = function() self:pop() end },
  } })
end

function UI:ask_name(title, value, done)
  self:push('name', { title = title, value = value or '', done = done, gx = 1, gy = 1, upper = true })
end

-- ---------------------------------------------------------------- editor de aspecto (avatar y personajes)
local function cycle(list, v, d)
  for i, x in ipairs(list) do if x == v then return list[(i - 1 + d) % #list + 1] end end
  return list[1]
end
local function step(v, n, d) return (v - 1 + d) % n + 1 end

function UI:edit_avatar(s, after)
  local p = s.profile
  self:push('editor', { mode = 'player', target = p, look = Looks.sanitize(p.avatar), slot_state = s, after = after })
end

function UI:edit_friend(s, i, fresh)
  local f = s.profile.friends[i]
  self:push('editor', { mode = 'friend', target = f, index = i, look = Looks.sanitize(f.look), slot_state = s,
                        fresh = fresh })
end

function UI:editor_rows(e)
  local l = e.look
  local rows = {}
  local function opt(label, value, left, right) rows[#rows + 1] = { label, value = value, left = left, right = right } end
  local function changed() e.preview = nil end
  if e.mode == 'friend' then
    local f = e.target
    rows[#rows + 1] = { 'Nom', value = f.name, action = function()
      self:ask_name('Nom del personatge', f.name, function(n) f.name = n end)
    end }
    opt('Relació', Profile.ROLE_NAMES[f.role], function() f.role = cycle(Profile.ROLES, f.role, -1) end,
      function() f.role = cycle(Profile.ROLES, f.role, 1) end)
    opt('Edat', Looks.AGE_NAMES[l.age], function() Looks.preset_age(l, cycle(Looks.AGES, l.age, -1)); changed() end,
      function() Looks.preset_age(l, cycle(Looks.AGES, l.age, 1)); changed() end)
  else
    rows[#rows + 1] = { 'Nom', value = e.target.name, action = function()
      self:ask_name('Com et dius?', e.target.name, function(n) e.target.name = n end)
    end }
    opt('Cos', Looks.BODY_NAMES[l.body], function()
      l.body = cycle(Looks.BODIES, l.body, -1); changed()
    end, function() l.body = cycle(Looks.BODIES, l.body, 1); changed() end)
  end
  local function idx_row(label, key, list, names)
    opt(label, names and names(l[key]) or tostring(l[key]), function() l[key] = step(l[key], #list, -1); changed() end,
      function() l[key] = step(l[key], #list, 1); changed() end)
  end
  local function list_row(label, key, list, names)
    opt(label, names[l[key]], function() l[key] = cycle(list, l[key], -1); changed() end,
      function() l[key] = cycle(list, l[key], 1); changed() end)
  end
  idx_row('Pell', 'skin', Looks.SKINS, function(v) return 'To ' .. v end)
  list_row('Cabell', 'hair', Looks.HAIRS, Looks.HAIR_NAMES)
  idx_row('Color del cabell', 'hair_color', Looks.HAIR_COLORS, function(v) return Looks.HAIR_COLORS[v][2] end)
  idx_row('Ulls', 'eyes', Looks.EYES, function(v) return Looks.EYES[v][2] end)
  list_row('Roba', 'outfit', Looks.OUTFITS, Looks.OUTFIT_NAMES)
  idx_row('Color de dalt', 'top', Looks.CLOTH, function(v) return Looks.CLOTH[v][2] end)
  idx_row('Color de baix', 'bottom', Looks.CLOTH, function(v) return Looks.CLOTH[v][2] end)
  idx_row('Sabates', 'shoes', Looks.CLOTH, function(v) return Looks.CLOTH[v][2] end)
  list_row('Barret', 'hat', Looks.HATS, Looks.HAT_NAMES)
  for _, a in ipairs(Looks.ACCESSORIES) do
    if e.mode == 'friend' or (a ~= 'cane' and a ~= 'apron') then
      local tog = function() l.acc[a] = not l.acc[a] or nil; changed() end
      opt(Looks.ACC_NAMES[a], l.acc[a] and 'Sí' or 'No', tog, tog)
    end
  end
  if e.mode == 'friend' then
    local f = e.target
    rows[#rows + 1] = { 'Casa', value = f.home and (f.home.street or 'triada') or 'triar al mapa', action = function()
      self:pick_place(f.home, 'On viu ' .. f.name .. '?', function(h) f.home = h end)
    end }
    opt('Interior', Profile.INTERIOR_NAMES[f.interior.kind], function() f.interior.kind = cycle(Profile.INTERIORS, f.interior.kind, -1) end,
      function() f.interior.kind = cycle(Profile.INTERIORS, f.interior.kind, 1) end)
    opt('Terra', Profile.FLOOR_NAMES[f.interior.floor], function() f.interior.floor = cycle(Profile.FLOORS, f.interior.floor, -1) end,
      function() f.interior.floor = cycle(Profile.FLOORS, f.interior.floor, 1) end)
    if f.role ~= 'avia' and f.role ~= 'avi' then
      local par = Profile.parents_of(nil, f)
      rows[#rows + 1] = { 'Pares', value = par.pare .. ' i ' .. par.mare, action = function()
        f.parents = Profile.parents_of(nil, f)
        self:push('parents', { owner = f, who = f.name })
      end }
    end
    local tc = function() f.interior.cat = not f.interior.cat end
    opt('Té un gat', f.interior.cat and 'Sí' or 'No', tc, tc)
    local td = function() f.interior.dog = not f.interior.dog end
    opt('Té un gos', f.interior.dog and 'Sí' or 'No', td, td)
  end
  rows[#rows + 1] = { 'Desar', action = function() self:editor_done(e) end }
  if e.mode == 'friend' then
    rows[#rows + 1] = { 'Esborrar aquest personatge', action = function()
      self:confirm('Esborrar ' .. e.target.name .. '?', function()
        local fr = e.slot_state.profile.friends
        local removed=table.remove(fr,e.index)
        if not self:save(e.slot_state) then table.insert(fr,e.index,removed); return end
        self:pop()
      end)
    end }
  end
  rows[#rows + 1] = { 'Cancel·lar', action = function() self:editor_cancel(e) end }
  return rows
end

function UI:editor_done(e)
  if e.mode == 'player' then e.target.avatar = e.look else e.target.look = e.look end
  if not self:save(e.slot_state) then return end
  self:pop()
  sfx(self, 'stamp')
  if e.after then e.after() end
end

function UI:editor_cancel(e)
  if e.mode == 'friend' and e.fresh then table.remove(e.slot_state.profile.friends, e.index) end
  self:pop()
  if e.after then e.after() end
end

-- vista previa: la hoja se rehace solo al cambiar el aspecto (no pasa por la caché de Looks)
function UI:preview(e)
  if not e.preview then
    local img = Canvas.to_image(Chars.sheet(Looks.spec(e.look)))
    local q = {}
    for r = 0, 3 do for c = 0, 5 do q[r * 6 + c + 1] = love.graphics.newQuad(c * 16, r * 24, 16, 24, 96, 96) end end
    e.preview = { img = img, q = q }
  end
  return e.preview
end

-- ---------------------------------------------------------------- selector de lugar en el mapa
-- cur: lugar actual o nil; done(place) con place = { tile_x, tile_y (casilla de delante), door_x, door_y, street }
function UI:pick_place(cur, title, done)
  local g = self.game
  local map = g:get_map('overworld')
  local cx, cy
  if cur then cx, cy = cur.tile_x, cur.tile_y
  else
    local sp = map:object('spawn', g.world.start_spawn)
    cx, cy = sp and math.floor(sp.x / 16) or 800, sp and math.floor(sp.y / 16) or 800
  end
  self:push('picker', { title = title, done = done, map = map, cx = cx, cy = cy, zoom = cur ~= nil, msg = nil,
                        view = Z.new(), cz = 2, btns = Z.buttons(292, 22) })
end

-- puertas de fachada cercanas (como World:find_house_door): casilla de puerta con suelo transitable delante
function UI.find_door(map, light_kind, tx, ty, radius)
  local best, bd
  for y = ty - radius, ty + radius do
    for x = tx - radius, tx + radius do
      if map:in_bounds(x, y + 1) and light_kind[map:tile_at('structures', x, y)] == 'door' and
          Collision.walk_at(map:cell(x, y + 1), 0) then
        local d = (x - tx) ^ 2 + (y - ty) ^ 2
        if not bd or d < bd then best, bd = { x, y }, d end
      end
    end
  end
  return best
end

-- geometría de la vista general (minimapa a pantalla completa con zoom)
function UI:picker_geom(s)
  local mm = self.game.sprites.minimap
  return { x = 0, y = 0, w = 320, h = 240 }, 232 * (mm and mm:getWidth() / mm:getHeight() or 1)
end

-- clic o toque: botones de zoom o mover el cursor al punto tocado
function UI:pointer(x, y)
  local s = self:top()
  if not (s and s.kind == 'picker') then return end
  local hit = Z.hit(s.btns, x, y)
  if hit then require('src.input').press(hit); return end
  if y < 18 or y > 222 then return end
  local map = s.map
  if s.zoom then
    local z = CLOSE_ZOOMS[s.cz]
    s.cx = math.floor((s.cx * 16 + 8 + (x - 160) / z) / 16)
    s.cy = math.floor((s.cy * 16 + 8 + (y - 120) / z) / 16)
  else
    local rect, base = self:picker_geom(s)
    Z.clamp(s.view, rect, base)
    local u, v = Z.unpos(s.view, rect, base, x, y)
    s.cx, s.cy = u * map.width, v * map.height
  end
  s.cx = math.max(4, math.min(map.width - 5, s.cx))
  s.cy = math.max(4, math.min(map.height - 5, s.cy))
  if s.zoom then s.cx, s.cy = math.floor(s.cx + 0.5), math.floor(s.cy + 0.5) end
end

function UI:picker_confirm(s)
  local g = self.game
  if not s.zoom then s.zoom = true; return end
  local door = UI.find_door(s.map, g.renderer.light_kind, s.cx, s.cy, 3)
  if not door then s.msg = 'Aquí no hi ha cap porta: acosta\'t a una casa'; sfx(self, 'block'); return end
  local place = { scene = 'overworld', tile_x = door[1], tile_y = door[2] + 1, door_x = door[1], door_y = door[2] }
  -- ha de ser accessible a peu des del centre del poble
  local Home = require('src.home')
  local ok, why = Home.resolve({ configured = true, scene = 'overworld', tile_x = place.tile_x, tile_y = place.tile_y },
    function(sc) return g:get_map(sc) end, g.world.start_spawn)
  if not ok then s.msg = 'No s\'hi pot arribar a peu: tria una altra porta'; sfx(self, 'block'); return end
  local Streets = require('src.systems.streets')
  place.street = Streets.name_at((door[1] + 0.5) * 16, (door[2] + 1.5) * 16, 64)
  if s.done(place)==false then return end
  self:pop()
  sfx(self, 'stamp')
end

-- ---------------------------------------------------------------- entrada
function UI:textinput(t)
  local s = self:top()
  if s and s.kind == 'name' then
    s.value = Profile.limit_name(s.value .. t)
    return true
  end
end

-- teclas en la pantalla de nombre: la tecla no llega a Input (así «z» o «x» escriben y no aceptan)
function UI:keypressed(key)
  local s = self:top()
  if not (s and s.kind == 'name') then return false end
  if key == 'backspace' then self:name_backspace(s)
  elseif key == 'return' or key == 'kpenter' then self:name_done(s)
  elseif key == 'escape' then self:pop()
  elseif key == 'f1' then return false -- confirmación táctil, independiente del texto
  elseif key == 'up' or key == 'down' or key == 'left' or key == 'right' then return false end
  return true
end

function UI:name_backspace(s)
  local n = #s.value
  while n > 0 and s.value:byte(n) >= 128 and s.value:byte(n) < 192 do n = n - 1 end
  s.value = s.value:sub(1, math.max(0, n - 1))
end

function UI:name_done(s)
  local v = Profile.clean_name(s.value, nil)
  if not v then sfx(self, 'block'); return end
  local index=#self.stack
  if s.done(v)==false then return end
  table.remove(self.stack,index)
  love.keyboard.setTextInput(false)
  if #self.stack==0 then self.game:to_title() end
end

local GRID = { { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J' }, { 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T' },
               { 'U', 'V', 'W', 'X', 'Y', 'Z', 'Ç', 'Ñ', '·', '-' }, { 'À', 'È', 'É', 'Í', 'Ï', 'Ò', 'Ó', 'Ú', 'Ü', '\'' },
               { 'Aa', 'Espai', '<-', 'Fet' } }
local LOWER = { ['À'] = 'à', ['È'] = 'è', ['É'] = 'é', ['Í'] = 'í', ['Ï'] = 'ï', ['Ò'] = 'ò', ['Ó'] = 'ó', ['Ú'] = 'ú',
                ['Ü'] = 'ü', ['Ç'] = 'ç', ['Ñ'] = 'ñ' }

-- veu (src/ui/speech.lua): la fila seleccionada o, al teclat de noms, la lletra assenyalada
local SCREEN_TITLE = { slots = 'Tria un perfil', editor = 'Personatge', choice = nil }
function UI:speech()
  local s = self:top()
  if not s then return nil end
  local screen = tostring(s.kind) .. '|' .. tostring(s.title) .. '|' .. #self.stack
  if s.kind == 'name' then
    local k = GRID[s.gy] and GRID[s.gy][s.gx]
    if not k then return nil end
    local say = k == '<-' and 'Esborrar' or (k == 'Aa' and 'Majúscules o minúscules' or k)
    return screen .. '|' .. s.gy .. ',' .. s.gx, say, screen, s.title
  end
  if s.kind == 'picker' then return screen, s.title or 'Tria un lloc al mapa', screen end
  local rows = self:rows(s)
  local r = rows[s.sel or 1]
  if not r then return nil end
  local label = tostring(r[1] or r.label or '') .. (r.value and (': ' .. tostring(r.value)) or '')
  return screen .. '|' .. tostring(s.sel) .. '|' .. label, label, screen, s.title or SCREEN_TITLE[s.kind]
end

function UI:update(dt, pressed, act)
  self.t = self.t + dt
  if self.flash_t then
    self.flash_t = self.flash_t - dt
    if self.flash_t <= 0 then self.flash_t, self.flash_text = nil, nil end
  end
  local s = self:top()
  if not s then return end
  act = act or {}
  if s.kind == 'picker' then self:update_picker(s, dt, pressed, act); return end
  if s.kind == 'name' then
    local row = GRID[s.gy]
    if pressed.up then s.gy = (s.gy - 2) % #GRID + 1; s.gx = math.min(s.gx, #GRID[s.gy]) end
    if pressed.down then s.gy = s.gy % #GRID + 1; s.gx = math.min(s.gx, #GRID[s.gy]) end
    row = GRID[s.gy]
    if pressed.left then s.gx = (s.gx - 2) % #row + 1 end
    if pressed.right then s.gx = s.gx % #row + 1 end
    if pressed.cancel then self:pop(); return end
    if pressed.confirm then
      local k = row[s.gx]
      if k == 'Fet' then self:name_done(s)
      elseif k == '<-' then self:name_backspace(s)
      elseif k == 'Aa' then s.upper = not s.upper
      elseif k == 'Espai' then s.value = Profile.limit_name(s.value .. ' ')
      else
        local ch = s.upper and k or (LOWER[k] or k:lower())
        s.value = Profile.limit_name(s.value .. ch)
      end
      sfx(self, 'talk')
    end
    return
  end
  local rows = self:rows(s)
  if #rows == 0 then return end
  s.sel = math.min(s.sel, #rows)
  if pressed.up then s.sel = (s.sel - 2) % #rows + 1; sfx(self, 'talk') end
  if pressed.down then s.sel = s.sel % #rows + 1; sfx(self, 'talk') end
  local r = rows[s.sel]
  if (pressed.left and r.left) then r.left(); sfx(self, 'talk') end
  if (pressed.right and r.right) then r.right(); sfx(self, 'talk') end
  if pressed.confirm then
    if r.action then sfx(self, 'confirm'); r.action()
    elseif r.right then r.right(); sfx(self, 'talk') end
  elseif pressed.cancel or pressed.pause then
    if s.kind == 'editor' then self:editor_cancel(s) else self:pop() end
    sfx(self, 'talk')
  end
end

function UI:update_picker(s, dt, pressed, act)
  local map = s.map
  if pressed.cancel or pressed.pause then
    if s.zoom then s.zoom = false else self:pop() end
    s.msg = nil
    return
  end
  if pressed.zoom_in or pressed.zoom_out then
    local d = pressed.zoom_in and 1 or -1
    if s.zoom then s.cz = math.max(1, math.min(#CLOSE_ZOOMS, s.cz + d))
    else Z.step(s.view, d) end
  end
  if pressed.confirm then self:picker_confirm(s); return end
  -- moure el cursor: a la vista general ràpid (en casselles de 5 m), de prop casella a casella amb repetició
  local h = (act.right and 1 or 0) - (act.left and 1 or 0)
  local v = (act.down and 1 or 0) - (act.up and 1 or 0)
  if s.zoom then
    local tap = (pressed.right and 1 or 0) - (pressed.left and 1 or 0)
    local tapv = (pressed.down and 1 or 0) - (pressed.up and 1 or 0)
    if tap ~= 0 or tapv ~= 0 then s.cx, s.cy, self.rep = s.cx + tap, s.cy + tapv, -0.25
    elseif h ~= 0 or v ~= 0 then
      self.rep = self.rep + dt
      if self.rep > 0.06 then self.rep = 0; s.cx, s.cy = s.cx + h, s.cy + v end
    end
    s.msg = nil
  else
    s.cx, s.cy = s.cx + h * 90 * dt, s.cy + v * 90 * dt
  end
  s.cx = math.max(4, math.min(map.width - 5, s.cx))
  s.cy = math.max(4, math.min(map.height - 5, s.cy))
  if s.zoom then
    s.cx, s.cy = math.floor(s.cx + 0.5), math.floor(s.cy + 0.5)
    map.chunks:update(s.cx * 16, s.cy * 16, 0, 0, 2)
  end
  s.view.fx, s.view.fy = s.cx / map.width, s.cy / map.height
end

-- ---------------------------------------------------------------- dibujo
function UI:draw_content()
  local s = self:top()
  if not s then return end
  col(C.bg); love.graphics.rectangle('fill', 0, 0, 320, 240)
  if s.kind == 'picker' then self:draw_picker(s); return end
  if s.kind == 'name' then self:draw_name(s); return end
  if s.kind == 'editor' then self:draw_editor(s); return end
  local title = ({ slots = 'Tria un perfil (fins a 5)', slot_menu = s.profile and s.profile.name or '',
                   friends = 'Amics i família', choice = s.title,
                   parents = 'Pares de ' .. tostring(s.who or '') })[s.kind] or ''
  local rows = self:rows(s)
  panel(12, 8, 296, 224)
  col(C.gold)
  local _, lines = self.game.font:getWrap(title, 272)
  for i, l in ipairs(lines) do love.graphics.print(l, 24, 12 + (i - 1) * 16) end
  local y0 = 16 + #lines * 16
  local view = math.floor((220 - y0) / 20)
  local top = math.max(1, math.min(s.sel - math.floor(view / 2), #rows - view + 1))
  love.graphics.setScissor(16, y0, 288, 220 - y0)
  for i = top, math.min(#rows, top + view - 1) do
    local y = y0 + (i - top) * 20
    if i == s.sel then col(C.sel); love.graphics.rectangle('fill', 18, y - 1, 284, 19) end
    col(C.text); love.graphics.print(rows[i][1], 26, y)
  end
  love.graphics.setScissor()
  -- miniatura del avatar a la lista de ranures i al menú del perfil
  if s.kind == 'slot_menu' then
    self:draw_look(s.profile.avatar, 262, 16, 2)
  end
  love.graphics.setColor(1, 1, 1)
end

function UI:draw_look(look, x, y, scale)
  local b = Looks.build(look)
  local dir = math.floor(self.t / 1.6) % 4
  local col_ = math.floor(self.t * 6) % 4
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(b.sheet, b.quad(({ 0, 3, 1, 2 })[dir + 1], col_), x, y, 0, scale, scale)
end

function UI:draw_editor(e)
  local rows = self:rows(e)
  local font = self.game.font
  panel(4, 4, 312, 232)
  col(C.gold); love.graphics.print(e.mode == 'player' and 'El teu avatar' or 'Personatge', 14, 8)
  -- vista prèvia gran que camina en les quatre direccions
  col({ 0.30, 0.45, 0.28 }); love.graphics.rectangle('fill', 14, 30, 84, 108)
  col({ 0.36, 0.52, 0.32 }); love.graphics.rectangle('fill', 14, 120, 84, 18)
  local pv = self:preview(e)
  local dir = math.floor(self.t / 1.6) % 4
  love.graphics.setColor(0.1, 0.08, 0.12, 0.3); love.graphics.ellipse('fill', 56, 132, 16, 4)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(pv.img, pv.q[({ 0, 3, 1, 2 })[dir + 1] * 6 + math.floor(self.t * 6) % 4 + 1], 32, 66, 0, 3, 3)
  col(C.dim)
  love.graphics.print('< >: canviar', 14, 146)
  love.graphics.print('Z: triar', 14, 162)
  -- files
  local view = 11
  local top = math.max(1, math.min(e.sel - 5, #rows - view + 1))
  love.graphics.setScissor(104, 26, 206, view * 19 + 4)
  for i = top, math.min(#rows, top + view - 1) do
    local r = rows[i]
    local y = 28 + (i - top) * 19
    if i == e.sel then col(C.sel); love.graphics.rectangle('fill', 104, y - 1, 206, 18) end
    local vw = 0
    if r.value then
      local v = (r.left and '< ' or '') .. r.value .. (r.right and ' >' or '')
      vw = font:getWidth(v)
      col(i == e.sel and C.text or C.gold)
      love.graphics.print(v, 306 - vw, y)
    end
    -- l'etiqueta no trepitja el valor: es retalla
    love.graphics.setScissor(104, 26, math.max(10, 200 - vw - 6), view * 19 + 4)
    col(C.text); love.graphics.print(r[1], 108, y)
    love.graphics.setScissor(104, 26, 206, view * 19 + 4)
  end
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1)
end

function UI:draw_name(s)
  local font = self.game.font
  panel(12, 12, 296, 216)
  col(C.gold); love.graphics.print(s.title, 24, 18)
  col({ 0.25, 0.22, 0.28 }); love.graphics.rectangle('fill', 24, 40, 272, 22)
  col(C.text)
  local caret = math.floor(self.t * 2) % 2 == 0 and '_' or ''
  love.graphics.print(s.value .. caret, 30, 42)
  for gy, row in ipairs(GRID) do
    for gx, k in ipairs(row) do
      local wide = #row < 10
      local w = wide and 64 or 25
      local x = 24 + (gx - 1) * (wide and 68 or 27)
      local y = 72 + (gy - 1) * 26
      local selected = gx == s.gx and gy == s.gy
      col(selected and C.sel or { 0.25, 0.22, 0.28 }); love.graphics.rectangle('fill', x, y, w, 22)
      local label = (not s.upper and not wide) and (LOWER[k] or k:lower()) or k
      col(C.text); love.graphics.print(label, math.floor(x + (w - font:getWidth(label)) / 2), y + 2)
    end
  end
  col(C.dim); love.graphics.print('Tria lletres amb A. Fet: acabar' , 24, 206)
  love.graphics.setColor(1, 1, 1)
end

function UI:draw_picker(s)
  local g = self.game
  local map = s.map
  local font = g.font
  local marks = self:place_marks()
  if s.zoom then
    local r = g.renderer
    local cz = CLOSE_ZOOMS[s.cz]
    local vw, vh = 320 / cz, 240 / cz
    local ox, oy = s.cx * 16 + 8 - vw / 2, s.cy * 16 + 8 - vh / 2
    local chunks = r:visible(map, { x = ox, y = oy, w = vw, h = vh })
    love.graphics.setColor(1, 1, 1)
    love.graphics.push(); love.graphics.scale(cz, cz); love.graphics.translate(-ox, -oy)
    r:draw_layer(chunks, 'ground'); r:draw_vectors(chunks, 0)
    r:draw_layer(chunks, 'ground_detail'); r:draw_layer(chunks, 'structures'); r:draw_layer(chunks, 'cover_low')
    -- portes on es pot triar casa
    local lk = r.light_kind
    local rx, ry = math.ceil(vw / 32) + 1, math.ceil(vh / 32) + 1
    for y = s.cy - ry, s.cy + ry do
      for x = s.cx - rx, s.cx + rx do
        if map:in_bounds(x, y + 1) and lk[map:tile_at('structures', x, y)] == 'door' then
          local blink = math.floor(self.t * 3) % 2 == 0
          love.graphics.setColor(1, 0.85, 0.3, blink and 0.9 or 0.5)
          love.graphics.rectangle('line', x * 16 + 0.5, y * 16 + 0.5, 15, 15)
        end
      end
    end
    for _, m in ipairs(marks) do
      love.graphics.setColor(m.color[1], m.color[2], m.color[3], 1)
      love.graphics.rectangle('fill', m.x * 16 + 4, m.y * 16 - 10, 8, 8)
      love.graphics.setColor(1, 1, 1)
      love.graphics.print(m.label, m.x * 16 + 14, m.y * 16 - 14)
    end
    -- cursor
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle('line', s.cx * 16 - 1, s.cy * 16 - 1, 18, 18)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
  else
    local mm = g.sprites.minimap
    local rect, base = self:picker_geom(s)
    s.view.fx, s.view.fy = s.cx / map.width, s.cy / map.height
    Z.clamp(s.view, rect, base)
    local S = Z.size(s.view, base)
    local x0, y0 = Z.pos(s.view, rect, base, 0, 0)
    if mm then love.graphics.setColor(1, 1, 1); love.graphics.draw(mm, x0, y0, 0, S / mm:getWidth(), S / mm:getHeight()) end
    local k = S / map.width
    for _, m in ipairs(marks) do
      love.graphics.setColor(m.color[1], m.color[2], m.color[3], 1)
      love.graphics.rectangle('fill', x0 + m.x * k - 2, y0 + m.y * k - 2, 5, 5)
    end
    local blink = math.floor(self.t * 4) % 2 == 0
    local cxp, cyp = x0 + s.cx * k, y0 + s.cy * k
    love.graphics.setColor(1, 1, 1, blink and 1 or 0.6)
    love.graphics.circle('line', cxp, cyp, 6)
    love.graphics.line(cxp - 9, cyp, cxp + 9, cyp)
    love.graphics.line(cxp, cyp - 9, cxp, cyp + 9)
  end
  -- barra d'informació
  col(C.bg, 0.85); love.graphics.rectangle('fill', 0, 0, 320, 18); love.graphics.rectangle('fill', 0, 222, 320, 18)
  col(C.gold); love.graphics.print(s.title, 6, 1)
  local Streets = require('src.systems.streets')
  local here = Streets.name_at(s.cx * 16 + 8, s.cy * 16 + 8, 96)
  col(C.text)
  love.graphics.print(s.msg or (s.zoom and ('Z: triar la porta · +/-: zoom' .. (here and (' · ' .. here) or '')) or
    'Fletxes: moure · +/-: zoom · Z: apropar-s\'hi'), 6, 223)
  love.graphics.setColor(1, 1, 1)
  local zv = s.view
  if s.zoom then zv = Z.new(); zv.i = s.cz == 1 and 1 or (s.cz == 2 and 3 or #Z.STEPS) end   -- solo marca los topes
  Z.draw_buttons(zv, s.btns, nil)
end

-- cases ja triades (pròpia i dels personatges) per veure-les al mapa
function UI:place_marks()
  local out = {}
  local s
  for i = #self.stack, 1, -1 do if self.stack[i].profile then s = self.stack[i]; break end end
  if not s then return out end
  local p = s.profile
  if p.home then out[#out + 1] = { x = p.home.tile_x, y = p.home.tile_y, label = 'Casa', color = { 0.84, 0.42, 0.29 } } end
  for _, f in ipairs(p.friends) do
    if f.home then out[#out + 1] = { x = f.home.tile_x, y = f.home.tile_y, label = f.name, color = { 0.83, 0.5, 0.65 } } end
  end
  return out
end

function UI:draw()
  self:draw_content()
  if self.flash_text then
    panel(12, 196, 296, 32); col(C.text)
    love.graphics.printf(self.flash_text, 20, 204, 280)
  end
  if self.save_error or self.notice then
    panel(12,174,296,54); col(C.text)
    local text=self.save_error and (self.save_error..'. Torna a prémer Desar per reintentar.') or self.notice
    love.graphics.printf(text,20,178,280)
  end
end
return UI
