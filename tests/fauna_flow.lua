-- Fauna en el juego real: calle (gatos/pájaros/perros), montaña (salvajes que atacan, XP) y descarga.
--   love . --test=tests/fauna_flow.lua --mute
return function(api)
  local sc = api.scene()
  local st = api.state()
  local Fauna = require('src.systems.fauna')
  api.check(sc.fauna ~= nil, 'el mundo abierto tiene fauna')

  -- busca un punto de calle/parque y el monte «de verdad» más cercano (rejilla gruesa)
  local pb = sc.player.body
  local cx, cy = math.floor(pb.x / 16), math.floor(pb.y / 16)
  local found = {}
  local Collision = require('src.world.collision')
  for r = 4, 60, 4 do
    for _, o in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } }) do
      local tx, ty = cx + o[1], cy + o[2]
      if sc.map:in_bounds(tx, ty) and Collision.walk_at(sc.map:cell(tx, ty), 0) then
        local z = Fauna.zone(sc:tile_name('ground', tx, ty))
        if (z == 'street' or z == 'park') and not found[z] then found[z] = { tx, ty } end
      end
    end
  end
  local bestd = math.huge
  for ty = 0, 1599, 16 do
    for tx = 0, 1599, 16 do
      local d = (tx - cx) ^ 2 + (ty - cy) ^ 2
      if d < bestd and Fauna.zone(sc:tile_name('ground', tx, ty)) == 'mountain' then
        local n, m = 0, 0
        for dy = -12, 12, 3 do for dx = -12, 12, 3 do
          local ax, ay = tx + dx, ty + dy
          if sc.map:in_bounds(ax, ay) then m = m + 1; if Fauna.zone(sc:tile_name('ground', ax, ay)) == 'mountain' then n = n + 1 end end
        end end
        if n / m > 0.9 then found.mountain, bestd = { tx, ty }, d end
      end
    end
  end
  api.check(found.mountain ~= nil, 'hay monte cerca')
  api.check(found.street ~= nil or found.park ~= nil, 'hay calle o parque cerca')

  -- calle/parque
  local s = found.street or found.park
  api.teleport(s[1], s[2]); api.wait(5)
  api.wait(60 * 25)
  local n = #sc.fauna.list
  print('animales en calle/parque: ' .. n)
  api.check(n > 0 and n <= 14, 'aparecen animales de calle sin pasar de 14 (' .. n .. ')')

  -- montaña
  local m = found.mountain
  st.hp = st.max_hp
  api.teleport(m[1], m[2]); api.wait(5)
  api.wait(60 * 40)
  local wild = sc.fauna:count_wild()
  print('salvajes: ' .. wild)
  api.check(wild > 0 and wild <= Fauna.CAP.wild, 'en la montaña hay salvajes (' .. wild .. ')')
  local e
  for _, x in ipairs(sc.enemies) do if x.fauna and x.state ~= 'dead' then e = x end end
  if e then
    -- pega al salvaje con la espada (sin esperar a que me muerda): XP y monedas
    local xp0 = st.xp or 0
    sc:enemy_event(e, e:damage(99, sc.player.body.x, sc.player.body.y) or 'dead')
    api.check(e.state == 'dead', 'se puede matar a un salvaje')
    api.check((st.xp or 0) > xp0 or st.char_level > 1, 'matarlo da XP')
  end
  -- descarga al alejarse
  api.teleport(s[1], s[2]); api.wait(60)
  api.check(sc.fauna:count_wild() == 0, 'al irte los salvajes se descargan')
end
