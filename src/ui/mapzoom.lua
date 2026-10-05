-- Zoom de los mapas de pantalla (mapa M, diario, selector de casa): pasos, centro, botones + / − y proyección.
-- view = { i = índice de paso, fx, fy = centro como fracción del mapa (0..1) }
local Z = { STEPS = { 1, 1.5, 2, 3, 4 } }

function Z.new(fx, fy) return { i = 1, fx = fx or 0.5, fy = fy or 0.5 } end
function Z.zoom(view) return Z.STEPS[view.i] end

-- cambia de paso (d = +1 / −1); devuelve true si ha cambiado
function Z.step(view, d)
  local n = math.max(1, math.min(#Z.STEPS, view.i + d))
  if n == view.i then return false end
  view.i = n
  return true
end

-- tamaño del mapa entero en pantalla y centro limitado para no salirse del borde
function Z.size(view, base) return base * Z.STEPS[view.i] end
function Z.clamp(view, rect, base)
  local S = Z.size(view, base)
  local hw, hh = rect.w / 2 / S, rect.h / 2 / S
  view.fx = hw >= 0.5 and 0.5 or math.max(hw, math.min(1 - hw, view.fx))
  view.fy = hh >= 0.5 and 0.5 or math.max(hh, math.min(1 - hh, view.fy))
end

-- posición en pantalla de la fracción (u, v) del mapa
function Z.pos(view, rect, base, u, v)
  local S = Z.size(view, base)
  return rect.x + rect.w / 2 + (u - view.fx) * S, rect.y + rect.h / 2 + (v - view.fy) * S
end

-- fracción del mapa bajo el punto de pantalla (x, y)
function Z.unpos(view, rect, base, x, y)
  local S = Z.size(view, base)
  return view.fx + (x - rect.x - rect.w / 2) / S, view.fy + (y - rect.y - rect.h / 2) / S
end

-- aplica las pulsaciones zoom_in / zoom_out y el desplazamiento con la cruceta; true si ha habido zoom
function Z.update(view, rect, base, dt, pressed, act)
  local changed = false
  if pressed.zoom_in then changed = Z.step(view, 1) or changed end
  if pressed.zoom_out then changed = Z.step(view, -1) or changed end
  if view.i > 1 and act then
    local S = Z.size(view, base)
    local h = (act.right and 1 or 0) - (act.left and 1 or 0)
    local v = (act.down and 1 or 0) - (act.up and 1 or 0)
    view.fx, view.fy = view.fx + h * 110 * dt / S, view.fy + v * 110 * dt / S
  end
  Z.clamp(view, rect, base)
  return changed
end

-- botones en pantalla (coordenadas virtuales 320×240): + arriba, − debajo
function Z.buttons(x, y)
  return { zoom_in = { x = x, y = y, w = 22, h = 22 }, zoom_out = { x = x, y = y + 26, w = 22, h = 22 } }
end

function Z.hit(btns, px, py)
  for name, r in pairs(btns) do
    if px >= r.x - 3 and px <= r.x + r.w + 3 and py >= r.y - 3 and py <= r.y + r.h + 3 then return name end
  end
end

function Z.draw_buttons(view, btns, font)
  for name, r in pairs(btns) do
    local off = (name == 'zoom_in' and view.i >= #Z.STEPS) or (name == 'zoom_out' and view.i <= 1)
    love.graphics.setColor(0.12, 0.10, 0.14, 0.88); love.graphics.rectangle('fill', r.x, r.y, r.w, r.h)
    love.graphics.setColor(0.96, 0.94, 0.89, off and 0.35 or 1); love.graphics.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    love.graphics.rectangle('fill', cx - 5, cy - 1, 11, 2)
    if name == 'zoom_in' then love.graphics.rectangle('fill', cx - 1, cy - 5, 2, 11) end
  end
  love.graphics.setColor(0.96, 0.94, 0.89)
  local first = btns.zoom_out
  if font then love.graphics.print('x' .. tostring(Z.STEPS[view.i]), first.x + 2, first.y + first.h + 4) end
  love.graphics.setColor(1, 1, 1)
end

return Z
