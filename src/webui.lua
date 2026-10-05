-- Small web-only UI bridge. Native keyboard/gamepad remain the fallback.
local json=require('src.lib.json')
local Profile=require('src.profile')
local M={seq=0,name_seq=0,last=nil,zoom_last=nil}
local WEB=love and love.system and love.system.getOS()=='Web'
function M.emit(message)
  if not WEB then return end
  local f=io.open('/dev/rodaui','w')
  if f then f:write(json.encode(message)..'\n');f:close() end
end
function M.handle(game,m)
  if type(m)~='table' then return end
  local ui=game.menu
  local s=ui and ui.top and ui:top()
  if m.type=='motion' and type(m.reduced)=='boolean' then require('src.motion').set('system',m.reduced);return end
  if m.type=='tts_word' or m.type=='tts_end' then require('src.tts').event(m);return end   -- ressaltar el que es llegeix
  if m.type=='owner' then
    if m.id~=nil and (type(m.id)~='string' or #m.id==0 or #m.id>64) then return end
    local error
    if game.minigame then error='Acaba el minijoc abans de canviar.'
    elseif s and s.kind~='slots' then error='Desa o cancel·la l’edició abans de canviar.'
    elseif game.scene and game.state and not game:save_game(false) then error='No s’ha pogut desar. Torna-ho a provar.' end
    if error then M.emit({type='owner',request=m.request,ok=false,id=Profile.owner,error=error});return end
    if Profile.owner~=m.id then
      if game.scene or game.menu then game:to_title() end
      Profile.set_owner(m.id)
      require('src.save').use(Profile.quick_dir())
      M.last=nil
      require('src.sync').pull()   -- els perfils d'aquest jugador que hi hagi al servidor
    end
    M.emit({type='owner',request=m.request,ok=true,id=Profile.owner})
    return
  end
  if m.type=='text'  and s and s.kind=='name' and s.web_id and m.id==s.web_id then
    if m.action=='replace' or m.action=='confirm' then
      if type(m.value)~='string' or #m.value>256 then return end
      s.value=Profile.limit_name(m.value)
    end
    if m.action=='confirm' then ui:name_done(s)
    elseif m.action=='cancel' then ui:pop() end
  end
end
function M.sync(game)
  if not M.ready then M.ready=true;M.emit({type='ready',owner=Profile.owner}) end
  local ui=game.menu
  local s=ui and ui.top and ui:top()
  local msg={type='text',active=false}
  if s and s.kind=='name' then
    if not s.web_id then M.name_seq=M.name_seq+1;s.web_id=M.name_seq end
    msg={type='text',active=true,id=s.web_id,title=s.title,value=s.value,maxChars=Profile.NAME_MAX,error=ui.save_error}
  end
  local encoded=json.encode(msg)
  if encoded~=M.last then M.last=encoded;M.emit(msg) end
  -- botones táctiles de zoom: solo con un mapa abierto (mapa M, diario, selector de casa)
  local zoom=ui~=nil and (ui.screen=='map' or ui.view~=nil or (s~=nil and s.kind=='picker'))
  if zoom~=M.zoom_last then M.zoom_last=zoom;M.emit({type='zoom',active=zoom}) end
end
function M.update(game)
  if not WEB then return end
  for _=1,16 do
    local path='/tmp/rodaui_'..(M.seq+1)..'.json'
    local f=io.open(path,'r');if not f then break end
    local raw=f:read(16384);f:close();os.remove(path);M.seq=M.seq+1
    local ok,m=pcall(json.decode,raw or '')
    if ok then M.handle(game,m) end
    M.emit({type='ack',seq=M.seq})
  end
  M.sync(game)
end
return M
