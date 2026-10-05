-- Perfils i partides entre aparells: el navegador de cada aparell els desa per separat (IndexedDB); aquí se'n
-- guarda una còpia al servidor de casa (tools/web_server.py, /api/sync/*) perquè el perfil creat al PC surti
-- també al mòbil. Per perfil (uid estable de src/profile.lua) guanya la versió més nova: el perfil per
-- `updated` i la partida per `saved_at`. Els esborrats deixen una marca perquè no tornin.
--   · Pujar: cada escriptura marca la ranura; Sync.update l'envia uns segons després (una a una).
--   · Baixar: en arrencar, en obrir la pantalla de perfils i en canviar de jugador del hub.
local json = require('src.lib.json')
local Storage = require('src.storage')

local Sync = { dirty = {}, wait = 0, busy = false, off = false, DELAY = 3, pulling = false }

local function Net() return require('src.net') end
local function Profile() return require('src.profile') end

function Sync.enabled()
  if Sync.off then return false end
  local ok, avail = pcall(function() return Net().available() end)
  return ok and avail
end

function Sync.mark(slot)
  if Sync.off or not slot then return end
  Sync.dirty[slot] = true
  Sync.wait = Sync.DELAY
end

local function save_path(slot) return Profile().dir(slot) .. '/save.json' end
local function fs() local P = Profile(); return P.fs or Storage.filesystem() end

local function read_save(slot)
  local f = fs()
  local raw = f.exists(save_path(slot)) and f.read(save_path(slot))
  if not raw then return nil end
  local ok, s = pcall(json.decode, raw)
  if ok and type(s) == 'table' then return s end
end

-- puja una ranura (perfil i partida)
local function push(slot, done)
  local P = Profile()
  local p = P.read(slot)
  if not p or not p.uid then done(); return end
  local disk = P.sanitize(p)
  disk.home_player_location, disk.home = disk.home, nil
  local save = read_save(slot)
  local body = { owner = P.owner or '', uid = p.uid, t = p.updated or 0, profile = disk }
  if save then body.save, body.save_t = save, tonumber(save.saved_at) or 0 end
  Net().post('/api/sync/push', body, function() done() end, 20)
end

function Sync.deleted(uid)
  if not Sync.enabled() then return end
  Net().post('/api/sync/delete', { owner = Profile().owner or '', uid = uid, t = os.time() }, function() end, 15)
end

-- cada fotograma (Game:update): envia les ranures pendents passat el retard
function Sync.update(dt)
  if Sync.off or Sync.busy or not next(Sync.dirty) then return end
  Sync.wait = Sync.wait - dt
  if Sync.wait > 0 or not Sync.enabled() then return end
  local slot = next(Sync.dirty)
  Sync.dirty[slot] = nil
  Sync.busy = true
  push(slot, function() Sync.busy = false; Sync.wait = 0.5 end)
end

-- aplica el que hi ha al servidor: perfils nous a ranures lliures, versions més noves a sobre, esborrats fora;
-- el que només és aquí (o és més nou aquí) es torna a pujar. busy_slot: la ranura que s'està jugant (no es toca)
function Sync.apply(res, busy_slot)
  local P = Profile()
  local remote = type(res.profiles) == 'table' and res.profiles or {}
  local deleted = type(res.deleted) == 'table' and res.deleted or {}
  local locals, changed = {}, false
  for i = 1, P.MAX_SLOTS do
    local p = P.read(i)
    if p then
      if not p.uid then p.uid = P.new_uid(); P.write(i, p) end   -- perfils d'abans: s'identifiquen i es pugen
      locals[p.uid] = { slot = i, p = p }
    end
  end
  for uid, r in pairs(remote) do
    if type(r) == 'table' and type(r.profile) == 'table' then
      local l = locals[uid]
      local rt, rst = tonumber(r.t) or 0, tonumber(r.save_t) or -1
      if not l then
        local slot = P.free_slot()
        if slot then
          local prof = r.profile
          prof.uid, prof.updated = uid, rt
          if P.write(slot, prof, true) then
            changed = true
            if type(r.save) == 'table' then
              local sp = save_path(slot)
              Storage.write(fs(), sp, sp:gsub('%.json$', '.tmp'), sp:gsub('%.json$', '.bak'), r.save,
                require('src.save').validate)
            end
          end
        end
      elseif l.slot ~= busy_slot then
        if rt > (l.p.updated or 0) then
          local prof = r.profile
          prof.uid, prof.updated = uid, rt
          if P.write(l.slot, prof, true) then changed = true end
        elseif (l.p.updated or 0) > rt then
          Sync.mark(l.slot)
        end
        local ls = read_save(l.slot)
        local lst = ls and tonumber(ls.saved_at) or -1
        if type(r.save) == 'table' and rst > lst then
          local sp = save_path(l.slot)
          if Storage.write(fs(), sp, sp:gsub('%.json$', '.tmp'), sp:gsub('%.json$', '.bak'), r.save,
              require('src.save').validate) then changed = true end
        elseif lst > rst then
          Sync.mark(l.slot)
        end
      end
    end
  end
  for uid, l in pairs(locals) do
    if not remote[uid] then
      local dt = tonumber(deleted[uid])
      if dt and dt >= (l.p.updated or 0) and l.slot ~= busy_slot then
        P.delete(l.slot, true); changed = true
      else
        Sync.mark(l.slot)
      end
    end
  end
  if changed then Storage.flush_web() end
  return changed
end

-- baixa del servidor; cb(changed) quan acaba (també sense connexió: changed = false). Si ja n'hi ha una en
-- curs (p. ex. la d'arrencar, i just després el hub tria el jugador), aquesta es fa quan acaba l'anterior: abans
-- es perdia i el mòbil no baixava els perfils del PC. Sync.on_change() s'avisa sempre que arriben canvis.
function Sync.pull(cb, busy_slot)
  cb = cb or function() end
  if not Sync.enabled() then cb(false); return end
  -- (una resposta perduda no pot deixar-ho encallat per sempre: passat el temps límit, es torna a demanar)
  if Sync.pulling and os.time() - (Sync.pull_t0 or 0) > 45 then Sync.pulling = false end
  if Sync.pulling then
    Sync.again = Sync.again or {}
    table.insert(Sync.again, { cb, busy_slot })
    return
  end
  Sync.pulling, Sync.pull_t0 = true, os.time()
  Sync.pull_seq = (Sync.pull_seq or 0) + 1
  local seq = Sync.pull_seq
  local owner = Profile().owner or ''
  Net().post('/api/sync/pull', { owner = owner }, function(res)
    if seq ~= Sync.pull_seq then return end   -- una de vella que ja s'havia donat per perduda
    Sync.pulling = false
    local changed = false
    if type(res) == 'table' and (Profile().owner or '') == owner then
      local ok, ch = pcall(Sync.apply, res, busy_slot)
      changed = ok and ch or false
    end
    if changed and Sync.on_change then pcall(Sync.on_change) end
    local again = Sync.again
    Sync.again = nil
    if again then   -- les que esperaven: una sola baixada més (amb el jugador d'ara) i s'avisa a tothom
      local last = again[#again]
      Sync.pull(function(ch2)
        cb(changed or ch2)
        for _, w in ipairs(again) do w[1](ch2) end
      end, last[2])
      return
    end
    cb(changed)
  end, 20)
end

return Sync
