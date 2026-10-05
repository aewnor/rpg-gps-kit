-- Vistes en diagonal (2026-10-05). Les fulles de personatge (16 × 24, 6 columnes × 4 files: avall, amunt, esquerra,
-- dreta) s'amplien en carregar-les amb 4 files més, compostes de les que ja hi ha, sense redibuixar res:
--   4 avall-esquerra: cap de perfil (esquerra) i cos de cara (avall)
--   5 avall-dreta:    cap de perfil (dreta) i cos de cara
--   6 amunt-esquerra: cap d'esquena (amunt) i cos de perfil (esquerra)
--   7 amunt-dreta:    cap d'esquena i cos de perfil (dreta)
-- Així serveix per a les fulles PNG (tools/chars.py) i per a l'avatar del perfil (src/paperdoll/chars.lua).
local D = {}

D.SPLIT = 12                                  -- fila on acaba el cap (com HEAD_ROWS de chars.lua) i comença el coll
D.ROW = { dl = 4, dr = 5, ul = 6, ur = 7 }
local SRC = { { 2, 0 }, { 3, 0 }, { 1, 2 }, { 1, 3 } }   -- { fila del cap, fila del cos } per a les files 4..7

-- ImageData 96 × 96 → ImageData 96 × 192 amb les files diagonals (altres mides: igual, sense diagonals)
function D.extend_data(src)
  local w, h = src:getDimensions()
  if w ~= 96 or h ~= 96 then return src, false end
  local out = love.image.newImageData(96, 192)
  out:paste(src, 0, 0, 0, 0, 96, 96)
  for k, s in ipairs(SRC) do
    local row = 3 + k
    for col = 0, 5 do
      out:paste(src, col * 16, row * 24, col * 16, s[1] * 24, 16, D.SPLIT)
      out:paste(src, col * 16, row * 24 + D.SPLIT, col * 16, s[2] * 24 + D.SPLIT, 16, 24 - D.SPLIT)
    end
  end
  return out, true
end

-- direcció diagonal a partir del moviment (h, v en -1..1) o nil si va recte
function D.of(h, v)
  if h == 0 or v == 0 then return nil end
  return (v > 0 and 'd' or 'u') .. (h < 0 and 'l' or 'r')
end

return D
