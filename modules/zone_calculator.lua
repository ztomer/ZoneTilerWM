--- Manages the geometric definition of layouts, zones, and tiles.
-- This module is responsible for:
-- - Detecting the appropriate layout for each monitor based on its name, resolution, or orientation.
-- - Calculating the precise frames (x, y, width, height) for every tile within a zone.
-- - Caching layout information to improve performance.
-- - Providing utility functions to convert between grid coordinates (e.g., "a1:b2") and pixel frames.
-- @module zone_calculator
-- @class zone_calculator
local hs_screen = hs.screen
local lru_cache = require "modules.lru_cache"
local resize_manager = require "modules.resize_manager"

local zone_calculator = {}

--@class Tile
--@field x number
--@field y number
--@field w number
--@field h number

--@class GridCoords
--@field col_start number
--@field row_start number
--@field num_cols number
--@field num_rows number

--@class GridConfig
--@field rows number
--@field cols number

--@class LayoutCacheEntry
--@field grid_config GridConfig
--@field layout_key string

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("zone_calculator")

-- Module state
local config = nil -- Set in init
local margins = nil -- Set in init
--@type lru_cache<string, LayoutCacheEntry>
local layout_cache = nil -- To be initialized in init()

local zones = {
    -- Active zones: monitor_id -> zone_key -> tiles[]
    --@type table<string, table<string, Tile[]>>
    by_monitor = {}
}

---
-- Creates a tile (a rectangle frame) from various coordinate formats.
-- It can interpret named positions ("full", "center"), grid coordinates ("a1:b2"),
-- or a direct coordinate table.
-- @local
-- @param screen hs.screen The screen object on which the tile will be created.
-- @param coords string|table The coordinates to use. Can be a string like "full", "a1:b2", or a table from `create_tile_from_grid_coords`.
-- @param rows number The total number of rows in the screen's grid.
-- @param cols number The total number of columns in the screen's grid.
-- @return Tile|nil A tile object {x, y, w, h} or nil if creation fails.
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

            return zone_calculator.create_tile_from_grid_coords(screen, {
                col_start = col_start,
                row_start = row_start,
                num_cols = col_end - col_start + 1,
                num_rows = row_end - row_start + 1
            }, rows, cols)
        end
    end
    debug_log("Could not create tile for coords:", coords, "on screen", screen:name())
    return nil
end

---
-- Determines the appropriate layout configuration for a given screen.
-- It uses a cached result if available. Otherwise, it determines the layout by checking:
-- 1. Custom screen configurations in `config.tiler.custom_screens`.
-- 2. Screen name patterns in `config.tiler.screen_detection.patterns`.
-- 3. Default logic based on resolution and orientation (portrait/landscape).
-- The result is then cached for future calls.
-- @param screen hs.screen The screen object.
-- @return GridConfig|nil The grid configuration table (e.g., {rows=3, cols=4}).
-- @return string|nil The key of the determined layout (e.g., "4x3").
function zone_calculator.get_layout_config(screen)
    local monitor_id = screen:getUUID()
    local cached = layout_cache:get(monitor_id)
    if cached then
        return cached.grid_config, cached.layout_key
    end

    -- Uncached logic starts here
    local frame = screen:frame()
    local name = screen:name()
    local is_portrait = frame.h > frame.w
    local layout_key

    -- Check custom screens first.
    -- NOTE: iterate keys in sorted order (not pairs()) so the chosen match is
    -- deterministic when several patterns match the same screen name. First match
    -- in sorted order wins (previously the last hash-order match won).
    if config.tiler.custom_screens then
        local keys = {}
        for k in pairs(config.tiler.custom_screens) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, screen_name_pattern in ipairs(keys) do
            local custom_config = config.tiler.custom_screens[screen_name_pattern]
            if name == screen_name_pattern or name:match(screen_name_pattern) then
                debug_log("Using custom screen layout for:", name, "->", custom_config.layout)
                layout_key = custom_config.layout
                break
            end
        end
    end

    -- Check pattern matches (sorted order for determinism; first match wins).
    if not layout_key and config.tiler.screen_detection and config.tiler.screen_detection.patterns then
        local keys = {}
        for k in pairs(config.tiler.screen_detection.patterns) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, pattern in ipairs(keys) do
            local l_key = config.tiler.screen_detection.patterns[pattern]
            if name:match(pattern) then
                debug_log("Screen name", name, "matched pattern", pattern, "-> using layout", l_key)
                layout_key = l_key
                break -- Found a match
            end
        end
    end

    -- Default based on resolution and orientation
    if not layout_key then
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
    end

    debug_log("Using default layout for screen:", name, "->", layout_key, "Portrait:", is_portrait)
    --@type GridConfig
    local grid_config = config.tiler.grids[layout_key]

    if grid_config and layout_key then
        layout_cache:set(monitor_id, {
            grid_config = grid_config,
            layout_key = layout_key
        })
    end
    return grid_config, layout_key
end

---
-- Creates and stores all zone and tile definitions for a specific monitor.
-- It determines the correct layout, then iterates through the zone definitions
-- for that layout, creating and storing the tile frames for each zone.
-- @param monitor_id string The stable ID of the monitor.
-- @param screen hs.screen The screen object to create zones for.
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
            --@type Tile[]
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

