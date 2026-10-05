-- Històries originals del joc: lectura al ritme del jugador, sense premis ni atzar.
local UI = require('src.minigames.ui')
local C = {}; C.__index = C
local stories = {
  theatre = { title='Teatre: La llavor viatgera', lines={
    'Una llavor arriba al poble. Busca un racó on poder créixer.',
    'La jardinera li ofereix terra. El núvol li porta una mica de pluja.',
    'El sol escalfa el jardí. Amb temps i cura, apareixen les primeres fulles.',
    'Ara hi ha un arbre per a tothom. Cuidar-lo és una feina compartida. Fi.' } },
  cinema = { title='Cinema: Un dia a la costa', lines={
    'Surt el sol damunt del mar. La platja es desperta a poc a poc.',
    'Un petit vaixell travessa la badia. Les gavines el saluden des del cel.',
    'Al camí de tornada, recollim una ampolla de la sorra i la reciclem.',
    'El vespre tenyeix el cel. Deixem la costa neta per tornar-hi demà. Fi.' } }
}
function C.new(params)
  local mode=params.mode=='theatre' and 'theatre' or 'cinema'
  return setmetatable({mode=mode,story=stories[mode],page=1,t=0,done=false,result={}},C)
end
function C:update(dt,act)
  if self.done then return end
  self.t=self.t+dt
  local p=act.pressed or {}
  if p.cancel then self.done=true;self.result={finished=false};return end
  if p.confirm then
    if self.page==#self.story.lines then self.done=true;self.result={finished=true}
    else self.page=self.page+1;self.t=0 end
  end
end
function C:draw(ui)
  local g=love.graphics
  UI.frame(self.story.title,ui.font)
  local reduced=require('src.motion').reduced
  local t=reduced and 0 or self.t
  g.setColor(.08,.08,.12);g.rectangle('fill',20,30,280,126)
  if self.mode=='theatre' then
    g.setColor(.46,.10,.18);g.rectangle('fill',20,30,35,126);g.rectangle('fill',265,30,35,126)
    for x=24,292,268 do g.setColor(.7,.22,.25);g.rectangle('fill',x,30,6,119) end
    g.setColor(.60,.36,.23);g.rectangle('fill',55,140,210,16)
    g.setColor(.92,.74,.38);g.polygon('fill',100,35,65,139,140,139)
    g.setColor(.3,.53,.35);g.rectangle('fill',175,128,46,12)
    g.setColor(.48,.28,.15);g.rectangle('fill',194,130-self.page*13,6,self.page*13)
    if self.page>=3 then g.setColor(.36,.72,.38);g.circle('fill',197,119-self.page*13,12+self.page*2) end
    local y=math.floor(math.sin(t*2)*2)
    g.setColor(.94,.72,.53);g.rectangle('fill',100,93+y,13,13)
    g.setColor(.35,.47,.76);g.rectangle('fill',96,106+y,21,25)
    g.setColor(.16,.2,.27);g.rectangle('fill',98,131,6,9);g.rectangle('fill',110,131,6,9)
  else
    g.setColor(self.page==4 and .6 or .35,.55,.72);g.rectangle('fill',24,34,272,65)
    UI.ICONS.sol(235,42,2)
    g.setColor(.15,.44,.62);g.rectangle('fill',24,99,272,39)
    for i=1,7 do g.setColor(.48,.74,.8);g.rectangle('fill',30+i*30+math.floor(math.sin(t+i)*4),108+(i%3)*8,15,2) end
    g.setColor(.85,.72,.49);g.rectangle('fill',24,138,272,14)
    if self.page==2 then
      local x=125+math.floor(math.sin(t*.5)*20)
      g.setColor(.72,.37,.23);g.polygon('fill',x-22,115,x+22,115,x+13,126,x-13,126)
      g.setColor(.96,.94,.84);g.polygon('fill',x,76,x,112,x+24,112)
    elseif self.page==3 then
      g.setColor(.32,.64,.44);g.rectangle('fill',147,132,8,15)
      g.setColor(.85,.94,.85);g.rectangle('fill',149,129,4,4)
    end
  end
  UI.col(UI.C.text);g.setFont(ui.font);g.printf(self.story.lines[self.page],24,166,272,'center')
  UI.center(self.page..' / '..#self.story.lines,202,ui.font,UI.C.dim)
  UI.help('A: continuar   B: sortir',ui.font)
end
return C
