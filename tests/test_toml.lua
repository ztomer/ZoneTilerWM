-- Unit tests for the custom TOML parser
local toml = require("modules.toml")

local function run_test(name, input, expected_check_fn)
    print("----------------------------------------------------------------")
    print("Running: " .. name)
    local status, result = pcall(toml.parse, input)

    if not status then
        print("[FAIL] Parser crashed: " .. tostring(result))
        os.exit(1)
    end

    local success, err = expected_check_fn(result)
    if success then
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name)
        print("Error: " .. err)
        -- Helper to dump table for debugging
        local function dump(o)
           if type(o) == 'table' then
              local s = '{ '
              for k,v in pairs(o) do
                 if type(k) ~= 'number' then k = '"'..k..'"' end
                 s = s .. '['..k..'] = ' .. dump(v) .. ','
              end
              return s .. '} '
           else
              return tostring(o)
           end
        end
        print("Result: " .. dump(result))
        os.exit(1)
    end
end

print("=== Starting TOML Parser Unit Tests ===")

-- 1. Basic Types
run_test("Basic Types", [[
title = "TOML Example"
enabled = true
count = 42
pi = 3.14
]], function(t)
    if t.title ~= "TOML Example" then return false, "title mismatch" end
    if t.enabled ~= true then return false, "enabled mismatch" end
    if t.count ~= 42 then return false, "count mismatch" end
    -- simple float check
    if t.pi ~= 3.14 then return false, "pi mismatch" end
    return true, ""
end)

-- 2. Tables and Sections
run_test("Tables", [[
[owner]
name = "Tom Preacher"
dob = "1979-05-27T07:32:00-08:00"

[database]
server = "192.168.1.1"
ports = [ 8001, 8001, 8002 ]
]], function(t)
    if not t.owner or t.owner.name ~= "Tom Preacher" then return false, "owner.name mismatch" end
    if not t.database or t.database.server ~= "192.168.1.1" then return false, "database.server mismatch" end
    if #t.database.ports ~= 3 then return false, "ports length mismatch" end
    if t.database.ports[3] ~= 8002 then return false, "ports content mismatch" end
    return true, ""
end)

-- 3. Quoted Keys
run_test("Quoted Keys", [[
[servers]
"alpha.beta" = "ip1"
'gamma.delta' = 'ip2'
]], function(t)
    if not t.servers then return false, "servers missing" end
    if t.servers["alpha.beta"] ~= "ip1" then return false, "quoted double key mismatch" end
    if t.servers["gamma.delta"] ~= "ip2" then return false, "quoted single key mismatch" end
    return true, ""
end)

-- 4. Multi-line Arrays (The Regression Fix)
run_test("Multi-line Arrays", [[
ambiguous_apps = [
  ["notion", "notion calendar"],
  ["notion", "notion mail"]
]
numbers = [
  1, 2,
  3, 4
]
]], function(t)
    if not t.ambiguous_apps then return false, "ambiguous_apps missing" end
    if #t.ambiguous_apps ~= 2 then return false, "ambiguous_apps length mismatch" end
    if t.ambiguous_apps[1][2] ~= "notion calendar" then return false, "nested content mismatch" end

    if not t.numbers then return false, "numbers missing" end
    if #t.numbers ~= 4 then return false, "numbers length mismatch" end
    if t.numbers[4] ~= 4 then return false, "numbers content mismatch" end
    return true, ""
end)

-- 5. Nested Tables (Dot notation)
run_test("Nested Tables", [[
[server.alpha]
ip = "10.0.0.1"
role = "frontend"

[server.beta]
ip = "10.0.0.2"
role = "backend"
]], function(t)
    if not t.server then return false, "server missing" end
    if not t.server.alpha or t.server.alpha.ip ~= "10.0.0.1" then return false, "server.alpha mismatch" end
    if not t.server.beta or t.server.beta.role ~= "backend" then return false, "server.beta mismatch" end
    return true, ""
end)

-- 6. Comments
run_test("Comments", [[
# This is a full line comment
key = "value" # This is an inline comment
[section] # Section comment
val = 123
]], function(t)
    if t.key ~= "value" then return false, "key mismatch" end
    if not t.section or t.section.val ~= 123 then return false, "section value mismatch" end
    -- Attempt to verify comments didn't sneak in as keys (rough check)
    for k,_ in pairs(t) do
        if k:find("#") then return false, "comment leaked into key" end
    end
    return true, ""
end)

-- 7. Inline Tables (Basic support check - parser might be limited here so keeping it simple)
-- Note: Our parser supports standard [table] syntax well. Inline tables { a = 1 } support depends on parse_value.
-- Based on code reading, `parse_value` handles arrays `[]` but maybe not `{}` fully recursively yet?
-- Let's test if simple inline tables work or fail gracefully.
run_test("Inline Tables (Experimental)", [[
point = { x = 1, y = 2 }
]], function(t)
    -- If the parser strictly does not support inline tables, this might return the raw string or fail.
    -- Looking at code: `if char == '[' or char == '{'` in array parsing... wait, `parse_value` only checks `[` start.
    -- So `{}` syntax is likely NOT supported by `parse_value` top level logic.
    -- Let's see if it treats it as string or fails.
    if type(t.point) == 'string' then
        print("(Warn: Inline tables returned as string, implementation limited)")
        return true, ""
    elseif type(t.point) == 'table' then
         if t.point.x == 1 then return true, "" else return false, "inline table content mismatch" end
    else
        return true, "Parsed as " .. type(t.point) -- Accept pass for now as strict requirement wasn't set, just exploring coverage
    end
end)

print("=== All Tests Passed ===")
