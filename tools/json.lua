-- tools/json.lua
-- Minimal, dependency-free JSON encode/decode for the differential oracle harness.
-- Scope: objects, arrays, strings (with standard escapes), numbers (int/float),
-- booleans, null. Sufficient for the oracle scenario/result contract; not a general
-- JSON library. Arrays are Lua sequences; objects are string-keyed tables. An empty
-- Lua table {} encodes as [] (the contract has no empty objects).

local json = {}

--------------------------------------------------------------------------------
-- Encode
--------------------------------------------------------------------------------

local escape_map = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function escape_str(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return escape_map[c] or string.format('\\u%04x', string.byte(c))
  end) .. '"'
end

local function is_array(t)
  -- A sequence with keys 1..n and no holes. Empty table counts as array.
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return true end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local encode_value

local function encode_number(v)
  if math.type and math.type(v) == 'integer' then
    return string.format('%d', v)
  end
  -- %.17g round-trips IEEE-754 doubles exactly; both sides compare with epsilon anyway.
  return string.format('%.17g', v)
end

encode_value = function(v)
  local t = type(v)
  if v == nil then
    return 'null'
  elseif t == 'boolean' then
    return v and 'true' or 'false'
  elseif t == 'number' then
    return encode_number(v)
  elseif t == 'string' then
    return escape_str(v)
  elseif t == 'table' then
    if is_array(v) then
      local parts = {}
      for i = 1, #v do parts[i] = encode_value(v[i]) end
      return '[' .. table.concat(parts, ',') .. ']'
    else
      -- Stable key order for reproducible output (important for diffs).
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = escape_str(tostring(k)) .. ':' .. encode_value(v[k])
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end
  else
    error('json: cannot encode type ' .. t)
  end
end

function json.encode(v)
  return encode_value(v)
end

--------------------------------------------------------------------------------
-- Decode (recursive descent)
--------------------------------------------------------------------------------

local function decode_error(s, i, msg)
  error(string.format('json: %s at byte %d (near %q)', msg, i, s:sub(i, i + 15)))
end

local parse_value

local function skip_ws(s, i)
  local _, j = s:find('^[ \t\r\n]*', i)
  return (j or i - 1) + 1
end

local unescape_map = {
  ['"'] = '"', ['\\'] = '\\', ['/'] = '/', ['b'] = '\b',
  ['f'] = '\f', ['n'] = '\n', ['r'] = '\r', ['t'] = '\t',
}

local function parse_string(s, i)
  -- assumes s:sub(i,i) == '"'
  local buf, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == '' then decode_error(s, j, 'unterminated string') end
    if c == '"' then
      return table.concat(buf), j + 1
    elseif c == '\\' then
      local e = s:sub(j + 1, j + 1)
      if e == 'u' then
        local hex = s:sub(j + 2, j + 5)
        local code = tonumber(hex, 16)
        if not code then decode_error(s, j, 'bad \\u escape') end
        -- Basic BMP only; encode to UTF-8.
        if code < 0x80 then
          buf[#buf + 1] = string.char(code)
        elseif code < 0x800 then
          buf[#buf + 1] = string.char(0xC0 + (code // 0x40), 0x80 + (code % 0x40))
        else
          buf[#buf + 1] = string.char(
            0xE0 + (code // 0x1000),
            0x80 + ((code // 0x40) % 0x40),
            0x80 + (code % 0x40))
        end
        j = j + 6
      else
        local r = unescape_map[e]
        if not r then decode_error(s, j, 'bad escape') end
        buf[#buf + 1] = r
        j = j + 2
      end
    else
      buf[#buf + 1] = c
      j = j + 1
    end
  end
end

local function parse_number(s, i)
  local pat = '^%-?%d+%.?%d*[eE]?[%+%-]?%d*'
  local num_str = s:match(pat, i)
  if not num_str or num_str == '' then decode_error(s, i, 'invalid number') end
  local n = tonumber(num_str)
  if not n then decode_error(s, i, 'invalid number') end
  return n, i + #num_str
end

local function parse_array(s, i)
  local arr, j = {}, skip_ws(s, i + 1)
  if s:sub(j, j) == ']' then return arr, j + 1 end
  while true do
    local v
    v, j = parse_value(s, j)
    arr[#arr + 1] = v
    j = skip_ws(s, j)
    local c = s:sub(j, j)
    if c == ',' then
      j = skip_ws(s, j + 1)
    elseif c == ']' then
      return arr, j + 1
    else
      decode_error(s, j, "expected ',' or ']'")
    end
  end
end

local function parse_object(s, i)
  local obj, j = {}, skip_ws(s, i + 1)
  if s:sub(j, j) == '}' then return obj, j + 1 end
  while true do
    if s:sub(j, j) ~= '"' then decode_error(s, j, 'expected string key') end
    local key
    key, j = parse_string(s, j)
    j = skip_ws(s, j)
    if s:sub(j, j) ~= ':' then decode_error(s, j, "expected ':'") end
    local v
    v, j = parse_value(s, skip_ws(s, j + 1))
    obj[key] = v
    j = skip_ws(s, j)
    local c = s:sub(j, j)
    if c == ',' then
      j = skip_ws(s, j + 1)
    elseif c == '}' then
      return obj, j + 1
    else
      decode_error(s, j, "expected ',' or '}'")
    end
  end
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '{' then return parse_object(s, i)
  elseif c == '[' then return parse_array(s, i)
  elseif c == '"' then return parse_string(s, i)
  elseif c == '-' or c:match('%d') then return parse_number(s, i)
  elseif s:sub(i, i + 3) == 'true' then return true, i + 4
  elseif s:sub(i, i + 4) == 'false' then return false, i + 5
  elseif s:sub(i, i + 3) == 'null' then return nil, i + 4
  else decode_error(s, i, 'unexpected character') end
end

function json.decode(s)
  local v, i = parse_value(s, 1)
  i = skip_ws(s, i)
  if i <= #s then decode_error(s, i, 'trailing garbage') end
  return v
end

return json
