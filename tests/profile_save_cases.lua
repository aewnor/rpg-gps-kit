local P = require('src.profile')
local UI = require('src.ui.profiles')
local files, fail = {}, nil
P.fs = {
 exists=function(n) return files[n]~=nil end,
 read=function(n) if fail=='read' then error('I/O') end return files[n] end,
 write=function(n,d) if fail=='write' or fail==n then return false end files[n]=d;return true end,
 remove=function(n) files[n]=nil;return true end,
 rename=function(a,b) if fail=='rename' then return false end files[b]=files[a];files[a]=nil;return true end,
}
local path=P.path(1)
files[path]='{broken'
assert(P.list()[1].error and P.list()[1].exists, 'corrupt slot must remain occupied with error')
files={}; assert(P.write(1,P.new('Alpha','nena')))
assert(P.write(1,P.new('Beta','nena')))
files[path]='{broken'
local p,err=P.read(1);assert(p and p.name=='Alpha' and err,'recover backup with warning')
assert(P.write(1,P.new('Gamma','nena')))
assert(P.read(1).name=='Gamma')
fail='write';assert(not P.write(1,P.new('Delta','nena')));fail=nil
assert(P.read(1).name=='Gamma','failed write preserves old profile')
fail='rename';assert(not P.write(1,P.new('Delta','nena')));fail=nil
assert(P.read(1).name=='Gamma','failed replace preserves old profile')
fail='read';local ok,v,e=pcall(P.read,1);assert(ok and not v and e,'read failure is reported');fail=nil
love={keyboard={setTextInput=function() end}}
local ui=setmetatable({stack={{kind='slots',sel=1}},t=0,game={audio={play=function() end},to_title=function()end}},UI)
files={};ui.slots=P.list();ui.edit_avatar=function(self) self.advanced=true end
ui:open_slot(1);ui:textinput('Prova');fail='write';ui:keypressed('return')
assert(ui:top().kind=='name' and not ui.advanced and ui.save_error,'failed create keeps draft')
fail=nil;ui:keypressed('return');assert(ui.advanced and P.read(1).name=='Prova','retry succeeds')
-- A disk read can fail between listing and opening the selected slot.
ui.stack={{kind='slots',sel=1}};ui.slots=P.list();fail='read';ui:open_slot(1)
assert(ui:top().kind=='slots' and ui.save_error,'failed read must not open a nil profile')
fail=nil
local Menu=require('src.ui.menu');local exited=false
local game={save_game=function()return false,'disk full'end,to_title=function()exited=true end}
local menu=Menu.new(game,'pause');local items=menu:items();items[#items][2]()
assert(not exited,'failed save must not leave game')
game.save_game=function()return true end;items[#items][2]();assert(exited)
-- padres, límite de amigos y duplicado de perfiles
files={}
local q=P.new('Nena','nena')
assert(q.parents.pare~='' and q.parents.mare~='','el jugador tiene padres por defecto')
assert(P.MAX_FRIENDS==12,'12 amigos y familiares')
for i=1,15 do q.friends[#q.friends+1]=P.new_friend(q,'amic') end
q.friends[1].parents={pare='Pau',mare='Rosa'}
assert(P.write(1,q))
local r=P.read(1)
assert(#r.friends==12,'el límite recorta a 12')
assert(r.friends[1].parents.pare=='Pau' and r.friends[1].parents.mare=='Rosa','padres del amigo se guardan')
assert(P.parents_of(r).pare==r.parents.pare and P.parents_of(r,r.friends[2]).pare==r.friends[2].parents.pare)
-- perfil antiguo sin parents: valores por defecto estables
local old=P.sanitize({name='Vell',friends={{id='f1',name='X',role='avi'}}})
assert(old.parents.pare and old.friends[1].parents.mare,'perfil sin parents se completa')
assert(P.sanitize({name='Vell',friends={{id='f1',name='X',role='avi'}}}).friends[1].parents.pare==old.friends[1].parents.pare,'defectos deterministas')
-- duplicar
files[P.dir(1)..'/save.json']='{"char_level":3}'
local dst=P.duplicate(1,false)
assert(dst==2 and P.read(2).name=='Nena 2' and #P.read(2).friends==12 and not files[P.dir(2)..'/save.json'],'duplicar sin partida')
local dst2=P.duplicate(1,true)
assert(dst2==3 and files[P.dir(3)..'/save.json']=='{"char_level":3}','duplicar con partida')
P.write(4,P.new('A','nena'));P.write(5,P.new('B','nena'))
local none,msg=P.duplicate(1,false)
assert(none==nil and msg,'sin ranura libre avisa')
print('profile_save_cases: OK')
