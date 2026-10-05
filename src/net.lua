-- Peticiones HTTP no bloqueantes al servidor del juego (tools/web_server.py), p. ej. /api/npc_chat.
--   · Web (love.js): no hay hilos ni sockets. index.html crea el dispositivo /dev/rodanet: lo que se
--     escribe ahí (una línea JSON) lo envía JavaScript con fetch y deja la respuesta en /tmp/rodanet_<id>.json.
--   · Escritorio: un love.thread con socket.http contra Net.base.
-- Siempre con tiempo límite: si no hay respuesta, cb(nil, 'timeout') y el juego sigue con su texto fijo.
local json = require('src.lib.json')

local Net = { pending = {}, threads = {}, seq = 0, base = 'http://127.0.0.1:8102' }
local WEB = love.system.getOS() == 'Web'

local THREAD = [[
local id, url, body = ...
require('love.thread')
local ok, res = pcall(function()
  local http = require('socket.http')
  local ltn12 = require('ltn12')
  http.TIMEOUT = 10
  local out = {}
  local _, code = http.request({ url = url, method = 'POST', sink = ltn12.sink.table(out),
    source = ltn12.source.string(body),
    headers = { ['Content-Type'] = 'application/json', ['X-Roda-Request'] = '1', ['Content-Length'] = tostring(#body) } })
  if code ~= 200 then return nil end
  return table.concat(out)
end)
love.thread.getChannel('roda_net_replies'):push({ id=id, raw=ok and res or '' })
]]

function Net.available()
  if WEB then
    local f = io.open('/dev/rodanet', 'w')
    if f then f:close() end   -- (antes se quedaba abierto en cada consulta)
    return f ~= nil
  end
  return pcall(require, 'socket.http')
end

function Net.post(path, body, cb, timeout)
  local count=0; for _ in pairs(WEB and Net.pending or Net.threads) do count=count+1 end
  if count>=8 then cb(nil,'massa peticions'); return end
  Net.seq = Net.seq + 1
  local id = tostring(Net.seq) .. '_' .. tostring(math.floor((love.timer.getTime() * 1000) % 1e9))
  local payload = json.encode(body)
  local ok = false
  if WEB then
    local f = io.open('/dev/rodanet', 'w')
    if f then
      f:write(json.encode({ id = id, path = path, body = body }) .. '\n')
      f:close()
      ok = true
    end
  else
    ok = pcall(function()
      local t = love.thread.newThread(THREAD)
      t:start(id, Net.base .. path, payload)
      Net.threads[id]=t
    end)
  end
  if not ok then cb(nil, 'sense connexió'); return end
  Net.pending[id] = { cb = cb, t0 = love.timer.getTime(), timeout = timeout or 15, keep = path ~= '/api/npc_chat' }
  return id
end

function Net.cancel(id)
  if not id then return end
  Net.pending[id]=nil
  if WEB then
    local f=io.open('/dev/rodanet','w')
    if f then f:write(json.encode({id=id,cmd='cancel'})..'\n');f:close() end
    os.remove('/tmp/rodanet_'..id..'.json')
  end
end
-- en tornar al títol: es descarten les converses (IA dels personatges) i res més: ni la sincronització de perfils
-- (src/sync.lua espera la resposta per alliberar Sync.pulling) ni la casa del plànol (/api/private_home) ni la
-- configuració, que es demanen en arrencar just quan el hub tria el jugador (si es perdien, la casa era genèrica)
function Net.cancel_all()
  local ids={};for id,p in pairs(Net.pending) do if not p.keep then ids[#ids+1]=id end end
  for _,id in ipairs(ids) do Net.cancel(id) end
end
local function deliver(id,raw)
  local p=Net.pending[id];Net.pending[id]=nil
  if not p then return end
  local ok,v=pcall(json.decode,raw or '')
  if ok and type(v)=='table' and not v.error then p.cb(v) else p.cb(nil,'resposta no vàlida') end
end
function Net.update(dt)
  if not WEB then
    local channel=love.thread.getChannel('roda_net_replies')
    for _=1,32 do
      local message=channel:pop();if not message then break end
      Net.threads[message.id]=nil;deliver(message.id,message.raw)
    end
    for id,t in pairs(Net.threads) do
      if not t:isRunning() then Net.threads[id]=nil end
    end
  end
  local ids={};for id in pairs(Net.pending) do ids[#ids+1]=id end
  for _,id in ipairs(ids) do
    local p=Net.pending[id]
    if p then
      if WEB then
        local name='/tmp/rodanet_'..id..'.json'
        local f=io.open(name,'r')
        if f then local raw=f:read('*a');f:close();os.remove(name);deliver(id,raw) end   -- (la còpia de perfils pot passar de 64 KB)
      end
      if Net.pending[id] and love.timer.getTime()-p.t0>p.timeout then Net.cancel(id);p.cb(nil,'timeout') end
    end
  end
end

return Net
