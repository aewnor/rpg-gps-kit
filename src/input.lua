-- Acciones abstractas de teclado/mando. Las pulsaciones se acumulan hasta el siguiente paso de
-- simulación y se consumen una sola vez (sobreviven a frames sin paso).
local Input = {}

local KEYS = {
  up = { 'up', 'w' }, down = { 'down', 's' }, left = { 'left', 'a' }, right = { 'right', 'd' },
  confirm = { 'f1', 'z', 'return', 'space', 'kpenter' }, cancel = { 'escape', 'backspace' },
  attack = { 'x' }, shield = { 'c', 'k', 'lshift' }, pause = { 'escape', 'p' },
  map = { 'm', 'tab' }, debug = { 'f3' }, bike = { 'b' }, horn = { 'h' }, journal = { 'j' }, inventory = { 'i' }, swap = { 'r' },
  spell = { 'v', 'l' }, spell_next = { 'e' }, spell_prev = { 'q' }, heal = { 'g' },
  zoom_in = { '=', '+', 'kp+' }, zoom_out = { '-', 'kp-' }, view = { 'n' },   -- vista allunyada del món (src/scenes/world_scene.lua)
}
local PAD = {
  up = { 'dpup' }, down = { 'dpdown' }, left = { 'dpleft' }, right = { 'dpright' },
  confirm = { 'a' }, cancel = { 'b' }, attack = { 'x' }, shield = { 'leftshoulder', 'rightshoulder' }, bike = { 'y' }, horn = { 'leftstick' },
  pause = { 'start' }, map = { 'back' }, spell = { 'rightstick' },
  zoom_in = { 'rightshoulder' }, zoom_out = { 'leftshoulder' },
}

local key_to_actions, pad_to_actions = {}, {}
for action, list in pairs(KEYS) do
  for _, k in ipairs(list) do
    key_to_actions[k] = key_to_actions[k] or {}
    table.insert(key_to_actions[k], action)
  end
end
for action, list in pairs(PAD) do
  for _, b in ipairs(list) do
    pad_to_actions[b] = pad_to_actions[b] or {}
    table.insert(pad_to_actions[b], action)
  end
end

local pending = {}
local virtual_held = {}
local joystick

function Input.keypressed(key)
  for _, a in ipairs(key_to_actions[key] or {}) do pending[a] = true end
end

function Input.gamepadpressed(js, button)
  joystick = js
  for _, a in ipairs(pad_to_actions[button] or {}) do pending[a] = true end
end

function Input.joystickadded(js) joystick = js end

-- rueda del ratón: acercar / alejar los mapas
function Input.wheel(dy)
  if dy > 0 then pending.zoom_in = true elseif dy < 0 then pending.zoom_out = true end
end

function Input.press(action) pending[action] = true end      -- entrada sintética (tests/benchmark)
function Input.hold(action, on) virtual_held[action] = on or nil end
function Input.release_all() virtual_held = {} end

local function held(action)
  if virtual_held[action] then return true end
  for _, k in ipairs(KEYS[action] or {}) do
    if love.keyboard.isDown(k) then return true end
  end
  if joystick and joystick:isGamepad() then
    for _, b in ipairs(PAD[action] or {}) do
      if joystick:isGamepadDown(b) then return true end
    end
    local ax, ay = joystick:getGamepadAxis('leftx'), joystick:getGamepadAxis('lefty')
    if action == 'left' and ax < -0.4 then return true end
    if action == 'right' and ax > 0.4 then return true end
    if action == 'up' and ay < -0.4 then return true end
    if action == 'down' and ay > 0.4 then return true end
    if action == 'shield' and joystick:getGamepadAxis('triggerleft') > 0.5 then return true end
  end
  return false
end

-- Se llama una vez por paso de simulación: devuelve acciones mantenidas y pulsadas (consumidas)
function Input.step()
  local pressed = pending
  pending = {}
  return {
    up = held('up'), down = held('down'), left = held('left'), right = held('right'),
    shield = held('shield'), attack_held = held('attack'),
    pressed = pressed,
  }
end

function Input.clear() pending = {} end

return Input
