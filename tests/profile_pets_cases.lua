local P=require('src.profile')
local UI=require('src.ui.profiles')
local Looks=require('src.paperdoll.looks')
local ui=setmetatable({},UI)
local p=P.new('Prova','nena')
local function rows(f)
 local found={}
 for _,r in ipairs(ui:editor_rows{mode='friend',target=f,look=Looks.sanitize(f.look)}) do found[r[1]]=r end
 return found
end
for _,role in ipairs({'avia','avi','amic','amiga'}) do
 local f=P.new_friend(p,role)
 local r=rows(f)
 assert((r.Pares~=nil)==(role~='avia' and role~='avi'),'parent editor visibility: '..role)
 assert(r['Té un gos'] and r['Té un gos'].value=='No','dog defaults off')
 r['Té un gos'].right()
 assert(f.interior.dog==true and rows(f)['Té un gos'].value=='Sí')
 local clean=P.sanitize{friends={f}}
 assert(clean.friends[1].interior.dog==true,'dog survives sanitizing')
 r['Té un gos'].left();assert(f.interior.dog==false,'dog can be removed')
end
local old=P.sanitize{friends={{id='f1',role='avia',interior={cat=true}}}}
assert(old.friends[1].interior.cat and old.friends[1].interior.dog==false,'old profiles keep cat, no surprise dog')
assert(P.sanitize{friends={{interior={dog='false'}}}}.friends[1].interior.dog==false,'strict boolean')
local f=P.new_friend(p,'avia');f.role='amiga';assert(rows(f).Pares,'changing role restores editor')
-- Real write/read path on an isolated in-memory filesystem.
local files={}
P.fs={exists=function(n)return files[n]~=nil end,read=function(n)return files[n] end,
 write=function(n,d)files[n]=d;return true end,remove=function(n)files[n]=nil;return true end,
 rename=function(a,b)files[b]=files[a];files[a]=nil;return true end}
f.interior.cat=true;f.interior.dog=true;p.friends={f}
assert(P.write(1,p));local loaded=assert(P.read(1))
assert(loaded.friends[1].interior.dog and loaded.friends[1].interior.cat,'both pets survive saving/reloading')
print('Profile UI, role changes and pets persistence OK')
