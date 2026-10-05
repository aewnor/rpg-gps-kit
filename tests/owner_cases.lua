local P=require('src.profile');local Save=require('src.save')
local files={};P.fs={exists=function(n)return files[n]~=nil end,read=function(n)return files[n]end,write=function(n,v)files[n]=v;return true end,remove=function(n)files[n]=nil;return true end}
assert(P.write(1,P.new('Local','nena')))
local old=P.path(1)
assert(P.set_owner('alpha'));assert(not P.read(1));assert(P.write(1,P.new('Alpha','nena')))
local alpha=P.path(1);assert(alpha~=old)
assert(P.set_owner('beta'));assert(not P.read(1));assert(P.write(1,P.new('Beta','nena')))
assert(P.set_owner('alpha'));assert(P.read(1).name=='Alpha')
assert(not P.set_owner(string.rep('x',65)));assert(P.read(1).name=='Alpha')
assert(P.set_owner(nil));assert(P.path(1)==old and P.read(1).name=='Local')
assert(P.set_owner('alpha'));assert(P.quick_dir()~=nil)
assert(P.set_owner(nil));assert(P.quick_dir()==nil)
love={system={getOS=function()return 'Linux'end}}
local Bridge=require('src.webui')
local game={scene={},state={},save_game=function()return false end,to_title=function()error('should not leave')end}
Bridge.handle(game,{type='owner',id='beta',request=1});assert(P.owner==nil,'failed save blocks owner switch')
local exited=false;game.save_game=function()return true end;game.to_title=function()exited=true;game.scene=nil end
Bridge.handle(game,{type='owner',id='beta',request=2});assert(P.owner=='beta' and exited)
assert(Save.DIR==P.quick_dir(),'quick saves isolated too')
P.set_owner(nil);Save.use(nil)
print('owner_cases: OK')
