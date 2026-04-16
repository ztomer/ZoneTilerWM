-- Test script for TOML parser multi-line support

local toml = require("modules.toml")

local input = [[
[app_switcher]
# Multi-line array test
ambiguous_apps = [
    ["notion", "notion calendar"],
    ["notion", "notion mail"]
]
single_line = [1, 2, 3]
]]

print("Parsing TOML input...")
local result = toml.parse(input)

local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         local key = k
         if type(key) ~= 'number' then key = '"'..key..'"' end
         s = s .. '['..key..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

print("Result:")
print(dump(result))

if result.app_switcher and result.app_switcher.ambiguous_apps then
    local apps = result.app_switcher.ambiguous_apps
    if type(apps) == 'table' and #apps == 2 then
        print("SUCCESS: Parsed multi-line array correctly.")
    else
        print("FAIL: parsed ambiguous_apps but structure is wrong. Type: " .. type(apps))
    end
else
    print("FAIL: app_switcher.ambiguous_apps is MISSING or nil.")
end
