-- band() portable: librería bit de LuaJIT si existe; si no (love.js, Lua 5.1), aritmética.
local ok, bit = pcall(require, 'bit')
if ok and bit then return { band = bit.band } end
local function band(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    local ra, rb = a % 2, b % 2
    if ra == 1 and rb == 1 then r = r + p end
    a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
  end
  return r
end
return { band = band }
