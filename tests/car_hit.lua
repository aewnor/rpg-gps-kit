-- Un coche en marcha atropella al jugador que se le cruza muy cerca: pierde vida y sale empujado
-- (love . --test=tests/car_hit.lua --mute).
return function(api)
  local Traffic = require('src.systems.traffic')
  api.wait(5)
  local tr = api.scene().traffic
  local st = api.state()
  local hit = false
  for _, car in ipairs(tr.cars) do
    if not car.decorative and not hit then
      local t = 0
      while car.v < 40 and t < 300 do api.wait(1); t = t + 1 end
      local x, y, ang, level = Traffic.pos(car)
      if level == 0 and car.v >= 40 then
        local hp0 = st.hp
        local b = api.player().body
        b.x, b.y, b.level = x + math.cos(ang) * 12, y + math.sin(ang) * 12, 0  -- justo delante del morro
        api.wait(40)
        if st.hp < hp0 then
          hit = true
          api.check(true, string.format('atropello: vida %d → %d', hp0, st.hp))
        end
        st.hp = st.max_hp
      end
    end
  end
  api.check(hit, 'algún coche atropella al jugador que se cruza')
end
