-- Minijocs dels POIs (fase 4). Cada minijoc és un mòdul independent amb la mateixa interfície:
--   Mod.new(params, rng) → objecte;  obj:update(dt, act);  obj:draw(ui);  obj.done / obj.result
--   obj.sfx(nom) (opcional) per als efectes de so. La lògica no fa servir love.*: es prova amb luajit.
-- Aquest fitxer els llança des dels aparells dels interiors (objectes 'arcade' de src/world/procgen.lua),
-- porta els límits diaris del gimnàs i aplica els premis esportius.
--
--   Casino Municipal: restaurant i sala de teatre/cinema amb obres originals del joc
--   Poliesportiu / Camp de futbol: penalties (tanda de penals) i circuit (circuit d'agilitat amb bici/patinet)
--   Gimnàs: rhythm (pesos → força, bici estàtica → resistència, cinta → agilitat)
local Input = require('src.input')


local M = {}

local supported = { cinema=true, penalties=true, circuit=true, rhythm=true, recycle=true }
M.STAT_MAX = 10
-- música de cada minijoc (src/audio.lua: 'none' = silenci, el ritme porta el seu metrònom)
M.MUSIC = { rhythm = 'none', cinema = 'none' }

-- comptadors del dia (es reinicien quan canvia state.day)
function M.daily(st)
  local d = st.day or 1
  st.minigames = st.minigames or {}
  local m = st.minigames
  if m.day ~= d then
    m.day = d
    m.trained = {}
  end
  m.tokens, m.bonus_tokens, m.roulette = nil, nil, nil -- retire legacy balances
  m.trained = m.trained or {}
  return m
end

-- ---------------------------------------------------------------- llançar i fer córrer
function M.start(game, id, params, on_end)
  if not supported[id] then return nil end
  local Mod = require('src.minigames.' .. id)
  local mg = Mod.new(params or {}, love.math.random)
  mg.sfx = function(n) game.audio.play(n) end
  game.minigame = { id = id, mg = mg, on_end = on_end, fade = 0 }
  game.audio.ctx = game.audio.ctx or {}
  game.audio.ctx.minigame = M.MUSIC[id] or 'arcade'
  Input.clear()
  return mg
end

function M.update(game, dt, act)
  local r = game.minigame
  r.fade = math.min(1, r.fade + dt * 5)
  r.mg:update(dt, act)
  if r.mg.done then
    game.minigame = nil
    if game.audio.ctx then game.audio.ctx.minigame = nil end
    Input.clear()
    if r.on_end then r.on_end(r.mg.result or {}) end
  end
end

function M.draw(game)
  local r = game.minigame
  love.graphics.push('all')
  r.mg:draw({ font = game.font, sprites = game.sprites })
  love.graphics.pop()
  if r.fade < 1 then   -- entrada amb fos des de negre
    love.graphics.setColor(0, 0, 0, 1 - require('src.motion').ease(r.fade))
    love.graphics.rectangle('fill', 0, 0, 320, 240)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- ---------------------------------------------------------------- des dels aparells (World:interact)
-- w: World; props: { game, stat, label } de l'objecte 'arcade'
function M.launch(w, props)
  local st = w.state
  local m = M.daily(st)
  local id = props.game
  if not supported[id] then return false end
  local params = { label = props.label, mode = props.mode }
  if id == 'rhythm' then
    params.stat = props.stat
    params.already = m.trained[props.stat] or (st.train[props.stat] or 0) >= M.STAT_MAX
  elseif id == 'circuit' then
    params.vehicle = (st.vehicles and st.vehicles.patinete) and 'patinete' or 'bici'
  end
  w.game.audio.play('confirm')
  M.start(w.game, id, params, function(res) M.apply(w, id, props, res) end)
  return true
end

-- premis en acabar (experiència i monedes per World:reward, que ja fa els números flotants i el so)
function M.apply(w, id, props, res)
  if not supported[id] then return false end
  if id == 'cinema' then return true end
  local st = w.state
  local m = M.daily(st)
  local b = w.player.body
  local function party(n) w.fx:preset('confetti', b.x, b.y - 14, n or 20); w.fx:preset('sparkle', b.x, b.y - 10, 8) end
  if id == 'penalties' then
    if (res.shots or 0) > 0 then
      local g = res.goals or 0
      w:reward(g * 12, g * 2, string.format('Penals: %d de %d', g, res.shots))
      if res.perfect then
        st.gems = (st.gems or 0) + 1
        w.hud:toast('Pleníssim! +1 gemma', 2.5)
        party(30)
      elseif g >= 3 then party(12) end
    end
  elseif id == 'circuit' then
    if res.finished then
      local xp = 10 + (res.passed or 0) * 2
      local coins = res.under_par and 8 or 2
      w:reward(xp, coins, string.format('Circuit: %.1f s', res.time))
      if res.perfect and res.under_par then
        if not m.circuit_bonus then
          m.circuit_bonus = true
          st.gems = (st.gems or 0) + 1
          w.hud:toast('Circuit perfecte i sota el rècord! +1 gemma', 3)
        end
        party(26)
      end
      st.minigames.circuit_best = math.min(st.minigames.circuit_best or math.huge, res.time)
    end
  elseif id == 'rhythm' then
    if res.finished then
      local k = res.stat
      w:reward(math.floor((res.pct or 0) * 30), 0)
      if res.passed and not m.trained[k] and (st.train[k] or 0) < M.STAT_MAX then
        m.trained[k] = true
        st.train[k] = (st.train[k] or 0) + 1
        local name = ({ strength = 'Força', resistance = 'Resistència', agility = 'Agilitat' })[k]
        w:popup(name .. ' +1', 'stat', b.x, b.y - 12)
        w.hud:toast(name .. ' +1 (' .. st.train[k] .. '/' .. M.STAT_MAX .. ')', 2.5)
        w.game.audio.play('levelup')
        party(18)
      elseif res.passed then
        w.hud:toast('Bona sessió! (l\'estadística ja ha pujat avui)', 2.5)
      end
    end
  end
end

return M
