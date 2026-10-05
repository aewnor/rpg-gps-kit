-- Generador procedural de interiores (Lua puro, sin love.*: lo usan el juego y el editor vía
-- tools/procgen_cli.lua). Devuelve capas con NOMBRES de tile (data/tiles.json) y objetos, en el
-- mismo formato que los interiores del editor de zonas:
--   { w, h, name, ground = {...}, detail = {...}, structures = {...}, overhead = {...},
--     objects = { {type='exit', x, y}, {type='npc', ...} }, spawn = {x, y} }
-- Tipos: house (casa con salón, cocina, dormitorios y baño), block (portal de pisos),
-- shop (tienda con mostrador y estanterías). Misma semilla → mismo interior.
local P = {}

-- habitacions de cada interior generat (spec → llista), fora del spec perquè no acabi al JSON de l'editor
local ROOMS = setmetatable({}, { __mode = 'k' })
function P.rooms(spec) return ROOMS[spec] end

local function rng(seed)
  local s = math.floor(math.abs(seed or 1)) % 2147483646 + 1
  return function(a, b)
    s = (s * 16807) % 2147483647
    local r = (s - 1) / 2147483646
    if a then return a + math.floor(r * (b - a + 1)) end
    return r
  end
end

local NAMES = { 'La Carme', 'En Jordi', 'La Montse', 'En Pau', 'La Laia', 'En Marc', 'La Núria', 'En Joan',
                'La Rosa', 'En Ramon', 'La Marta', 'En Xavi', 'La Pilar', 'En Toni' }
local SPRITES = { 'npc_elder', 'npc_girl', 'npc_baker', 'npc_fisher', 'npc_ranger', 'npc_postie', 'npc_kid', 'npc_lady' }
local THEMED
local SAY = {
  house = { { 'Hola! Passa, passa.', 'Aquesta casa és petita però molt acollidora.' },
            { 'Ui, quina visita!', 'Vols un got d\'aigua? Fa calor avui.' },
            { 'Estic fent el dinar.', 'Fa una olor de fideuà...' },
            { 'Has vist el mar avui?', 'Des de la terrassa es veu una mica.' },
            { 'Hola! Estava regant les plantes.', 'Si les cuides, creixen molt!' },
            { 'Benvinguda!', 'El meu gat s\'amaga sota el sofà quan ve gent.' },
            { 'Ara mateix llegia un conte.', 'És d\'un drac que tenia por de la foscor.' },
            { 'Hola! Vols jugar a les endevinalles?', 'Què és blanc i ve del cel? La neu!' },
            { 'Avui he fet galetes de xocolata.', 'Encara són calentes, compte!' },
            { 'Saps què?', 'Des de casa sento les onades del mar.' },
            { 'Hola!', 'Recorda rentar-te les mans abans de dinar.' },
            { 'Quina il·lusió!', 'Fa molt que no venia ningú a casa.' } },
  shop = { { 'Bon dia! Què et poso?', 'Avui tenim préssecs molt bons.' },
           { 'Benvingut a la botiga!', 'Si busques res, m\'ho dius.' },
           { 'Hola! Vols una mandarina?', 'Són dolcetes i fan bona olor.' },
           { 'Bon dia!', 'Recorda dir «si us plau» i «gràcies».' },
           { 'Hola! Tenim pa acabat de fer.', 'Fa una olor boníssima!' },
           { 'Benvinguda!', 'Avui hi ha pomes vermelles i verdes.' } },
  block = { { 'Hola, veí!', 'Tenim ascensor nou: només has de triar la planta.' },
            { 'Has vist la bústia?', 'Sempre està plena de propaganda.' },
            { 'Hola!', 'Al terrat hi ha roba estesa que balla amb el vent.' },
            { 'Bon dia!', 'Al tercer hi viu un gos que es diu Lluna.' },
            { 'Ei, hola!', 'Puja per l\'escala, que és bo per a les cames!' } },
}

-- rejilla de nombres de tile
local function grid(w, h, fill)
  local t = {}
  for i = 1, w * h do t[i] = fill end
  return t
end

-- ---------------------------------------------------------------- interiores de POIs con minijuegos (fase 4)
-- Distribución fija (siempre igual): máquinas y aparatos son tiles sólidos con un objeto 'arcade' encima
-- (props.game = cinema | penalties | circuit | rhythm) que abre el minijuego (src/minigames/).
-- opts.npc: personaje del servicio (mismo service_id que el de fuera) para hablar dentro.
local POI_SIZE = { casino = { 34, 24 }, gym = { 16, 11 }, sports = { 28, 21 }, football = { 18, 12 }, school = { 16, 12 },
                   church = { 15, 20 }, chapel = { 9, 9 }, library = { 18, 13 }, townhall = { 18, 13 },
                   clinic = { 16, 12 }, police = { 16, 12 }, post = { 14, 10 }, station = { 18, 10 } }
local POI_FLOOR = { casino = 'i_floor_carpet_', gym = 'i_floor_wood_', sports = 'i_floor_court_', football = 'g_grass_',
                    school = 'i_floor_tile_', church = 'i_floor_stone_', chapel = 'i_floor_stone_',
                    library = 'i_floor_wood_', townhall = 'i_floor_carpet_', clinic = 'i_floor_tile_',
                    police = 'i_floor_tile_', post = 'i_floor_tile_', station = 'i_floor_stone_' }
local POI_NAME = { casino = 'Casino Municipal', gym = 'Gimnàs', sports = 'Poliesportiu', football = 'Camp de futbol',
                   school = 'Aula de l\'Escola Salvador Espriu', church = 'Església de Sant Bartomeu',
                   chapel = 'Ermita de Berà', library = 'Biblioteca Municipal', townhall = 'Ajuntament ' .. require('src.place').of(),
                   clinic = require('src.place').is_roda() and 'CAP Roda de Berà' or 'Centre de salut', police = 'Policia Local', post = 'Oficina de Correus',
                   station = require('src.place').is_roda() and 'Estació de Roda de Mar' or 'Estació' }
P.POI_NAME = POI_NAME

-- ---------------------------------------------------------------- botigues grans (súpers i bricolatge)
-- Mida de 5 a 10 vegades una botiga normal: passadissos de prestatgeries amb rètols de secció, frescos a
-- l'entrada, neveres i congeladors al fons, línia de caixes amb caixeres i gent comprant.
P.STORE_SIZE = { super = { 44, 30 }, diy = { 64, 40 } }
local SUPER_SECTIONS = { 'Esmorzars', 'Pasta i arròs', 'Conserves', 'Làctics', 'Begudes', 'Neteja', 'Dolços',
                         'Higiene', 'Cuina del món', 'Mascotes' }
local DIY_SECTIONS = { { 'Fusta', 'i_diy_wood' }, { 'Pintura', 'i_diy_paint' }, { 'Eines', 'i_diy_tools' },
                       { 'Rajoles', 'i_diy_tiles' }, { 'Lampisteria', 'i_diy_pipe' }, { 'Jardí', 'i_diy_garden' },
                       { 'Magatzem', 'i_pallet' } }
local SHOPPER_SAY = { { 'On deuen tenir la llet?', 'Ah, al fons, a les neveres!' }, { 'Avui hi ha ofertes!' },
                      { 'Necessito cargols i una mica de pintura.' }, { 'Has vist quina cua a la caixa?' },
                      { 'M\'emporto fruita per a tota la setmana.' }, { 'El carro d\'aquest súper grinyola!' } }

