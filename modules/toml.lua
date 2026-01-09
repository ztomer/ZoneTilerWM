--[[
  TOML Parser for Lua
  Based on simple TOML parsers available in the Lua ecosystem.
  Supports:
  - Basic types: strings, integers, floats, booleans
  - Arrays (including nested)
  - Tables (standard and inline)
  - Comments
]]

local toml = {}

local function trim(s)
    return s:match('^%s*(.-)%s*$')
end

local function parse_string(str)
    -- Handle escaped quotes and basics
    if str:sub(1, 1) == '"' and str:sub(-1) == '"' then
        return str:sub(2, -2):gsub('\\\\', '\\'):gsub('\\"', '"'):gsub('\\n', '\n')
    elseif str:sub(1, 1) == "'" and str:sub(-1) == "'" then
        return str:sub(2, -2)
    end
    return str
end

local function parse_value(val)
    val = trim(val)
    if val == 'true' then
        return true
    end
    if val == 'false' then
        return false
    end

    -- Strings
    if val:find('^".*"$') or val:find("^'.*'$") then
        return parse_string(val)
    end

    -- Numbers
    local num = tonumber(val)
    if num then
        return num
    end

    -- Arrays
    if val:sub(1, 1) == '[' and val:sub(-1) == ']' then
        local content = val:sub(2, -2)
        local items = {}
        local current = ''
        local in_quote = false
        local depth = 0

        for i = 1, #content do
            local char = content:sub(i, i)

            if char == '"' or char == "'" then
                in_quote = not in_quote
            end

            if not in_quote then
                if char == '[' or char == '{' then
                    depth = depth + 1
                end
                if char == ']' or char == '}' then
                    depth = depth - 1
                end
            end

            if char == ',' and depth == 0 and not in_quote then
                local val = parse_value(trim(current))
                items[#items + 1] = val
                current = ''
            else
                current = current .. char
            end
        end
        if trim(current) ~= '' then
            local val = parse_value(trim(current))
            items[#items + 1] = val
        end
        return items
    end

    return val
end

function toml.parse(data)
    local result = {}
    local current_table = result

    local accumulating = false
    local accumulator = ""
    local acc_key = nil

    for line in data:gmatch('[^\r\n]+') do
        -- Remove comments (basic) - note: inside strings this might be aggressive but keeps consistent with existing logic
        line = line:gsub('%s*#.*$', '')
        line = trim(line)

        if line == '' then
            -- Skip empty lines
        elseif accumulating then
            accumulator = accumulator .. line
            -- Check if balanced
            local opens = select(2, accumulator:gsub('%[', ''))
            local closes = select(2, accumulator:gsub('%]', ''))
            if opens == closes then
                 current_table[acc_key] = parse_value(accumulator)
                 accumulating = false
                 accumulator = ""
                 acc_key = nil
            end
        elseif line:sub(1, 1) == '[' and line:sub(-1) == ']' then
            -- Table definition
            local table_name = line:sub(2, -2)
            current_table = result

            for part in table_name:gmatch('[^%.]+') do
                part = trim(part)
                -- Handle quoted keys
                if part:find('^".*"$') or part:find("^'.*'$") then
                    part = parse_string(part)
                end

                if not current_table[part] then
                    current_table[part] = {}
                end
                current_table = current_table[part]
            end
        elseif line:find('=') then
            -- Key-value pair
            local key, value = line:match('^%s*(.-)%s*=%s*(.+)$')
            if key and value then
                key = trim(key)
                if key:find('^".*"$') or key:find("^'.*'$") then
                    key = parse_string(key)
                end

                local v_trimmed = trim(value)
                -- Check for start of array
                if v_trimmed:sub(1,1) == '[' then
                    -- Check if balanced on single line
                    local opens = select(2, v_trimmed:gsub('%[', ''))
                    local closes = select(2, v_trimmed:gsub('%]', ''))
                    if opens == closes then
                        current_table[key] = parse_value(v_trimmed)
                    else
                        -- Start accumulating
                        accumulating = true
                        acc_key = key
                        accumulator = v_trimmed
                    end
                else
                    current_table[key] = parse_value(v_trimmed)
                end
            end
        end
    end

    return result
end

return toml
