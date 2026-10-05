-- Fulles de vehicles en diagonal (love . --test=tests/vehicle_diag_shots.lua --mute): vd_<vehicle>.png
return function(api)
  local P = require('src.profile')
  local Looks = require('src.paperdoll.looks')
  local b = Looks.build(P.new('Prova', 'nena').avatar, true)
  api.check(b.bike_diag and b.bike_diag.img:getWidth() == 64 and b.bike_diag.img:getHeight() == 128, 'bici: 4 diagonals × 2')
  local S = require('src.paperdoll.sheets')
  local spec = Looks.spec(P.new('Prova', 'nena').avatar)
  S.diag(spec, 'bike'):to_imagedata():encode('png', 'vd_bike.png')
  S.bike(spec):to_imagedata():encode('png', 'vc_bike.png')
  for _, v in ipairs({ 'patinete', 'scooter', 'motocross', 'cavall_brown' }) do
    api.check(b.vehicles[v].diag ~= nil, v .. ' en diagonal')
    S.diag(spec, v):to_imagedata():encode('png', 'vd_' .. v .. '.png')
    S.vehicle(spec, v):to_imagedata():encode('png', 'vc_' .. v .. '.png')
  end
  local Player = require('src.entities.player')
  api.check(Player.vehicle_diag(math.pi * 0.75) == 0 and Player.vehicle_diag(math.pi / 4) == 1 and
    Player.vehicle_diag(-math.pi * 0.75) == 2 and Player.vehicle_diag(-math.pi / 4) == 3 and Player.vehicle_diag(0) == nil,
    'el rumb tria la diagonal')
end