function P.store(opts)
  local kind = opts.kind
  local size = opts.size or P.STORE_SIZE[kind]
  local w, h = size[1], size[2]
  local r = rng(opts.seed or (w * 131 + h))
  local L = { ground = grid(w, h, ''), detail = grid(w, h, ''), structures = grid(w, h, ''), overhead = grid(w, h, '') }
  local function set(layer, x, y, v) if x >= 0 and y >= 0 and x < w and y < h then L[layer][y * w + x + 1] = v end end
  local function get(x, y) return L.structures[y * w + x + 1] end
  for y = 0, h - 1 do for x = 0, w - 1 do set('ground', x, y, 'i_floor_store_' .. ((x + y) % 2)) end end
  local ex = math.floor(w / 2)
  for x = 0, w - 1 do
    set('structures', x, 0, 'i_wall_top')
    set('structures', x, 1, (x % 6 == 3 and x > 1 and x < w - 2) and 'i_wall_window' or 'i_wall')
    if math.abs(x - ex) > 1 then set('structures', x, h - 1, 'i_wall_top') end
  end
  for y = 0, h - 1 do set('structures', 0, y, 'i_wall_top'); set('structures', w - 1, y, 'i_wall_top') end
  for dx = -1, 1 do set('ground', ex + dx, h - 1, 'i_exit') end
  local objects = { { type = 'exit', x = ex, y = h - 1 } }
  local function sign(x, y, say) objects[#objects + 1] = { type = 'sign', x = x, y = y, say = say } end
  local function display(x, y, section)
    objects[#objects + 1] = { type = 'display', x = x, y = y, section = section,
      service_id = opts.npc and opts.npc.service_id }
  end
  local function npc(x, y, sprite, name, say, facing, wander)
    objects[#objects + 1] = { type = 'npc', x = x, y = y, sprite = sprite, name = name, say = say,
                              facing = facing or 'down', wander = wander or 0 }
  end
  -- línia de caixes: caixa (amb la caixera a sota de la pantalla) i cinta, amb passadissos entre caixes
  local cy = h - 6
  local tills, n_tills = {}, kind == 'diy' and 6 or 5
  local span = 5
  local x0 = ex - math.floor(n_tills * span / 2) + 1
  for k = 0, n_tills - 1 do
    local x = x0 + k * span
    if x > 2 and x + 2 < w - 2 then
      set('structures', x, cy, 'i_till'); set('structures', x + 1, cy, 'i_checkout'); set('structures', x + 2, cy, 'i_checkout')
      tills[#tills + 1] = { x, cy + 1 }
    end
  end
  -- carros i cistelles a l'entrada
  for x = 2, 5 do set('structures', x, h - 3, 'i_cart') end
  set('structures', w - 3, h - 3, 'i_baskets'); set('structures', w - 4, h - 3, 'i_baskets')
  -- passadissos: columnes de prestatgeries de 2 caselles d'ample amb un passadís transversal al mig
  local top, bottom = 5, cy - 3
  local mid = math.floor((top + bottom) / 2)
  local sections = {}
  local col = 0
  local first_x = kind == 'super' and 6 or 4
  for x = first_x, w - 6, 4 do
    col = col + 1
    local tile_fn
    if kind == 'super' then
      local v = col % 6
      tile_fn = function() return 'i_shelf_food_' .. v end
      sections[#sections + 1] = { x = x, name = SUPER_SECTIONS[(col - 1) % #SUPER_SECTIONS + 1] }
    else
      local sec = DIY_SECTIONS[(col - 1) % #DIY_SECTIONS + 1]
      tile_fn = function() return sec[2] end
      sections[#sections + 1] = { x = x, name = sec[1] }
    end
    for y = top, bottom do
      if y ~= mid and y ~= mid + 1 then
        set('structures', x, y, tile_fn()); set('structures', x + 1, y, tile_fn())
      end
    end
  end
  for _, sc in ipairs(sections) do
    -- Els caps de gòndola i el costat del passadís són interactius.
    display(sc.x, top, sc.name)
    display(sc.x + 1, bottom, sc.name)
    for y = top + 2, bottom - 1, 3 do
      if y ~= mid and y ~= mid + 1 then display(sc.x, y, sc.name) end
    end
  end
  -- fons: neveres (súper) o palets amb material (bricolatge)
  for x = 2, w - 3 do
    if kind == 'super' then
      set('structures', x, 2, (x % 2 == 0) and 'i_fridge_shop' or 'i_fridge')
      if x > 3 and x < w - 4 and x % 7 < 4 then set('structures', x, 3, 'i_freezer') end
    else
      set('structures', x, 2, x % 3 == 0 and 'i_pallet' or 'i_diy_wood')
    end
  end
  if kind == 'super' then
    display(2, 2, 'Làctics')
    display(w - 3, 2, 'Congelats')
    -- frescos a l'esquerra de l'entrada: fruita, verdura i pa
    for y = top, bottom do
      if y ~= mid then set('structures', 2, y, (y % 3 == 0) and 'i_bread' or ('i_fruit_' .. (y % 4))) end
    end
    for y = top, bottom do
      if y ~= mid then display(2, y, y % 3 == 0 and 'Forn' or 'Fruita i verdura') end
    end
  else
    for y = top, bottom do if y ~= mid then set('structures', 2, y, 'i_diy_garden') end end
    for y = top, bottom, 3 do if y ~= mid then display(2, y, 'Jardí') end end
    set('structures', w - 3, h - 4, 'i_counter'); set('structures', w - 4, h - 4, 'i_cashier')
    display(w - 3, h - 4, 'Informació')
  end
  set('structures', 1, h - 2, 'i_plant'); set('structures', w - 2, h - 2, 'i_plant')
  -- caixeres (la del servei és la primera: compra i venda) i compradors pels passadissos
  local cashier_sprites = { 'npc_clerk', 'npc_lady', 'npc_girl', 'npc_clerk', 'npc_lady', 'npc_girl' }
  for i, t in ipairs(tills) do
    if i == 1 and opts.npc then
      local n = opts.npc
      objects[#objects + 1] = { type = 'npc', x = t[1], y = t[2], sprite = n.sprite, name = n.name, say = { '...' },
                                facing = 'down', wander = 0, service = n.service, service_id = n.service_id, label = n.label }
    else
      npc(t[1], t[2], cashier_sprites[i], 'Caixera', { 'Bon dia! Tens targeta de client?', 'Vols bossa?' }, 'down', 0)
      local n = objects[#objects]
      if opts.npc then n.service, n.service_id, n.label = opts.npc.service, opts.npc.service_id, opts.npc.label end
    end
  end
  -- Un client per passadís: ruta vertical, pausa per mirar productes i retorn.
  -- El carro queda a la mateixa franja lliure de dues caselles.
  for k, sc in ipairs(sections) do
    local x, y = sc.x + 2, top + 2 + (k % 3)
    npc(x, y, SPRITES[(k % #SPRITES) + 1], 'Client',
      kind == 'diy' and { 'Estic preparant un projecte per a casa.', 'Ara miraré la secció de ' .. sc.name .. '.' }
        or { 'Avui toca fer la compra!', 'Estic buscant la secció de ' .. sc.name .. '.' }, 'down', 2)
    local n = objects[#objects]
    n.cart = kind == 'diy' and 'flatbed' or 'basket'
    n.route = { { x, top + 1 }, { x, bottom } }
    n.cart_load = k % 3
  end
  -- Taulells especialitzats: l'art existent diferencia frescos, llums i eines.
  local counter_section = kind == 'diy' and 'Il·luminació' or 'Peixateria'
  for y = top, bottom, 3 do
    set('structures', w - 3, y, kind == 'diy' and 'i_lamp' or 'i_freezer')
    display(w - 3, y, counter_section)
  end
  display(2, h - 3, 'Carros')
  display(w - 3, h - 3, 'Cistelles')
  local name = opts.name or (kind == 'diy' and 'Botiga de bricolatge' or 'Supermercat')
  return { w = w, h = h, name = name, kind = kind, ground = L.ground, detail = L.detail, structures = L.structures,
           overhead = L.overhead, objects = objects, spawn = { ex, h - 2 }, spawn_facing = 'up' }
end

-- casa amb placas solars (tools/decorate_map.py solar_roofs → objecte solar_house a la porta): la planta baixa
-- té pantalla domòtica, inversor i bateries, carregador del cotxe, un robot aspirador i un cofre amb un aparell
function P.solarize(spec, seed)
  local w, h = spec.w, spec.h
  local r = rng((seed or 1) + 77)
  local function idx(x, y) return y * w + x + 1 end
  local function get(x, y) return spec.structures[idx(x, y)] end
  local function set(x, y, v) spec.structures[idx(x, y)] = v end
  local function free(x, y)
    return x > 0 and y > 1 and x < w - 1 and y < h - 1 and (get(x, y) == '' or get(x, y) == nil)
      and spec.ground[idx(x, y)] ~= 'i_exit'
  end
  local placed = {}
  for x = 2, w - 3 do   -- pantalla a la paret de dalt (no a una finestra)
    if get(x, 1) == 'i_wall' then set(x, 1, 'i_smart_panel'); placed.panel = x; break end
  end
  for x = w - 3, 2, -1 do   -- inversor i bateries, junts, a la fila de sota la paret
    if free(x, 2) and free(x - 1, 2) then
      set(x, 2, 'i_battery'); set(x - 1, 2, 'i_inverter')
      placed.inv = { x - 1, 2 }
      break
    end
  end
  if free(1, h - 2) then set(1, h - 2, 'i_ev_charger') end
  for _ = 1, 40 do
    local x, y = r(2, w - 3), r(3, h - 3)
    if free(x, y) then set(x, y, 'i_robot_vac'); break end
  end
  spec.objects = spec.objects or {}
  if placed.inv then
    local ix, iy = placed.inv[1], placed.inv[2]
    for _, c in ipairs({ { ix - 1, iy }, { ix, iy + 1 }, { ix + 1, iy + 1 }, { ix - 1, iy + 1 } }) do
      if free(c[1], c[2]) then
        spec.objects[#spec.objects + 1] = { type = 'sign', x = c[1], y = c[2], say = {
          'Aquesta casa funciona amb el sol!',
          'Les plaques del teulat fan electricitat; l\'inversor la prepara i les bateries la guarden per a la nit.' } }
        break
      end
    end
  end
  for _ = 1, 60 do
    local x, y = r(2, w - 3), r(3, h - 3)
    if free(x, y) then
      spec.objects[#spec.objects + 1] = { type = 'chest', x = x, y = y,
                                          item = (r() < 0.5) and 'bateria_solar' or 'llanterna' }
      break
    end
  end
  spec.solar = true
  return spec
end

function P.poi(opts)
  if P.STORE_SIZE[opts.kind] then return P.store(opts) end
  local kind = opts.kind
  local w, h = POI_SIZE[kind][1], POI_SIZE[kind][2]
  local L = { ground = grid(w, h, ''), detail = grid(w, h, ''), structures = grid(w, h, ''), overhead = grid(w, h, '') }
  local function idx(x, y) return y * w + x + 1 end
  local function set(layer, x, y, v) if x >= 0 and y >= 0 and x < w and y < h then L[layer][idx(x, y)] = v end end
  for y = 0, h - 1 do
    for x = 0, w - 1 do set('ground', x, y, POI_FLOOR[kind] .. ((x + y) % 2)) end
  end
  local ex = math.floor(w / 2)
  for x = 0, w - 1 do
    set('structures', x, 0, 'i_wall_top')
    set('structures', x, 1, (x % 5 == 2 and x > 0 and x < w - 1) and 'i_wall_window' or 'i_wall')
    if x ~= ex then set('structures', x, h - 1, 'i_wall_top') end
  end
  for y = 0, h - 1 do set('structures', 0, y, 'i_wall_top'); set('structures', w - 1, y, 'i_wall_top') end
  set('ground', ex, h - 1, 'i_exit')
  local objects = { { type = 'exit', x = ex, y = h - 1 } }
  local function arcade(x, y, tile, game, extra)
    set('structures', x, y, tile)
    local o = { type = 'arcade', x = x, y = y, game = game }
    for k, v in pairs(extra or {}) do o[k] = v end
    objects[#objects + 1] = o
  end
  local function sign(x, y, say) objects[#objects + 1] = { type = 'sign', x = x, y = y, say = say } end
  local function book(x, y, say) objects[#objects + 1] = { type = 'sign', x = x, y = y, say = say, book = true } end
  local function person(x, y, sprite, name, say, facing)
    objects[#objects + 1] = { type = 'npc', x = x, y = y, sprite = sprite, name = name, say = say, facing = facing or 'down',
                              wander = 0 }
  end
  if kind == 'casino' then
    -- Comedor y cocina a la izquierda; escenario, pantalla y butacas a la derecha.
    for y = 2, h - 5 do set('structures', 15, y, 'i_wall_top') end
    for y = 2, h - 2 do for x = 1, 14 do set('ground', x, y, 'i_floor_tile_' .. ((x+y)%2)) end end
    for x = 2, 12 do set('structures', x, 3, 'i_counter') end
    set('structures', 2, 2, 'i_fridge'); set('structures', 5, 2, 'i_stove'); set('structures', 8, 2, 'i_sink')
    for _, y in ipairs({7, 11, 15}) do for _, x in ipairs({3, 9}) do
      set('structures', x, y, 'i_table'); set('structures', x+1, y, 'i_table')
      set('structures', x, y+1, 'i_chair'); set('structures', x+1, y-1, 'i_chair')
    end end
    set('structures', 4, 17, 'i_cashier'); set('structures', 5, 17, 'i_counter')
    for x = 18, 30 do for y = 3, 5 do set('ground', x, y, 'i_floor_wood_' .. ((x+y)%2)) end end
    for x = 21, 27 do set('structures', x, 2, 'i_blackboard') end
    for _, y in ipairs({9, 12, 15}) do for x = 18, 30 do
      if x ~= 23 and x ~= 24 and x ~= 25 then set('structures', x, y, 'i_armchair') end
    end end
    arcade(20, 6, 'i_desk', 'cinema', { label = 'Teatre: La llavor viatgera', mode = 'theatre' })
    arcade(28, 6, 'i_pc', 'cinema', { label = 'Cinema: Un dia a la costa', mode = 'cinema' })
    for _, x in ipairs({1, 13, 17, 32}) do set('structures', x, 20, 'i_plant') end
    objects[#objects+1] = {type='chest', x=12, y=19, item='radio', flag='casino_radio_found'}
    sign(2, 20, { 'RESTAURANT · Demana la carta a en Pep.', 'Menjador al fons; sala de teatre i cinema a la dreta.' })
    sign(29, 19, { 'TEATRE I CINEMA · Entrada lliure.', 'Teatre al faristol esquerre; cinema al projector dret.', 'Obres originals creades per al joc.' })
    for _, n in ipairs({
      {7, 4, 'npc_cook', 'La cuinera', 'La sopa ja està a punt!'},
      {6, 10, 'npc_lady', 'Una comensal', 'Després de dinar anirem al teatre.'},
      {19, 17, 'npc_tourist', 'Un espectador', "M'agrada veure històries a la pantalla gran."}
    }) do objects[#objects+1] = {type='npc', x=n[1], y=n[2], sprite=n[3], name=n[4], say={n[5]}, facing='down', wander=0} end
  elseif kind == 'church' then   -- nau amb bancs a banda i banda, passadís central, altar i vitralls
    for x = 2, w - 3, 3 do set('structures', x, 1, 'i_wall_stained') end
    for x = ex - 2, ex + 2 do set('structures', x, 2, 'i_altar') end
    set('structures', ex - 4, 2, 'i_candles'); set('structures', ex + 4, 2, 'i_candles')
    for y = 3, 4 do for x = ex - 1, ex + 1 do set('ground', x, y, 'i_rug_c') end end
    for y = 6, h - 4, 2 do
      for x = 2, ex - 2 do set('structures', x, y, 'i_pew') end
      for x = ex + 2, w - 3 do set('structures', x, y, 'i_pew') end
    end
    for y = 5, h - 2 do set('ground', ex, y, 'i_rug') end
    set('structures', 1, h - 3, 'i_plant'); set('structures', w - 2, h - 3, 'i_plant')
    person(ex, 4, 'npc_elder', 'Mossèn Joan', { 'Benvingut a l\'església de Sant Bartomeu!',
      'Sant Bartomeu és el patró del poble: la seva festa és el 24 d\'agost.',
      'Si fas silenci, sentiràs les campanes tocar les hores.' })
    sign(1, 3, { 'Les campanes del campanar toquen cada hora en punt.', 'Des de la plaça les sents de lluny!' })
    person(3, h - 5, 'npc_lady', 'Veïna', { 'Vinc a encendre una espelma per l\'àvia.' }, 'up')
  elseif kind == 'chapel' then   -- ermita petita a la vora de l'Arc de Berà
    set('structures', ex, 1, 'i_wall_stained'); set('structures', ex, 2, 'i_altar')
    set('structures', ex - 2, 2, 'i_candles'); set('structures', ex + 2, 2, 'i_candles')
    for y = 4, h - 3, 2 do set('structures', ex - 2, y, 'i_pew'); set('structures', ex - 1, y, 'i_pew')
      set('structures', ex + 1, y, 'i_pew'); set('structures', ex + 2, y, 'i_pew') end
    sign(1, 3, { 'Una ermita petita i silenciosa, molt a prop de l\'Arc de Berà.',
                 'Els romans hi passaven per la Via Augusta, el gran camí de l\'Imperi.' })
  elseif kind == 'library' then   -- prestatgeries en files, taules de lectura, ordinadors i la bibliotecària
    for x = 1, w - 2 do if x % 4 ~= 0 then set('structures', x, 2, 'i_shelf') end end
    for row = 0, 1 do
      for x = 2, w - 3 do if x ~= ex and x ~= ex - 1 and x ~= ex + 1 then set('structures', x, 5 + row * 3, 'i_shelf') end end
    end
    set('structures', 2, h - 3, 'i_table'); set('structures', 3, h - 3, 'i_table'); set('structures', 2, h - 2, 'i_chair')
    set('structures', w - 4, h - 3, 'i_pc'); set('structures', w - 3, h - 3, 'i_pc')
    set('structures', 1, 3, 'i_plant')
    book(2, 2, { 'Llibre: L\'Arc de Berà', 'És un arc de triomf romà de fa més de 2.000 anys.',
                 'Era a la Via Augusta, el camí que anava de Roma fins a Cadis.' })
    book(6, 2, { 'Llibre: El Roc de Sant Gaietà', 'Un barri vora el mar fet als anys seixanta,',
                 'amb carrerons i cases que imiten els pobles antics de tot Espanya.' })
    book(10, 2, { 'Llibre: Animals del Mediterrani', 'Al port s\'hi pesquen orades, llobarros i sards.',
                  'I a la sorra de la platja hi viuen crancs ben petits!' })
    book(3, 5, { 'Llibre: Contes per dormir', 'Hi havia una vegada un drac que vivia a la muntanya de Roda...',
                 '...però aquesta història l\'hauràs de descobrir tu!' })
    book(w - 4, 5, { 'Llibre: Com funciona una bici', 'Pedals, cadena i rodes: i el casc, sempre posat!' })
    book(5, 8, { 'Atles del món', 'La Terra té cinc oceans i set continents.' })
    sign(ex + 3, h - 3, { 'Biblioteca: parla fluix, si us plau!', 'Pots llegir els llibres de les prestatgeries.' })
  elseif kind == 'townhall' then   -- vestíbul amb taulell, despatx de l'alcaldessa i sala de plens
    for x = 3, 7 do set('structures', x, 4, 'i_counter') end
    set('structures', 1, 2, 'i_flag'); set('structures', w - 2, 2, 'i_flag')
    for x = w - 8, w - 3 do set('structures', x, 6, 'i_table') end
    for x = w - 8, w - 3 do set('structures', x, 7, 'i_chair') end
    set('structures', w - 5, 2, 'i_desk'); set('structures', 9, 2, 'i_shelf'); set('structures', 10, 2, 'i_shelf')
    set('structures', 2, h - 3, 'i_plant'); set('structures', w - 3, h - 3, 'i_plant')
    for y = 5, h - 2 do set('ground', ex, y, 'i_rug') end
    person(5, 3, 'npc_lady', 'La funcionària', { 'Bon dia! Vols fer-te el carnet de la biblioteca?',
      'Aquí es fan els papers del poble: empadronar-se, permisos...' })
    sign(w - 6, 5, { 'Sala de plens: aquí es reuneixen els regidors i l\'alcaldessa.' })
  elseif kind == 'clinic' then   -- sala d'espera, recepció i consulta amb llitera
    for x = 2, 6 do set('structures', x, h - 4, 'i_bench') end
    for x = 2, 6 do set('structures', x, 5, 'i_bench') end
    for x = 9, 12 do set('structures', x, 4, 'i_counter') end
    set('structures', w - 3, 2, 'i_bed'); set('structures', w - 5, 2, 'i_desk'); set('structures', w - 2, 6, 'i_sink')
    set('structures', 1, 2, 'i_plant'); set('structures', 8, 2, 'i_clock')
    person(10, 3, 'npc_lady', 'La infermera', { 'Bon dia! Seu a la sala d\'espera, si us plau.',
      'Recorda: rentar-se les mans és la millor manera de no posar-se malalt.' })
    person(3, 6, 'npc_elder', 'Un avi', { 'Vinc a prendre\'m la pressió. Tot bé!' }, 'up')
  elseif kind == 'police' then   -- despatxos, ràdio i un calabós buit
    for x = 2, 5 do set('structures', x, 4, 'i_counter') end
    set('structures', 8, 2, 'i_desk'); set('structures', 9, 2, 'i_pc'); set('structures', 11, 2, 'i_desk')
    for y = 2, 5 do set('structures', w - 4, y, 'i_cell') end
    set('structures', w - 3, 5, 'i_cell'); set('structures', w - 2, 5, 'i_cell')
    set('structures', 1, 2, 'i_flag'); set('structures', 1, h - 3, 'i_plant')
    sign(w - 3, 3, { 'El calabós està buit: aquí tothom es porta bé!' })
    person(3, 3, 'npc_police', 'Agent de guàrdia', { 'Policia Local, bon dia!',
      'Si et perds, busca un agent o demana ajuda en una botiga.', 'El telèfon d\'emergències és el 112.' })
  elseif kind == 'post' then   -- taulell, apartats de correus i paquets
    for x = 3, 9 do set('structures', x, 4, 'i_counter') end
    for x = 1, w - 2 do if x % 3 ~= 0 then set('structures', x, 1, 'i_mailbox') end end
    set('structures', w - 3, h - 3, 'i_box'); set('structures', w - 2, h - 3, 'i_box'); set('structures', 1, h - 3, 'i_box')
    person(6, 3, 'npc_postie', 'El carter', { 'Bon dia! Vols enviar una postal?',
      'Les cartes porten segell i l\'adreça ben escrita.' })
  elseif kind == 'station' then   -- vestíbul, màquines de bitllets i bancs
    set('structures', 2, 2, 'i_ticket'); set('structures', 3, 2, 'i_ticket')
    for x = w - 7, w - 3 do set('structures', x, 2, 'i_counter') end
    for x = 3, 8 do set('structures', x, 6, 'i_bench') end
    set('structures', ex, 1, 'i_clock'); set('structures', w - 2, h - 3, 'i_plant')
    sign(5, 2, { 'Trens cap a Tarragona i cap a Barcelona.', 'Mira l\'horari i no perdis el tren!' })
    person(w - 5, 3, 'npc_postie', 'El revisor', { 'Bitllet, si us plau! Bon viatge!' })
  elseif kind == 'gym' then
    for y = 3, 6 do for x = 2, 13 do set('ground', x, y, 'i_mat') end end
    arcade(3, 3, 'i_weights', 'rhythm', { stat = 'strength', label = 'Pesos (força)' })
    arcade(7, 3, 'i_gym_bike', 'rhythm', { stat = 'resistance', label = 'Bici estàtica (resistència)' })
    arcade(11, 3, 'i_treadmill', 'rhythm', { stat = 'agility', label = 'Cinta de córrer (agilitat)' })
    set('structures', 14, 2, 'i_plant'); set('structures', 1, 8, 'i_box')
    sign(5, 2, { 'Segueix el ritme amb les fletxes!', 'Una sessió bona al dia per aparell puja l\'estadística.' })
  elseif kind == 'school' then   -- aula: pissarra, pupitres en files, prestatgeries i la mestra
    for x = 5, 10 do set('structures', x, 1, 'i_blackboard') end
    for row = 0, 2 do
      for col = 0, 3 do set('structures', 3 + col * 3, 5 + row * 2, 'i_school_desk') end
    end
    set('structures', 1, 2, 'i_shelf'); set('structures', 14, 2, 'i_shelf'); set('structures', 14, 6, 'i_plant')
    set('structures', 2, 9, 'i_pc')
    sign(12, 2, { 'Avui toca: conèixer el nostre poble.', 'Carrers, places, l\'escola, el CAP i la Policia Local.' })
  elseif kind == 'sports' then
    -- pavelló: pista de futbol sala amb línies, porteries als dos extrems i grades als laterals
    local x0, x1, y0, y1 = 5, w - 6, 3, h - 4
    for y = y0, y1 do
      for x = x0, x1 do
        if y == y0 or y == y1 or y == math.floor((y0 + y1) / 2) then set('ground', x, y, 'i_court_line') end
      end
    end
    local gx = ex - 1
    arcade(gx, y0, 'i_goal_l', 'penalties', { label = 'Porteria' })
    arcade(gx + 1, y0, 'i_goal_m', 'penalties', { label = 'Porteria' })
    arcade(gx + 2, y0, 'i_goal_r', 'penalties', { label = 'Porteria' })
    for k, p in ipairs({ 'i_goal_l', 'i_goal_m', 'i_goal_r' }) do set('structures', gx - 1 + k, y1 - 1, p) end
    for y = 3, h - 4 do
      for _, x in ipairs({ 1, 2, w - 3, w - 2 }) do
        if y ~= math.floor((y0 + y1) / 2) then set('structures', x, y, 'i_bleacher') end   -- passadís al mig
      end
    end
    arcade(x0 + 1, y1 - 3, 'i_cones', 'circuit', { label = 'Circuit d\'agilitat' })
    arcade(x0 + 2, y1 - 3, 'i_cones', 'circuit', { label = 'Circuit d\'agilitat' })
    set('structures', 3, 2, 'i_trophies'); set('structures', w - 4, 2, 'i_trophies')
    sign(gx - 2, y0 + 1, { 'Tanda de penals: 5 xuts contra el porter.' })
    sign(x0 + 3, y1 - 3, { 'Circuit d\'agilitat: esquiva els cons amb la bici o el patinet!' })
    for k = 1, 4 do   -- públic a les grades
      objects[#objects + 1] = { type = 'npc', x = (k % 2 == 0) and 2 or w - 3, y = 3 + k * 3, sprite = SPRITES[k + 1],
                                name = 'Afició', say = { 'Som-hi, equip!', 'Quin golàs!' }, facing = (k % 2 == 0) and 'right' or 'left',
                                wander = 0 }
    end
  elseif kind == 'football' then
    local gx = ex - 1
    arcade(gx, 2, 'i_goal_l', 'penalties', { label = 'Porteria' })
    arcade(gx + 1, 2, 'i_goal_m', 'penalties', { label = 'Porteria' })
    arcade(gx + 2, 2, 'i_goal_r', 'penalties', { label = 'Porteria' })
    for x = 1, w - 2 do if x < gx - 1 or x > gx + 3 then set('ground', x, 5, kind == 'sports' and 'i_court_line' or 'g_park_0') end end
    if kind == 'sports' then
      arcade(3, 8, 'i_cones', 'circuit', { label = 'Circuit d\'agilitat' })
      arcade(4, 8, 'i_cones', 'circuit', { label = 'Circuit d\'agilitat' })
      set('structures', w - 3, 2, 'i_trophies'); set('structures', w - 4, 2, 'i_trophies')
      sign(6, 8, { 'Circuit d\'agilitat: esquiva els cons amb la bici o el patinet!' })
    else
      set('structures', 2, 2, 'i_box'); set('structures', w - 3, 2, 'i_box')
    end
    sign(gx - 2, 3, { 'Tanda de penals: 5 xuts contra el porter.' })
  end
  if opts.npc then
    local n = opts.npc
    local NPC_AT = { casino = { 5, 18 }, gym = { 9, 7 }, sports = { 20, 15 }, football = { 13, 6 }, school = { 8, 3 },
                     library = { ex, h - 4 }, townhall = { w - 5, 3 }, clinic = { w - 4, 4 }, police = { 9, 3 },
                     post = { 4, 3 }, station = { w - 4, 3 }, church = { ex + 3, 4 }, chapel = { ex + 1, 3 } }
    local at = NPC_AT[kind] or { ex, 3 }
    local nx, ny = at[1], at[2]
    objects[#objects + 1] = { type = 'npc', x = nx, y = ny, sprite = n.sprite, name = n.name, say = { '...' },
                              facing = 'down', wander = 0, service = n.service, service_id = n.service_id,
                              label = n.label }
  end
  return { w = w, h = h, name = opts.name or POI_NAME[kind], kind = kind, ground = L.ground, detail = L.detail,
           structures = L.structures, overhead = L.overhead, objects = objects, spawn = { ex, h - 2 },
           spawn_facing = 'up' }
end

-- ---------------------------------------------------------------- locals reals (data/locals.json → opts.theme)
-- Cada tipus de local té el seu mobiliari i un personatge amb el nom del local que t'atén.
local ROLE = { restaurant = 'El cambrer', takeaway = 'La cuinera', music = 'El DJ', icecream = 'La gelatera',
               animals = 'La veterinària', health = 'La infermera', pharmacy = 'La farmacèutica', beauty = 'La perruquera',
               industry = 'L\'encarregat', office = 'La gestora', bank = 'El caixer', school = 'La professora',
               trade = 'L\'operari', garage = 'El mecànic', sport = 'La monitora', stay = 'El recepcionista' }
local THEME_SAY = {
  restaurant = { 'Taula per a un? Seu on vulguis!', 'Avui hi ha arròs negre i crema catalana.' },
  takeaway = { 'Ho vols per emportar?', 'El pollastre a l\'ast surt en cinc minuts.' },
  music = { 'Benvingut! Ara sona la cançó de l\'estiu.', 'Balla una mica, que és gratis!' },
  icecream = { 'De quin gust el vols?', 'El de torró és el que més agrada.' },
  animals = { 'Hola! Avui vacunem un gatet.', 'Els animals també van al metge.' },
  health = { 'Seu a la sala d\'espera, si us plau.', 'Recorda rentar-te les mans!' },
  pharmacy = { 'Bon dia! Necessites tiretes?', 'Els medicaments, sempre amb un adult.' },
  beauty = { 'Tallem una mica les puntes?', 'Avui tenim la cadira lliure.' },
  industry = { 'Aquí dins fem coses a la cadena!', 'Compte amb les màquines, només mirar.' },
  office = { 'Bon dia! En què et puc ajudar?', 'Omplim un paper i llestos.' },
  bank = { 'Vols obrir una guardiola?', 'Estalviar a poc a poc fa molta feina.' },
  school = { 'Aquí fem classes de repàs.', 'Avui toca anglès: hello!' },
  trade = { 'Fem obres i reparacions.', 'Porta casc si passes per l\'obra!' },
  garage = { 'Aquest cotxe necessita oli nou.', 'Les rodes sempre ben inflades.' },
  sport = { 'Escalfem una mica?', 'Beu aigua després de l\'esport.' },
  stay = { 'Benvinguts! Teniu reserva?', 'L\'esmorzar és a les vuit.' },
}
local THEME_FLOOR = { restaurant = 'i_floor_wood_', takeaway = 'i_floor_wood_', music = 'i_floor_carpet_',
                      sport = 'i_floor_wood_', stay = 'i_floor_carpet_', office = 'i_floor_wood_', bank = 'i_floor_carpet_' }
local function npc_of(c, theme, x, y)
  local who = ROLE[theme] or 'La dependenta'
  c.objects[#c.objects + 1] = { type = 'npc', x = x, y = y, sprite = SPRITES[c.R(1, #SPRITES)],
                                name = c.name and (who .. ' · ' .. c.name) or who, say = THEME_SAY[theme] or SAY.shop[1],
                                facing = 'down', wander = 0 }
end
local function tables(r, c)        -- taules amb cadires, en files (restaurant, gelateria)
  for y = r.y0 + 3, r.y1 - 2, 3 do
    for x = r.x0 + 1, r.x1 - 3, 4 do
      if c.free(x + 1, y) and not c.keep[c.idx(x + 1, y)] and c.free(x, y) and c.free(x + 2, y) then
        c.set('structures', x, y, 'i_chair'); c.set('structures', x + 1, y, 'i_table'); c.set('structures', x + 2, y, 'i_chair')
      end
    end
  end
end
local function bar(r, c, fridge)  -- barra al fons amb la caixa (i neveres al darrere)
  for x = r.x0 + 1, r.x1 - 1 do c.set('structures', x, r.y0, fridge and (x % 3 == 0 and 'i_fridge_shop' or 'i_shelf') or 'i_shelf') end
  for x = r.x0 + 2, r.x1 - 2 do c.set('structures', x, r.y0 + 2, x == r.x1 - 2 and 'i_cashier' or 'i_counter') end
  return r.x1 - 3, r.y0 + 1
end
THEMED = {
  restaurant = function(r, c) local nx, ny = bar(r, c, true); tables(r, c); npc_of(c, 'restaurant', nx, ny) end,
  takeaway = function(r, c) local nx, ny = bar(r, c, true); c.put(r, 'i_stove', 2, 'left'); npc_of(c, 'takeaway', nx, ny) end,
  icecream = function(r, c)
    for x = r.x0 + 2, r.x1 - 2 do c.set('structures', x, r.y0 + 2, x % 2 == 0 and 'i_fridge_shop' or 'i_counter') end
    tables(r, c); npc_of(c, 'icecream', r.x1 - 3, r.y0 + 1)
  end,
  music = function(r, c)
    for x = r.x0 + 1, r.x1 - 1 do c.set('structures', x, r.y0, x % 3 == 1 and 'i_wall_neon' or 'i_shelf') end
    for x = r.x0 + 2, r.x0 + 5 do c.set('structures', x, r.y0 + 2, x == r.x0 + 5 and 'i_cashier' or 'i_counter') end
    local cx, cy = math.floor((r.x0 + r.x1) / 2) + 2, math.floor((r.y0 + r.y1) / 2) + 1
    for y = cy - 1, cy + 1 do for x = cx - 2, cx + 2 do if c.free(x, y) then c.set('ground', x, y, 'i_rug_c') end end end
    c.put(r, 'i_tv', 1, 'right'); npc_of(c, 'music', r.x0 + 3, r.y0 + 1)
  end,
  animals = function(r, c)
    c.put(r, 'i_table', 2, 'mid'); c.put(r, 'i_desk', 1, 'left'); c.put(r, 'i_pc', 1, 'left'); c.put(r, 'i_shelf', 2, 'right')
    c.put(r, 'i_plant', 1, 'right')
    for k = 1, 2 do
      c.objects[#c.objects + 1] = { type = 'npc', x = r.x0 + 2 + k * 3, y = r.y1 - 1, sprite = k == 1 and 'npc_cat_orange' or 'npc_cat_grey',
                                    name = 'Un pacient', say = { 'Miau!', 'Prrr...' }, facing = 'down', wander = 2 }
    end
    npc_of(c, 'animals', r.x0 + 4, r.y0 + 2)
  end,
  industry = function(r, c)
    for y = r.y0 + 1, r.y1 - 2, 3 do
      for x = r.x0 + 1, r.x1 - 2 do
        if not c.keep[c.idx(x, y)] and x % 7 ~= 3 then c.set('structures', x, y, (x % 5 == 0) and 'i_box' or 'i_counter') end
      end
    end
    c.put(r, 'i_cones', 2, 'right'); npc_of(c, 'industry', r.x0 + 3, r.y1 - 1)
  end,
  sport = function(r, c)
    for _, n in ipairs({ 'i_treadmill', 'i_gym_bike', 'i_weights', 'i_treadmill', 'i_gym_bike' }) do c.put(r, n, 1) end
    c.put(r, 'i_mat', 2, 'mid'); npc_of(c, 'sport', r.x0 + 2, r.y0 + 2)
  end,
}
for _, k in ipairs({ 'health', 'pharmacy', 'beauty', 'office', 'bank', 'school', 'trade', 'garage', 'stay' }) do
  THEMED[k] = function(r, c)
    c.put(r, 'i_desk', 2, 'mid'); c.put(r, 'i_pc', 1, 'mid')
    if k == 'pharmacy' then for x = r.x0 + 1, r.x1 - 1 do c.set('structures', x, r.y0, 'i_shelf') end end
    if k == 'beauty' then c.put(r, 'i_sink', 2, 'left'); c.put(r, 'i_armchair', 2, 'left') end
    if k == 'garage' then c.put(r, 'i_box', 3, 'left'); c.put(r, 'i_cones', 2, 'right'); c.put(r, 'i_bike', 1, 'right') end
    if k == 'school' then c.put(r, 'i_blackboard', 2, 'mid'); c.put(r, 'i_school_desk', 3, 'mid') end
    for _ = 1, 3 do c.put(r, 'i_chair', 1, 'left') end
    c.put(r, 'i_plant', 1, 'right')
    npc_of(c, k, r.x1 - 3, r.y0 + 1)
  end
end

function P.generate(opts)
  local kind = opts.kind or 'house'
  local R = rng(opts.seed)
  local w, h
  if kind == 'shop' then w, h = R(14, 18), R(10, 12)
  elseif kind == 'block' then w, h = R(12, 15), R(10, 12)
  elseif kind == 'flat' then w, h = R(15, 19), R(11, 13)
  else w, h = R(18, 24), R(13, 16) end
  w, h = math.min(opts.w or w, kind == 'shop' and 40 or 30), math.min(opts.h or h, 30)
  -- planta de dalt d'una casa: sense porta al carrer; s'hi arriba per l'escala (opts.stairs)
  local upper = kind == 'upper'
  local L = { ground = grid(w, h, 'i_floor_wood_0'), detail = grid(w, h, ''), structures = grid(w, h, ''),
              overhead = grid(w, h, '') }
  local function idx(x, y) return y * w + x + 1 end
  local function set(layer, x, y, v) if x >= 0 and y >= 0 and x < w and y < h then L[layer][idx(x, y)] = v end end
  local function get(layer, x, y) return L[layer][idx(x, y)] end
  local function free(x, y) return x > 0 and y > 1 and x < w - 1 and y < h - 1 and get('structures', x, y) == '' end

  -- muros exteriores: arriba remate + pared con ventanas; lados y abajo remate; salida abajo al centro
  local ex = math.floor(w / 2)
  for x = 0, w - 1 do
    set('structures', x, 0, 'i_wall_top')
    set('structures', x, 1, (x % 5 == 2 and x > 0 and x < w - 1) and 'i_wall_window' or 'i_wall')
    if x ~= ex or upper then set('structures', x, h - 1, 'i_wall_top') end
  end
  for y = 0, h - 1 do set('structures', 0, y, 'i_wall_top'); set('structures', w - 1, y, 'i_wall_top') end
  set('structures', 0, 1, 'i_wall_top'); set('structures', w - 1, 1, 'i_wall_top')
  local objects = {}
  if not upper then
    set('ground', ex, h - 1, 'i_exit')
    objects[1] = { type = 'exit', x = ex, y = h - 1, target_scene = opts.exit_scene, target_spawn = opts.exit_spawn }
  end
  local keep = {}  -- celdas que deben quedar libres (paso)
  local function mark(x, y) keep[idx(x, y)] = true end
  if not upper then for y = h - 3, h - 2 do mark(ex, y) end end
  -- escala a una altra planta: 2 graons a dalt a l'esquerra (x = 1, 2), i el replà de sota lliure
  local st = opts.stairs
  if st then
    for x = 1, 2 do mark(x, 2); mark(x, 3); mark(x, 4) end
  end
  -- ascensor a la paret de dalt (portal d'un bloc): objecte 'arcade' amb game = 'lift' i la llista de plantes
  if opts.lift then
    local lx = w - 3
    set('structures', lx, 1, 'i_lift'); mark(lx, 2); mark(lx, 3)
    objects[#objects + 1] = { type = 'arcade', x = lx, y = 1, game = 'lift', label = 'Ascensor', floors = opts.lift.floors,
                              current = opts.lift.current }
    objects[#objects + 1] = { type = 'spawn', name = 'lift', x = lx, y = 2 }
  end

  local rooms, layout = {}, nil
  if kind == 'shop' then
    rooms[1] = { x0 = 1, y0 = 2, x1 = w - 2, y1 = h - 2, type = 'shop' }
  elseif kind == 'block' then
    rooms[1] = { x0 = 1, y0 = 2, x1 = w - 2, y1 = h - 2, type = 'lobby' }
  else
    -- (pis i planta de dalt: la mateixa partició que una casa) — 10 distribucions (src/world/house_layouts.lua):
    -- la llavor de la porta tria quina; la planta de dalt fa servir la mateixa, amb dormitoris i bany
    local HL = require('src.world.house_layouts')
    layout = opts.layout or HL.pick(opts.seed)
    rooms = HL.build(layout, w, h, R, ex, function(x, y, v) set('structures', x, y, v) end, mark)
    if upper then
      local UP = { living = 'bedroom', studio = 'bedroom', loft = 'bedroom', kitchen = 'bath', dining = 'study',
                   patio = 'terrace', hall = 'hall' }
      for _, r in ipairs(rooms) do r.type = UP[r.type] or r.type end
    end
  end

  local HLF = require('src.world.house_layouts')
  local FLOOR = setmetatable({ shop = 'i_floor_tile_0', lobby = 'i_floor_tile_1' }, { __index = HLF.FLOOR })
  for _, r in ipairs(rooms) do
    local f = FLOOR[r.type] or 'i_floor_wood_0'
    if layout and (r.type == 'living' or r.type == 'loft' or r.type == 'studio') and HLF.LIVING_FLOOR[layout] then
      f = HLF.LIVING_FLOOR[layout]
    end
    for y = r.y0, r.y1 do for x = r.x0, r.x1 do
      set('ground', x, y, r.type == 'patio' and ('g_grass_' .. (x * 7 + y * 3) % 3) or f)
    end end
  end
  if not upper then set('ground', ex, h - 1, 'i_exit') end
  if st then   -- graons (sortida cap a l'altra planta) i punt d'arribada just a sota
    for x = 1, 2 do
      for y = 2, 4 do set('structures', x, y, '') end
      set('ground', x, 2, st.dir == 'up' and 'i_stairs_up' or 'i_stairs_down')
      objects[#objects + 1] = { type = 'exit', x = x, y = 2, target_scene = st.target, target_spawn = st.target_spawn }
    end
    objects[#objects + 1] = { type = 'spawn', name = st.arrive or 'from_stairs', x = 1, y = 3 }
  end

  -- caselles lliures que no s'enllacen amb la sortida (o l'escala): un moble no pot fer-ne de noves (abans, un
  -- moble que tapava una porta deixava una habitació tancada i el reparador final la buidava sencera)
  local sx0, sy0 = ex, h - 2
  if upper then sx0, sy0 = 1, 3 end
  local function lost_cells()
    local function ok(x, y) local t = get('structures', x, y); return t == '' or t == 'i_shower' end
    if not ok(sx0, sy0) then return 0 end
    local seen, q, head = { [idx(sx0, sy0)] = true }, { sx0, sy0 }, 1
    while q[head] do
      local x, y = q[head], q[head + 1]; head = head + 2
      for d = 1, 4 do
        local nx, ny = x + (d == 1 and 1 or d == 2 and -1 or 0), y + (d == 3 and 1 or d == 4 and -1 or 0)
        if nx > 0 and ny > 1 and nx < w - 1 and ny < h - 1 and not seen[idx(nx, ny)] and ok(nx, ny) then
          seen[idx(nx, ny)] = true; q[#q + 1] = nx; q[#q + 1] = ny
        end
      end
    end
    local n = 0
    for y = 2, h - 2 do for x = 1, w - 2 do if ok(x, y) and not seen[idx(x, y)] then n = n + 1 end end end
    return n
  end
  local lost0
  local function blocks(cells)   -- cells: { x, y, x, y… } ja posades; si tanquen pas, es treuen
    lost0 = lost0 or 0
    if lost_cells() > lost0 then
      for i = 1, #cells, 2 do set('structures', cells[i], cells[i + 1], '') end
      return true
    end
  end
  -- colocar un mueble de 1×n contra una pared (arriba primero), sin tapar el paso
  local function put(r, name, n, where)
    n = n or 1
    local tries = 0
    while tries < 40 do
      tries = tries + 1
      local x, y
      where = where or 'top'
      if where == 'top' then x, y = R(r.x0, math.max(r.x0, r.x1 - n + 1)), r.y0
      elseif where == 'left' then x, y = r.x0, R(r.y0 + 1, r.y1)
      elseif where == 'right' then x, y = r.x1 - n + 1, R(r.y0 + 1, r.y1)
      else x, y = R(r.x0 + 1, math.max(r.x0 + 1, r.x1 - n)), R(r.y0 + 1, math.max(r.y0 + 1, r.y1 - 1)) end
      local ok = true
      for k = 0, n - 1 do
        if not free(x + k, y) or keep[idx(x + k, y)] then ok = false end
      end
      if ok then
        local cells = {}
        for k = 0, n - 1 do set('structures', x + k, y, name); cells[#cells + 1] = x + k; cells[#cells + 1] = y end
        if not blocks(cells) then return x, y end
      end
    end
  end
  local function put2v(r, top_name, bot_name)   -- mueble de 1×2 en vertical (cama)
    for _ = 1, 40 do
      local x, y = R(r.x0, r.x1), r.y0
      if free(x, y) and free(x, y + 1) and not keep[idx(x, y)] and not keep[idx(x, y + 1)] then
        set('structures', x, y, top_name); set('structures', x, y + 1, bot_name)
        if not blocks({ x, y, x, y + 1 }) then return x, y end
      end
    end
  end

  lost0 = lost_cells()
  for _, r in ipairs(rooms) do
    local rw = r.x1 - r.x0 + 1
    if r.type == 'living' then
      put(r, 'i_tv', 1); put(r, 'i_shelf', 1); put(r, 'i_plant', 1)
      if R() < 0.4 then put(r, 'i_fireplace', 1) end
      local cx, cy = math.floor((r.x0 + r.x1) / 2), math.floor((r.y0 + r.y1) / 2)
      for y = cy, cy + 1 do
        for x = cx - 1, cx + 1 do if free(x, y) then set('ground', x, y, 'i_rug_c') end end
      end
      put(r, 'i_sofa', math.min(3, rw - 2), 'mid')
      put(r, 'i_armchair', 1, 'left'); put(r, 'i_radiator', 1, 'right'); put(r, 'i_lamp', 1, 'right')
      if not upper then   -- banc de taller (src/systems/crafting.lua): s'hi creen objectes amb materials
        local bx, by = put(r, 'i_workbench', 1, 'right')
        if bx then objects[#objects + 1] = { type = 'arcade', x = bx, y = by, game = 'taller', label = 'Banc de taller' } end
      end
    elseif r.type == 'bedroom' then
      put2v(r, 'i_bed_t', 'i_bed_b'); put(r, 'i_nightstand', 1); put(r, 'i_wardrobe', 2)
      if R() < 0.6 then put(r, 'i_pc', 1) end
      if R() < 0.5 then put(r, 'i_toys', 1, 'mid') end
    elseif r.type == 'kitchen' then
      local n = math.max(2, math.min(4, rw - 2))
      local x = put(r, 'i_counter', n) or put(r, 'i_counter', 2)
      if x and get('structures', x + n - 1, r.y0) ~= 'i_counter' then n = 2 end
      if x then
        set('structures', x, r.y0, 'i_fridge')
        if n >= 3 then set('structures', x + 1, r.y0, 'i_stove'); set('structures', x + n - 1, r.y0, 'i_sink') end
      end
      put(r, 'i_table', 2, 'mid'); put(r, 'i_washer', 1, 'right')
    elseif r.type == 'bath' then
      put(r, 'i_toilet', 1); put(r, 'i_sink', 1)
      local x, y = put(r, 'i_bath', 2)
      if not x then put(r, 'i_shower', 1) end
    elseif r.type == 'studio' or r.type == 'loft' then   -- espai obert: cuina en línia, sofà i tele (i llit a l'estudi)
      local n = math.max(2, math.min(4, rw - 4))
      local x = put(r, 'i_counter', n)
      if x then
        set('structures', x, r.y0, 'i_fridge')
        if n >= 3 then set('structures', x + 1, r.y0, 'i_stove'); set('structures', x + n - 1, r.y0, 'i_sink') end
      end
      if r.type == 'studio' then put2v(r, 'i_bed_t', 'i_bed_b'); put(r, 'i_wardrobe', 1, 'right') end
      put(r, 'i_tv', 1); put(r, 'i_sofa', math.min(3, rw - 3), 'mid'); put(r, 'i_table', 2, 'mid')
      put(r, 'i_plant', 1, 'left'); put(r, 'i_lamp', 1, 'right'); put(r, 'i_shelf', 1)
      if not upper then
        local bx, by = put(r, 'i_workbench', 1, 'right')
        if bx then objects[#objects + 1] = { type = 'arcade', x = bx, y = by, game = 'taller', label = 'Banc de taller' } end
      end
    elseif r.type == 'kids' then
      put2v(r, 'i_bed_t', 'i_bed_b'); put(r, 'i_toys', 1, 'mid'); put(r, 'i_blackboard', 1); put(r, 'i_nightstand', 1)
    elseif r.type == 'study' then
      put(r, 'i_desk', 1); put(r, 'i_pc', 1); put(r, 'i_shelf', 2); put(r, 'i_chair', 1, 'mid')
      put(r, 'i_plant', 1, 'left'); if R() < 0.5 then put(r, 'i_board_l', 1, 'right') end
    elseif r.type == 'dining' then
      put(r, 'i_table', math.min(3, math.max(1, rw - 3)), 'mid'); put(r, 'i_chair', 1, 'mid'); put(r, 'i_shelf', 1)
      put(r, 'i_clock', 1); put(r, 'i_plant', 1, 'right')
    elseif r.type == 'patio' then
      for _ = 1, 3 do put(r, 'i_plant', 1, 'mid') end
      put(r, 'i_bench', 1, 'left'); put(r, 'i_baskets', 1, 'right')
    elseif r.type == 'terrace' then
      put(r, 'i_plant', 1, 'left'); put(r, 'i_plant', 1, 'right'); put(r, 'i_chair', 1, 'mid'); put(r, 'i_table', 1, 'mid')
    elseif r.type == 'hall' then
      put(r, 'i_plant', 1, 'left'); put(r, 'i_shelf', 1, 'right')
    elseif r.type == 'shop' and THEMED[opts.theme] then
      local fl = THEME_FLOOR[opts.theme]
      if fl then for y = 2, h - 2 do for x = 1, w - 2 do set('ground', x, y, fl .. ((x + y) % 2)) end end end
      THEMED[opts.theme](r, { w = w, h = h, R = R, set = set, free = free, keep = keep, idx = idx, put = put,
                              objects = objects, name = opts.name })
    elseif r.type == 'shop' then
      for k = 0, math.min(w - 4, 12), 1 do
        if k % 3 ~= 2 then set('structures', 2 + k, 2, k % 4 == 0 and 'i_fridge_shop' or 'i_shelf') end
      end
      for y = 5, h - 5, 3 do
        for x = 3, w - 5 do if x % 6 ~= 0 and free(x, y) and not keep[idx(x, y)] then set('structures', x, y, 'i_shelf') end end
      end
      local cx = w - 5
      for x = cx, w - 2 do set('structures', x, h - 4, x == cx and 'i_cashier' or 'i_counter') end
      objects[#objects + 1] = { type = 'npc', x = w - 3, y = h - 5, sprite = SPRITES[R(1, #SPRITES)],
                                name = opts.name and ('La dependenta · ' .. opts.name) or NAMES[R(1, #NAMES)],
                                say = SAY.shop[R(1, #SAY.shop)], facing = 'down', wander = 0 }
    elseif r.type == 'lobby' then
      for x = 4, 6 do set('structures', x, 2, 'i_mailbox') end
      if not st then set('ground', w - 3, 2, 'i_stairs_up'); set('ground', w - 2, 2, 'i_stairs_up') end
      put(r, 'i_plant', 1, 'right'); put(r, 'i_bike', 1, 'right')
    end
  end

  -- habitante y, a veces, un gato
  if kind ~= 'shop' then
    local lr = rooms[1]
    for _ = 1, 30 do
      local x, y = R(lr.x0 + 1, lr.x1 - 1), R(lr.y0 + 1, lr.y1 - 1)
      if free(x, y) and not keep[idx(x, y)] then
        local pool = SAY[kind] or SAY.house
        objects[#objects + 1] = { type = 'npc', x = x, y = y, sprite = SPRITES[R(1, #SPRITES)], name = NAMES[R(1, #NAMES)],
                                  say = pool[R(1, #pool)], facing = 'down', wander = 2 }
        break
      end
    end
    if R() < 0.35 then
      for _ = 1, 30 do
        local x, y = R(2, w - 3), R(3, h - 3)
        if free(x, y) and not keep[idx(x, y)] then
          objects[#objects + 1] = { type = 'npc', x = x, y = y, sprite = R() < 0.5 and 'npc_cat_orange' or 'npc_cat_grey',
                                    name = 'El gat', say = { 'Miau!', 'Prrr...' }, facing = 'down', wander = 3 }
          break
        end
      end
    end
  end

  -- garantizar acceso: toda celda libre debe enlazar con la salida (si no, quitar el mueble que estorba)
  local function reach()
    local seen, q = { [idx(sx0, sy0)] = true }, { { sx0, sy0 } }
    local head = 1
    while q[head] do
      local x, y = q[head][1], q[head][2]; head = head + 1
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if nx > 0 and ny > 1 and nx < w - 1 and ny < h - 1 and not seen[idx(nx, ny)] and
            (get('structures', nx, ny) == '' or get('structures', nx, ny) == 'i_shower') then
          seen[idx(nx, ny)] = true; q[#q + 1] = { nx, ny }
        end
      end
    end
    return seen
  end
  for _ = 1, 6 do
    local seen = reach()
    local fixed = false
    for y = 2, h - 2 do
      for x = 1, w - 2 do
        if get('structures', x, y) == '' and not seen[idx(x, y)] then
          -- abrir el mueble vecino más cercano al paso
          for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }) do
            local nx, ny = x + d[1], y + d[2]
            local t = get('structures', nx, ny)
            if t ~= '' and t ~= 'i_wall_top' and t ~= 'i_wall' and t ~= 'i_wall_window' then
              set('structures', nx, ny, ''); fixed = true; break
            end
          end
        end
      end
    end
    if not fixed then break end
  end
  local title = ({ house = 'Casa', shop = 'Botiga', block = 'Portal', flat = 'Pis', upper = 'Planta de dalt' })[kind] or 'Interior'
  local spec = { w = w, h = h, name = opts.name or title, kind = kind, layout = layout, ground = L.ground, detail = L.detail,
                 structures = L.structures, overhead = L.overhead, objects = objects,
                 spawn = (not upper) and { ex, h - 2 } or nil }
  ROOMS[spec] = rooms
  return spec
end

-- ---------------------------------------------------------------- decoració per rol (cases d'amics i familiars)
-- opts: { seed, age = 'kid' | 'adult' | 'elder' }. Afegeix mobles i detalls a un interior de P.generate sense tapar cap pas:
-- cada peça es desa només si totes les cel·les lliures segueixen enllaçades amb la sortida.
-- Els avis tenen butaques, plantes, fotos (prestatgeries) i rellotge; els nens i nenes pòsters (pissarres), joguines i
-- bicicleta; els adults un racó d'escriptori. El dormitori de dalt és el de la persona.
function P.enrich(spec, opts)
  local rooms = ROOMS[spec]
  if not rooms or not spec.spawn then return spec end
  opts = opts or {}
  local age = opts.age or 'kid'
  local R = rng((opts.seed or 1) * 31 + 17)
  local w, h = spec.w, spec.h
  local S, G = spec.structures, spec.ground
  local function idx(x, y) return y * w + x + 1 end
  local reserved = {}
  reserved[idx(spec.spawn[1], spec.spawn[2])] = true
  for _, o in ipairs(spec.objects) do
    if o.type ~= 'npc' then reserved[idx(o.x, o.y)] = true end
  end
  local function inside(x, y) return x > 0 and y > 1 and x < w - 1 and y < h - 1 end
  local function lost()
    local seen, q, head = { [idx(spec.spawn[1], spec.spawn[2])] = true }, { { spec.spawn[1], spec.spawn[2] } }, 1
    while q[head] do
      local x, y = q[head][1], q[head][2]; head = head + 1
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if inside(nx, ny) and not seen[idx(nx, ny)] and (S[idx(nx, ny)] == '' or S[idx(nx, ny)] == 'i_shower') then
          seen[idx(nx, ny)] = true; q[#q + 1] = { nx, ny }
        end
      end
    end
    local n = 0
    for y = 2, h - 2 do for x = 1, w - 2 do
      if S[idx(x, y)] == '' and not seen[idx(x, y)] then n = n + 1 end
    end end
    return n
  end
  local base = lost()
  local function try(x, y, name)
    if not inside(x, y) or S[idx(x, y)] ~= '' or reserved[idx(x, y)] then return false end
    local g = G[idx(x, y)] or ''
    if g == 'i_exit' or g:match('^i_stairs') then return false end
    S[idx(x, y)] = name
    if lost() > base then S[idx(x, y)] = ''; return false end
    return true
  end
  local function place(r, name, where)
    for _ = 1, 24 do
      local x, y
      if where == 'top' then x, y = R(r.x0, r.x1), r.y0
      elseif where == 'side' then x, y = (R() < 0.5) and r.x0 or r.x1, R(r.y0 + 1, r.y1)
      else x, y = R(r.x0, r.x1), R(r.y0 + 1, r.y1) end
      if try(x, y, name) then return x, y end
    end
  end
  local function rug(r, name)   -- catifa al terra (transitable) enmig de l'habitació
    local cx, cy = math.floor((r.x0 + r.x1) / 2), math.floor((r.y0 + r.y1) / 2)
    for y = cy, cy + 1 do for x = cx - 1, cx do
      if inside(x, y) and S[idx(x, y)] == '' and (G[idx(x, y)] or ''):match('^i_floor') then G[idx(x, y)] = name end
    end end
  end
  local function wall(r, names)   -- quadre/rellotge/pissarra a la paret de dalt (només sobre paret llisa)
    for _ = 1, 12 do
      local x = R(r.x0, r.x1 - (#names - 1))
      local ok = r.y0 == 2
      for k = 0, #names - 1 do if S[idx(x + k, 1)] ~= 'i_wall' then ok = false end end
      if ok then
        for k = 0, #names - 1 do S[idx(x + k, 1)] = names[k + 1] end
        return true
      end
    end
  end

  local bedroom_done = false
  for _, r in ipairs(rooms) do
    if r.type == 'living' then
      place(r, 'i_lamp', 'side'); place(r, 'i_plant', 'side')
      if age == 'elder' then
        place(r, 'i_armchair', 'any'); place(r, 'i_armchair', 'side'); place(r, 'i_shelf', 'top'); place(r, 'i_shelf', 'top')
        place(r, 'i_plant', 'any'); wall(r, { 'i_clock' })
      elseif age == 'adult' then
        place(r, 'i_shelf', 'top'); place(r, 'i_armchair', 'side'); wall(r, { 'i_clock' })
      else
        place(r, 'i_toys', 'any'); place(r, 'i_bike', 'side'); place(r, 'i_box', 'side'); wall(r, { 'i_clock' })
      end
    elseif r.type == 'bedroom' then
      if not bedroom_done then
        bedroom_done = true
        rug(r, 'i_rug_c')
        place(r, 'i_lamp', 'side')
        if age == 'kid' then
          place(r, 'i_toys', 'any'); place(r, 'i_toys', 'any'); place(r, 'i_box', 'side'); place(r, 'i_pc', 'top')
          wall(r, { 'i_board_l', 'i_board_r' })
        elseif age == 'adult' then
          local x, y = place(r, 'i_desk', 'top')
          if x then try(x, y + 1, 'i_chair') end
          place(r, 'i_pc', 'top'); place(r, 'i_shelf', 'top'); wall(r, { 'i_clock' })
        else
          place(r, 'i_armchair', 'side'); place(r, 'i_plant', 'side'); place(r, 'i_shelf', 'top'); wall(r, { 'i_clock' })
        end
      else
        place(r, 'i_plant', 'side')
        if age ~= 'elder' then place(r, 'i_toys', 'any') end
      end
    elseif r.type == 'kitchen' then
      for y = r.y0, r.y1 do for x = r.x0, r.x1 do
        if S[idx(x, y)] == 'i_table' then
          try(x, y - 1, 'i_chair'); try(x, y + 1, 'i_chair'); try(x + 1, y + 1, 'i_chair')
          break
        end
      end end
      place(r, 'i_plant', 'side'); wall(r, { 'i_clock' })
    elseif r.type == 'bath' then
      place(r, 'i_washer', 'side'); place(r, 'i_plant', 'side'); rug(r, 'i_rug')
    end
  end
  return spec
end

-- ---------------------------------------------------------------- edificis de diverses plantes (fase 6)
-- Casa de 2 plantes (escala) o bloc de pisos: portal (planta baixa) → replà de cada planta (escala amunt i
-- avall, ascensor, portes dels pisos) → pisos. Cada planta i cada pis és una escena generada; es lliguen amb
-- sortides (target_scene / target_spawn) i punts d'arribada amb nom.
local ORD = { 'Planta baixa', '1a planta', '2a planta', '3a planta', '4a planta', '5a planta', '6a planta' }
local FLAT_ORD = { '1r', '2n', '3r', '4t', '5è', '6è' }
function P.floor_label(k) return ORD[k + 1] or (k .. 'a planta') end
function P.flat_label(k, j) return (FLAT_ORD[k] or (k .. 'è')) .. ' ' .. j .. 'a' end
function P.floor_id(base, k) return k == 0 and base or (base .. '_p' .. k) end
function P.flat_id(base, k, j) return base .. '_p' .. k .. '_' .. j end

-- replà de la planta k: escala amunt (si no és l'última) i avall, ascensor i les portes dels pisos
function P.landing(opts)
  local k, n, flats, base = opts.floor, opts.floors, opts.flats, opts.base
  local R = rng(opts.seed)
  local w, h = 7 + flats * 4, 8
  local L = { ground = grid(w, h, 'i_floor_tile_1'), detail = grid(w, h, ''), structures = grid(w, h, ''),
              overhead = grid(w, h, '') }
  local function set(layer, x, y, v) L[layer][y * w + x + 1] = v end
  for y = 2, h - 2 do for x = 1, w - 2 do set('ground', x, y, (x + y) % 2 == 0 and 'i_floor_tile_1' or 'i_floor_tile_0') end end
  for x = 0, w - 1 do
    set('structures', x, 0, 'i_wall_top'); set('structures', x, h - 1, 'i_wall_top')
    set('structures', x, 1, 'i_wall')
  end
  for y = 0, h - 1 do set('structures', 0, y, 'i_wall_top'); set('structures', w - 1, y, 'i_wall_top') end
  local objects = {}
  local function exit(x, y, scene, spawn) objects[#objects + 1] = { type = 'exit', x = x, y = y, target_scene = scene, target_spawn = spawn } end
  local function spawn(name, x, y) objects[#objects + 1] = { type = 'spawn', name = name, x = x, y = y } end
  -- escala: amunt a dalt a l'esquerra, avall a baix a l'esquerra
  if k < n - 1 then
    for x = 1, 2 do set('ground', x, 2, 'i_stairs_up'); exit(x, 2, P.floor_id(base, k + 1), 'from_down') end
    spawn('from_up', 1, 3)
  end
  for x = 1, 2 do set('ground', x, h - 2, 'i_stairs_down'); exit(x, h - 2, P.floor_id(base, k - 1), 'from_up') end
  spawn('from_down', 1, h - 3)
  -- portes dels pisos
  for j = 1, flats do
    local dx = 1 + j * 4
    set('structures', dx, 1, 'i_flat_door'); set('ground', dx, 2, 'i_rug')
    exit(dx, 1, P.flat_id(base, k, j), 'spawn_in')
    spawn('from_flat_' .. j, dx, 2)
  end
  -- ascensor
  local lx = w - 2
  set('structures', lx, 1, 'i_lift')
  objects[#objects + 1] = { type = 'arcade', x = lx, y = 1, game = 'lift', label = 'Ascensor', floors = opts.lift_floors,
                            current = k }
  spawn('lift', lx, 2)
  set('structures', w - 2, h - 2, 'i_plant')
  if R() < 0.5 then set('structures', 4, h - 2, 'i_bike') end
  -- de tant en tant, un veí al replà
  if R() < 0.45 then
    objects[#objects + 1] = { type = 'npc', x = R(4, w - 4), y = 4, sprite = SPRITES[R(1, #SPRITES)], name = NAMES[R(1, #NAMES)],
                              say = SAY.block[R(1, #SAY.block)], facing = 'down', wander = 2 }
  end
  return { w = w, h = h, name = 'Replà · ' .. P.floor_label(k), kind = 'landing', ground = L.ground, detail = L.detail,
           structures = L.structures, overhead = L.overhead, objects = objects }
end

-- opts: { kind = 'house' | 'block', seed, base (id de la planta baixa), floors (plantes comptant la baixa),
--         flats (pisos per replà; si no, 2 o 3), name }
-- → { entry = base, specs = { [id] = spec }, floors = n, flats = m }
function P.building(opts)
  local base, seed = opts.base, opts.seed or 1
  local n = math.max(1, math.min(6, math.floor(opts.floors or 1)))
  local specs = {}
  if opts.kind == 'house' then
    if n < 2 then
      specs[base] = P.generate({ kind = 'house', seed = seed, name = opts.name })
      return { entry = base, specs = specs, floors = 1 }
    end
    local up = base .. '_p1'
    specs[base] = P.generate({ kind = 'house', seed = seed, name = (opts.name or 'Casa') .. ' · planta baixa',
                               stairs = { dir = 'up', target = up, target_spawn = 'from_down', arrive = 'from_up' } })
    specs[up] = P.generate({ kind = 'upper', seed = seed, name = (opts.name or 'Casa') .. ' · planta de dalt',
                             stairs = { dir = 'down', target = base, target_spawn = 'from_up', arrive = 'from_down' } })
    return { entry = base, specs = specs, floors = 2 }
  end
  -- bloc de pisos (com a mínim, planta baixa + 1)
  n = math.max(2, n)
  local flats = opts.flats or (rng(seed + 5)(1, 2) + 1)
  local lift_floors = {}
  for k = 0, n - 1 do lift_floors[k + 1] = { label = P.floor_label(k), scene = P.floor_id(base, k) } end
  specs[base] = P.generate({ kind = 'block', seed = seed, name = opts.name or 'Portal',
                             stairs = { dir = 'up', target = P.floor_id(base, 1), target_spawn = 'from_down', arrive = 'from_up' },
                             lift = { floors = lift_floors, current = 0 } })
  for k = 1, n - 1 do
    local id = P.floor_id(base, k)
    specs[id] = P.landing({ floor = k, floors = n, flats = flats, base = base, seed = seed + k * 131, lift_floors = lift_floors })
    for j = 1, flats do
      specs[P.flat_id(base, k, j)] = P.generate({ kind = 'flat', seed = seed + k * 977 + j * 61, name = 'Pis ' .. P.flat_label(k, j),
                                                  exit_scene = id, exit_spawn = 'from_flat_' .. j })
    end
  end
  return { entry = base, specs = specs, floors = n, flats = flats }
end

return P
