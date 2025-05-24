--[[
Simplified Zone Tiler for Hammerspoon
====================================

Hierarchy: Monitor → Zone → Tile
- Each monitor has unique stable ID
- Each zone is a collection of tiles (window positions)
- Cross-monitor movement preserves zone+tile or uses cache
]] local config = require "config"
local tiler = {}

-- Window memory integration
local window_memory = nil

-- Debug logging
local function debug_log(...)
    if tiler.debug then
        local args = {...}
        local message = table.concat(args, " ")
        print("[Tiler] " .. message)
    end
end

-- State variable for managing focus cycling
local current_focus_cycle_manager = {
    zone_key = nil, -- The zone key for the active cycle (e.g., "h")
    monitor_id_logical = nil, -- The logical monitor ID for the cycle
    window_ids_in_order = {}, -- An ordered array of window IDs for the current cycle
    current_idx_in_cycle_list = 0 -- 0 means "uninitialized" or "before the first window"
    -- Otherwise, it's the 1-based index of the last window focused in this cycle
}

------------------------------------------
-- Smart placement
------------------------------------------

-- Smart placement module
local smart_placement = {}

-- Compute distance map for empty space finding
function smart_placement.compute_distance_map(screen, cell_size)
    local screen_frame = screen:frame()
    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)

    -- Initialize grid
    local grid = {}
    for i = 1, grid_height do
        grid[i] = {}
        for j = 1, grid_width do
            grid[i][j] = 0 -- 0 = empty
        end
    end

    -- Mark occupied cells
    for _, win in pairs(hs.window.allWindows()) do
        if win:screen():id() == screen:id() and win:isStandard() then
            local frame = win:frame()
            local x1 = math.floor((frame.x - screen_frame.x) / cell_size) + 1
            local y1 = math.floor((frame.y - screen_frame.y) / cell_size) + 1
            local x2 = math.ceil((frame.x + frame.w - screen_frame.x) / cell_size)
            local y2 = math.ceil((frame.y + frame.h - screen_frame.y) / cell_size)

            for i = math.max(1, y1), math.min(grid_height, y2) do
                for j = math.max(1, x1), math.min(grid_width, x2) do
                    grid[i][j] = 1 -- 1 = occupied
                end
            end
        end
    end

    -- BFS to compute distances from occupied cells
    local distance = {}
    local queue = {}

    for i = 1, grid_height do
        distance[i] = {}
        for j = 1, grid_width do
            if grid[i][j] == 1 then
                distance[i][j] = 0
                table.insert(queue, {i, j})
            else
                distance[i][j] = -1 -- -1 = unvisited
            end
        end
    end

    local directions = {{0, 1}, {0, -1}, {1, 0}, {-1, 0}}
    local head = 1
    while head <= #queue do
        local cell = queue[head]
        head = head + 1
        local i, j = cell[1], cell[2]

        for _, dir in pairs(directions) do
            local ni, nj = i + dir[1], j + dir[2]
            if ni >= 1 and ni <= grid_height and nj >= 1 and nj <= grid_width and distance[ni][nj] == -1 then
                distance[ni][nj] = distance[i][j] + 1
                table.insert(queue, {ni, nj})
            end
        end
    end

    return distance, screen_frame
end

-- Find best position for a window
function smart_placement.find_best_position(screen, window_width, window_height)
    local cell_size = config.tiler.smart_placement and config.tiler.smart_placement.cell_size or 50
    local distance_map, screen_frame = smart_placement.compute_distance_map(screen, cell_size)

    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)
    local window_grid_width = math.ceil(window_width / cell_size)
    local window_grid_height = math.ceil(window_height / cell_size)

    local best_score = -1
    local best_pos = {
        x = screen_frame.x + 100, -- Default fallback x
        y = screen_frame.y + 100 -- Default fallback y
    }

    for i = 1, math.max(1, grid_height - window_grid_height + 1) do
        for j = 1, math.max(1, grid_width - window_grid_width + 1) do
            local min_distance_in_rect = math.huge
            local covered_occupied_cell = false

            for di = 0, window_grid_height - 1 do
                for dj = 0, window_grid_width - 1 do
                    if i + di <= grid_height and j + dj <= grid_width then
                        local dist = distance_map[i + di][j + dj]
                        if dist == 0 then -- This cell is occupied
                            covered_occupied_cell = true
                            break
                        end
                        if dist < min_distance_in_rect then
                            min_distance_in_rect = dist
                        end
                    end
                end
                if covered_occupied_cell then
                    break
                end
            end

            if not covered_occupied_cell and min_distance_in_rect > best_score then
                best_score = min_distance_in_rect
                best_pos = {
                    x = screen_frame.x + (j - 1) * cell_size,
                    y = screen_frame.y + (i - 1) * cell_size
                }
            end
        end
    end
    debug_log("Smart placement best score:", best_score, "at x:", best_pos.x, "y:", best_pos.y)
    return best_pos
end

