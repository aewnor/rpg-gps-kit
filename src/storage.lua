-- JSON durability shared by profiles and saves. Native replace is atomic; web copy keeps a verified backup.
local json = require('src.lib.json')
local S = {}
function S.filesystem()
  return {
    exists = function(n) return love.filesystem.getInfo(n) ~= nil end,
    read = function(n) return love.filesystem.read(n) end,
    write = function(n,d)
      local dir=n:match('^(.*)/[^/]+$'); if dir then love.filesystem.createDirectory(dir) end
      return love.filesystem.write(n,d)
    end,
    remove = function(n) return love.filesystem.remove(n) end,
    rename = function(a,b)
      local base=love.filesystem.getSaveDirectory()
      local ok,v=pcall(os.rename,base..'/'..a,base..'/'..b)
      if ok and v then return true end
      local data=love.filesystem.read(a)
      if data and love.filesystem.write(b,data) then love.filesystem.remove(a); return true end
      return false
    end,
  }
end
-- Web: love.js keeps saves in memory until IndexedDB is synced; web/persist.js flushes on this message.
function S.flush_web()
  if not (love and love.system and love.system.getOS()=='Web') then return end
  local f=io.open('/dev/rodaui','w')
  if f then f:write('{"type":"saved"}\n');f:close() end
end
function S.read(f,n,validate)
  local ok,v,err=pcall(function()
    if not f.exists(n) then return nil,nil end
    local raw=f.read(n); if not raw then return nil,'No es pot llegir el fitxer' end
    local good,data=pcall(json.decode,raw)
    if not good or not validate(data) then return nil,'Fitxer danyat o versió incompatible' end
    return data
  end)
  if not ok then return nil,'Error de lectura' end
  return v,err
end
function S.write(f,n,tmp,bak,data,validate)
  local ok,v,err=pcall(function()
    local raw=json.encode(data,true)
    if not validate(data) then return false,'Dades no vàlides' end
    if not f.write(tmp,raw) or not S.read(f,tmp,validate) then return false,'No es pot desar el temporal' end
    local old,why=S.read(f,n,validate)
    -- A broken primary must never replace the last valid backup.
    if old then
      local btmp=bak..'.tmp'
      if not f.write(btmp,json.encode(old,true)) or not S.read(f,btmp,validate) then return false,'No es pot crear la còpia' end
      local replaced = f.rename and f.rename(btmp,bak) or (not f.rename and f.write(bak,f.read(btmp)))
      if not replaced then return false,'No es pot conservar la còpia' end
      if f.remove then f.remove(btmp) end
    elseif why and not S.read(f,bak,validate) then
      return false,'Fitxer danyat: conserva’l i recupera una còpia abans de desar'
    end
    local replaced = f.rename and f.rename(tmp,n) or (not f.rename and f.write(n,raw))
    if not replaced then return false,'No es pot substituir el guardat' end
    if not S.read(f,n,validate) then return false,'No es pot verificar el guardat; còpia conservada' end
    if f.remove then f.remove(tmp) end
    S.flush_web()
    return true
  end)
  if not ok then return false,'Error en desar; torna-ho a provar' end
  return v,err
end
return S
