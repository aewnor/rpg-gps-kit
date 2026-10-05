package.path='./?.lua;./?/init.lua;'..package.path
local A=require('src.audio')
assert(A.pick{outdoor=true,vehicle='bici'}=='bike','bici propia')
assert(A.pick{outdoor=true,vehicle='cavall'}=='horse','caballo propio')
assert(A.pick{outdoor=true,swimming=true}=='swim','nadar propio')
local Radio=require('src.systems.radio')
local st={inventory={}}
assert(not Radio.tune(st,'radio_pop'),'locked before finding radio')
st.inventory.radio=1
for _,station in ipairs(Radio.STATIONS) do
 assert(Radio.tune(st,station.track))
 assert(A.pick{radio=Radio.track(st),vehicle='bici',outdoor=true}==station.track)
 assert(A.pick{radio=station.track,minigame='none'}==nil,'rhythm takes precedence')
 local len,notes=A.SONGS[station.track]();assert(len>=16 and #notes>40)
 for _,n in ipairs(notes) do assert(n.t>=0 and n.t<len and n.dur>0 and n.freq>0) end
end
assert(not Radio.tune(st,'bad_station'))
assert(Radio.tune(st,nil) and Radio.track(st)==nil)
for _,id in ipairs({'bike','horse','swim'}) do local len,notes=A.SONGS[id]();assert(len>=16 and #notes>40) end
print('RADIO CASES OK')
-- Carga de opciones antiguas y datos fuera de rango sin tocar disco real.
local J=require('src.lib.json');local stored=J.encode({tts={on=false},audio={master=9,music=-2,effects=.3}})
love={filesystem={getInfo=function() return true end,read=function() return stored end,write=function(_,v) stored=v;return true end}}
local S=require('src.settings');local s=S.load()
assert(s.audio.master==1 and s.audio.music==0 and s.audio.effects==.3 and not s.tts.on)
s.audio.custom=true;s.audio.master=.2;S.save();assert(S.load().audio.master==.2)
stored='{"tts":{"on":false}}';s=S.load();assert(s.audio.master==.6 and not s.audio.custom)
A.configure(s,{volum=.4,volum_musica=.2});assert(A.volume==.4 and A.music_volume==.2)
s.audio.custom=true;s.audio.master=0;A.configure(s,{volum=1});assert(A.volume==0)
print('VOLUME SETTINGS OK')