-- Place window smartly
function smart_placement.place_window(window)
    if not window or not window:isStandard() then
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
    if window_state and window_state.get and window_state.get(window:id()) then
        debug_log("Skipping smart placement, window already in a zone:", window:application():name())
        return false
    end

    local frame = window:frame()
    local pos = smart_placement.find_best_position(screen, frame.w, frame.h)

    window:setFrame({
        x = pos.x,
        y = pos.y,
        w = frame.w, -- Keep original width
        h = frame.h -- Keep original height
    })

    debug_log("Smart placed window", window:application():name(), "at x:", pos.x, "y:", pos.y)
    return true
end

------------------------------------------
-- Monitor Management
------------------------------------------

local monitors = {
    -- Stable monitor IDs that persist across reconnections
    registry = {}, -- monitor_key -> {id, name, frame, logical_id}
    next_logical_id = 1
}

-- Generate stable monitor key from screen properties
local function get_monitor_key(screen)
    local frame = screen:frame()
    local name = screen:name()
    -- Use position + resolution + name for stable identification
    return string.format("%s_%.0f_%.0f_%dx%d", name:gsub("[%s%-]", "_"), frame.x, frame.y, frame.w, frame.h)
end

-- Get or create stable monitor ID
function monitors.get_id(screen)
    local key = get_monitor_key(screen)

    if not monitors.registry[key] then
        monitors.registry[key] = {
            system_id = screen:id(),
            name = screen:name(),
            frame = screen:frame(),
            logical_id = monitors.next_logical_id,
            key = key
        }
        monitors.next_logical_id = monitors.next_logical_id + 1
        debug_log("Registered new monitor:", key, "logical_id:", monitors.registry[key].logical_id)
    else
        -- Update system ID and frame in case it changed (e.g. screen arrangement, resolution)
        monitors.registry[key].system_id = screen:id()
        monitors.registry[key].frame = screen:frame()
        monitors.registry[key].name = screen:name() -- Name might change too
    end

    return monitors.registry[key].logical_id
end

-- Get screen by monitor ID
function monitors.get_screen(monitor_id)
    for _, data in pairs(monitors.registry) do
        if data.logical_id == monitor_id then
            -- Find current screen with this system ID
            for _, screen_obj in ipairs(hs.screen.allScreens()) do
                if screen_obj:id() == data.system_id then
                    return screen_obj
                end
            end
            -- If not found by system_id, try to find by key
            for _, screen_obj in ipairs(hs.screen.allScreens()) do
                if get_monitor_key(screen_obj) == data.key then
                    debug_log("Found monitor", monitor_id, "by key after system_id mismatch. Updating registry.")
                    -- Update the registry with the new system_id
                    monitors.registry[data.key].system_id = screen_obj:id()
                    monitors.registry[data.key].frame = screen_obj:frame()
                    monitors.registry[data.key].name = screen_obj:name()
                    return screen_obj
                end
            end
            debug_log("Could not find screen for monitor_id:", monitor_id, "system_id:", data.system_id)
            return nil
        end
    end
    debug_log("Monitor ID not found in registry:", monitor_id)
    return nil
end

-- Expose monitors for window_memory
tiler.monitors = monitors

------------------------------------------
-- Zone and Tile Management
------------------------------------------

