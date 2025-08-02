-- zone_calculator.lua
-- Manages zone definitions, layouts, and calculates tile frames for each monitor.
local hs_screen = hs.screen
local lru_cache = require "modules.lru_cache"

local zone_calculator = {}

-- Module state
local config = nil -- Set in init
local margins = nil -- Set in init
local debug_log = function(...)
end -- Placeholder, will be set in init
local layout_cache = nil -- To be initialized in init()

local zones = {
    -- Active zones: monitor_id -> zone_key -> tiles[]
    by_monitor = {}
}

-- Create tile from grid coordinates or named position
local function create_tile(screen, coords, rows, cols)
    local frame = screen:frame()
    local w, h, x, y = frame.w, frame.h, frame.x, frame.y

    -- Handle named positions
    if type(coords) == "string" then
        if coords == "full" then
            return {
                x = x,
                y = y,
                w = w,
                h = h
            }
        elseif coords == "center" then
            return {
                x = x + w / 4,
                y = y + h / 4,
                w = w / 2,
                h = h / 2
            }
        elseif coords == "left-half" then
            return {
                x = x,
                y = y,
                w = w / 2,
                h = h
            }
        elseif coords == "right-half" then
            return {
                x = x + w / 2,
                y = y,
                w = w / 2,
                h = h
            }
        elseif coords == "top-half" then
            return {
                x = x,
                y = y,
                w = w,
                h = h / 2
            }
        elseif coords == "bottom-half" then
            return {
                x = x,
                y = y + h / 2,
                w = w,
                h = h / 2
            }
        end

        -- Parse grid coordinates like "a1:b2" or "a1"
        local col_start_char, row_start_str, col_end_char, row_end_str = coords:match(
            "([a-z])([0-9]+):?([a-z]?)([0-9]*)")
        if col_start_char and row_start_str then
            local col_start = string.byte(col_start_char) - string.byte('a') + 1
            local row_start = tonumber(row_start_str)
            local col_end = col_end_char ~= "" and (string.byte(col_end_char) - string.byte('a') + 1) or col_start
            local row_end = row_end_str ~= "" and tonumber(row_end_str) or row_start

            local col_width = w / cols
            local row_height = h / rows
            local tile_x = x + (col_start - 1) * col_width
            local tile_y = y + (row_start - 1) * row_height
            local tile_w = (col_end - col_start + 1) * col_width
            local tile_h = (row_end - row_start + 1) * row_height

            if margins and margins.enabled then
                local margin = margins.size or 0
                local apply_left_margin = (col_start == 1 and margins.screen_edge) or (col_start > 1)
                local apply_top_margin = (row_start == 1 and margins.screen_edge) or (row_start > 1)
                local apply_right_margin = (col_end == cols and margins.screen_edge) or (col_end < cols)
                local apply_bottom_margin = (row_end == rows and margins.screen_edge) or (row_end < rows)

                if apply_left_margin then
                    tile_x = tile_x + margin
                    tile_w = tile_w - margin
                end
                if apply_top_margin then
                    tile_y = tile_y + margin
                    tile_h = tile_h - margin
                end
                if apply_right_margin then
                    tile_w = tile_w - margin
                end
                if apply_bottom_margin then
                    tile_h = tile_h - margin
                end
            end
            return {
                x = tile_x,
                y = tile_y,
                w = tile_w,
                h = tile_h
            }
        end
    end
    debug_log("Could not create tile for coords:", coords, "on screen", screen:name())
    return nil
end

-- Get zone layout for screen (exposed for smart_placer)
function zone_calculator.get_layout_config(screen)
    local frame = screen:frame()
    local name = screen:name()
    local is_portrait = frame.h > frame.w

    -- Check custom screens first
    if config.tiler.custom_screens then
        for screen_name_pattern, custom_config in pairs(config.tiler.custom_screens) do
            -- Allow exact match or pattern match for custom_screens key
            if name == screen_name_pattern or name:match(screen_name_pattern) then
                debug_log("Using custom screen layout for:", name, "->", custom_config.layout)
                return config.tiler.grids[custom_config.layout], custom_config.layout
            end
        end
    end

    -- Check pattern matches
    if config.tiler.screen_detection and config.tiler.screen_detection.patterns then
        for pattern, layout_key in pairs(config.tiler.screen_detection.patterns) do
            if name:match(pattern) then
                debug_log("Screen name", name, "matched pattern", pattern, "-> using layout", layout_key)
                return config.tiler.grids[layout_key], layout_key
            end
        end
    end

    -- Default based on resolution and orientation
    local layout_key
    if is_portrait then
        if config.tiler.screen_detection and config.tiler.screen_detection.portrait then
            if frame.h >= (config.tiler.screen_detection.portrait.large and
                config.tiler.screen_detection.portrait.large.min_height_for_layout_check or 2000) then
                layout_key = config.tiler.screen_detection.portrait.large.layout
            else
                layout_key = config.tiler.screen_detection.portrait.small.layout
            end
        else -- Fallback if portrait config is missing
            layout_key = frame.w >= 1440 and "1x3" or "1x2"
        end
    else
        local aspect_ratio = frame.w / frame.h
        if frame.w >= 3840 then
            layout_key = "4x3"
        elseif frame.w >= 3440 or aspect_ratio > 2.0 then
            layout_key = "4x3"
        elseif frame.w >= 2560 then
            layout_key = "3x3"
        elseif frame.w >= 1920 then
            layout_key = "3x2"
        else
            layout_key = "2x2"
        end
    end
    debug_log("Using default layout for screen:", name, "->", layout_key, "Portrait:", is_portrait)
    return config.tiler.grids[layout_key], layout_key
