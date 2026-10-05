-- Decodifica chunks binarios de tools/compile_maps.py:
-- zlib( 'RC1' w:u8 h:u8 mascara:u16 nflips:u16 | capas u16[w*h]... | coll u8[w*h] | comp u32[w*h] | flips )
local Codec = {}
local LAYERS = { 'ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead', 'height' }

local byte = string.byte

local function u16(s, i) local a, b = byte(s, i, i + 1); return a + b * 256 end

function Codec.decode(raw)
  local s = love.data.decompress('string', 'zlib', raw)
  assert(s:sub(1, 3) == 'RC1', 'chunk con formato desconocido')
  local w, h = byte(s, 4), byte(s, 5)
  local mask, nflips = u16(s, 6), u16(s, 8)
  local n = w * h
  local c = { w = w, h = h }
  local p = 10
  local bit = 1
  for li = 1, #LAYERS do
    if mask % (bit * 2) >= bit then
      local t = {}
      for i = 1, n do
        local a, b = byte(s, p, p + 1)
        t[i] = a + b * 256
        p = p + 2
      end
      c[LAYERS[li]] = t
    end
    bit = bit * 2
  end
  local coll = { byte(s, p, p + n - 1) }
  c.coll = coll
  p = p + n
  local comp = {}
  for i = 1, n do
    local a, b, cc, d = byte(s, p, p + 3)
    comp[i] = a + b * 256 + cc * 65536 + d * 16777216
    p = p + 4
  end
  c.comp = comp
  if nflips > 0 then
    c.flips = {}
    for _ = 1, nflips do
      local li, i0, i1, f = byte(s, p, p + 3)
      local name = LAYERS[li + 1]
      c.flips[name] = c.flips[name] or {}
      c.flips[name][i0 + i1 * 256 + 1] = f
      p = p + 4
    end
  end
  return c
end

return Codec
