-- Composicions originals sintetitzades; cada tema té melodia, compàs i instrumentació propis.
local X={}
local function midi(n) return 440*2^((n-69)/12) end
local scores={
 bike={bpm=132,beats=8,kind='pulse',roots={50,55,47,57},mel={74,78,81,78,76,74,69,0,71,74,79,78,76,74,73,69}},
 horse={bpm=112,beats=6,kind='tri',roots={48,53,55,48},mel={72,76,79,0,76,74,77,81,79,77,76,72}},
 swim={bpm=74,beats=8,kind='tri',roots={50,53,48,55},soft=true,mel={74,0,81,0,78,0,76,0,72,0,79,0,76,0,74,0}},
 radio_pop={bpm=118,beats=8,kind='square',roots={48,45,53,55},mel={76,79,0,81,79,76,74,72,69,72,76,0,74,72,71,0}},
 radio_electro={bpm=140,beats=8,kind='saw',roots={45,41,48,43},mel={69,81,76,72,69,76,81,72,65,77,72,69,65,72,77,69}},
 radio_folk={bpm=100,beats=6,kind='pulse',roots={55,48,50,55},mel={79,76,74,71,74,76,72,76,79,81,79,76}},
 radio_chill={bpm=66,beats=8,kind='tri',roots={53,50,46,48},soft=true,mel={77,0,0,81,0,79,0,0,74,0,0,77,0,76,0,0}},
}
for id,score in pairs(scores) do
 local s=score
 X[id]=function()
  local notes,e={},30/s.bpm
  local function add(t,dur,n,kind,vol)
   notes[#notes+1]={t=t,dur=dur,freq=midi(n),kind=kind,vol=vol,decay=s.soft and 1.4 or .8}
  end
  for bar=0,15 do
   local root=s.roots[bar%4+1]
   for i=0,s.beats-1 do
    local t=(bar*s.beats+i)*e
    if i%2==0 then add(t,e*1.8,root-12+(i%4==2 and 7 or 0),'tri',s.soft and .12 or .18) end
    if i%2==1 then add(t,e*1.3,root+12+({0,4,7})[i%3+1],'tri',.045) end
    local n=s.mel[(bar*s.beats+i)%#s.mel+1]
    if n>0 then add(t,e*(s.soft and 2.8 or .85),n+(bar>=8 and (s.soft and -12 or 12) or 0),s.kind,s.kind=='saw' and .045 or .075) end
    if not s.soft then
     notes[#notes+1]={t=t,dur=.025,freq=1,kind='noise',vol=i%s.beats==0 and .065 or .018}
     if i%4==0 then notes[#notes+1]={t=t,dur=.09,freq=100,kind='tri',vol=.14,slide=-.65} end
    end
   end
  end
  return 16*s.beats*e,notes
 end
end
return X
