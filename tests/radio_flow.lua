return function(api)
 local g=api.scene().game
 g.dev.turbo=1
 local A=g.audio
 local R=require('src.systems.radio')
 local S=require('src.settings')
 local Input=require('src.input')
 g.settings.audio={custom=false,master=.6,music=.45,effects=1}
 S.data=g.settings;A.configure(g.settings)
 local function shot(name)
  api.wait(2)
  love.graphics.captureScreenshot(function(d) d:encode('png',name..'.png') end);api.wait(2)
 end
 R.open(g)
 api.check(g.menu.title=='Ràdio de butxaca','ràdio bloquejada abans de trobar-la')
 g:close_menu()
 local pep
 for _,n in ipairs(api.scene().npcs) do if n.props.service_id=='casino' then pep=n;break end end
 api.teleport(math.floor(pep.body.x/16),math.floor(pep.body.y/16)+1);api.player().facing='up'
 api.wait(2);api.press('confirm');api.wait(3);g.menu.list[1][2]();api.wait(40)
 local chest
 for _,c in ipairs(api.scene().chests) do if c.obj.props.item=='radio' then chest=c end end
 api.check(chest~=nil,'cofre de la ràdio al Casino')
 api.teleport(chest.rect.x/16,chest.rect.y/16+1);api.player().facing='up';api.wait(2);api.press('confirm');api.wait(4)
 api.check(R.has(api.state()),'trobar ràdio dóna objecte persistent')
 shot('radio-found')
 for _=1,8 do api.press('confirm');api.wait(2) end
 R.open(g);shot('radio-stations')
 g.menu.list[3][2]();api.wait(3)
 api.check(R.track(api.state())=='radio_electro' and A.pick(A.ctx)=='radio_electro','sintonitzar emissora des del menú')
 api.check(g:save_game(false),'guardar ràdio i emissora')
 g:continue_game();api.wait(40)
 api.check(R.has(api.state()) and R.track(api.state())=='radio_electro','continuar conserva objecte i emissora')
 g:open_audio_options(false)
 g.menu.list[1].adjust(-1)
 api.check(A.volume==0,'volum general arriba a zero')
 api.press('right');api.wait(3)
 api.check(math.abs(A.volume-.1)<.001,'dreta augmenta volum amb control mòbil')
 api.press('left');api.wait(3)
 api.check(A.volume==0,'esquerra redueix volum')
 g.menu.list[1].adjust(.6);g.menu.list[2].adjust(-1);g.menu.list[3].adjust(-.7)
 api.check(A.music_volume==0 and math.abs(A.effects_volume-.3)<.001,'controls independents')
 local restored=S.load()
 api.check(restored.audio.custom and restored.audio.music==0 and math.abs(restored.audio.effects-.3)<.001,'volums persistents en disc')
 g.settings=restored
 g:apply_config{volum=1,volum_musica=1}
 api.check(A.volume==.6 and A.music_volume==0,'config del servidor no trepitja preferència local')
 g:open_audio_options(false);shot('radio-volume')
 g:close_menu()
 R.tune(api.state(),nil);api.scene():update_audio({})
 api.check(A.pick(A.ctx)=='day','apagar ràdio recupera música del lloc')
 -- Verifica el context real de desplaçament, sense dependre d'una ruta pel mapa.
 local sc=api.scene();local old=sc.def.outdoor;sc.def.outdoor=true
 for _,id in ipairs({'bici','cavall'}) do
  sc.player.vehicle={id=id,speed=0};sc:update_audio({})
  api.check(A.pick(A.ctx)==(id=='bici' and 'bike' or 'horse'),'música del vehicle '..id)
 end
 sc.player.vehicle=nil;sc.player.swimming=true;sc:update_audio({})
 api.check(A.pick(A.ctx)=='swim','música de natació')
 sc.player.swimming=nil;sc.def.outdoor=old
 for _,id in ipairs({'bike','horse','swim','radio_pop','radio_electro','radio_folk','radio_chill'}) do A.request(id) end
 A.finish_all()
 for _,id in ipairs({'bike','horse','swim','radio_pop','radio_electro','radio_folk','radio_chill'}) do
  api.check(A.music[id] and A.music[id].src:getDuration()>16,'àudio sintetitzat: '..id)
 end
 print('RADIO FLOW OK')
end