local zones = {
    -- Zone templates: zone_key -> tile_definitions[]
    templates = {},

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

            if tiler.margins and tiler.margins.enabled then
                local margin = tiler.margins.size or 0
                local apply_left_margin = (col_start == 1 and tiler.margins.screen_edge) or (col_start > 1)
                local apply_top_margin = (row_start == 1 and tiler.margins.screen_edge) or (row_start > 1)
                local apply_right_margin = (col_end == cols and tiler.margins.screen_edge) or (col_end < cols)
                local apply_bottom_margin = (row_end == rows and tiler.margins.screen_edge) or (row_end < rows)

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

-- Get zone layout for screen
local function get_zone_layout_config(screen)
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
function zones.create_for_monitor(monitor_id, screen)
    local grid_config, layout_key = get_zone_layout_config(screen)

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
function zones.get(monitor_id, zone_key)
    if zones.by_monitor[monitor_id] and zones.by_monitor[monitor_id][zone_key] then
        return zones.by_monitor[monitor_id][zone_key]
    end
    return nil
end

------------------------------------------
-- Window State Management
------------------------------------------

window_state = {
    -- window_id -> {monitor_id, zone_key, tile_index}
    positions = {},

    -- app_name -> monitor_id -> {zone_key, tile_index}
    app_memory = {}
}

-- Set window position
function window_state.set(window_id, monitor_id, zone_key, tile_index)
    window_state.positions[window_id] = {
        monitor_id = monitor_id,
        zone_key = zone_key,
        tile_index = tile_index
    }
    -- App memory update
    local window = hs.window.get(window_id)
    if window then
        local app_name = window:application():name()
        if not window_state.app_memory[app_name] then
            window_state.app_memory[app_name] = {}
        end
        window_state.app_memory[app_name][monitor_id] = {
            zone_key = zone_key,
            tile_index = tile_index
        }

        -- Notify window_memory if available
        if window_memory and window_memory.on_window_positioned then
            window_memory.on_window_positioned(window, monitor_id, zone_key, tile_index)
        end
    end
end

-- Get window position
function window_state.get(window_id)
    return window_state.positions[window_id]
end

-- Get remembered position for app on monitor
function window_state.get_app_memory(app_name, monitor_id)
    return window_state.app_memory[app_name] and window_state.app_memory[app_name][monitor_id]
end

-- Clean up window state
function window_state.cleanup(window_id)
    debug_log("Cleaning up window state for ID:", window_id)
    window_state.positions[window_id] = nil
end

-- Expose window_state for window_memory
tiler.window_state = window_state

------------------------------------------
-- Rectangle Utility Functions
------------------------------------------
local function frames_match(frame1, frame2, tolerance)
    tolerance = tolerance or 10
    if not frame1 or not frame2 then
        return false
    end
    return math.abs(frame1.x - frame2.x) <= tolerance and math.abs(frame1.y - frame2.y) <= tolerance and
               math.abs((frame1.w or frame1.width or 0) - (frame2.w or frame2.width or 0)) <= tolerance and
               math.abs((frame1.h or frame1.height or 0) - (frame2.h or frame2.height or 0)) <= tolerance
end

------------------------------------------
-- Window Utility Functions
------------------------------------------
local function is_problem_app(app_name)
    if not tiler.problem_apps or not app_name then
        return false
    end
    local lower_app_name = app_name:lower()
    for _, name in ipairs(tiler.problem_apps) do
        if name:lower() == lower_app_name then
            return true
        end
    end
    return false
end

local function apply_frame(window, frame, force_screen_obj)
    if not window or not window:isStandard() or not frame then
        debug_log("apply_frame: Invalid window or frame.")
        return false
    end
    local valid_frame = {
        x = frame.x,
        y = frame.y,
        w = frame.w or frame.width,
        h = frame.h or frame.height
    }
    if not (type(valid_frame.x) == "number" and type(valid_frame.y) == "number" and type(valid_frame.w) == "number" and
        valid_frame.w > 0 and type(valid_frame.h) == "number" and valid_frame.h > 0) then
        debug_log("apply_frame: Invalid frame parameters - x,y,w,h must be positive numbers.", hs.inspect(valid_frame))
        return false
    end

    if force_screen_obj and window:screen():id() ~= force_screen_obj:id() then
        debug_log("Moving window", window:application():name(), "to screen:", force_screen_obj:name())
        window:moveToScreen(force_screen_obj, false, true, 0)
    end

    local saved_duration = hs.window.animationDuration
    hs.window.animationDuration = 0
    local success = window:setFrame(valid_frame)
    hs.window.animationDuration = saved_duration

    if not success then
        debug_log("apply_frame: setFrame failed for window", window:application():name())
    end
    return success
end

local function apply_frame_to_problem_app(window, frame, app_name, screen_obj)
    debug_log("Using special handling for problem app:", app_name)
    if screen_obj and window:screen():id() ~= screen_obj:id() then
        window:moveToScreen(screen_obj, false, true, 0)
    end
    -- Attempt multiple times with delays
    local attempts = 5
    local delay = 0.1
    local function attempt_set_frame(current_attempt)
        if not window or not window:isStandard() then
            return
        end
        debug_log("Problem app", app_name, "setFrame attempt", current_attempt, "to", hs.inspect(frame))
        apply_frame(window, frame, screen_obj)

        if current_attempt < attempts then
            hs.timer.doAfter(delay, function()
                if window:isStandard() and not frames_match(window:frame(), frame, 20) then
                    debug_log("Problem app", app_name, "frame did not stick, retrying...")
                    attempt_set_frame(current_attempt + 1)
                else
                    debug_log("Problem app", app_name, "frame stuck or retries exhausted.")
                end
            end)
        end
    end
    attempt_set_frame(1)
    return true
end

local function apply_tile(window, tile, screen_obj)
    if not window or not window:isStandard() or not tile then
        debug_log("apply_tile: Invalid window or tile.")
        return false
    end
    local app_name = window:application():name()
    if is_problem_app(app_name) then
        return apply_frame_to_problem_app(window, tile, app_name, screen_obj)
    else
        return apply_frame(window, tile, screen_obj)
    end
end

-- Move window to zone/tile
function tiler.move_window_to_zone(zone_key)
    local window = hs.window.focusedWindow()
    if not window then
        debug_log("No focused window for move_window_to_zone");
        return false
    end

    local window_id = window:id()
    local screen_obj = window:screen()
    local monitor_id = monitors.get_id(screen_obj)

    debug_log("Moving window", window_id, "(", window:application():name(), ") to zone", zone_key, "on monitor",
        monitor_id)

    local current_pos = window_state.get(window_id)
    local zone_tiles = zones.get(monitor_id, zone_key)

    if not zone_tiles or #zone_tiles == 0 then
        debug_log("No tiles found for zone", zone_key, "on monitor", monitor_id, "(", screen_obj:name(), ")")
        -- Try to create zones for this monitor if they are missing
        if not zones.by_monitor[monitor_id] then
            debug_log("Zones not initialized for monitor", monitor_id, screen_obj:name(), ". Initializing now.")
            zones.create_for_monitor(monitor_id, screen_obj)
            zone_tiles = zones.get(monitor_id, zone_key)
            if not zone_tiles or #zone_tiles == 0 then
                debug_log("Still no tiles after re-initialization for zone", zone_key)
                return false
            end
        else
            debug_log("Zone key", zone_key, "specifically not found for monitor", monitor_id)
            return false
        end
    end

    local tile_index_to_apply = 1 -- 1-based index
    if current_pos and current_pos.zone_key == zone_key and current_pos.monitor_id == monitor_id then
        tile_index_to_apply = (current_pos.tile_index % #zone_tiles) + 1
    end

    local tile_to_apply = zone_tiles[tile_index_to_apply]
    if not tile_to_apply then
        debug_log("Tile index", tile_index_to_apply, "out of bounds for zone", zone_key)
        return false
    end

    if apply_tile(window, tile_to_apply, screen_obj) then
        window_state.set(window_id, monitor_id, zone_key, tile_index_to_apply)
        debug_log("Applied tile", tile_index_to_apply, "of zone", zone_key, "to window", window:application():name())
        return true
    end
    debug_log("Failed to apply tile for window", window:application():name())
    return false
end

-- Position window from memory (called by window_memory)
function tiler.position_window_from_memory(window, monitor_id, zone_key, tile_index)
    if not window or not window:isStandard() then
        return false
    end

    local screen_obj = monitors.get_screen(monitor_id)
    if not screen_obj then
        debug_log("Could not find screen for monitor ID:", monitor_id)
        return false
    end

    local zone_tiles = zones.get(monitor_id, zone_key)
    if not zone_tiles or not zone_tiles[tile_index] then
        debug_log("Could not find tile", tile_index, "in zone", zone_key, "on monitor", monitor_id)
        return false
    end

    local tile = zone_tiles[tile_index]
    if apply_tile(window, tile, screen_obj) then
        window_state.set(window:id(), monitor_id, zone_key, tile_index)
        debug_log("Positioned window from memory: zone", zone_key, "tile", tile_index)
        return true
    end

    return false
end

-- Move window to next/previous monitor
function tiler.move_window_to_monitor(direction)
    local window = hs.window.focusedWindow()
    if not window then
        return false
    end

    local window_id = window:id()
    local app_name = window:application():name()
    local current_screen_obj = window:screen()
    local current_monitor_id = monitors.get_id(current_screen_obj)

    local all_screens = hs.screen.allScreens()
    if #all_screens < 2 then
        return false
    end

    local current_screen_idx_in_list = -1
    for i, s in ipairs(all_screens) do
        if s:id() == current_screen_obj:id() then
            current_screen_idx_in_list = i
            break
        end
    end
    if current_screen_idx_in_list == -1 then
        return false
    end

    local target_screen_idx
    if direction == "next" then
        target_screen_idx = (current_screen_idx_in_list % #all_screens) + 1
    else -- "previous"
        target_screen_idx = (current_screen_idx_in_list - 2 + #all_screens) % #all_screens + 1
    end
    local target_screen_obj = all_screens[target_screen_idx]
    local target_monitor_id = monitors.get_id(target_screen_obj)

    debug_log("Moving window", app_name, "from monitor", current_monitor_id, "to monitor", target_monitor_id, "(",
        target_screen_obj:name(), ")")

    -- Check if zones exist for target monitor, create if not
    if not zones.by_monitor[target_monitor_id] then
        debug_log("Initializing zones for target monitor", target_monitor_id, target_screen_obj:name())
        zones.create_for_monitor(target_monitor_id, target_screen_obj)
    end

    local remembered_pos = window_state.get_app_memory(app_name, target_monitor_id)
    if remembered_pos then
        local zone_tiles = zones.get(target_monitor_id, remembered_pos.zone_key)
        if zone_tiles and zone_tiles[remembered_pos.tile_index] then
            if apply_tile(window, zone_tiles[remembered_pos.tile_index], target_screen_obj) then
                window_state.set(window_id, target_monitor_id, remembered_pos.zone_key, remembered_pos.tile_index)
                debug_log("Moved", app_name, "to remembered position on monitor", target_monitor_id)
                return true
            end
        end
    end

    local current_tiler_pos = window_state.get(window_id)
    if current_tiler_pos then
        local zone_tiles = zones.get(target_monitor_id, current_tiler_pos.zone_key)
        if zone_tiles then
            local tile_idx_to_try = math.min(current_tiler_pos.tile_index, #zone_tiles)
            if zone_tiles[tile_idx_to_try] and apply_tile(window, zone_tiles[tile_idx_to_try], target_screen_obj) then
                window_state.set(window_id, target_monitor_id, current_tiler_pos.zone_key, tile_idx_to_try)
                debug_log("Moved", app_name, "to equivalent zone/tile on monitor", target_monitor_id)
                return true
            end
        end
    end

    -- Last resort: move to a default zone (e.g., "0" or "j") on target monitor
    local default_zone_keys = {"0", "j"}
    for _, dz_key in ipairs(default_zone_keys) do
        local zone_tiles = zones.get(target_monitor_id, dz_key)
        if zone_tiles and zone_tiles[1] then
            if apply_tile(window, zone_tiles[1], target_screen_obj) then
                window_state.set(window_id, target_monitor_id, dz_key, 1)
                debug_log("Moved", app_name, "to default zone '", dz_key, "' on monitor", target_monitor_id)
                return true
            end
        end
    end

    -- If all else fails, just move it to the screen without tiling
    debug_log("Could not find suitable tile, moving window", app_name, "to screen", target_screen_obj:name(),
        "without tiling.")
    window:moveToScreen(target_screen_obj)
    window_state.cleanup(window_id)
    return true
end

-- Helper function to get window stacking order (Z-order)
local function get_window_z_order(window)
    local ordered_windows = hs.window.orderedWindows()
    for i, w in ipairs(ordered_windows) do
        if w:id() == window:id() then
            return i -- Lower number means more on top
        end
    end
    return 999999 -- Should not happen for a valid window
end

-- Helper function to check if window is already in list
local function is_window_in_list_by_id(window_id, window_list_of_structs)
    for _, zw_struct in ipairs(window_list_of_structs) do
        if zw_struct.window_id == window_id then
            return true
        end
    end
    return false
end

-- Helper function to collect windows for a zone
local function collect_zone_windows(monitor_id, zone_key, screen_obj, zone_tiles_for_this_zone)
    local zone_windows_collected = {}
    local overlap_threshold = config.tiler.overlap_threshold or 0.5

    if not screen_obj then
        debug_log("collect_zone_windows: screen_obj is nil for monitor_id", monitor_id, "zone_key", zone_key)
        return zone_windows_collected
    end
    if not zone_tiles_for_this_zone or #zone_tiles_for_this_zone == 0 then
        debug_log("collect_zone_windows: No tiles provided for zone", zone_key, "on monitor", monitor_id)
        return zone_windows_collected
    end

    -- Phase 1: Add explicitly assigned windows
    for _, win in ipairs(hs.window.allWindows()) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == screen_obj:id() then
            local pos = window_state.get(win:id())
            if pos and pos.monitor_id == monitor_id and pos.zone_key == zone_key then
                if not is_window_in_list_by_id(win:id(), zone_windows_collected) then
                    table.insert(zone_windows_collected, {
                        window = win,
                        window_id = win:id(),
                        app_name = win:application():name(),
                        tile_index = pos.tile_index,
                        explicit = true,
                        z_order = get_window_z_order(win)
                    })
                end
            end
        end
    end

    -- Phase 2: Add windows by overlap
    for tile_idx, tile_frame in ipairs(zone_tiles_for_this_zone) do
        for _, win in ipairs(hs.window.allWindows()) do
            if win:isStandard() and not win:isMinimized() and win:screen():id() == screen_obj:id() then
                if not is_window_in_list_by_id(win:id(), zone_windows_collected) then
                    local overlap = calculate_overlap_percentage(win:frame(), tile_frame)
                    if overlap >= overlap_threshold then
                        table.insert(zone_windows_collected, {
                            window = win,
                            window_id = win:id(),
                            app_name = win:application():name(),
                            tile_index = tile_idx,
                            explicit = false,
                            z_order = get_window_z_order(win),
                            overlap_debug = overlap
                        })
                    end
                end
            end
        end
    end
    return zone_windows_collected
end

-- Helper function to sort zone windows (for initial cycle order)
local function sort_zone_windows_for_intuitive_order(zone_windows_list)
    table.sort(zone_windows_list, function(a, b)
        if a.tile_index ~= b.tile_index then
            return a.tile_index < b.tile_index
        end
        if a.explicit ~= b.explicit then
            return a.explicit
        end
        return a.z_order < b.z_order
    end)
end

-- Main focus cycling function (STATEFUL REWRITE)
function tiler.focus_zone_windows(target_zone_key)
    local focused_window_before_call = hs.window.focusedWindow()
    if not focused_window_before_call then
        debug_log("focus_zone_windows: No focused window to start.")
        return false
    end

    local focused_window_id_before_call = focused_window_before_call:id()
    local current_screen_obj = focused_window_before_call:screen()
    if not current_screen_obj then
        debug_log("focus_zone_windows: Focused window has no screen.")
        return false
    end
    local current_monitor_id = monitors.get_id(current_screen_obj)

    debug_log(string.format("=== Focus zone '%s' on %s (%s) ===", target_zone_key, current_screen_obj:name(),
        current_monitor_id))
    debug_log(string.format("Window focused before call: %s (ID: %s)", focused_window_before_call:application():name(),
        focused_window_id_before_call))

    local cfcm = current_focus_cycle_manager -- shorthand

    -- Determine if the cycle needs to be rebuilt
    local needs_rebuild = false
    if target_zone_key ~= cfcm.zone_key or current_monitor_id ~= cfcm.monitor_id_logical or #cfcm.window_ids_in_order ==
        0 then
        needs_rebuild = true
        debug_log(string.format(
            "Rebuilding cycle: Zone/Monitor changed or cycle empty. Target Zone: %s, Current Cycle Zone: %s. Target Monitor: %s, Current Cycle Monitor: %s. Stored cycle items: %d",
            target_zone_key, cfcm.zone_key or "nil", current_monitor_id, cfcm.monitor_id_logical or "nil",
            #cfcm.window_ids_in_order))
    else
        -- Cycle seems to be for the same zone/monitor. Check if content is still valid.
        local zone_tiles_for_check = zones.get(current_monitor_id, target_zone_key)
        if not zone_tiles_for_check or #zone_tiles_for_check == 0 then
            debug_log("No tiles for zone " .. target_zone_key .. " during validation. Forcing rebuild.")
            needs_rebuild = true
        else
            local actual_windows_in_zone_now = collect_zone_windows(current_monitor_id, target_zone_key,
                current_screen_obj, zone_tiles_for_check)

            if #actual_windows_in_zone_now ~= #cfcm.window_ids_in_order then
                needs_rebuild = true
                debug_log(string.format("Rebuilding cycle: Number of windows in zone changed. Stored: %d, Actual: %d.",
                    #cfcm.window_ids_in_order, #actual_windows_in_zone_now))
            else
                -- Check if the window IDs match exactly
                local actual_ids_set = {}
                for _, zw in ipairs(actual_windows_in_zone_now) do
                    actual_ids_set[zw.window_id] = true
                end
                for _, id_in_stored_list in ipairs(cfcm.window_ids_in_order) do
                    if not actual_ids_set[id_in_stored_list] then
                        needs_rebuild = true
                        debug_log("Rebuilding cycle: A window from the stored cycle (ID: " .. id_in_stored_list ..
                                      ") is no longer in the zone.")
                        break
                    end
                end
            end

            if not needs_rebuild then
                -- If set of windows is the same, check if user manually focused a different window WITHIN the zone
                local focused_is_in_zone_currently = false
                for _, id_in_list in ipairs(cfcm.window_ids_in_order) do
                    if id_in_list == focused_window_id_before_call then
                        focused_is_in_zone_currently = true;
                        break
                    end
                end

                if not focused_is_in_zone_currently then
                    needs_rebuild = true
                    debug_log("Rebuilding cycle: Window focused before call (ID: " .. focused_window_id_before_call ..
                                  ") is not in the current cycle list. Forcing rebuild.")
                end
            end
        end
    end

    if needs_rebuild then
        debug_log(
            "Rebuilding focus cycle list for zone '" .. target_zone_key .. "' on monitor " .. current_monitor_id ..
                "...")
        cfcm.zone_key = target_zone_key
        cfcm.monitor_id_logical = current_monitor_id
        cfcm.window_ids_in_order = {}
        cfcm.current_idx_in_cycle_list = 0 -- Reset index

        local zone_tiles = zones.get(current_monitor_id, target_zone_key)
        if not zone_tiles or #zone_tiles == 0 then
            debug_log("No tiles found for zone '" .. target_zone_key .. "' on monitor " .. current_monitor_id ..
                          ". Cycle cleared.")
            return false
        end

        local collected_windows = collect_zone_windows(current_monitor_id, target_zone_key, current_screen_obj,
            zone_tiles)
        if #collected_windows == 0 then
            debug_log("No windows found in zone '" .. target_zone_key .. "'. Cycle cleared.")
            return false
        end

        sort_zone_windows_for_intuitive_order(collected_windows)

        debug_log("Sorted windows for new cycle order:")
        for i, zw in ipairs(collected_windows) do
            table.insert(cfcm.window_ids_in_order, zw.window_id)
            debug_log(string.format("  %d: %s (ID: %s, tile %d, z:%d, %s)", i, zw.app_name, zw.window_id, zw.tile_index,
                zw.z_order, zw.explicit and "explicit" or "overlap " .. (zw.overlap_debug or "")))
        end

        -- Determine starting index for the new/rebuilt cycle
        local initial_focus_target_idx_in_new_list = 0
        for i, id_in_list in ipairs(cfcm.window_ids_in_order) do
            if id_in_list == focused_window_id_before_call then
                initial_focus_target_idx_in_new_list = i
                debug_log(string.format("Window focused before call (ID: %s) found at index %d in new cycle list.",
                    focused_window_id_before_call, i))
                break
            end
        end
        cfcm.current_idx_in_cycle_list = initial_focus_target_idx_in_new_list
        if initial_focus_target_idx_in_new_list == 0 then
            debug_log(
                "Window focused before call not in new cycle list. Cycle will start from the beginning of the new list.")
        end
    end

    if #cfcm.window_ids_in_order == 0 then
        debug_log("No windows available for cycling in zone '" .. target_zone_key .. "'.")
        return false
    end

    -- Advance the cycle index
    local num_windows_in_cycle = #cfcm.window_ids_in_order
    cfcm.current_idx_in_cycle_list = (cfcm.current_idx_in_cycle_list % num_windows_in_cycle) + 1

    local window_id_to_focus = cfcm.window_ids_in_order[cfcm.current_idx_in_cycle_list]
    local window_to_focus = hs.window.get(window_id_to_focus)

    if window_to_focus and window_to_focus:isStandard() and not window_to_focus:isMinimized() then
        debug_log(string.format("Cycling to window %d of %d: %s (ID: %s)", cfcm.current_idx_in_cycle_list,
            num_windows_in_cycle, window_to_focus:application():name(), window_id_to_focus))
        window_to_focus:focus()

        if config.tiler.flash_on_focus then
            local frame = window_to_focus:frame()
            local flash = hs.canvas.new(frame):appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {
                    red = 0.5,
                    green = 0.5,
                    blue = 1.0,
                    alpha = 0.3
                }
            })
            flash:show()
            hs.timer.doAfter(0.2, function()
                flash:delete()
            end)
        end
        return true
    else
        debug_log(string.format(
            "Window ID %s (at new cycle index %d) to focus was not found, invalid, or not standard. Cycle may be stale.",
            window_id_to_focus, cfcm.current_idx_in_cycle_list))
        cfcm.zone_key = nil -- Force full rebuild next time
        cfcm.window_ids_in_order = {}
        cfcm.current_idx_in_cycle_list = 0
        return false
    end
end

-- Debug function to inspect a specific zone
function tiler.debug_zone(zone_key)
    local fe = hs.window.focusedWindow()
    if not fe then
        print("No focused window to determine screen");
        return
    end
    local screen = fe:screen()
    if not screen then
        print("Focused window has no screen");
        return
    end

    local monitor_id = monitors.get_id(screen)
    print("=== Debugging zone '" .. zone_key .. "' on " .. screen:name() .. " (Monitor Logical ID: " .. monitor_id ..
              ") ===")

    local zone_tiles = zones.get(monitor_id, zone_key)
    if not zone_tiles then
        print("Zone '" .. zone_key .. "' not found on monitor " .. monitor_id)
        if zones.by_monitor[monitor_id] then
            print("\nAvailable zones on this monitor:")
            for key, _ in pairs(zones.by_monitor[monitor_id]) do
                print("  " .. key)
            end
        else
            print("No zones initialized for this monitor.")
        end
        return
    end

    print("\nZone '" .. zone_key .. "' has " .. #zone_tiles .. " tiles:")
    for i, tile in ipairs(zone_tiles) do
        print(string.format("  Tile %d: x=%.1f, y=%.1f, w=%.1f, h=%.1f", i, tile.x, tile.y, tile.w, tile.h))
    end

    local zone_windows = collect_zone_windows(monitor_id, zone_key, screen, zone_tiles)
    sort_zone_windows_for_intuitive_order(zone_windows)

    print("\nWindows in zone '" .. zone_key .. "' (sorted for potential cycle): " .. #zone_windows)
    for i, zw in ipairs(zone_windows) do
        print(string.format("  %d: %s (ID: %s) - Tile %d, Explicit: %s, Z-Order: %d, Overlap: %.1f%%", i, zw.app_name,
            zw.window_id, zw.tile_index, tostring(zw.explicit), zw.z_order, (zw.overlap_debug or 0) * 100))
    end

    print("\nCurrent Focus Cycle Manager State:")
    print(hs.inspect(current_focus_cycle_manager))
end

-- Helper function for overlap calculation
function calculate_overlap_percentage(rect1, rect2)
    if not rect1 or not rect2 or rect1.w <= 0 or rect1.h <= 0 then
        return 0
    end
    local x_overlap = math.max(0, math.min(rect1.x + rect1.w, rect2.x + rect2.w) - math.max(rect1.x, rect2.x))
    local y_overlap = math.max(0, math.min(rect1.y + rect1.h, rect2.y + rect2.h) - math.max(rect1.y, rect2.y))
    local overlap_area = x_overlap * y_overlap
    return overlap_area / (rect1.w * rect1.h)
end

------------------------------------------
-- Event Handling
------------------------------------------

local function handle_window_destroyed(window)
    if window then
        debug_log("Window destroyed:", window:id(), window:application() and window:application():name() or "N/A")
        window_state.cleanup(window:id())
        -- Check if this window was part of the current focus cycle and invalidate if so
        if current_focus_cycle_manager.zone_key then
            local removed = false
            for i = #current_focus_cycle_manager.window_ids_in_order, 1, -1 do
                if current_focus_cycle_manager.window_ids_in_order[i] == window:id() then
                    table.remove(current_focus_cycle_manager.window_ids_in_order, i)
                    removed = true
                    break
                end
            end
            if removed then
                debug_log("Removed destroyed window from current focus cycle. Cycle list may be stale or empty.")
                if #current_focus_cycle_manager.window_ids_in_order == 0 then
                    current_focus_cycle_manager.zone_key = nil -- Force full rebuild
                    current_focus_cycle_manager.current_idx_in_cycle_list = 0
                elseif current_focus_cycle_manager.current_idx_in_cycle_list >
                    #current_focus_cycle_manager.window_ids_in_order then
                    current_focus_cycle_manager.current_idx_in_cycle_list =
                        #current_focus_cycle_manager.window_ids_in_order
                end
                -- Forcing a full rebuild on next focus might be safer than trying to adjust index here.
                current_focus_cycle_manager.zone_key = nil
            end
        end
    end
end

local function handle_window_created(window)
    -- Notify window_memory of new window
    if window_memory and window_memory.on_window_created then
        window_memory.on_window_created(window)
    end

    -- Handle smart placement if enabled
    if config.tiler.smart_placement and config.tiler.smart_placement.enabled then
        if window and window:isStandard() then
            -- Delay to allow window to fully initialize its properties
            hs.timer.doAfter(0.2, function()
                if window:isStandard() then -- Recheck, might have closed or changed
                    smart_placement.place_window(window)
                end
            end)
        end
    end
end

local function handle_screen_change()
    debug_log("Screen configuration changed")
    hs.timer.doAfter(0.5, function() -- Delay to allow screens to settle
        monitors.registry = {} -- Clear the old registry
        monitors.next_logical_id = 1
        zones.by_monitor = {}
        for _, screen_obj in ipairs(hs.screen.allScreens()) do
            local monitor_id = monitors.get_id(screen_obj) -- Re-register all monitors
            zones.create_for_monitor(monitor_id, screen_obj)
        end
        -- Invalidate current focus cycle as monitor setup changed
        current_focus_cycle_manager.zone_key = nil
        current_focus_cycle_manager.window_ids_in_order = {}
        current_focus_cycle_manager.current_idx_in_cycle_list = 0
        debug_log("Reinitialized monitors and zones. Focus cycle invalidated.")
    end)
end

------------------------------------------
-- Initialization
------------------------------------------

function tiler.start()
    debug_log("Starting tiler")

    tiler.debug = config.tiler.debug
    tiler.margins = config.tiler.margins
    tiler.problem_apps = config.tiler.problem_apps

    for _, screen_obj in ipairs(hs.screen.allScreens()) do
        local monitor_id = monitors.get_id(screen_obj)
        zones.create_for_monitor(monitor_id, screen_obj)
    end

    local modifier = config.tiler.modifier
    local focus_modifier = config.tiler.focus_modifier

    local all_zone_keys = {}
    if config.tiler.layouts then
        for _, layout_config in pairs(config.tiler.layouts) do
            for zone_key, _ in pairs(layout_config) do
                if zone_key ~= "default" then
                    all_zone_keys[zone_key] = true
                end
            end
        end
    end

    local zone_key_list_for_debug = {}
    for zk, _ in pairs(all_zone_keys) do
        table.insert(zone_key_list_for_debug, zk)
    end
    debug_log("Registering hotkeys for zone keys:", table.concat(zone_key_list_for_debug, ", "))

    for zone_key_str, _ in pairs(all_zone_keys) do
        hs.hotkey.bind(modifier, zone_key_str, function()
            tiler.move_window_to_zone(zone_key_str)
        end)
        if focus_modifier then
            hs.hotkey.bind(focus_modifier, zone_key_str, function()
                tiler.focus_zone_windows(zone_key_str)
            end)
        end
    end

    hs.hotkey.bind(modifier, "p", function()
        tiler.move_window_to_monitor("next")
    end)
    hs.hotkey.bind(modifier, ";", function()
        tiler.move_window_to_monitor("previous")
    end)

    -- Watch for window events
    local window_filter_events = {hs.window.filter.windowDestroyed, hs.window.filter.windowCreated}
    local window_watcher = hs.window.filter.new(window_filter_events)
    window_watcher:subscribe(hs.window.filter.windowDestroyed, handle_window_destroyed)
    window_watcher:subscribe(hs.window.filter.windowCreated, handle_window_created)

    local screen_watcher = hs.screen.watcher.new(handle_screen_change):start()

    debug_log("Tiler started successfully")
    return tiler
end

-- Set window_memory reference (called from init)
function tiler.set_window_memory(wm)
    window_memory = wm
    debug_log("Window memory integration enabled")
end

return tiler
