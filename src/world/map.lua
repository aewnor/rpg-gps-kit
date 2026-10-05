-- Datos de una escena: índice, chunks y consultas de celda. Sin render (ver renderer.lua).
local Chunks = require('src.world.chunks')

local Map = {}
Map.__index = Map

local OUTSIDE = 1 -- fuera del mapa: sólido

-- loader(path) -> tabla Lua del índice; chunk_loader(path) -> chunk decodificado
function Map.load(dir, loader, chunk_loader)
  local self = setmetatable({}, Map)
  self.dir = dir
  self.loader = loader
  self.index = loader(dir .. '/index.lua')
  local ix = self.index
  self.scene = ix.scene
  self.width, self.height = ix.width, ix.height
  self.chunk = ix.chunk
  self.tile = ix.tile
  self.props = ix.props or {}
  self.objects = ix.objects
  self.routes = ix.routes
  self.anim = ix.anim or {}
  self.chunks = Chunks.new(self, chunk_loader)
  -- vías vectoriales (opcional; los interiores no tienen). Se comprueba antes de cargar: en love.js
  -- (Lua 5.1) un fichero ausente rompe dentro del pcall y tumba el juego al entrar en un interior.
  local lpath = dir .. '/lines.lua'
  local has_lines = not (love and love.filesystem) or love.filesystem.getInfo(lpath) ~= nil
  local ok, lines = false, nil
  if has_lines then ok, lines = pcall(loader, lpath) end
  if ok and type(lines) == 'table' then
    require('src.world.vectors').prepare(lines)
    self.lines = lines
  end
  self.by_name = {}
  for _, o in ipairs(self.objects) do
    self.by_name[o.type .. ':' .. o.name] = o
  end
  return self
end

function Map:object(type_, name)
  return self.by_name[type_ .. ':' .. name]
end

function Map:objects_of(type_)
  local out = {}
  for _, o in ipairs(self.objects) do
    if o.type == type_ then out[#out + 1] = o end
  end
  return out
end

function Map:in_bounds(tx, ty)
  return tx >= 0 and ty >= 0 and tx < self.width and ty < self.height
end

-- código de colisión (ver collision.lua)
function Map:cell(tx, ty)
  if tx < 0 or ty < 0 or tx >= self.width or ty >= self.height then return OUTSIDE end
  local c = self.chunks:get(math.floor(tx / self.chunk), math.floor(ty / self.chunk))
  return c.coll[(ty % self.chunk) * c.w + (tx % self.chunk) + 1]
end

-- componente conexa a nivel 0 (para validar la casa y los spawns)
function Map:component(tx, ty)
  if not self:in_bounds(tx, ty) then return 0 end
  local c = self.chunks:get(math.floor(tx / self.chunk), math.floor(ty / self.chunk))
  return c.comp[(ty % self.chunk) * c.w + (tx % self.chunk) + 1]
end

-- altura del terreno (metros) y superficie (0 natural, 1 pavimento, 2 tierra, 3 escaleras) de la casilla.
-- Mapas sin capa de altura (interiores, cueva): 0, 1.
function Map:height_at(tx, ty)
  if not self:in_bounds(tx, ty) then return 0, 0 end
  local c = self.chunks:get(math.floor(tx / self.chunk), math.floor(ty / self.chunk))
  local h = c.height
  if not h then return 0, 1 end
  local v = h[(ty % self.chunk) * c.w + (tx % self.chunk) + 1]
  return v % 1024, math.floor(v / 1024)
end

Map.LEVEL_M = 8   -- metros por nivel de terreno (como tools/realdata.py LEVEL_STEP_M)

function Map:level_at(tx, ty)
  return math.floor((self:height_at(tx, ty)) / Map.LEVEL_M)
end

function Map:tile_at(layer, tx, ty)
  if not self:in_bounds(tx, ty) then return 0 end
  local c = self.chunks:get(math.floor(tx / self.chunk), math.floor(ty / self.chunk))
  local l = c[layer]
  return l and l[(ty % self.chunk) * c.w + (tx % self.chunk) + 1] or 0
end

return Map
