-- smart_placer.lua
-- Contains the logic for intelligently placing new windows in empty tiles.
local hs_window = hs.window

local smart_placer = {}

-- Module state
local config = nil -- Set in init
local monitor_manager = nil -- Set in init
local zone_calculator = nil -- Set in init
local window_state_manager = nil -- Set in init
local window_actions = nil -- Set in init
local debug_log = function(...)
end -- Placeholder, will be set in init

--- Checks if two rectangles intersect.
-- @local
-- @param r1 (table) A rectangle with `{x, y, w, h}`.
-- @param r2 (table) A rectangle with `{x, y, w, h}`.
-- @return (boolean) `true` if they intersect, `false` otherwise.
local function rectangles_intersect(r1, r2)
    if not r1 or not r2 then return false end
    return not (r2.x >= r1.x + r1.w or r2.x + r2.w <= r1.x or r2.y >= r1.y + r1.h or r2.y + r2.h <= r1.y)
end

-- Place window smartly by finding the largest free tile on the monitor
function smart_placer.place_window(window)
    if not window or not window:isStandard() or window:isMinimized() then
        return false
    end

    if not config.tiler.smart_placement or not config.tiler.smart_placement.enabled then
        return false
    end

    -- Exclude configured apps from smart placement
    local app_name = window:application() and window:application():name()
    if app_name and config.tiler.smart_placement.exclude_apps then
        for _, excluded_app in ipairs(config.tiler.smart_placement.exclude_apps) do
            if app_name == excluded_app then
                debug_log("Skipping smart placement for excluded app:", app_name)
                return false
            end
        end
    end

    local screen = window:screen()
    if not screen then
        return false
    end

    -- Skip if window is already in a tiler-managed zone
    if window_state_manager and window_state_manager.get and window_state_manager.get(window:id()) then
        debug_log("Skipping smart placement, window already in a zone:", app_name)
        return false
    end

    local monitor_id = monitor_manager.get_id(screen)

    -- 1. Get all other windows on the same screen to check for overlaps
    local all_windows_on_screen = hs_window.filter.new(false):setScreens(screen:name()):getWindows()
    local occupied_frames = {}
    for _, win in ipairs(all_windows_on_screen) do
        if win:id() ~= window:id() then
            table.insert(occupied_frames, win:frame())
        end
    end

    -- 2. Get layout for this monitor to know which zones and tiles are available
    local _, layout_key = zone_calculator.get_layout_config(screen)
    if not layout_key then
        debug_log("Smart placer: could not determine layout key for monitor", monitor_id)
        return false
    end

    local layout_zones = config.tiler.layouts[layout_key]
    if not layout_zones then
        debug_log("Smart placer: no layout found for key", layout_key)
        return false
    end

    -- 3. Iterate through all zones and their tiles to find the largest free one
    local best_tile = nil
    local best_zone_key = nil
    local best_tile_index = -1
    local max_area = -1

    for zone_key, _ in pairs(layout_zones) do
        if zone_key ~= "default" then
            local zone_tiles = zone_calculator.get(monitor_id, zone_key)
            if zone_tiles then
                for i = 1, #zone_tiles do
                    local candidate_tile = zone_tiles[i]
                    local is_occupied = false
                    for _, occupied_frame in ipairs(occupied_frames) do
                        if rectangles_intersect(candidate_tile, occupied_frame) then
                            is_occupied = true
                            break
                        end
                    end

                    if not is_occupied then
                        local area = candidate_tile.w * candidate_tile.h
                        if area > max_area then
                            max_area = area
                            best_tile = candidate_tile
                            best_zone_key = zone_key
                            best_tile_index = i
                        end
                    end
                end
            end
        end
    end

    -- 4. If a best tile was found, move the window there
    if best_tile and best_zone_key and best_tile_index > 0 then
        debug_log("Smart placer found largest empty tile: monitor", monitor_id, "zone", best_zone_key, "tile",
            best_tile_index)
        return window_actions.position_window_from_memory(window, monitor_id, best_zone_key, best_tile_index)
    end

    debug_log("Smart placer could not find any empty tile for window:", app_name)
    return false
end


-- Initialize the module
function smart_placer.init(cfg, mm, zc, wsm, wa, log_func)
    config = cfg
    monitor_manager = mm
    zone_calculator = zc
    window_state_manager = wsm
    window_actions = wa
    debug_log = log_func or debug_log
    debug_log("SmartPlacer initialized")
end

return smart_placer