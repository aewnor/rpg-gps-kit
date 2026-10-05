-- Marca del mapa (state.marker = { x, y, label } en píxels del món): es posa a la pantalla del mapa (Z al
-- centre, o X per anar passant per casa i les cases dels amics) i al joc surt una brúixola cap allà.
-- En arribar-hi s'esborra sola.
local Marker = {}

Marker.ARRIVE = 28   -- px

-- llocs ràpids: casa i cases dels amics i avis del perfil
function Marker.places(g)
  local out = {}
  if g.home then out[#out + 1] = { x = g.home.x, y = g.home.y, label = 'Casa' } end
  for _, fr in ipairs(g.friends or {}) do
    local h = fr.def.home
    if h then out[#out + 1] = { x = h.tile_x * 16 + 8, y = h.tile_y * 16 + 8, label = 'Casa de ' .. fr.def.name } end
  end
  return out
end

function Marker.set(st, x, y, label)
  st.marker = { x = math.floor(x), y = math.floor(y), label = label or 'Marca' }
end

function Marker.clear(st) st.marker = nil end

function Marker.get(st)
  local m = st and st.marker
  if type(m) == 'table' and tonumber(m.x) and tonumber(m.y) then return m end
end

-- a l'exterior: si hi has arribat, s'esborra i avisa
function Marker.update(w)
  local m = Marker.get(w.state)
  if not m or w.id ~= 'overworld' then return end
  local b = w.player.body
  if (m.x - b.x) ^ 2 + (m.y - b.y) ^ 2 < Marker.ARRIVE ^ 2 then
    Marker.clear(w.state)
    w.hud:toast('Has arribat: ' .. (m.label or 'Marca') .. '!', 2.5)
    w.game.audio.play('stamp')
  end
end

local PIN = { 0.93, 0.33, 0.36 }

-- agulla al món (si és a la vista)
function Marker.draw_world(w, ox, oy)
  local m = Marker.get(w.state)
  if not m or w.id ~= 'overworld' or not w.cam:visible(m.x - 8, m.y - 24, 16, 28, 0) then return end
  local x, y = math.floor(m.x - ox), math.floor(m.y - oy)
  local bob = math.floor(math.sin(love.timer.getTime() * 3) * 1.5 + 0.5)
  love.graphics.setColor(0, 0, 0, 0.3); love.graphics.ellipse('fill', x, y + 1, 4, 1.5)
  love.graphics.setColor(PIN); love.graphics.polygon('fill', x - 4, y - 14 + bob, x + 4, y - 14 + bob, x, y - 4 + bob)
  love.graphics.circle('fill', x, y - 15 + bob, 5)
  love.graphics.setColor(1, 1, 1); love.graphics.circle('fill', x, y - 15 + bob, 2)
end

-- brúixola (a baix a la dreta; si hi ha missió activa, a sobre del seu requadre)
function Marker.draw_hud(w)
  local m = Marker.get(w.state)
  if not m then return end
  local font = w.game.font
  local x0, y0 = 206, (w.town and w.town.text) and 166 or 202
  love.graphics.setColor(0.12, 0.10, 0.14, 0.78); love.graphics.rectangle('fill', x0, y0, 112, 34, 4)
  love.graphics.setColor(PIN); love.graphics.rectangle('line', x0 + 0.5, y0 + 0.5, 111, 33, 4)
  local cx, cy = x0 + 14, y0 + 17
  if w.id == 'overworld' then
    local b = w.player.body
    local dx, dy = m.x - b.x, m.y - b.y
    local a = math.atan2(dy, dx)
    local function p(r, da) return cx + math.cos(a + da) * r, cy + math.sin(a + da) * r end
    local ax, ay = p(11, 0)
    local bx, by = p(8, 2.5)
    local qx, qy = p(3, math.pi)
    local dx2, dy2 = p(8, -2.5)
    love.graphics.setColor(PIN); love.graphics.polygon('fill', ax, ay, bx, by, qx, qy, dx2, dy2)
    local meters = math.floor(math.sqrt(dx * dx + dy * dy) / 16 * 4 / 5 + 0.5) * 5
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(meters >= 1000 and string.format('%.1f km', meters / 1000) or (meters .. ' m'), x0 + 28, y0)
  else
    love.graphics.setColor(1, 1, 1); love.graphics.print('Surt al carrer', x0 + 28, y0)
  end
  love.graphics.setColor(0.96, 0.94, 0.89)
  love.graphics.setScissor(x0 + 28, y0 + 16, 82, 17)
  local text = m.label or 'Marca'
  local tw = font and font:getWidth(text) or 0
  local off = tw > 82 and ((love.timer.getTime() * 18) % (tw + 20)) or 0
  love.graphics.print(text, x0 + 28 - off, y0 + 16)
  if off > 0 then love.graphics.print(text, x0 + 28 - off + tw + 20, y0 + 16) end
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1)
end

-- agulla a la pantalla del mapa (at: funció píxel del món → pantalla)
function Marker.draw_map(st, at)
  local m = Marker.get(st)
  if not m then return end
  local x, y = at(m.x, m.y)
  love.graphics.setColor(0.1, 0.08, 0.12); love.graphics.circle('fill', x, y - 6, 5)
  love.graphics.setColor(PIN); love.graphics.polygon('fill', x - 3, y - 6, x + 3, y - 6, x, y)
  love.graphics.circle('fill', x, y - 6, 4)
  love.graphics.setColor(1, 1, 1); love.graphics.circle('fill', x, y - 6, 1.5)
end

return Marker
