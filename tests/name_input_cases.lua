-- Route the actual web A key through the menu/Input path used by main.lua.
love = { keyboard = { setTextInput = function() end, isDown = function() return false end } }
local UI = require('src.ui.profiles')
local Input = require('src.input')
local f = assert(io.open('web/index.html')); local html = f:read('*a'); f:close()
local touch = assert(html:match('id="a".-data%-key="([^"]+)"')):lower()
local ui = setmetatable({ game = { audio = { play = function() end }, to_title = function() end },
  slots = {}, stack = { { kind = 'slots', sel = 1 } }, t = 0 }, UI)
local result
local function key(k)
  if not ui:keypressed(k) then Input.keypressed(k) end
  local act = Input.step(); ui:update(1/60, act.pressed, act)
end
ui:ask_name('Nom', '', function(v) result = v end)
key(touch)
assert(ui:top().value == 'A', 'mobile A must select A, not be consumed as text')
key('right'); key(touch)
assert(ui:top().value == 'AB', 'mobile direction + A selects next letter')
ui:top().gy, ui:top().gx = 5, 3; key(touch)
assert(ui:top().value == 'A', 'grid backspace')
ui:top().gx = 2; key(touch)
ui:textinput('É'); key('backspace'); ui:textinput('Ç')
assert(ui:top().value == 'A Ç', 'space, accent and UTF-8 deletion')
key('z'); assert(ui:top().value == 'A Ç', 'physical Z must not select grid')
ui:textinput('z'); assert(ui:top().value == 'A Çz')
ui:top().gx = 4; key(touch)
assert(result == 'A Çz' and ui:top().kind == 'slots', 'Fet submits once')
ui:ask_name('Nom', '', function(v) result = v end)
ui:textinput('Èric'); key('return'); assert(result == 'Èric', 'physical Enter submits')
ui:ask_name('Nom', '', function() error('cancel submitted') end); key('escape')
assert(ui:top().kind == 'slots', 'cancel returns')
print('name_input_cases: OK (mobile grid + physical keyboard)')
