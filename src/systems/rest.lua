-- Menjar i dormir (item 11). Lua pur excepte el dibuix (love.graphics només a Rest.draw*).
--
-- API per als interiors (src/systems/family.lua ja la crida; qualsevol llit/nevera nou només l'ha de cridar):
--   Rest.sleep(w)         llit: pantalla negra «Zzz…», passen 8 h de joc (Daylight.skip), cura vida i MP, els
--                         personatges amb horari van al lloc que els toca, i es desa la partida. w = World.
--   Rest.eat(w [, dish])  nevera: plat de casa (dish = { name, hp, mp } fraccions del màxim, o un id de Rest.HOME);
--                         cooldown de 2 h de joc. Cura segons el plat.
--   Rest.restaurant(w, n, sv)  menú d'un restaurant (servei kind = 'restaurant' de data/services.json).
--   Rest.use_medkit(w)    tecla G: gasta un Botiquí (o, si no, una Farmaciola) de la motxilla.
--   Rest.attach(w) / Rest.interact(w, fx, fy) / Rest.can_interact(w, fx, fy) / Rest.draw_kits(w, add):
--                         botiquins de paret als interiors (cases, escola) i objectes de mapa type = 'medkit',
--                         'bed' i 'fridge' (props opcionals). Un cop al dia de joc per botiquí.
--   Rest.update(w, dt) -> true si la pantalla de dormir bloqueja el joc · Rest.draw(w)
local Rest = {}

local Daylight = require('src.systems.daylight')

Rest.SLEEP_MINUTES = 480
Rest.EAT_COOLDOWN = 120          -- minuts de joc entre dos àpats de casa
Rest.FADE_OUT, Rest.HOLD, Rest.FADE_IN = 0.9, 1.8, 0.9

-- plats de casa: hp/mp = fracció del màxim que recuperen
Rest.HOME = {
  truita = { name = 'Truita de patates', hp = 0.35, mp = 0.25 },
  macarrons = { name = 'Macarrons', hp = 0.45, mp = 0.2 },
  escudella = { name = 'Escudella', hp = 0.5, mp = 0.35 },
  iogurt = { name = 'Iogurt i fruita', hp = 0.2, mp = 0.3 },
  pa_tomaquet = { name = 'Pa amb tomàquet', hp = 0.3, mp = 0.15 },
}
local HOME_ORDER = { 'truita', 'macarrons', 'escudella', 'iogurt', 'pa_tomaquet' }

-- menús dels restaurants: { plat, preu, hp, mp }
Rest.MENUS = {
  cat = {
    { 'Truita de patates', 8, 0.4, 0.2 },
    { 'Escudella i carn d\'olla', 14, 0.7, 0.4 },
    { 'Menú del dia', 24, 1, 1 },
  },
  wok = {
    { 'Nous de wok', 9, 0.4, 0.25 },
    { 'Arròs tres delícies', 14, 0.65, 0.4 },
    { 'Menú de l\'Oki', 24, 1, 1 },
  },
  mar = {
    { 'Musclos al vapor', 10, 0.4, 0.3 },
    { 'Fideuà', 16, 0.75, 0.5 },
    { 'Suquet de peix', 26, 1, 1 },
  },
}

local function ceil_frac(max, f) return math.ceil((max or 0) * f) end

-- aplica un plat (fraccions del màxim); torna (hp guanyat, mp guanyat)
function Rest.heal(st, hp_frac, mp_frac)
  local h0, m0 = st.hp, st.mp or 0
  st.hp = math.min(st.max_hp, st.hp + ceil_frac(st.max_hp, hp_frac or 0))
  if st.max_mp then st.mp = math.min(st.max_mp, (st.mp or 0) + ceil_frac(st.max_mp, mp_frac or 0)) end
  return st.hp - h0, (st.mp or 0) - m0
end

function Rest.now(st) return (st.day or 1) * 1440 + (st.clock or 600) end

local function toast(w, text, dur) if w.hud then w.hud:toast(text, dur or 2.5) end end

-- ---------------------------------------------------------------- nevera / àpats
function Rest.eat(w, dish)
  local st = w.state
  if st.hp >= st.max_hp and (st.mp or 0) >= (st.max_mp or 0) then
    toast(w, 'No tens gana: ja estàs ben carregada', 2); return false
  end
  local now = Rest.now(st)
  if st.family_fed and now - st.family_fed < Rest.EAT_COOLDOWN then
    toast(w, 'Ja has menjat fa poc', 2); return false
  end
  if type(dish) == 'string' then dish = Rest.HOME[dish] end
  if not dish then
    local k = HOME_ORDER[(math.floor(now / 60) + (st.char_level or 1)) % #HOME_ORDER + 1]
    dish = Rest.HOME[k]
  end
  st.family_fed = now
  local dh, dm = Rest.heal(st, dish.hp, dish.mp)
  if w.game and w.game.audio then w.game.audio.play('talk') end
  toast(w, string.format('%s: +%d vida, +%d MP', dish.name, dh, dm), 3)
  return true
end

function Rest.restaurant(w, n, sv)
  local st, g = w.state, w.game
  local menu = Rest.MENUS[sv and sv.menu or 'cat'] or Rest.MENUS.cat
  local items = {}
  for _, d in ipairs(menu) do
    local name, price, hp, mp = d[1], d[2], d[3], d[4]
    items[#items + 1] = { string.format('%s  %d mon.', name, price), function()
      g:close_menu()
      if st.hp >= st.max_hp and (st.mp or 0) >= (st.max_mp or 0) then
        w.dialogue:show(n.props.say_name, { 'Ja estàs tipa! Torna quan tinguis gana.' }); return
      end
      if not require('src.systems.rpg').pay(st, price) then toast(w, 'No tens prou monedes (' .. price .. ')', 2); return end
      local dh, dm = Rest.heal(st, hp, mp)
      g.audio.play('chest')
      w.dialogue:show(n.props.say_name, { string.format('Bon profit! %s.', name), string.format('+%d vida, +%d MP', dh, dm) })
    end }
  end
  items[#items + 1] = { 'Res, gràcies', function() g:close_menu() end }
  g:open_list(sv and sv.label or 'Restaurant', items)
end

-- ---------------------------------------------------------------- botiquins
-- tecla G: gasta un Botiquí o, si no en té, una Farmaciola
function Rest.use_medkit(w)
  local st, g = w.state, w.game
  local Rpg = require('src.systems.rpg')
  for _, id in ipairs({ 'botiqui', 'farmaciola' }) do
    if (st.inventory[id] or 0) > 0 then
      local msg = Rpg.use(st, g.items, id, w.player)
      if msg then toast(w, msg, 2.5); g.audio.play('chest') end
      return msg ~= nil
    end
  end
  toast(w, 'No tens cap botiquí', 2)
  return false
end

-- un botiquí gratis al dia en un servei (CAP, comissaria): torna true si se'l dona
function Rest.free_kit(w, key)
  local st = w.state
  st.missions = st.missions or {}
  st.missions.kit_day = st.missions.kit_day or {}
  local today = st.day or 1
  if st.missions.kit_day[key] == today then return false end
  st.missions.kit_day[key] = today
  st.inventory.botiqui = (st.inventory.botiqui or 0) + 1
  return true
end

local KIT_KINDS = { house = true, flat = true, upper = true, school = true, landing = false }

local function spec_of(w)
  local gen = w.game and w.game.generated
  return gen and gen[w.id] and gen[w.id].spec or nil
end

-- botiquins de paret: objectes del mapa type = 'medkit' + un a cada interior generat de casa/pis/escola
function Rest.attach(w)
  w.medkits, w.beds_fridges, w.fountains = {}, {}, {}
  for _, o in ipairs(w.map.objects or {}) do
    if o.type == 'medkit' then
      w.medkits[#w.medkits + 1] = { name = o.name or ('medkit_' .. #w.medkits), x = o.x, y = o.y }
    elseif o.type == 'fountain' then
      w.fountains = w.fountains or {}
      w.fountains[#w.fountains + 1] = { x = o.x, y = o.y }
    elseif o.type == 'bed' or o.type == 'fridge' then
      w.beds_fridges[#w.beds_fridges + 1] = { kind = o.type, x = o.x + (o.w or 0) / 2, y = o.y + (o.h or 0) / 2, dish = o.props and o.props.dish }
    end
  end
  local spec = spec_of(w)
  if spec and KIT_KINDS[spec.kind] and spec.structures then
    -- primera cel·la de paret amb terra buit a sota, triada per la mida de l'interior (determinista)
    local cands = {}
    for x = 1, spec.w - 2 do
      for y = 1, 2 do
        local s = spec.structures[y * spec.w + x + 1] or ''
        local below = spec.structures[(y + 1) * spec.w + x + 1] or ''
        if s == 'i_wall' and below == '' then cands[#cands + 1] = { x, y } end
      end
    end
    if #cands > 0 then
      local c = cands[(spec.w * 7 + spec.h * 3) % #cands + 1]
      w.medkits[#w.medkits + 1] = { name = 'medkit_wall', x = c[1] * 16 + 8, y = c[2] * 16 + 8 }
    end
  end
end

local function near(w, fx, fy, x, y, r) return (x - fx) ^ 2 + (y - fy) ^ 2 < r * r end

function Rest.can_interact(w, fx, fy)
  for _, k in ipairs(w.medkits or {}) do if near(w, fx, fy, k.x, k.y + 4, 15) then return true end end
  for _, o in ipairs(w.beds_fridges or {}) do if near(w, fx, fy, o.x, o.y, 16) then return true end end
  return false
end

function Rest.interact(w, fx, fy)
  if w.rest_fx then return true end
  for _, o in ipairs(w.beds_fridges or {}) do
    if near(w, fx, fy, o.x, o.y, 16) then
      if o.kind == 'bed' then Rest.sleep(w) else Rest.eat(w, o.dish) end
      return true
    end
  end
  for _, f in ipairs(w.fountains or {}) do   -- font d'aigua: un glop fresc, +1 cor (com a molt un cop per minut)
    if near(w, fx, fy, f.x, f.y, 16) then
      local st = w.state
      if (st.sim_time or 0) - (w.drank_at or -999) < 60 then
        toast(w, 'Ja has begut fa poc. Aigua fresqueta!', 2)
      else
        w.drank_at = st.sim_time or 0
        st.hp = math.min(st.max_hp, st.hp + 2)
        toast(w, 'Glop d\'aigua fresca: +1 cor', 2)
        w.game.audio.play('swim')
      end
      return true
    end
  end
  for _, k in ipairs(w.medkits or {}) do
    if near(w, fx, fy, k.x, k.y + 4, 15) then
      w.sstate.kits = w.sstate.kits or {}
      local today = w.state.day or 1
      if w.sstate.kits[k.name] == today then
        toast(w, 'El botiquí és buit. Demà en tindrà un altre.', 2.5)
      else
        w.sstate.kits[k.name] = today
        w.state.inventory.botiqui = (w.state.inventory.botiqui or 0) + 1
        toast(w, '+1 Botiquí', 2)
        w.game.audio.play('chest')
      end
      return true
    end
  end
  return false
end

-- caixa blanca amb creu vermella a la paret (s'afegeix a la llista d'entitats de World:draw)
function Rest.draw_kits(w, add, ox, oy)
  local today = w.state.day or 1
  local got = w.sstate and w.sstate.kits or {}
  for _, k in ipairs(w.medkits or {}) do
    if w.cam:visible(k.x - 8, k.y - 8, 16, 16, 0) then
      add(k.y + 6, function()
        local x, y = math.floor(k.x - ox), math.floor(k.y - oy)
        love.graphics.setColor(0.93, 0.93, 0.9); love.graphics.rectangle('fill', x - 5, y - 4, 10, 9)
        love.graphics.setColor(0.35, 0.33, 0.4); love.graphics.rectangle('line', x - 4.5, y - 3.5, 9, 8)
        if got[k.name] == today then love.graphics.setColor(0.6, 0.6, 0.6) else love.graphics.setColor(0.85, 0.15, 0.15) end
        love.graphics.rectangle('fill', x - 1, y - 3, 2, 7); love.graphics.rectangle('fill', x - 3, y - 1, 6, 2)
        love.graphics.setColor(1, 1, 1)
      end)
    end
  end
end

-- ---------------------------------------------------------------- dormir
-- els personatges amb horari van al lloc que els toca a la nova hora (sense veure'ls caminar)
function Rest.refresh_npcs(w)
  local Town = require('src.systems.town')
  local Schedule = require('src.systems.schedule')
  local st = w.state
  for _, n in ipairs(w.npcs or {}) do
    local r = n.routine
    if r and r.kind ~= 'patrol' then
      local place = Schedule.place(r.kind, st.clock, st.day)
      r.place, r.tick, r.path = place, 0, nil
      local ok, goal = pcall(Town.place_pos, w, n, place)
      if ok and goal and not goal.raw then
        r.goal = goal
        n.body.x, n.body.y = goal[1], goal[2]
        if n.sync_blocker then n:sync_blocker() end
      end
      n.walk = nil
      n.hidden = Schedule.hidden(place)
    end
  end
end

function Rest.sleep(w)
  if w.rest_fx then return false end
  w.rest_fx = { t = 0, applied = false }
  if w.game and w.game.audio then w.game.audio.play('door') end
  return true
end

-- «Esperar» (menú de pausa): passa `minutes` de rellotge amb la mateixa fosa de dormir, sense curar
function Rest.wait(w, minutes)
  if w.rest_fx or not (minutes and minutes > 0) then return false end
  w.rest_fx = { t = 0, applied = false, wait = minutes }
  return true
end

local function apply_wait(w, minutes)
  Daylight.skip(w.state, minutes)
  Rest.refresh_npcs(w)
  if w.game and w.game.save_game then pcall(w.game.save_game, w.game, false) end
end

local function apply_sleep(w)
  local st = w.state
  st.hp = st.max_hp
  if st.max_mp then st.mp = st.max_mp end
  if w.player then w.player.stamina = w.player.max_stamina or w.player.stamina end
  Daylight.skip(st, Rest.SLEEP_MINUTES)
  st.family_fed = nil
  Rest.refresh_npcs(w)
  if w.game and w.game.save_game then pcall(w.game.save_game, w.game, false) end
end

-- true mentre dura la pantalla de dormir (el joc queda aturat)
function Rest.update(w, dt)
  local fx = w.rest_fx
  if not fx then return false end
  fx.t = fx.t + dt
  if not fx.applied and fx.t >= Rest.FADE_OUT then
    fx.applied = true
    if fx.wait then apply_wait(w, fx.wait) else apply_sleep(w) end
  end
  if fx.t >= Rest.FADE_OUT + Rest.HOLD + Rest.FADE_IN then
    w.rest_fx = nil
    if fx.wait then toast(w, 'Ha passat el temps. Són les ' .. Daylight.label(w.state.clock) .. '.', 4); return true end
    toast(w, 'Has dormit 8 hores: ' .. Daylight.label(w.state.clock) .. '. Vida i MP al màxim!', 4)
  end
  return true
end

function Rest.draw(w)
  local fx = w.rest_fx
  if not fx then return end
  local t = fx.t
  local a
  if t < Rest.FADE_OUT then a = t / Rest.FADE_OUT
  elseif t < Rest.FADE_OUT + Rest.HOLD then a = 1
  else a = math.max(0, 1 - (t - Rest.FADE_OUT - Rest.HOLD) / Rest.FADE_IN) end
  love.graphics.setColor(0.04, 0.03, 0.09, a)
  love.graphics.rectangle('fill', 0, 0, 320, 240)
  if a > 0.5 then
    local n = 1 + math.floor(t * 2) % 3
    local z = fx.wait and ('Esperant' .. ('.'):rep(n)) or ('Z' .. ('z'):rep(n) .. '…')
    local f = w.game.font
    love.graphics.setColor(0.8, 0.85, 1, (a - 0.5) * 2)
    love.graphics.print(z, math.floor(160 - f:getWidth(z) / 2), 112)
  end
  love.graphics.setColor(1, 1, 1)
end

return Rest
