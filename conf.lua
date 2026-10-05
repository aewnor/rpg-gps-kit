-- Ventana y módulos de LÖVE. Resolución lógica 320×240 escalada ×3 por defecto.
function love.conf(t)
  t.identity = 'rpg-altafulla'
  -- la versión web (love.js) es 11.4: sin esto el navegador saca un «Compatibility Warning» al cargar
  local ok, v = pcall(function() return love.isVersionCompatible and not love.isVersionCompatible('11.5') end)
  t.version = (ok and v) and '11.4' or '11.5'
  t.window.title = 'Altafulla'
  t.window.width = 960
  t.window.height = 720
  t.window.minwidth = 320
  t.window.minheight = 240
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.video = false
end