---
-- Retrieves the calculated tiles for a specific zone on a monitor.
-- @param monitor_id string The ID of the monitor.
-- @param zone_key string The key of the desired zone.
-- @return Tile[]|nil An array of tile frame objects, or nil if the zone is not found.
function zone_calculator.get(monitor_id, zone_key)
    if not zones.by_monitor[monitor_id] then
        print("[ZoneCalc] ERROR: No zones for monitor ID: " .. tostring(monitor_id))
        -- Trigger lazy init?
        return nil
    end
    if zones.by_monitor[monitor_id] and zones.by_monitor[monitor_id][zone_key] then
        return zones.by_monitor[monitor_id][zone_key]
    end
    return nil
end

---
-- Clears all cached zone and layout information.
-- This is called when screen configurations change to force recalculation.
function zone_calculator.clear_all()
    zones.by_monitor = {}
    if layout_cache then
        layout_cache:clear()
    end
end

---
-- Checks if zones have been calculated and stored for a given monitor.
-- @param monitor_id string The ID of the monitor to check.
-- @return boolean `true` if zones exist, `false` otherwise.
function zone_calculator.has_zones(monitor_id)
    if zones.by_monitor[monitor_id] then
        return true
    end
    return false
end

---
-- Prints debugging information about a zone's tiles to the console.
-- @param monitor_id string The ID of the monitor where the zone resides.
-- @param zone_key string The key of the zone to inspect.
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

---
-- Calculates a tile frame based on numeric grid coordinates.
-- This is the core geometric calculation function.
-- @param screen hs.screen The screen object.
-- @param grid_coords GridCoords A table with {col_start, row_start, num_cols, num_rows}.
-- @param rows number The total number of rows in the screen's grid.
-- @param cols number The total number of columns in the screen's grid.
-- @return Tile A tile object {x, y, w, h} with margins applied.
function zone_calculator.create_tile_from_grid_coords(screen, grid_coords, rows, cols)
    local frame = screen:frame()
    local w, h, x, y = frame.w, frame.h, frame.x, frame.y
    local monitor_id = require("modules.monitor_manager").get_id(screen)

    local col_start = grid_coords.col_start
    local row_start = grid_coords.row_start
    local col_end = grid_coords.col_start + grid_coords.num_cols - 1
    local row_end = grid_coords.row_start + grid_coords.num_rows - 1

    -- Helper to get cumulative offset for a grid line
    local function get_line_pos(axis, index, total_size, count)
        if index <= 0 then return 0 end
        if index >= count then return total_size end

        local default_pos = (index / count) * total_size
        local offset_pct = resize_manager.get_offset(monitor_id, axis, index)
        local offset_px = offset_pct * total_size

        return default_pos + offset_px
    end

    local x_start = get_line_pos("x", col_start - 1, w, cols)
    local x_end = get_line_pos("x", col_end, w, cols)
    local y_start = get_line_pos("y", row_start - 1, h, rows)
    local y_end = get_line_pos("y", row_end, h, rows)

    local tile_x = x + x_start
    local tile_y = y + y_start
    local tile_w = x_end - x_start
    local tile_h = y_end - y_start

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

---
-- Reverse-engineers the grid coordinates from a given tile frame.
-- This is used for features that need to understand a window's position in
-- terms of the grid, not just pixels.
-- @param screen hs.screen The screen object.
-- @param tile Tile The tile frame {x, y, w, h}.
-- @param rows number The total number of rows in the screen's grid.
-- @param cols number The total number of columns in the screen's grid.
-- @return GridCoords|nil A grid coordinate table {col_start, row_start, num_cols, num_rows} or nil on failure.
function zone_calculator.get_grid_coords_for_tile(screen, tile, rows, cols)
    local frame = screen:frame()
    local w, h, x, y = frame.w, frame.h, frame.x, frame.y

    local col_width = w / cols
    local row_height = h / rows

    -- Reverse calculate the grid coordinates from the tile frame
    -- This needs to account for margins
    local margin = (margins and margins.enabled) and margins.size or 0

    -- Find the closest grid cell for the top-left corner
    local col_start = math.floor((tile.x - x) / col_width + 0.5) + 1
    local row_start = math.floor((tile.y - y) / row_height + 0.5) + 1

    -- Find the closest grid cell for the bottom-right corner
    local col_end = math.floor((tile.x - x + tile.w) / col_width + 0.5) + 1
    local row_end = math.floor((tile.y - y + tile.h) / row_height + 0.5) + 1

    -- Adjust for margins (this is tricky and might need refinement)
    -- A simple heuristic: if a tile edge is very close to a margin line, adjust it
    -- For now, we'll stick to the geometric calculation and refine if needed.

    local num_cols = col_end - col_start
    local num_rows = row_end - row_start

    -- Basic validation
    if col_start < 1 or row_start < 1 or col_end > cols or row_end > rows or num_cols < 1 or num_rows < 1 then
        debug_log("Could not accurately determine grid coordinates for tile.")
        return nil
    end

    return {
        col_start = col_start,
        row_start = row_start,
        num_cols = num_cols,
        num_rows = num_rows
    }
end

---
-- Initializes the `zone_calculator` module.
-- @param cfg table The main configuration table from `config.lua`.
-- @param margins_cfg table The margin configuration.
-- @param log_func function The logging function to use.
function zone_calculator.init(cfg, margins_cfg, log_func)
    config = cfg
    margins = margins_cfg
    debug_log = log_func or debug_log
    layout_cache = lru_cache.new(10) -- Cache up to 10 monitor layouts
    resize_manager.init()
    debug_log("ZoneCalculator initialized")
end

return zone_calculator