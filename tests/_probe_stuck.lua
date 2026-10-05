return function(api)
  api.wait(5)
  api.teleport(725, 947)
  api.wait(5)
  local sc = api.scene()
  local n
  for _, x in ipairs(sc.npcs) do if x.name == 'npc_fisher' then n = x end end
  print('[probe] fisher', n.body.x, n.body.y, math.floor(n.body.x/16), math.floor(n.body.y/16))
  local dev = require('src.devtools')
  local gx, gy = math.floor(n.body.x / 16), math.floor(n.body.y / 16)
  api.walk_to(function(tx, ty) return math.abs(tx - gx) + math.abs(ty - gy) == 1 end, 6)
  local b = api.player().body
  print('[probe] end', b.x, b.y, b.level)
  local C = require('src.world.collision')
  for ty = 945, 949 do
    local row = {}
    for tx = 722, 729 do row[#row+1] = tostring(sc.map:cell(tx, ty)) end
    print('[probe] row', ty, table.concat(row, ' '))
  end
end
