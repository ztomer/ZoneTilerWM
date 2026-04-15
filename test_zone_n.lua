-- Test zone n directly
local config = require("modules.config")
local monitor_manager = require("modules.monitor_manager")
local zone_calculator = require("modules.zone_calculator")
local window_cache = require("modules.window_cache")

zone_calculator.init(config, config.tiler.margins, function() end)

local screen = hs.window.focusedWindow():screen()
local mid = monitor_manager.get_id(screen)
zone_calculator.create_for_monitor(mid, screen)

-- Check zone n tiles
print("=== Zone n tiles ===")
local n_tiles = zone_calculator.get(mid, "n")
for i, t in ipairs(n_tiles) do
    print(i, "x="..t.x.." y="..t.y.." w="..t.w.." h="..t.h)
end

-- Check what's in cache for this screen  
print("=== Cache for screen "..mid.." ===")
local cache_windows = window_cache.get_for_screen_with_cache(mid)
for i, info in ipairs(cache_windows) do
    print(i, info.app_name, "x="..info.frame.x.." y="..info.frame.y.." w="..info.frame.w.." h="..info.frame.h)
end

-- What placement sees
print("=== Largest-free-space would see ===")
local occupied = {}
for _, info in ipairs(cache_windows) do
    table.insert(occupied, info.frame)
end
print("Occupied frames: "..#occupied)

-- Check if any tile is free
local free_tiles = {}
for i, tile in ipairs(n_tiles) do
    local is_occupied = false
    for _, occ in ipairs(occupied) do
        if not (tile.x >= occ.x + occ.w or tile.x + tile.w <= occ.x or tile.y >= occ.y + occ.h or tile.y + tile.h <= occ.y) then
            is_occupied = true
            break
        end
    end
    if not is_occupied then
        table.insert(free_tiles, tile)
    end
end

print("Free tiles in zone n: "..#free_tiles)
for i, t in ipairs(free_tiles) do
    print(i, "x="..t.x.." y="..t.y.." w="..t.w.." h="..t.h)
end