-- Direct zone test
local config = require("modules.config")
local monitor_manager = require("modules.monitor_manager")
local zone_calculator = require("modules.zone_calculator")

-- Initialize 
zone_calculator.init(config, config.tiler.margins, function() end)

-- Get current screen
local screen = hs.window.focusedWindow():screen()
if not screen then
    print("No focused window")
    return
end
local mid = monitor_manager.get_id(screen)

-- Create zones for this monitor
zone_calculator.create_for_monitor(mid, screen)

-- Check zone y tiles
print("=== Zone y tiles ===")
local y_tiles = zone_calculator.get(mid, "y")
if y_tiles then
    for i, t in ipairs(y_tiles) do
        print(i, "x="..t.x.." y="..t.y.." w="..t.w.." h="..t.h)
    end
end

-- Check expected coords
print("=== Expected from config ===")
local y_config = config.tiler.layouts["2x2"]["y"]
if y_config then
    for _, coord in ipairs(y_config) do
        print(coord)
    end
end

-- Write to log
local f = io.open(os.getenv("HOME").."/zone_test.log", "w")
if y_tiles then
    f:write("Zone y tiles:\n")
    for i, t in ipairs(y_tiles) do
        f:write(i.." x="..t.x.." y="..t.y.." w="..t.w.." h="..t.h.."\n")
    end
end
if y_config then
    f:write("Config: "..table.concat(y_config, ", ").."\n")
end
f:close()
print("Log written to ~/zone_test.log")