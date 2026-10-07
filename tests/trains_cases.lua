local Trains = require('src.systems.trains')
local function setup(points)
  local t = Trains.new({routes={{type='route_train',name='test',points=points,props={}}},objects={}},
    {speed=40,period=60,stop=5})
  local tr={line=t.lines[1],head=180,dir=1}
  t.current={tr}
  return t,tr
end
local cam={visible=function() return true end}
local function near(a,b) assert(math.abs(a-b)<1e-6, tostring(a)..' ~= '..tostring(b)) end
local t,tr=setup({{0,0},{600,180}})
local c=t:cars(cam)[1]
assert(type(c.angle)=='number','El vagón necesita el ángulo real de la vía')
near(c.angle,math.atan2(180,600))
near(c.y,c.x*0.3)
local f=c
tr.dir=-1
c=t:cars(cam)[1]
near(math.cos(c.angle),-math.cos(f.angle))
near(math.sin(c.angle),-math.sin(f.angle))
-- Al atravesar un vértice, ambos ejes sostienen el vagón y el giro es continuo.
t,tr=setup({{0,0},{200,0},{400,100}})
local prev
for s=183,217,0.1 do
  tr.head=s+24
  c=t:cars(cam)[1]
  if prev then
    assert(math.abs(c.angle-prev.angle)<0.01,'salto de orientación en curva')
    assert((c.x-prev.x)^2+(c.y-prev.y)^2<0.02,'salto de posición')
  end
  prev=c
end
-- Entrada/salida, túneles y selección de vagones siguen siendo válidas.
for _,dir in ipairs({1,-1}) do
  tr.dir=dir
  for s=-160,610,10 do
    tr.head=s
    for _,car in ipairs(t:cars(cam)) do assert(car.angle==car.angle) end
  end
end
print('OK trains: pendiente arbitraria, ambos sentidos, giro continuo y extremos')
