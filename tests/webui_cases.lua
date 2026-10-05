love={system={getOS=function()return 'Linux'end},keyboard={setTextInput=function()end,isDown=function()return false end}}
local UI=require('src.ui.profiles')
local Bridge=require('src.webui')
local result
local ui=setmetatable({stack={{kind='slots',sel=1}},t=0,game={audio={play=function()end},to_title=function()end}},UI)
local game={menu=ui}
ui:ask_name('Nom','',function(v)result=v end)
Bridge.sync(game)
local id=ui:top().web_id
assert(id,'name session identifier')
Bridge.handle(game,{type='text',id=id+1,action='confirm',value='Other'})
assert(not result and ui:top().value=='','stale session ignored')
Bridge.handle(game,{type='text',id=id,action='replace',value='Àlex Ç'})
assert(ui:top().value=='Àlex Ç','full-value replace preserves Unicode')
Bridge.handle(game,{type='text',id=id,action='confirm',value='Àlex Ç'})
assert(result=='Àlex Ç' and ui:top().kind=='slots')
Bridge.handle(game,{type='text',id=id,action='confirm',value='Other'})
assert(result=='Àlex Ç','duplicate confirmation ignored')
ui:ask_name('Nom','',function()error('cancel submitted')end);Bridge.sync(game)
Bridge.handle(game,{type='text',id=ui:top().web_id,action='cancel'})
assert(ui:top().kind=='slots')
print('webui_cases: OK')
