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

-- Place window smartly
function smart_placer.place_window(window)
    if not window or not window:isStandard() or window:isMinimized() then
        return false
    end

    if not config.tiler.smart_placement or not config.tiler.smart_placement.enabled then
        return false
    end

    -- Exclude configured apps from smart placement
    if config.tiler.smart_placement.exclude_apps then
        local app_name = window:application():name()
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
        debug_log("Skipping smart placement, window already in a zone:", window:application():name())
        return false
    end

    local monitor_id = monitor_manager.get_id(screen)

    -- 1. Get all occupied tiles on this monitor
    local occupied_tiles = {} -- Set of "zone_key:tile_index"
    local all_states = window_state_manager._state.positions
    for _, pos in pairs(all_states) do
        if pos.monitor_id == monitor_id then
            local key = pos.zone_key .. ":" .. tostring(pos.tile_index)
            occupied_tiles[key] = true
        end
    end

    -- 2. Get layout for this monitor to know which zones are available
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

    -- 3. Define a search order for zones and search for an empty tile
    local zone_search_order = {"j", "h", "k", "y", "u", "i", "n", "m", ",", "0"} -- Could be configurable
    for zone_key, _ in pairs(layout_zones) do
        local found = false
        for _, z in ipairs(zone_search_order) do
            if z == zone_key then
                found = true;
                break
            end
        end
        if not found and zone_key ~= "default" then
            table.insert(zone_search_order, zone_key)
        end
    end

    for _, zone_key in ipairs(zone_search_order) do
        local zone_tiles = zone_calculator.get(monitor_id, zone_key)
        if zone_tiles then
            for i = 1, #zone_tiles do
                local tile_key = zone_key .. ":" .. tostring(i)
                if not occupied_tiles[tile_key] then
                    debug_log("Smart placer found empty tile: monitor", monitor_id, "zone", zone_key, "tile", i)
                    return window_actions.position_window_from_memory(window, monitor_id, zone_key, i)
                end
            end
        end
    end

    debug_log("Smart placer could not find any empty tile for window:", window:application():name())
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
