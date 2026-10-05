local replies,threads={},{}
local now=0
love={system={getOS=function()return 'Linux'end},timer={getTime=function()return now end},thread={}}
love.thread.getChannel=function(name)
 return {pop=function()return table.remove(replies,1)end}
end
love.thread.newThread=function() local t={};function t:start(id)self.id=id;threads[id]=self end;function t:isRunning()return true end;return t end
local Net=require('src.net')
local called=0;local id=Net.post('/api/npc_chat',{},function()called=called+1 end)
Net.cancel(id);replies[1]={id=id,raw='{"reply":"late"}'};Net.update(0)
assert(#replies==0 and called==0,'cancelled native replies drained, no callback')
for i=1,8 do assert(Net.post('/api/npc_chat',{},function()end)) end
local extra=Net.post('/api/npc_chat',{},function(v,e)assert(not v and e);called=called+1 end)
assert(not extra and called==1,'pending calls bounded')
Net.cancel_all();now=30;Net.update(0)
assert(next(Net.pending)==nil)
print('net_cases: OK')
