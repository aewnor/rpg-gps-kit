-- JSON mínimo (decodificar/codificar) para datos y guardados. Sin dependencias.
local json = {}

local escape_map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
                     ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k <= 0 or k % 1 ~= 0 then return false end
    n = math.max(n, k)
  end
  return n == #t
end

local function encode(v, out, indent, depth)
  local t = type(v)
  if t == 'nil' then out[#out + 1] = 'null'
  elseif t == 'boolean' then out[#out + 1] = tostring(v)
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then error('número no codificable') end
    if v % 1 == 0 and math.abs(v) < 2^53 then out[#out + 1] = string.format('%d', v)
    else out[#out + 1] = string.format('%.6g', v) end
  elseif t == 'string' then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      return escape_map[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
  elseif t == 'table' then
    local nl = indent and ('\n' .. string.rep(indent, depth + 1)) or ''
    local close = indent and ('\n' .. string.rep(indent, depth)) or ''
    if next(v) == nil then out[#out + 1] = is_array(v) and '[]' or '{}'; return end
    if is_array(v) then
      out[#out + 1] = '['
      for i, x in ipairs(v) do
        if i > 1 then out[#out + 1] = ',' end
        out[#out + 1] = nl
        encode(x, out, indent, depth + 1)
      end
      out[#out + 1] = close .. ']'
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      out[#out + 1] = '{'
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = ',' end
        out[#out + 1] = nl
        encode(k, out, indent, depth + 1)
        out[#out + 1] = indent and ': ' or ':'
        local val = v[k]
        if val == nil then val = v[tonumber(k)] end
        encode(val, out, indent, depth + 1)
      end
      out[#out + 1] = close .. '}'
    end
  else
    error('tipo no codificable: ' .. t)
  end
end

function json.encode(v, pretty)
  local out = {}
  encode(v, out, pretty and '  ' or nil, 0)
  return table.concat(out)
end

-- decodificador recursivo
local function decode_error(s, i, msg)
  error(string.format('JSON inválido en %d: %s', i, msg), 0)
end

local function skip(s, i)
  local _, e = s:find('^[ \n\r\t]*', i)
  return e + 1
end

local decode_value

local function decode_string(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == '' then decode_error(s, j, 'cadena sin cerrar') end
    if c == '"' then return table.concat(out), j + 1 end
    if c == '\\' then
      local e = s:sub(j + 1, j + 1)
      local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
      if map[e] then out[#out + 1] = map[e]; j = j + 2
      elseif e == 'u' then
        local cp = tonumber(s:sub(j + 2, j + 5), 16)
        if not cp then decode_error(s, j, 'escape \\u inválido') end
        j = j + 6
        if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == '\\u' then
          local lo = tonumber(s:sub(j + 2, j + 5), 16)
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          j = j + 6
        end
        if cp < 0x80 then out[#out + 1] = string.char(cp)
        elseif cp < 0x800 then out[#out + 1] = string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
        elseif cp < 0x10000 then
          out[#out + 1] = string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
        else
          out[#out + 1] = string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
            0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
        end
      else decode_error(s, j, 'escape desconocido') end
    else
      local k = s:find('["\\]', j)
      if not k then decode_error(s, j, 'cadena sin cerrar') end
      out[#out + 1] = s:sub(j, k - 1)
      j = k
    end
  end
end

function decode_value(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == '{' then
    local obj = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while true do
      i = skip(s, i)
      if s:sub(i, i) ~= '"' then decode_error(s, i, 'se esperaba una clave') end
      local k
      k, i = decode_string(s, i)
      i = skip(s, i)
      if s:sub(i, i) ~= ':' then decode_error(s, i, "se esperaba ':'") end
      obj[k], i = decode_value(s, i + 1)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == '}' then return obj, i + 1 end
      if d ~= ',' then decode_error(s, i, "se esperaba ',' o '}'") end
      i = i + 1
    end
  elseif c == '[' then
    local arr = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while true do
      arr[#arr + 1], i = decode_value(s, i)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == ']' then return arr, i + 1 end
      if d ~= ',' then decode_error(s, i, "se esperaba ',' o ']'") end
      i = i + 1
    end
  elseif c == '"' then
    return decode_string(s, i)
  elseif s:sub(i, i + 3) == 'true' then return true, i + 4
  elseif s:sub(i, i + 4) == 'false' then return false, i + 5
  elseif s:sub(i, i + 3) == 'null' then return nil, i + 4
  else
    local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
    if not num or num == '' then decode_error(s, i, 'valor inesperado') end
    return tonumber(num), i + #num
  end
end

function json.decode(s)
  if type(s) ~= 'string' then error('json.decode espera una cadena', 0) end
  local v, i = decode_value(s, 1)
  i = skip(s, i)
  if i <= #s then decode_error(s, i, 'contenido sobrante') end
  return v
end

return json
