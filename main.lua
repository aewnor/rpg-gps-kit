-- Arranque: callbacks de LÖVE. Ver src/game.lua.
local Game = require('src.game')
local Input = require('src.input')

local game

local function parse_args(list)
  local out = {}
  for _, a in ipairs(list or {}) do
    local k, v = a:match('^%-%-([%w_]+)=?(.*)$')
    if k then out[k] = (v ~= '' and v) or true end
  end
  return out
end

function love.load(arg_list)
  local args = parse_args(arg_list)
  game = Game.new(args)
  if args.bench or args.test or args.shot then
    local Dev = require('src.devtools')
    game.dev = Dev.new(game, args)
  else
    game.audio.music_play('overworld')
  end
end

function love.update(dt) game:update(dt) end
function love.draw() game:draw() end
function love.keypressed(key)
  if game:keypressed(key) then return end   -- p. ej. escribir un nombre en el editor de perfiles
  Input.keypressed(key)
end
function love.textinput(t) game:textinput(t) end
function love.gamepadpressed(js, b) Input.gamepadpressed(js, b) end
function love.joystickadded(js) Input.joystickadded(js) end
function love.mousepressed(x, y, b) if b == 1 then game:pointer(x, y) end end
function love.wheelmoved(_, dy) Input.wheel(dy) end
function love.focus(f) game:focus(f) end
-- tancar la finestra (escriptori) desa la partida
function love.quit()
  if game and game.scene and game.state and not game.dev then game:save_game(false) end
  return false
end

-- error inesperat: pantalla amable en català (no la pantalla blava amb el traç) i reinici; el traç va al
-- registre (consola i error.log) per depurar-lo. La partida s'autodesa cada minut (src/game.lua).
function love.errorhandler(msg)
  msg = tostring(msg)
  local trace = debug.traceback('Error: ' .. msg, 2):gsub('\n[^\n]+$', '')
  print(trace)
  pcall(love.filesystem.append, 'error.log', os.date('%Y-%m-%d %H:%M:%S') .. '\n' .. trace .. '\n\n')
  -- pruebas y bancos de pruebas sin pantalla: salir (si no, se quedaría esperando una tecla)
  if not love.window or not love.graphics or not love.event or (game and game.dev) then return end
  if not love.graphics.isCreated() or not love.window.isOpen() then
    if not pcall(love.window.setMode, 960, 720) then return end
  end
  pcall(function() love.mouse.setVisible(true); love.mouse.setGrabbed(false) end)
  if love.audio then pcall(love.audio.stop) end
  love.graphics.reset()
  local big = love.graphics.newFont(28)
  local small = love.graphics.newFont(14)
  local short = msg:gsub('^[^:]*:%d+: ', ''):sub(1, 140)
  local function draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.clear(0.12, 0.10, 0.14)
    love.graphics.setColor(0.96, 0.94, 0.89)
    love.graphics.setFont(big)
    love.graphics.printf('Ups! Alguna cosa ha fallat.', 20, h * 0.32, w - 40, 'center')
    love.graphics.setFont(small)
    love.graphics.printf('La partida es desa sola cada minut, així que gairebé no has perdut res.\n\n' ..
      'Prem Intro o toca la pantalla per tornar a començar.\n(Al navegador, també pots recarregar la pàgina.)',
      40, h * 0.32 + 60, w - 80, 'center')
    love.graphics.setColor(0.65, 0.61, 0.66)
    love.graphics.printf('Per als adults: ' .. short, 40, h - 50, w - 80, 'center')
    love.graphics.present()
  end
  return function()
    love.event.pump()
    for e, a in love.event.poll() do
      if e == 'quit' then return 1 end
      if (e == 'keypressed' and (a == 'return' or a == 'kpenter' or a == 'space' or a == 'escape')) or
          e == 'touchpressed' or e == 'mousepressed' or e == 'gamepadpressed' then
        return 'restart'
      end
    end
    draw()
    if love.timer then love.timer.sleep(0.1) end
  end
end