end

-- Initialize zones for a monitor
function zone_calculator.create_for_monitor(monitor_id, screen)
    local grid_config, layout_key = zone_calculator.get_layout_config(screen)

    if not grid_config or not layout_key then
        debug_log("Failed to get layout for monitor", monitor_id, screen:name(), "- using default 2x2.")
        grid_config = config.tiler.grids["2x2"]
        layout_key = "2x2"
    end

    local rows = grid_config.rows
    local cols = grid_config.cols

    zones.by_monitor[monitor_id] = {}
    debug_log("Creating zones for monitor", monitor_id, screen:name(), "layout_key:", layout_key, "grid:",
        cols .. "x" .. rows)

    local zone_definitions = config.tiler.layouts[layout_key] or config.tiler.layouts["default"]

    if not zone_definitions then
        debug_log("No zone definitions found for layout_key:", layout_key, "- using default definitions.")
        zone_definitions = config.tiler.layouts["default"]
    end
    if not zone_definitions then
        debug_log("CRITICAL: No default zone definitions found in config.tiler.layouts. Zones will not be created.")
        return
    end

    for zone_key, tile_coords_array in pairs(zone_definitions) do
        if zone_key ~= "default" then -- "default" itself is not a zone key for hotkeys
            local tiles_for_this_zone = {}
            for _, coords_str in ipairs(tile_coords_array) do
                local tile = create_tile(screen, coords_str, rows, cols)
                if tile then
                    table.insert(tiles_for_this_zone, tile)
                end
            end
            if #tiles_for_this_zone > 0 then
                zones.by_monitor[monitor_id][zone_key] = tiles_for_this_zone
            else
                debug_log("No tiles created for zone", zone_key, "on monitor", monitor_id, "for layout", layout_key)
            end
        end
    end
end

-- Get zone for monitor
function zone_calculator.get(monitor_id, zone_key)
    if zones.by_monitor[monitor_id] and zones.by_monitor[monitor_id][zone_key] then
        return zones.by_monitor[monitor_id][zone_key]
    end
    return nil
end

-- Clear all calculated zones (used on screen change)
function zone_calculator.clear_all()
    zones.by_monitor = {}
end

-- Check if zones exist for a monitor
function zone_calculator.has_zones(monitor_id)
    if zones.by_monitor[monitor_id] then
        return true
    end
    return false
end

-- Debug function to inspect a specific zone's tiles
function zone_calculator.debug_zone_tiles(monitor_id, zone_key)
    local zone_tiles = zone_calculator.get(monitor_id, zone_key)
    if not zone_tiles then
        print("Zone '" .. zone_key .. "' not found on monitor " .. monitor_id)
        if zones.by_monitor[monitor_id] then
            print("\nAvailable zones on this monitor:")
            local available_keys = {}
            for key, _ in pairs(zones.by_monitor[monitor_id]) do
                table.insert(available_keys, key)
            end
            table.sort(available_keys)
            print("  " .. table.concat(available_keys, ", "))
        else
            print("No zones initialized for this monitor.")
        end
        return
    end

    print("\nZone '" .. zone_key .. "' has " .. #zone_tiles .. " tiles:")
    for i, tile in ipairs(zone_tiles) do
        print(string.format("  Tile %d: x=%.1f, y=%.1f, w=%.1f, h=%.1f", i, tile.x, tile.y, tile.w, tile.h))
    end
end

-- Initialize the module
function zone_calculator.init(cfg, margins_cfg, log_func)
    config = cfg
    margins = margins_cfg
    debug_log = log_func or debug_log
    debug_log("ZoneCalculator initialized")
end

return zone_calculator
