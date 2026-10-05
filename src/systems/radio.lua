-- La ràdio és un objecte de la partida; l'emissora escollida es desa amb el perfil.
local R={}
R.STATIONS={
 {track='radio_pop',name='88.4 · Ràdio Pop'},
 {track='radio_electro',name='93.2 · Ona Electrònica'},
 {track='radio_folk',name='101.6 · Camins Folk'},
 {track='radio_chill',name='107.8 · Mar en Calma'},
}
function R.has(st) return st and st.inventory and (st.inventory.radio or 0)>0 end
function R.valid(id) for _,s in ipairs(R.STATIONS) do if s.track==id then return true end end return false end
function R.track(st) return R.has(st) and R.valid(st.radio_station) and st.radio_station or nil end
function R.tune(st,id)
 if not R.has(st) or (id~=nil and not R.valid(id)) then return false end
 st.radio_station=id;return true
end
function R.open(g)
 if not R.has(g.state) then
  g:open_list('Ràdio de butxaca',{{'On es troba?',function()
   g:close_menu();g.scene.dialogue:show('Una ràdio per descobrir',{'Hi ha un cofre amb una ràdio al Casino.','Busca al menjador, a prop del taulell. Després podràs sintonitzar-la des de Personatge.'})
  end}});return
 end
 local current=R.track(g.state)
 local rows={{(not current and '> ' or '')..'Apagada · música del lloc',function()
  R.tune(g.state,nil);g:close_menu();g.scene:update_audio({});g.hud:toast('Ràdio apagada',2)
 end}}
 for _,station in ipairs(R.STATIONS) do
  local s=station
  rows[#rows+1]={(current==s.track and '> ' or '')..s.name,function()
   R.tune(g.state,s.track);g.audio.request(s.track);g:close_menu();g.scene:update_audio({});g.hud:toast(s.name,3)
  end}
 end
 rows[#rows+1]={'Volum i so',function() g:open_audio_options(false) end}
 g:open_list('FM · Ràdio de butxaca',rows)
end
return R
