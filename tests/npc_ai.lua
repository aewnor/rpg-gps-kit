-- Conversación con un personaje con IA (maps/source/npcs.json) en el juego real: pide respuesta al
-- servidor (tools/web_server.py → Groq), muestra opciones y responde a una (love . --test=tests/npc_ai.lua --mute).
return function(api)
  api.wait(5)
  local scene = api.scene()
  local npc
  for _, n in ipairs(scene.npcs) do if n.props.ai then npc = n; break end end
  api.check(npc ~= nil, 'hay un personaje con IA en el mapa')
  if not npc then return end
  npc.wander = 0
  local tx, ty = math.floor(npc.body.x / 16), math.floor(npc.body.y / 16)
  api.teleport(tx, ty + 1); api.wait(3)
  api.player().facing = 'up'
  api.press('confirm'); api.wait(5)
  local function page() return scene.dialogue.open and scene.dialogue.pages[scene.dialogue.page] or nil end
  local t = 0
  while page() == '...' and t < 1500 do api.wait(1); t = t + 1 end
  local reply = page()
  print('[test] resposta: ' .. tostring(reply))
  api.check(reply and reply ~= '...' and #reply > 3, 'el personatge respon (' .. math.floor(t / 60 * 10) / 10 .. ' s)')
  api.talk_through(4)
  api.wait(5)
  local g = scene.game
  api.check(g.menu and g.menu.screen == 'list', 'apareixen opcions per continuar')
  if g.menu and g.menu.list and g.menu.list[1] then
    print('[test] opció: ' .. g.menu.list[1][1])
    g.menu.list[1][2]()
    api.wait(5)
    t = 0
    while page() == '...' and t < 1500 do api.wait(1); t = t + 1 end
    print('[test] resposta 2: ' .. tostring(page()))
    api.check(page() and page() ~= '...', 'respon a l\'opció triada')
    api.talk_through(4)
    if g.menu then g:close_menu() end
  end
end
