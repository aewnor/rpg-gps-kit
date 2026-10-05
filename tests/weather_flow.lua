-- Temps (love . --test=tests/weather_flow.lua --mute): cada temps de config/joc.json es veu a l'exterior
-- (desa weather_<temps>.png), quan plou l'avatar porta el xubasquer i se'l treu quan para; el mode automàtic
-- és determinista per dia i bloc de 6 hores.
return function(api)
  local g = api.scene().game
  local w = api.scene()
  local Weather = require('src.systems.weather')
  local Looks = require('src.paperdoll.looks')
  api.talk_through()
  -- automàtic: mateix dia i hora → mateix temps; la neu només a l'hivern
  api.check(Weather.auto(12, 400, 7) == Weather.auto(12, 400, 7), 'el temps automàtic és determinista')
  local snow_summer, snow_winter = 0, 0
  for d = 1, 400 do
    if Weather.auto(d, 600, 7) == 'neu' then snow_summer = snow_summer + 1 end
    if Weather.auto(d, 600, 1) == 'neu' then snow_winter = snow_winter + 1 end
  end
  api.check(snow_summer == 0 and snow_winter > 0, 'neu només a l\'hivern (' .. snow_winter .. ' de 400 dies al gener)')
  api.check(Weather.pick({ day = 3, clock = 600 }, 'boira') == 'boira', 'la configuració fixa el temps')
  api.check(Weather.pick({ day = 3, clock = 600 }, 'xx') == Weather.auto(3, 600, tonumber(os.date('%m'))),
    'un temps desconegut torna a l\'automàtic')

  g.profile = g.profile or { name = 'Proves' }
  g.profile.avatar = g.profile.avatar or Looks.default('nena')
  g:apply_skin('avatar')
  local plain = Looks.key(g.profile.avatar)
  w.state.clock = 660
  for _, kind in ipairs(Weather.KINDS) do
    g.config.temps = kind
    for _ = 1, 600 do api.wait(1); if g.weather and g.weather.kind == kind and g.weather.level >= 1 then break end end
    api.check(g.weather.kind == kind and g.weather.level >= 1, 'fa ' .. kind)
    if kind == 'pluja' then
      api.check(g.avatar_key ~= plain and g.avatar_key:find('hood', 1, true) ~= nil, 'quan plou porta el xubasquer')
    end
    local file, done = 'weather_' .. kind .. '.png', false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  api.check(g.avatar_key == plain, 'quan para de ploure es treu el xubasquer')
  g.config.temps = 'auto'
end
