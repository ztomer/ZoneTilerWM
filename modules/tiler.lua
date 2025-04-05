--[[
Zone Tiler for Hammerspoon
===========================

A window management system that allows defining zones on the screen and cycling window sizes within those zones.
]] -- Load configuration from config file
local config = require "config"
-- Load LRU cache utility
local lru_cache = require "modules.lru_cache"

-- Define the tiler namespace for public API only
local tiler = {
    -- Version information
    _version = "1.1.0",

    -- Internal state - these will be populated later
    _window_id2zone_id = {},
    _zone_id2zone = {},
    _modes = {},
    _window_watcher = nil,
    _screen_watcher = nil,
    _screen_memory = {}, -- Format: [window_id][screen_id] = {zone_id, tile_idx}
    _window_focus_idx = {}, -- Initialize focus tracking table
    _position_group_idx = {}, -- Tracks which position group was last focused

    -- Public user configuration tables
    layouts = {
        default = {
            small = "2x2",
            medium = "3x2",
            large = "3x3",
            extra_large = "4x3"
        },
        custom = {}
    },

    -- Zone configurations
    zone_configs = {}
}

-- Create caches for different functions
local cache = {
    -- For expensive layout calculations
    tile_positions = lru_cache.new(500), -- Cache for tile position calculations
    zone_tiles = lru_cache.new(200), -- Cache for zone tile configurations
    screen_modes = lru_cache.new(50), -- Cache for screen mode detection

    -- For window state (no eviction limit needed as we'll manage this explicitly)
    window_positions = lru_cache.new(1000) -- Plenty of room for window state
}

-- Create local tables for organizing related functions
local rect = {}
local grid_coords = {}
local window_state = {}
local window_utils = {}
local zone_finder = {}
local smart_placement = {}
local layout_utils = {}

-- Module settings - will be populated from config
local settings = {}

-- Debug logging function
local function debug_log(...)
    if not settings.debug then
        return
    end

    local args = {...}
    local message = ""
    for i, v in ipairs(args) do
        message = message .. tostring(v) .. " "
    end

    print("[TilerDebug] " .. message)
end

-- Add debugging for cache performance
local function log_cache_stats()
    if not settings.debug then
        return
    end

    debug_log("Cache statistics:")
    for name, c in pairs(cache) do
        local stats = c:stats()
        debug_log(string.format("  %s: %d/%d items, %.1f%% hit rate (%d hits, %d misses)", name, stats.size,
            stats.max_size, stats.hit_ratio * 100, stats.hits, stats.misses))
    end
end

------------------------------------------
-- Rectangle Utility Functions
------------------------------------------

-- Calculate overlap between two rectangles
function rect.calculate_overlap(rect1, rect2)
    -- Normalize rectangle formats
    local r1 = {
        x = rect1.x,
        y = rect1.y,
        w = rect1.width or rect1.w,
        h = rect1.height or rect1.h
    }

    local r2 = {
        x = rect2.x,
        y = rect2.y,
        w = rect2.width or rect2.w,
        h = rect2.height or rect2.h
    }

    -- Calculate intersection
    local x_overlap = math.max(0, math.min(r1.x + r1.w, r2.x + r2.w) - math.max(r1.x, r2.x))
    local y_overlap = math.max(0, math.min(r1.y + r1.h, r2.y + r2.h) - math.max(r1.y, r2.y))

    -- Return overlap area
    return x_overlap * y_overlap
end

-- Calculate overlap percentage relative to the first rectangle
function rect.calculate_overlap_percentage(rect1, rect2)
    local overlap_area = rect.calculate_overlap(rect1, rect2)
    local rect1_area = (rect1.width or rect1.w) * (rect1.height or rect1.h)

    if rect1_area <= 0 then
        return 0
    end

    return overlap_area / rect1_area
end

-- Check if two frames (approximately) match
function rect.frames_match(frame1, frame2, tolerance)
    tolerance = tolerance or 10

    return math.abs(frame1.x - frame2.x) <= tolerance and math.abs(frame1.y - frame2.y) <= tolerance and
               math.abs((frame1.width or frame1.w) - (frame2.width or frame2.w)) <= tolerance and
               math.abs((frame1.height or frame1.h) - (frame2.height or frame2.h)) <= tolerance
end

------------------------------------------
-- Grid Coordinate Functions
------------------------------------------

-- Parse grid coordinates from various formats
function grid_coords.parse(coords_string, max_cols, max_rows)
    -- Handle different types of input
    if type(coords_string) ~= "string" then
        return coords_string
    end

    -- Handle named positions
    if coords_string == "full" or coords_string == "center" or coords_string:match("%-half$") then
        return coords_string
    end

    -- Parse string format like "a1:b2" or "a1"
    local pattern = "([a-z])([0-9]+):?([a-z]?)([0-9]*)"
    local col_start_char, row_start_str, col_end_char, row_end_str = coords_string:match(pattern)

    if not col_start_char or not row_start_str then
        return nil
    end

    -- Convert column letters to numbers (a=1, b=2, etc.)
    local col_start = string.byte(col_start_char) - string.byte('a') + 1
    local row_start = tonumber(row_start_str)

    -- Handle single cell case
    local col_end, row_end
    if col_end_char == "" or row_end_str == "" then
        col_end = col_start
        row_end = row_start
    else
        col_end = string.byte(col_end_char) - string.byte('a') + 1
        row_end = tonumber(row_end_str)
    end

    -- Ensure coordinates don't exceed grid bounds
    col_start = math.max(1, math.min(col_start, max_cols))
    row_start = math.max(1, math.min(row_start, max_rows))
    col_end = math.max(1, math.min(col_end, max_cols))
    row_end = math.max(1, math.min(row_end, max_rows))

    return {col_start, row_start, col_end, row_end}
end

------------------------------------------
-- Window State Management Functions
------------------------------------------

-- Initialize window state tracking
function window_state.init()
    window_state._data = {}
    window_state._zone_windows = {}
end

-- Associate a window with a zone
function window_state.associate_window_with_zone(window_id, zone, tile_idx)
    if not window_id or not zone then
        return false
    end

    tile_idx = tile_idx or 0

    -- Remove from any existing zones
    window_state.remove_window_from_all_zones(window_id)

    -- Update state tracking
    tiler._window_id2zone_id[window_id] = zone.id

    -- Store state in the cache
    local state = {
        zone_id = zone.id,
        tile_idx = tile_idx
    }
    cache.window_positions:set(window_id, state)

    -- Update zone's tracking
    zone.window_to_tile_idx[window_id] = tile_idx

    -- Update zone windows list
    if not window_state._zone_windows[zone.id] then
        window_state._zone_windows[zone.id] = {}
    end

    -- Check if window is already in the list before adding
    local found = false
    for i, wid in ipairs(window_state._zone_windows[zone.id]) do
        if wid == window_id then
            found = true
            break
        end
    end

    if not found then
        table.insert(window_state._zone_windows[zone.id], window_id)
        debug_log("Added window", window_id, "to zone windows list for zone", zone.id)
    end

    return true
end

-- Remove a window from all zones
function window_state.remove_window_from_all_zones(window_id)
    if not window_id then
        return false
    end

    -- Remove from cache
    cache.window_positions:remove(window_id)

    for zone_id, zone in pairs(tiler._zone_id2zone) do
        if zone.window_to_tile_idx and zone.window_to_tile_idx[window_id] ~= nil then
            zone.window_to_tile_idx[window_id] = nil
            debug_log("Removed window", window_id, "from zone", zone_id)

            -- Remove from zone_windows list
            if window_state._zone_windows[zone_id] then
                for i, wid in ipairs(window_state._zone_windows[zone_id]) do
                    if wid == window_id then
                        table.remove(window_state._zone_windows[zone_id], i)
                        debug_log("Removed window", window_id, "from zone_windows for zone", zone_id)
                        break
                    end
                end
            end
        end
    end

    -- Clear from global mapping
    tiler._window_id2zone_id[window_id] = nil

    -- Clear from window state
    if window_state._data[window_id] then
        window_state._data[window_id].zone_id = nil
    end

    return true
end

-- Get the zone for a window
function window_state.get_window_zone(window_id)
    if not window_id then
        return nil, nil
    end

    -- Check the cache first
    local state = cache.window_positions:get(window_id)
    if state and state.zone_id then
        return tiler._zone_id2zone[state.zone_id], state.zone_id
    end

    -- Fallback to old tracking method
    local zone_id = tiler._window_id2zone_id[window_id]
    if zone_id then
        return tiler._zone_id2zone[zone_id], zone_id
    end

    -- If still not found, try to find by window title
    local win = hs.window.get(window_id)
    if win and win:isStandard() then
        local app_name = win:application():name()
        local win_title = win:title()

        -- Check if we're tracking any windows for this app
        for tracked_win_id, tracked_zone_id in pairs(tiler._window_id2zone_id) do
            local tracked_win = hs.window.get(tracked_win_id)
            -- Skip if window no longer exists
            if not tracked_win then
                goto continue
            end

            -- Check if same app and same title
            if tracked_win:application():name() == app_name and tracked_win:title() == win_title then
                local found_zone = tiler._zone_id2zone[tracked_zone_id]
                if found_zone then
                    -- Found a match, associate this window
                    tiler._window_id2zone_id[window_id] = tracked_zone_id
                    if found_zone.window_to_tile_idx then
                        found_zone.window_to_tile_idx[window_id] = found_zone.window_to_tile_idx[tracked_win_id] or 0
                    end
                    debug_log("Associated window", window_id, "with zone", tracked_zone_id, "by title match")
                    return found_zone, tracked_zone_id
                end
            end

            ::continue::
        end
    end

    return nil, nil
end

------------------------------------------
-- Window Manipulation Functions
------------------------------------------
-- Check if an app is in the problem list
function window_utils.is_problem_app(app_name)
    if not settings.problem_apps or not app_name then
        return false
    end

    local lower_app_name = app_name:lower()
    for _, name in ipairs(settings.problem_apps) do
        if name:lower() == lower_app_name then
            return true
        end
    end

    return false
end

-- Apply a frame to a window with proper handling (enhanced to handle invalid frames)
function window_utils.apply_frame(window, frame, force_screen)
    if not window or not window:isStandard() then
        return false
    end

    -- Check if window isn't in any zone yet - try to find by title
    local win_id = window:id()
    if not tiler._window_id2zone_id[win_id] then
        -- Try to find a matching window by title
        window_state.get_window_zone(win_id)
    end

    -- Validate frame parameters
    if not frame or type(frame.x) ~= "number" or type(frame.y) ~= "number" or type(frame.w) ~= "number" and
        type(frame.width) ~= "number" or type(frame.h) ~= "number" and type(frame.height) ~= "number" then
        debug_log("Invalid frame parameters:", frame)
        return false
    end

    -- Normalize frame format
    local valid_frame = {
        x = frame.x,
        y = frame.y,
        w = frame.w or frame.width,
        h = frame.h or frame.height
    }

    -- Ensure all frame values are present and positive
    if valid_frame.w <= 0 or valid_frame.h <= 0 then
        debug_log("Invalid frame dimensions:", valid_frame)
        return false
    end

    -- Force move to screen first if specified
    if force_screen then
        window:moveToScreen(force_screen, false, true, 0)
    end

    -- Apply frame with animation disabled
    local saved_duration = hs.window.animationDuration
    hs.window.animationDuration = 0
    window:setFrame(valid_frame)
    hs.window.animationDuration = saved_duration

    return true
end

-- Special handling for problem apps
function window_utils.apply_frame_to_problem_app(window, frame, app_name)
    if not window or not frame then
        return false
    end

    debug_log("Using special handling for app:", app_name)

    -- First attempt with animation
    local saved_duration = hs.window.animationDuration
    hs.window.animationDuration = 0.01
    window:setFrame(frame)
    hs.window.animationDuration = saved_duration

    -- Multiple attempts with delays
    for attempt = 2, 10 do
        hs.timer.doAfter((attempt - 1) * 0.1, function()
            -- Check if the window moved from where we put it
            local current_frame = window:frame()
            if not rect.frames_match(current_frame, frame) then
                debug_log("Detected position change, forcing position (attempt " .. attempt .. ")")
                window:setFrame(frame)
            end
        end)
    end

    -- Final verification with a longer delay
    hs.timer.doAfter(0.5, function()
        local final_frame = window:frame()
        if not rect.frames_match(final_frame, frame) then
            debug_log("Final position check failed, forcing position one last time")
            window:setFrame(frame)

            -- Log the final position for debugging
            hs.timer.doAfter(0.1, function()
                local result_frame = window:frame()
                debug_log(
                    "Final position: x=" .. result_frame.x .. ", y=" .. result_frame.y .. ", w=" .. result_frame.w ..
                        ", h=" .. result_frame.h)
            end)
        end
    end)

    return true
end

------------------------------------------
-- Zone Finder Functions
------------------------------------------

-- Find a zone by ID on a specific screen
function zone_finder.find_zone_by_id_on_screen(zone_id, screen)
    if not screen or not zone_id then
        return nil, nil
    end

    local screen_id = screen:id()
    local screen_specific_id = zone_id .. "_" .. screen_id

    -- First try exact screen-specific match
    if tiler._zone_id2zone[screen_specific_id] then
        debug_log("Found exact screen-specific match:", screen_specific_id)
        return tiler._zone_id2zone[screen_specific_id], screen_specific_id
    end

    -- Then try pattern matching for this screen
    for id, zone in pairs(tiler._zone_id2zone) do
        if zone.screen and zone.screen:id() == screen_id then
            if id == zone_id or id:match("^" .. zone_id .. "_%d+$") then
                debug_log("Found zone match on current screen:", id)
                return zone, id
            end
        end
    end

    -- Fallback to base zone ID if needed
    if tiler._zone_id2zone[zone_id] then
        debug_log("Using base zone (not screen-specific):", zone_id)
        return tiler._zone_id2zone[zone_id], zone_id
    end

    debug_log("No matching zone found for", zone_id, "on screen", screen:name())
    return nil, nil
end

-- Find the best matching zone for a window
function zone_finder.find_best_zone_for_window(win)
    if not win or not win:isStandard() then
        return nil
    end

    local screen = win:screen()
    if not screen then
        return nil
    end

    local screen_id = screen:id()
    local win_frame = win:frame()

    -- Find zones on this specific screen
    local screen_zones = {}
    for id, zone in pairs(tiler._zone_id2zone) do
        if zone.screen and zone.screen:id() == screen_id then
            table.insert(screen_zones, zone)
        end
    end

    if #screen_zones == 0 then
        debug_log("No zones found for screen:", screen:name())
        return nil
    end

    -- Find best matching zone based on window position and size
    local best_zone = nil
    local best_match_score = 0
    local best_tile_idx = 0

    for _, zone in ipairs(screen_zones) do
        -- Skip zones with no tiles
        if zone.tile_count == 0 then
            goto next_zone
        end

        -- Check each tile in the zone
        for i = 0, zone.tile_count - 1 do
            local tile = zone.tiles[i]
            if not tile then
                goto next_tile
            end

            -- Calculate overlap percentage
            local overlap_percentage = rect.calculate_overlap_percentage(win_frame, tile)

            -- Calculate size similarity (how close the window and tile are in size)
            local width_ratio = math.min(win_frame.w, tile.width) / math.max(win_frame.w, tile.width)
            local height_ratio = math.min(win_frame.h, tile.height) / math.max(win_frame.h, tile.height)
            local size_similarity = (width_ratio + height_ratio) / 2

            -- Calculate center distance
            local win_center_x = win_frame.x + win_frame.w / 2
            local win_center_y = win_frame.y + win_frame.h / 2
            local tile_center_x = tile.x + tile.width / 2
            local tile_center_y = tile.y + tile.height / 2
            local center_distance = math.sqrt((win_center_x - tile_center_x) ^ 2 + (win_center_y - tile_center_y) ^ 2)

            -- Normalize center distance to screen size
            local screen_frame = screen:frame()
            local screen_diagonal = math.sqrt(screen_frame.w ^ 2 + screen_frame.h ^ 2)
            local normalized_distance = 1 - (center_distance / screen_diagonal)

            -- Combined score (50% overlap, 30% size similarity, 20% center proximity)
            local score = (overlap_percentage * 0.5) + (size_similarity * 0.3) + (normalized_distance * 0.2)

            -- Check if this is best match so far
            if score > best_match_score and score > 0.4 then -- Must be at least 40% match
                best_match_score = score
                best_zone = zone
                best_tile_idx = i
            end

            ::next_tile::
        end

        ::next_zone::
    end

    if not best_zone or best_match_score <= 0 then
        return nil
    end

    debug_log("Found best matching zone:", best_zone.id, "with score:", best_match_score)
    return {
        zone = best_zone,
        tile_idx = best_tile_idx,
        score = best_match_score
    }
end

------------------------------------------
-- Smart Placement Functions
------------------------------------------

-- Compute a distance map for smart window placement
function smart_placement.compute_distance_map(screen, cell_size)
    if not screen or not cell_size or cell_size <= 0 then
        return nil
    end

    local screen_frame = screen:frame()
    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)

    -- Initialize grid: 0 means empty
    local grid = {}
    for i = 1, grid_height do
        grid[i] = {}
        for j = 1, grid_width do
            grid[i][j] = 0
        end
    end

    -- Mark cells occupied by existing windows
    for _, win in pairs(hs.window.allWindows()) do
        if win:screen() == screen then
            local frame = win:frame()
            local x1 = math.floor(frame.x / cell_size) + 1
            local y1 = math.floor(frame.y / cell_size) + 1
            local x2 = math.ceil((frame.x + frame.w) / cell_size)
            local y2 = math.ceil((frame.y + frame.h) / cell_size)
            for i = math.max(1, y1), math.min(grid_height, y2) do
                for j = math.max(1, x1), math.min(grid_width, x2) do
                    grid[i][j] = 1 -- 1 means occupied
                end
            end
        end
    end

    -- BFS to compute distances
    local distance = {}
    for i = 1, grid_height do
        distance[i] = {}
        for j = 1, grid_width do
            distance[i][j] = grid[i][j] == 1 and 0 or -1 -- -1 means unvisited
        end
    end

    local queue = {}
    for i = 1, grid_height do
        for j = 1, grid_width do
            if grid[i][j] == 1 then
                table.insert(queue, {i, j})
            end
        end
    end

    local directions = {{0, 1}, {0, -1}, {1, 0}, {-1, 0}}
    while #queue > 0 do
        local cell = table.remove(queue, 1)
        local i, j = cell[1], cell[2]
        for _, dir in pairs(directions) do
            local ni, nj = i + dir[1], j + dir[2]
            if ni >= 1 and ni <= grid_height and nj >= 1 and nj <= grid_width and distance[ni][nj] == -1 then
                distance[ni][nj] = distance[i][j] + 1
                table.insert(queue, {ni, nj})
            end
        end
    end

    return distance
end

-- Find the best position based on a distance map
function smart_placement.find_best_position(screen, window_width, window_height, cell_size, distance_map)
    if not screen or not window_width or not window_height or not cell_size or not distance_map then
        return nil
    end

    if window_width <= 0 or window_height <= 0 or cell_size <= 0 then
        return nil
    end

    local screen_frame = screen:frame()
    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)
    local window_grid_width = math.ceil(window_width / cell_size)
    local window_grid_height = math.ceil(window_height / cell_size)

    local best_score = -1
    local best_pos = {
        x = 0,
        y = 0
    }

    for i = 1, grid_height - window_grid_height + 1 do
        for j = 1, grid_width - window_grid_width + 1 do
            local min_distance = math.huge
            for di = 0, window_grid_height - 1 do
                for dj = 0, window_grid_width - 1 do
                    local dist = distance_map[i + di][j + dj]
                    if dist < min_distance then
                        min_distance = dist
                    end
                end
            end
            if min_distance > best_score then
                best_score = min_distance
                best_pos = {
                    x = (j - 1) * cell_size,
                    y = (i - 1) * cell_size
                }
            end
        end
    end

    return best_pos
end

-- Smart placement of a window
function smart_placement.place_window(win)
    if not win or not win:isStandard() then
        return false
    end

    local screen = win:screen()
    if not screen then
        return false
    end

    local cell_size = 50 -- Grid size for placement calculation
    local distance_map = smart_placement.compute_distance_map(screen, cell_size)
    if not distance_map then
        return false
    end

    local frame = win:frame()
    if not frame or frame.w <= 0 or frame.h <= 0 then
        return false
    end

    local pos = smart_placement.find_best_position(screen, frame.w, frame.h, cell_size, distance_map)
    if not pos then
        return false
    end

    win:setFrame({
        x = pos.x,
        y = pos.y,
        w = frame.w,
        h = frame.h
    })

    return true
end

------------------------------------------
-- Layout Utility Functions
------------------------------------------

-- Calculate tile position from grid coordinates
function layout_utils.calculate_tile_position(screen, col_start, row_start, col_end, row_end, rows, cols)
    if not screen or not col_start or not row_start or not col_end or not row_end or not rows or not cols then
        return nil
    end

    if cols <= 0 or rows <= 0 then
        return nil
    end

    -- Create a cache key
    local cache_key = lru_cache.key_maker(screen:id(), -- Screen ID
    col_start, row_start, -- Start position
    col_end, row_end, -- End position
    rows, cols, -- Grid dimensions
    settings.margins -- Margin settings (as they affect calculation)
    )

    -- Check cache first
    local cached_result = cache.tile_positions:get(cache_key)
    if cached_result then
        return cached_result
    end

    local frame = screen:frame()
    local w = frame.w
    local h = frame.h
    local x = frame.x
    local y = frame.y

    -- Get margin settings
    local use_margins = settings.margins.enabled
    local margin_size = settings.margins.size or 0
    local screen_edge_margins = settings.margins.screen_edge

    -- Add debugging for portrait monitors
    local is_portrait = h > w
    if is_portrait then
        debug_log(string.format("Portrait monitor detected: %s (%.1f x %.1f)", screen:name(), w, h))
    end

    -- Calculate grid cell dimensions
    local col_width = w / cols
    local row_height = h / rows

    -- Calculate absolute position and size without margins
    local tile_x = x + (col_start - 1) * col_width
    local tile_y = y + (row_start - 1) * row_height
    local tile_width = (col_end - col_start + 1) * col_width
    local tile_height = (row_end - row_start + 1) * row_height

    -- Apply margins if enabled
    if use_margins then
        -- Apply screen edge margins if enabled
        if screen_edge_margins then
            -- Left edge
            if col_start == 1 then
                tile_x = tile_x + margin_size
                tile_width = tile_width - margin_size
            end

            -- Top edge
            if row_start == 1 then
                tile_y = tile_y + margin_size
                tile_height = tile_height - margin_size
            end

            -- Right edge
            if col_end == cols then
                tile_width = tile_width - margin_size
            end

            -- Bottom edge
            if row_end == rows then
                tile_height = tile_height - margin_size
            end
        end

        -- Apply internal margins between cells
        -- Only subtract from width if this isn't the rightmost column
        if col_end < cols then
            tile_width = tile_width - margin_size
        end

        -- Only subtract from height if this isn't the bottom row
        if row_end < rows then
            tile_height = tile_height - margin_size
        end

        -- Add margin to x position if not in the leftmost column
        if col_start > 1 and not screen_edge_margins then
            tile_x = tile_x + margin_size
            tile_width = tile_width - margin_size
        end

        -- Add margin to y position if not in the top row
        if row_start > 1 and not screen_edge_margins then
            tile_y = tile_y + margin_size
            tile_height = tile_height - margin_size
        end
    end

    -- Ensure tiles stay within screen bounds
    if tile_x + tile_width > x + w then
        tile_width = (x + w) - tile_x
    end

    if tile_y + tile_height > y + h then
        tile_height = (y + h) - tile_y
    end

    -- Log the calculation details for debugging
    if settings.debug then
        print(string.format(
            "[TilerDebug] Grid calc: screen %s, cell=%.1fx%.1f, position=%.1f,%.1f to %.1f,%.1f → x=%.1f, y=%.1f, w=%.1f, h=%.1f",
            screen:name(), col_width, row_height, col_start, row_start, col_end, row_end, tile_x, tile_y, tile_width,
            tile_height))
    end

    -- Create the result
    local result = {
        x = tile_x,
        y = tile_y,
        width = tile_width,
        height = tile_height
    }

    -- Cache the result
    cache.tile_positions:set(cache_key, result)

    return result
end

-- Create a tile based on grid coordinates
function layout_utils.create_tile_from_grid_coords(screen, coord_string, rows, cols)
    if not screen or not rows or not cols then
        return nil
    end

    if rows <= 0 or cols <= 0 then
        return nil
    end

    -- Get the screen's absolute frame
    local display_rect = screen:frame()
    local w = display_rect.w
    local h = display_rect.h
    local x = display_rect.x
    local y = display_rect.y

    if settings.debug then
        print(string.format("[TilerDebug] Creating tile on screen %s with frame: x=%.1f, y=%.1f, w=%.1f, h=%.1f",
            screen:name(), x, y, w, h))
    end

    -- Handle different coordinate formats using the grid_coords utility
    if type(coord_string) == "string" then
        -- Named positions
        if coord_string == "full" then
            return {
                x = x,
                y = y,
                width = w,
                height = h,
                description = "Full screen"
            }
        elseif coord_string == "center" then
            return {
                x = x + w / 4,
                y = y + h / 4,
                width = w / 2,
                height = h / 2,
                description = "Center"
            }
        elseif coord_string == "left-half" then
            return {
                x = x,
                y = y,
                width = w / 2,
                height = h,
                description = "Left half"
            }
        elseif coord_string == "right-half" then
            return {
                x = x + w / 2,
                y = y,
                width = w / 2,
                height = h,
                description = "Right half"
            }
        elseif coord_string == "top-half" then
            return {
                x = x,
                y = y,
                width = w,
                height = h / 2,
                description = "Top half"
            }
        elseif coord_string == "bottom-half" then
            return {
                x = x,
                y = y + h / 2,
                width = w,
                height = h / 2,
                description = "Bottom half"
            }
        end
    end

    -- Parse grid coordinates
    local parsed_coords = grid_coords.parse(coord_string, cols, rows)
    if not parsed_coords then
        debug_log("Invalid grid coordinates:", coord_string)
        return nil
    end

    -- If we have a table of coordinates, extract them
    local col_start, row_start, col_end, row_end
    if type(parsed_coords) == "table" then
        col_start = parsed_coords[1]
        row_start = parsed_coords[2]
        col_end = parsed_coords[3] or col_start
        row_end = parsed_coords[4] or row_start
    else
        -- If parsing returned something else, use it directly
        return parsed_coords
    end

    -- Calculate pixel coordinates using our helper function
    local tile_pos = layout_utils.calculate_tile_position(screen, col_start, row_start, col_end, row_end, rows, cols)
    if not tile_pos then
        return nil
    end

    -- Add the description to the returned table
    if type(coord_string) == "string" then
        tile_pos.description = coord_string
    else
        tile_pos.description = "Grid position"
    end

    return tile_pos
end

------------------------------------------
-- Zone Structure
------------------------------------------

-- Get all tiles for a zone configuration
function layout_utils.get_zone_tiles(screen, zone_key, rows, cols)
    -- Create a cache key
    local cache_key = lru_cache.key_maker(screen:id(), -- Screen ID
    zone_key, -- Zone key
    rows, cols -- Grid dimensions
    )

    -- Check cache first
    local cached_result = cache.zone_tiles:get(cache_key)
    if cached_result then
        return cached_result
    end

    local screen_name = screen:name()
    local layout_type = nil

    debug_log(
        "get_zone_tiles for screen: " .. screen_name .. ", key: " .. zone_key .. ", rows: " .. rows .. ", cols: " ..
            cols)

    -- 1. Check for custom screens - exact match by name
    if config.tiler.custom_screens and config.tiler.custom_screens[screen_name] then
        layout_type = config.tiler.custom_screens[screen_name].layout
        debug_log("Using custom screen layout: " .. layout_type)

        -- 2. Check for pattern matches in screen names
    elseif config.tiler.screen_detection and config.tiler.screen_detection.patterns then
        for pattern, layout in pairs(config.tiler.screen_detection.patterns) do
            if screen_name:match(pattern) then
                layout_type = layout
                debug_log("Matched screen pattern: " .. pattern .. " using layout: " .. layout_type)
                break
            end
        end
    end

    -- 3. If no match by screen name/pattern, attempt to match by grid dimensions
    if not layout_type then
        -- Look through all grid definitions to find a match
        if config.tiler.grids then
            for lt, grid in pairs(config.tiler.grids) do
                if grid.cols == cols and grid.rows == rows then
                    layout_type = lt
                    debug_log("Matched grid dimensions " .. cols .. "x" .. rows .. " to layout: " .. layout_type)
                    break
                end
            end
        end
    end

    -- 4. If still no match, default to the string representation
    if not layout_type then
        layout_type = cols .. "x" .. rows
        debug_log("No layout match found, using dimensional name: " .. layout_type)
    end

    -- Get zone configuration for this layout and key
    local config_entry = nil

    -- First try exact layout and key match
    if config.tiler.layouts and config.tiler.layouts[layout_type] and config.tiler.layouts[layout_type][zone_key] then
        config_entry = config.tiler.layouts[layout_type][zone_key]
        debug_log("Using " .. layout_type .. " layout for zone key: " .. zone_key)

        -- Try default layout for this key
    elseif config.tiler.layouts and config.tiler.layouts["default"] and config.tiler.layouts["default"][zone_key] then
        config_entry = config.tiler.layouts["default"][zone_key]
        debug_log("Using default layout for zone key: " .. zone_key)

        -- Last resort - general default
    elseif config.tiler.layouts and config.tiler.layouts["default"] and config.tiler.layouts["default"]["default"] then
        config_entry = config.tiler.layouts["default"]["default"]
        debug_log("Using default fallback for zone key: " .. zone_key)
    else
        -- If all else fails, provide a sensible default
        config_entry = {"full", "center"}
        debug_log("No configuration found, using hardcoded default for zone key: " .. zone_key)
    end

    -- If the config is an empty table, return empty tiles
    if config_entry and #config_entry == 0 then
        debug_log("Zone " .. zone_key .. " disabled for layout " .. layout_type)
        return {}
    end

    -- Process the tiles
    local tiles = {}
    for _, coords in ipairs(config_entry) do
        local tile = layout_utils.create_tile_from_grid_coords(screen, coords, rows, cols)
        if tile then
            table.insert(tiles, tile)
        end
    end

    -- Cache the result
    cache.zone_tiles:set(cache_key, tiles)

    return tiles
end

-- Determine which layout mode to use based on screen properties
function layout_utils.get_mode_for_screen(screen)
    -- Create a cache key - screen properties that affect the decision
    local screen_frame = screen:frame()
    local cache_key = lru_cache.key_maker(screen:name(), screen_frame.w, screen_frame.h)

    -- Check cache first
    local cached_result = cache.screen_modes:get(cache_key)
    if cached_result then
        return cached_result
    end

    -- Original code to determine layout
    local width = screen_frame.w
    local height = screen_frame.h
    local is_portrait = height > width
    local screen_name = screen:name()

    debug_log(string.format("Screen dimensions: %.1f x %.1f", width, height))
    debug_log("Screen name: " .. screen_name)

    local result = nil

    -- 1. Check for custom screen layout (exact match)
    if config.tiler.custom_screens[screen_name] then
        debug_log("Using custom layout for screen: " .. screen_name)
        result = config.tiler.custom_screens[screen_name].grid
    end

    if not result then
        -- 2. Check for pattern match in screen name
        for pattern, layout_type in pairs(config.tiler.screen_detection.patterns) do
            if screen_name:match(pattern) then
                debug_log("Matched screen pattern: " .. pattern .. " - using layout: " .. layout_type)
                if config.tiler.grids[layout_type] then
                    result = config.tiler.grids[layout_type]
                    break
                end
            end
        end
    end

    if not result then
        -- 3. Try to extract screen size from name
        local size_pattern = "(%d+)[%s%-]?inch"
        local size_match = screen_name:match(size_pattern)

        if size_match then
            local screen_size = tonumber(size_match)
            debug_log("Extracted screen size from name: " .. screen_size .. " inches")

            if is_portrait then
                -- Portrait mode layouts
                for _, size_config in pairs(config.tiler.screen_detection.portrait) do
                    local matches = false
                    if size_config.min and size_config.max then
                        matches = screen_size >= size_config.min and screen_size <= size_config.max
                    elseif size_config.min then
                        matches = screen_size >= size_config.min
                    elseif size_config.max then
                        matches = screen_size <= size_config.max
                    end

                    if matches and config.tiler.grids[size_config.layout] then
                        debug_log("Using portrait layout: " .. size_config.layout)
                        result = config.tiler.grids[size_config.layout]
                        break
                    end
                end
            else
                -- Landscape mode layouts based on size
                for _, size_config in pairs(config.tiler.screen_detection.sizes) do
                    local matches = false
                    if size_config.min and size_config.max then
                        matches = screen_size >= size_config.min and screen_size <= size_config.max
                    elseif size_config.min then
                        matches = screen_size >= size_config.min
                    elseif size_config.max then
                        matches = screen_size <= size_config.max
                    end

                    if matches and config.tiler.grids[size_config.layout] then
                        debug_log("Using size-based layout: " .. size_config.layout)
                        result = config.tiler.grids[size_config.layout]
                        break
                    end
                end
            end
        end
    end

    if not result then
        -- 4. Resolution-based fallback
        if is_portrait then
            if width >= 1440 or height >= 2560 then
                debug_log("High-resolution portrait screen - using 1x3 layout")
                result = config.tiler.grids["1x3"]
            else
                debug_log("Standard portrait screen - using 1x2 layout")
                result = config.tiler.grids["1x2"]
            end
        else
            -- Landscape orientation
            local aspect_ratio = width / height
            local is_ultrawide = aspect_ratio > 2.0

            if width >= 3840 or height >= 2160 then
                debug_log("Detected 4K or higher resolution - using 4x3 layout")
                result = config.tiler.grids["4x3"]
            elseif width >= 3440 or is_ultrawide then
                debug_log("Detected ultrawide monitor - using 4x2 layout")
                result = {
                    cols = 4,
                    rows = 2
                }
            elseif width >= 2560 or height >= 1440 then
                debug_log("Detected 1440p resolution - using 3x3 layout")
                result = config.tiler.grids["3x3"]
            elseif width >= 1920 or height >= 1080 then
                debug_log("Detected 1080p resolution - using 3x2 layout")
                result = config.tiler.grids["3x2"]
            else
                debug_log("Detected smaller resolution - using 2x2 layout")
                result = config.tiler.grids["2x2"]
            end
        end
    end

    -- Cache the result
    cache.screen_modes:set(cache_key, result)

    return result
end

------------------------------------------
-- Tile Structure
------------------------------------------

-- Create a new tile
local function tile_new(x, y, width, height)
    if not x or not y or not width or not height then
        return nil
    end

    if width <= 0 or height <= 0 then
        return nil
    end

    local tile = {
        x = x,
        y = y,
        width = width,
        height = height,
        description = nil
    }

    return tile
end

-- Convert tile to string for logging
local function tile_to_string(tile)
    if not tile then
        return "nil tile"
    end

    local desc = tile.description and (" - " .. tile.description) or ""
    return string.format("Tile(x=%.1f, y=%.1f, w=%.1f, h=%.1f%s)", tile.x, tile.y, tile.width, tile.height, desc)
end

-- Set human-readable description for a tile
local function tile_set_description(tile, desc)
    if not tile then
        return nil
    end

    tile.description = desc
    return tile -- For method chaining
end

------------------------------------------
-- Zone Structure
------------------------------------------

-- Create a new zone
local function zone_new(id, hotkey, screen)
    if not id then
        return nil
    end

    local zone = {
        id = id,
        hotkey = hotkey,
        tiles = {},
        tile_count = 0,
        window_to_tile_idx = {},
        description = nil,
        screen = screen
    }

    return zone
end

-- Set human-readable description for a zone
local function zone_set_description(zone, desc)
    if not zone then
        return nil
    end

    zone.description = desc
    return zone -- For method chaining
end

-- Add a new tile configuration to a zone
local function zone_add_tile(zone, x, y, width, height, description)
    if not zone or not x or not y or not width or not height then
        return zone
    end

    local tile = tile_new(x, y, width, height)
    if not tile then
        return zone
    end

    if description then
        -- Make sure description is always a string
        if type(description) == "table" then
            -- If it's a table, use a generic description or handle it specially
            tile_set_description(tile, "Tile position")
        else
            tile_set_description(tile, description)
        end
    end
    zone.tiles[zone.tile_count] = tile
    zone.tile_count = zone.tile_count + 1

    -- Format description for logging, ensuring it's a string
    local desc_text = ""
    if description then
        if type(description) == "string" then
            desc_text = "(" .. description .. ")"
        else
            desc_text = "(complex tile definition)"
        end
    end

    debug_log("Added tile to zone", zone.id, "total tiles:", zone.tile_count, desc_text)
    return zone -- For method chaining
end

-- Rotate through tile configurations for a window
local function zone_rotate_tile(zone, window_id)
    if not zone or not window_id then
        return -1
    end

    -- Always initialize if window not already in this zone
    if not zone.window_to_tile_idx[window_id] then
        debug_log("Window not properly tracked in zone - initializing")
        zone.window_to_tile_idx[window_id] = 0

        -- Update global tracking
        window_state.associate_window_with_zone(window_id, zone, 0)

        return 0
    end

    -- Advance to next tile configuration with wrap-around
    local next_idx = (zone.window_to_tile_idx[window_id] + 1) % zone.tile_count
    zone.window_to_tile_idx[window_id] = next_idx

    -- Update global tracking
    if not window_state._data[window_id] then
        window_state._data[window_id] = {}
    end
    window_state._data[window_id].zone_id = zone.id
    window_state._data[window_id].tile_idx = next_idx

    local desc = ""
    if zone.tiles[next_idx] and zone.tiles[next_idx].description then
        desc = " - " .. zone.tiles[next_idx].description
    end
    debug_log("Rotated window", window_id, "to tile index", next_idx, "in zone", zone.id, desc)

    -- Update the memory for this screen
    if zone.screen and tiler._screen_memory[window_id] then
        local screen_id = zone.screen:id()
        if not tiler._screen_memory[window_id] then
            tiler._screen_memory[window_id] = {}
        end

        tiler._screen_memory[window_id][screen_id] = {
            zone_id = zone.id,
            tile_idx = next_idx
        }
        debug_log("Updated remembered position for window", window_id, "on screen", screen_id, "zone", zone.id, "tile",
            next_idx)
    end

    return next_idx
end

-- Add a window to a zone
local function zone_add_window(zone, window_id)
    if not zone or not window_id then
        debug_log("Cannot add nil window to zone", zone and zone.id)
        return false
    end

    -- Use the window_state utility to handle association
    if not window_state.associate_window_with_zone(window_id, zone, 0) then
        return false
    end

    debug_log("Added window", window_id, "to zone", zone.id)

    -- Store position in screen memory
    if zone.screen then
        -- Initialize window's memory if needed
        if not tiler._screen_memory[window_id] then
            tiler._screen_memory[window_id] = {}
        end

        local screen_id = zone.screen:id()
        tiler._screen_memory[window_id][screen_id] = {
            zone_id = zone.id,
            tile_idx = 0
        }
        debug_log("Remembered position for window", window_id, "on screen", screen_id, "zone", zone.id, "tile", 0)
    end

    return true
end

-- Resize a window to match the current tile
-- Resize a window to match the current tile
local function zone_resize_window(zone, window_id)
    if not zone or not window_id then
        return false
    end

    local tile_idx = zone.window_to_tile_idx[window_id]
    if not tile_idx then
        debug_log("Cannot resize window", window_id, "- not in zone", zone.id)
        return false
    end

    local tile = zone.tiles[tile_idx]
    if not tile then
        debug_log("Invalid tile index", tile_idx, "for window", window_id)
        return false
    end

    local window = hs.window.get(window_id)
    if not window or not window:isStandard() then
        debug_log("Cannot find valid window with ID", window_id, "- seeking replacement")

        -- Clean up invalid window ID
        window_state.remove_window_from_all_zones(window_id)

        -- Try several approaches to find a replacement window

        -- 1. Try to get the app name and title from our records
        local app_name = nil
        local window_title = nil
        if window_state._data and window_state._data[window_id] then
            app_name = window_state._data[window_id].app_name
            window_title = window_state._data[window_id].title
        end

        debug_log("Searching for replacement - App:", app_name or "unknown", "Title:", window_title or "unknown")

        -- 2. If we don't have the app name, try using known problem apps
        if not app_name and settings.problem_apps then
            for _, prob_app in ipairs(settings.problem_apps) do
                local app = hs.application.find(prob_app)
                if app then
                    app_name = prob_app
                    debug_log("Found problem app:", app_name)
                    break
                end
            end
        end

        local replacement_win = nil

        -- 3. Try to find a window with matching title and app (most reliable)
        if app_name and window_title then
            debug_log("Looking for window with app:", app_name, "and title containing:", window_title)
            for _, win in ipairs(hs.window.allWindows()) do
                if win:isStandard() and win:application():name() == app_name then
                    local title = win:title()
                    -- Check for title similarity (accept partial matches)
                    if title and (title:find(window_title) or window_title:find(title)) then
                        replacement_win = win
                        debug_log("Found window by title match:", win:id(), "title:", title)
                        break
                    end
                end
            end
        end

        -- 4. Try focused window if no title match was found
        if not replacement_win then
            local focused_win = hs.window.focusedWindow()
            if focused_win and focused_win:isStandard() then
                replacement_win = focused_win
                debug_log("Using focused window:", focused_win:id())
            end
        end

        -- 5. If we have an app name but no focused window, find app's main window
        if not replacement_win and app_name then
            debug_log("Looking for any window of app:", app_name)
            local app = hs.application.find(app_name)
            if app then
                local app_windows = app:allWindows()
                for _, win in ipairs(app_windows) do
                    if win:isStandard() and not win:isMinimized() then
                        replacement_win = win
                        debug_log("Found window:", win:id(), "from app:", app_name)
                        break
                    end
                end
            end
        end

        -- 6. Last resort: look through all windows on the current screen
        if not replacement_win and zone.screen then
            debug_log("Looking for any window on screen:", zone.screen:name())
            for _, win in ipairs(hs.window.allWindows()) do
                if win:isStandard() and not win:isMinimized() and win:screen():id() == zone.screen:id() then
                    replacement_win = win
                    debug_log("Found window:", win:id(), "on current screen")
                    break
                end
            end
        end

        -- If we found a replacement window, use it
        if replacement_win then
            -- Add the replacement window to this zone
            zone_add_window(zone, replacement_win:id())

            -- Now resize it using the original tile_idx
            if zone.window_to_tile_idx[replacement_win:id()] ~= nil then
                zone.window_to_tile_idx[replacement_win:id()] = tile_idx

                -- Recursive call to resize the new window
                return zone_resize_window(zone, replacement_win:id())
            end
        else
            debug_log("No replacement window found")
        end

        return false
    end

    -- Get the screen for this zone
    local target_screen = zone.screen
    if not target_screen then
        -- Fallback to current screen if zone doesn't have one assigned
        target_screen = window:screen()
        debug_log("Zone has no screen assigned, using window's current screen:", target_screen:name())
    end

    -- Get the application name and window title for future reference
    local app_name = window:application():name()
    local window_title = window:title()

    -- Store app name and title for future reference
    if not window_state._data[window_id] then
        window_state._data[window_id] = {}
    end
    window_state._data[window_id].app_name = app_name
    window_state._data[window_id].title = window_title

    local needs_special_handling = window_utils.is_problem_app(app_name)

    -- Apply the tile dimensions to the window on the correct screen
    -- For portrait monitor with negative coordinates, explicitly move to screen first
    local screen_name = target_screen:name()
    local is_portrait = target_screen:frame().h > target_screen:frame().w
    local has_negative_coords = target_screen:frame().x < 0 or target_screen:frame().y < 0

    -- Create the frame that will be applied
    local frame = {
        x = tile.x,
        y = tile.y,
        w = tile.width,
        h = tile.height
    }

    if is_portrait and has_negative_coords then
        -- Special handling for portrait monitors with negative coordinates
        debug_log("Special handling for portrait monitor:", screen_name)

        -- Force move to the screen first to ensure we're on the right screen
        window:moveToScreen(target_screen, false, false, 0)

        -- Then set the position - use a very short delay to ensure the window has time to move
        hs.timer.doAfter(0.05, function()
            debug_log("Setting frame with delay for window", window_id, "to", tile_to_string(tile), "on screen",
                target_screen:name())

            if needs_special_handling then
                -- Special handling for problem apps
                window_utils.apply_frame_to_problem_app(window, frame, app_name)
            else
                -- Normal handling
                window_utils.apply_frame(window, frame)
            end
        end)
    else
        -- Normal case - set frame directly
        debug_log("Setting frame for window", window_id, "to", tile_to_string(tile), "on screen", target_screen:name())

        if needs_special_handling then
            -- Special handling for problem apps
            window_utils.apply_frame_to_problem_app(window, frame, app_name)
        else
            -- Normal handling
            window_utils.apply_frame(window, frame)
        end
    end

    return true
end

-- Register a zone with the Tiler
local function zone_register(zone)
    if not zone then
        return nil
    end

    -- Create a unique zone ID that includes the screen
    local full_id = zone.id
    if zone.screen then
        -- Add screen ID to make it unique, but keep original ID for hotkey referencing
        full_id = zone.id .. "_" .. zone.screen:id()
    end

    tiler._zone_id2zone[full_id] = zone

    -- Also register with the simple ID, if not already registered
    -- This ensures that hotkeys will find a zone even if they don't specify a screen
    if not tiler._zone_id2zone[zone.id] then
        tiler._zone_id2zone[zone.id] = zone
    end

    debug_log("Registered zone", full_id)

    -- Set up the hotkey for this zone
    if zone.hotkey then
        hs.hotkey.bind(zone.hotkey[1], zone.hotkey[2], function()
            activate_move_zone(zone.id)
        end)
        debug_log("Bound hotkey", zone.hotkey[1], zone.hotkey[2], "to zone", zone.id)

        -- Focus hotkey for switching between windows in this zone
        local focus_modifier = settings.focus_modifier or {"shift", "ctrl", "cmd"}
        hs.hotkey.bind(focus_modifier, zone.hotkey[2], function()
            focus_zone_windows(zone.id)
        end)
        debug_log("Bound focus hotkey", focus_modifier, zone.hotkey[2], "to zone", zone.id)
    end

    return zone -- For method chaining
end

------------------------------------------
-- Keyboard Layout Utils
------------------------------------------

-- Define keyboard layout for auto-mapping
local keyboard_layouts = {
    -- Define rows of keys for easy grid mapping
    number_row = {"6", "7", "8", "9", "0"},
    top_row = {"y", "u", "i", "o", "p"},
    home_row = {"h", "j", "k", "l", ";"},
    bottom_row = {"n", "m", ",", ".", "/"}
}

-- Creates a 2D array of key mappings based on the keyboard layout
local function create_key_map(rows, cols)
    if not rows or not cols or rows <= 0 or cols <= 0 then
        return {}
    end

    local mapping = {}
    local available_rows = {keyboard_layouts.top_row, keyboard_layouts.home_row, keyboard_layouts.bottom_row,
                            keyboard_layouts.number_row}

    -- Ensure we don't exceed available keys
    rows = math.min(rows, #available_rows)
    cols = math.min(cols, 5) -- Max 5 columns from each row

    debug_log("Creating key map for", rows, "×", cols, "grid")

    for r = 1, rows do
        mapping[r] = {}
        local key_row = available_rows[r]
        for c = 1, cols do
            mapping[r][c] = key_row[c]
        end
    end

    return mapping
end

------------------------------------------
-- Layout Creation Functions
------------------------------------------

-- Create a grid layout for a screen
local function create_grid_layout(screen, cols, rows, key_map, modifier)
    if not screen or not cols or not rows then
        return nil
    end

    if cols <= 0 or rows <= 0 then
        return nil
    end

    if not key_map then
        key_map = create_key_map(rows, cols)
    end

    local display_rect = screen:frame()
    local w = display_rect.w
    local h = display_rect.h
    local x = display_rect.x
    local y = display_rect.y

    -- Store the screen reference for later use
    local screen_id = screen:id()
    local screen_name = screen:name()

    -- Calculate dimensions for a regular grid
    local col_width = w / cols
    local row_height = h / rows

    debug_log("Grid cell size:", col_width, "×", row_height)

    local zones = {}

    -- Get layout type based on grid dimensions
    local layout_type = cols .. "x" .. rows
    debug_log("Layout type for this grid:", layout_type)

    -- Create zones for each key in the layout configuration
    if config.tiler.layouts and config.tiler.layouts[layout_type] then
        for key, _ in pairs(config.tiler.layouts[layout_type]) do
            if key ~= "default" then -- Skip default fallback
                local hotkey = modifier and key and {modifier, key}
                debug_log("Creating zone", key, "with hotkey", key)

                local zone = zone_new(key, hotkey, screen)
                if not zone then
                    goto continue_keys
                end

                zone_set_description(zone, string.format("Zone %s - Screen: %s", key, screen:name()))

                -- Get tile configurations for this zone
                local zone_tiles = layout_utils.get_zone_tiles(screen, key, rows, cols)

                -- Add each tile to the zone
                for _, tile in ipairs(zone_tiles) do
                    zone_add_tile(zone, tile.x, tile.y, tile.width, tile.height, tile.description)
                end

                -- If no tiles were added, add a default one based on position
                if zone.tile_count == 0 then
                    -- For now, use full screen as default
                    zone_add_tile(zone, x, y, w, h, "Default size")
                end

                zone_register(zone)
                table.insert(zones, zone)

                ::continue_keys::
            end
        end
    else
        -- Fallback to the old key mapping approach
        for r = 1, rows do
            for c = 1, cols do
                local zone_id = key_map[r][c] or (r .. "_" .. c)
                local key = key_map[r][c]

                if key then
                    local hotkey = modifier and key and {modifier, key}
                    debug_log("Creating zone", zone_id, "with hotkey", key)

                    local zone = zone_new(zone_id, hotkey, screen)
                    if not zone then
                        goto continue_grid
                    end

                    zone_set_description(zone, string.format("Row %d, Col %d - Screen: %s", r, c, screen:name()))

                    -- Get tile configurations for this zone
                    local zone_tiles = layout_utils.get_zone_tiles(screen, key, rows, cols)

                    -- Add each tile to the zone
                    for _, tile in ipairs(zone_tiles) do
                        zone_add_tile(zone, tile.x, tile.y, tile.width, tile.height, tile.description)
                    end

                    -- If no tiles were added, add a default one
                    if zone.tile_count == 0 then
                        local zone_x = x + (c - 1) * col_width
                        local zone_y = y + (r - 1) * row_height
                        zone_add_tile(zone, zone_x, zone_y, col_width, row_height, "Default size")
                    end

                    zone_register(zone)
                    table.insert(zones, zone)
                end

                ::continue_grid::
            end
        end
    end

    -- Create special zone for center
    local center_key = "0"
    local center_zone = zone_new("center", {modifier, center_key}, screen)
    if center_zone then
        zone_set_description(center_zone, "Center zone - Screen: " .. screen:name())

        local center_tiles = layout_utils.get_zone_tiles(screen, "0", rows, cols)
        for _, tile in ipairs(center_tiles) do
            zone_add_tile(center_zone, tile.x, tile.y, tile.width, tile.height, tile.description)
        end

        -- Add default center tiles if none were configured
        if center_zone.tile_count == 0 then
            zone_add_tile(center_zone, x + w / 4, y + h / 4, w / 2, h / 2, "Center")
            zone_add_tile(center_zone, x + w / 6, y + h / 6, w * 2 / 3, h * 2 / 3, "Large center")
            zone_add_tile(center_zone, x, y, w, h, "Full screen")
        end

        zone_register(center_zone)
        table.insert(zones, center_zone)
    end

    local mode = {
        screen_id = screen:id(),
        cols = cols,
        rows = rows,
        zones = zones
    }

    tiler._modes[screen:id()] = mode
    return mode
end

-- Initialize a screen mode with the given configuration
-- Initialize a screen mode with the given configuration
local function init_mode(screen, mode_config)
    if not screen then
        return nil
    end

    debug_log("Creating zones for layout: " .. tostring(mode_config))
    for key, _ in pairs(config.tiler.layouts["2x2"]) do
        debug_log("Registering hotkey for: " .. key)
    end

    local grid_cols, grid_rows, key_map, modifier

    if type(mode_config) == "string" then
        -- Parse a simple configuration like "3x3"
        local cols, rows = mode_config:match("(%d+)x(%d+)")
        grid_cols = tonumber(cols) or 3
        grid_rows = tonumber(rows) or 3
        key_map = create_key_map(grid_rows, grid_cols)
        modifier = settings.modifier
    elseif type(mode_config) == "table" then
        -- Use detailed configuration
        grid_cols = mode_config.cols or 3
        grid_rows = mode_config.rows or 3
        key_map = mode_config.key_map or create_key_map(grid_rows, grid_cols)
        modifier = mode_config.modifier or settings.modifier
    else
        -- Default to 3x3 grid
        grid_cols = 3
        grid_rows = 3
        key_map = create_key_map(grid_rows, grid_cols)
        modifier = settings.modifier
    end

    debug_log("Initializing", grid_cols, "×", grid_rows, "grid for screen", screen:name())

    -- Create the grid layout
    return create_grid_layout(screen, grid_cols, grid_rows, key_map, modifier)
end

------------------------------------------
-- Window Management Functions
------------------------------------------

-- Handle moving a window to a zone or cycling its tile
function activate_move_zone(zone_id)
    if not zone_id then
        return false
    end

    debug_log("Activating zone", zone_id)

    -- Get focused window
    local win = hs.window.focusedWindow()
    if not win then
        debug_log("No focused window")
        return false
    end

    local win_id = win:id()
    local current_screen = win:screen()
    if not current_screen then
        debug_log("Window has no screen")
        return false
    end

    local current_screen_id = current_screen:id()
    local screen_name = current_screen:name()

    debug_log("Window is on screen: " .. screen_name .. " (ID: " .. current_screen_id .. ")")

    -- Use zone_finder to locate the target zone
    local target_zone, target_zone_id = zone_finder.find_zone_by_id_on_screen(zone_id, current_screen)

    -- If no zones found on current screen, give up
    if not target_zone then
        debug_log("No matching zones found on current screen. Not moving window.")
        return false
    end

    -- At this point we have a valid target zone
    debug_log("Using zone: " .. target_zone.id .. " on screen: " .. screen_name)

    -- Check where the window is currently
    local current_zone, current_zone_id = window_state.get_window_zone(win_id)

    -- Check if window is actually in this zone (sanity check)
    local is_in_zone = false
    if target_zone.window_to_tile_idx and target_zone.window_to_tile_idx[win_id] ~= nil then
        is_in_zone = true
    end

    -- Ensure consistent state
    if (current_zone_id == target_zone.id) ~= is_in_zone then
        debug_log("Inconsistent state detected: id match =", (current_zone_id == target_zone.id), "is_in_zone =",
            is_in_zone, "- repairing")

        -- If it claims to be in this zone but isn't, add it
        if current_zone_id == target_zone.id and not is_in_zone then
            target_zone.window_to_tile_idx[win_id] = 0
        end

        -- If it's in this zone but not tracked, update tracking
        if is_in_zone and current_zone_id ~= target_zone.id then
            window_state.associate_window_with_zone(win_id, target_zone, 0)
        end
    end

    -- Handle the three possible cases
    if not current_zone_id then
        -- Window is not in any zone, add it to the target zone
        debug_log("Adding window", win_id, "to zone", target_zone.id)
        zone_add_window(target_zone, win_id)
    elseif current_zone_id ~= target_zone.id then
        -- Window is in a different zone, move it to the target zone
        debug_log("Moving window", win_id, "from zone", current_zone_id, "to zone", target_zone.id)

        -- Remove from the old zone and add to the new one
        window_state.associate_window_with_zone(win_id, target_zone, 0)
    else
        -- Window already in this zone, rotate through tiles
        debug_log("Rotating window", win_id, "in zone", target_zone.id)
        zone_rotate_tile(target_zone, win_id)
    end

    -- Apply the new tile dimensions
    zone_resize_window(target_zone, win_id)

    -- For debugging, confirm the new position
    hs.timer.doAfter(0.1, function()
        local new_frame = win:frame()
        debug_log("Position after applying tile: " ..
                      string.format("x=%.1f, y=%.1f, w=%.1f, h=%.1f", new_frame.x, new_frame.y, new_frame.w, new_frame.h))
    end)

    return true
end

-- Focus on windows in a particular zone
function focus_zone_windows(zone_id)
    if not zone_id then
        return false
    end

    debug_log("Focusing on windows in zone", zone_id)

    -- Get focused window
    local current_win = hs.window.focusedWindow()
    if not current_win then
        debug_log("No focused window")
        return false
    end

    local current_win_id = current_win:id()
    local current_screen = current_win:screen()
    if not current_screen then
        debug_log("Window has no screen")
        return false
    end

    local screen_name = current_screen:name()

    debug_log("Looking for zone", zone_id, "on screen", screen_name, "(ID:", current_screen:id(), ")")

    -- Find the appropriate zone using the zone_finder utility
    local target_zone, target_zone_id = zone_finder.find_zone_by_id_on_screen(zone_id, current_screen)

    if not target_zone then
        debug_log("No matching zone found on screen", screen_name)
        return false
    end

    -- Now we have a valid zone, check if it has tile definitions
    if target_zone.tile_count == 0 then
        debug_log("Zone has no tile definitions")
        return false
    end

    -- Create a tracking key for this zone+screen combination
    local focus_key = target_zone_id .. "_screen_" .. current_screen:id()

    -- Initialize focus index tracking if needed
    if not tiler._window_focus_idx then
        tiler._window_focus_idx = {}
    end

    -- Find all windows in this zone
    local zone_windows = {}

    -- 1. First check for windows explicitly assigned to this zone
    if window_state._zone_windows[target_zone_id] then
        for _, win_id in ipairs(window_state._zone_windows[target_zone_id]) do
            local win = hs.window.get(win_id)
            if win and win:isStandard() and not win:isMinimized() and win:screen():id() == current_screen:id() then
                table.insert(zone_windows, win_id)
            end
        end
    end

    -- 2. Then, find windows that significantly overlap with the primary zone tile(s)
    local primary_tiles = {}

    -- Determine which tile positions are primary for this zone
    -- To do this, we'll get the first 1-2 tile configurations from the zone
    -- Since these represent the most common/characteristic configurations
    local tiles_to_check = math.min(2, target_zone.tile_count)
    for i = 0, tiles_to_check - 1 do
        if target_zone.tiles[i] then
            table.insert(primary_tiles, target_zone.tiles[i])
        end
    end

    -- We'll also specifically check if any tile index is assigned to current window
    -- and include that tile as well (if not already included)
    if target_zone.window_to_tile_idx and target_zone.window_to_tile_idx[current_win_id] ~= nil then
        local idx = target_zone.window_to_tile_idx[current_win_id]
        local found = false

        -- Check if this tile is already in primary_tiles
        for _, tile in ipairs(primary_tiles) do
            if tile == target_zone.tiles[idx] then
                found = true
                break
            end
        end

        if not found and target_zone.tiles[idx] then
            table.insert(primary_tiles, target_zone.tiles[idx])
        end
    end

    -- Check all windows for significant overlap with primary tiles
    local all_windows = hs.window.allWindows()
    for _, win in ipairs(all_windows) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == current_screen:id() then
            local win_id = win:id()

            -- Skip if already in our list
            local already_included = false
            for _, existing_id in ipairs(zone_windows) do
                if existing_id == win_id then
                    already_included = true
                    break
                end
            end

            if not already_included then
                local win_frame = win:frame()

                -- Check each primary tile for significant overlap
                for _, tile in ipairs(primary_tiles) do
                    local overlap = rect.calculate_overlap_percentage(win_frame, tile)

                    -- Only include windows with significant overlap (50% or more)
                    if overlap >= 0.5 then
                        table.insert(zone_windows, win_id)
                        break -- No need to check other tiles
                    end
                end
            end
        end
    end

    if #zone_windows == 0 then
        debug_log("No windows found in zone", target_zone_id, "on screen", screen_name)
        return false
    end

    debug_log("Found", #zone_windows, "windows in zone", target_zone_id)

    -- Determine which window to focus next
    local next_win_idx = 1

    -- Check if current window is in the list
    local current_idx = nil
    for i, win_id in ipairs(zone_windows) do
        if win_id == current_win_id then
            current_idx = i
            break
        end
    end

    if current_idx then
        -- Move to next window in cycle
        next_win_idx = (current_idx % #zone_windows) + 1
        debug_log("Current window is in list at position", current_idx, "moving to", next_win_idx)
    else
        -- Current window not in list, use remembered index or start from beginning
        if tiler._window_focus_idx[focus_key] then
            next_win_idx = ((tiler._window_focus_idx[focus_key]) % #zone_windows) + 1
            debug_log("Using remembered index", next_win_idx)
        else
            debug_log("Starting from first window in list")
        end
    end

    -- Update remembered index
    tiler._window_focus_idx[focus_key] = next_win_idx

    -- Focus the next window
    local next_win_id = zone_windows[next_win_idx]
    local next_win = hs.window.get(next_win_id)

    if not next_win then
        debug_log("Failed to focus window", next_win_id, "- window may have been closed")
        return false
    end

    next_win:focus()
    debug_log("Focused window", next_win_id, "in zone", target_zone_id, "(", next_win_idx, "of", #zone_windows, ")")

    -- Visual feedback
    if settings.flash_on_focus then
        local frame = next_win:frame()
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
end

------------------------------------------
-- Screen Movement and Focus Functions
------------------------------------------

-- Function to move focus to next screen
function tiler.focus_next_screen()
    debug_log("Moving focus to next screen")

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        debug_log("Only one screen detected, focus move canceled")
        return false
    end

    -- Get current screen
    local current_screen = hs.screen.mainScreen()
    local current_screen_id = current_screen:id()

    -- Find next screen
    local next_screen = nil
    for i, screen in ipairs(screens) do
        if screen:id() == current_screen_id then
            next_screen = screens[(i % #screens) + 1]
            break
        end
    end

    if not next_screen then
        debug_log("Couldn't identify next screen")
        return false
    end

    -- Find windows on the next screen
    local next_windows = {}
    local all_windows = hs.window.allWindows()

    for _, win in ipairs(all_windows) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == next_screen:id() then
            table.insert(next_windows, win)
        end
    end

    if #next_windows == 0 then
        debug_log("No windows found on next screen:", next_screen:name())
        return false
    end

    -- Focus the frontmost window on that screen
    table.sort(next_windows, function(a, b)
        return a:id() > b:id() -- Usually more recent windows have higher IDs
    end)

    next_windows[1]:focus()
    debug_log("Focused window", next_windows[1]:id(), "on screen", next_screen:name())
    return true
end

-- Function to move focus to previous screen
function tiler.focus_previous_screen()
    debug_log("Moving focus to previous screen")

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        debug_log("Only one screen detected, focus move canceled")
        return false
    end

    -- Get current screen
    local current_screen = hs.screen.mainScreen()
    local current_screen_id = current_screen:id()

    -- Find previous screen
    local prev_screen = nil
    for i, screen in ipairs(screens) do
        if screen:id() == current_screen_id then
            prev_screen = screens[((i - 2) % #screens) + 1]
            break
        end
    end

    if not prev_screen then
        debug_log("Couldn't identify previous screen")
        return false
    end

    -- Find windows on the previous screen
    local prev_windows = {}
    local all_windows = hs.window.allWindows()

    for _, win in ipairs(all_windows) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == prev_screen:id() then
            table.insert(prev_windows, win)
        end
    end

    if #prev_windows == 0 then
        debug_log("No windows found on previous screen:", prev_screen:name())
        return false
    end

    -- Focus the frontmost window on that screen
    table.sort(prev_windows, function(a, b)
        return a:id() > b:id() -- Usually more recent windows have higher IDs
    end)

    prev_windows[1]:focus()
    debug_log("Focused window", prev_windows[1]:id(), "on screen", prev_screen:name())
    return true
end

-- Function to set up screen focus movement hotkeys
function tiler.setup_screen_focus_keys()
    hs.hotkey.bind(settings.focus_modifier, "p", tiler.focus_next_screen)
    hs.hotkey.bind(settings.focus_modifier, ";", tiler.focus_previous_screen)
    debug_log("Screen focus movement keys set up")
end

-- Helper function to move window to screen and restore position
local function move_window_to_screen(win, target_screen)
    if not win or not target_screen then
        return false
    end

    local win_id = win:id()
    local target_screen_id = target_screen:id()

    -- First move the window to the target screen
    win:moveToScreen(target_screen)

    -- Check if we have a remembered position for this window on the target screen
    if tiler._screen_memory[win_id] and tiler._screen_memory[win_id][target_screen_id] then
        local memory = tiler._screen_memory[win_id][target_screen_id]
        local zone_id = memory.zone_id
        local tile_idx = memory.tile_idx

        debug_log("Restoring window", win_id, "to remembered position on screen", target_screen_id, "zone", zone_id,
            "tile", tile_idx)

        -- Find the zone on the target screen
        local target_zone = zone_finder.find_zone_by_id_on_screen(zone_id, target_screen)

        if target_zone then
            -- Remove the window from any current zone
            window_state.remove_window_from_all_zones(win_id)

            -- Add to the remembered zone with the remembered tile index
            target_zone.window_to_tile_idx[win_id] = tile_idx
            window_state.associate_window_with_zone(win_id, target_zone, tile_idx)

            -- Resize to the remembered tile
            zone_resize_window(target_zone, win_id)

            return true
        end
    else
        debug_log("No remembered position for window", win_id, "on screen", target_screen_id)
    end

    -- If we reached here, either there's no remembered position or we couldn't restore it
    -- In this case, the window is moved to the target screen but not positioned
    return false
end

-- Function to move to next screen with position memory
local function move_to_next_screen()
    local win = hs.window.focusedWindow()
    if not win then
        return false
    end

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        return false
    end

    -- Find current screen
    local current_screen = win:screen()
    local current_screen_id = current_screen:id()

    -- Find next screen
    local next_screen = nil
    for i, screen in ipairs(screens) do
        if screen:id() == current_screen_id then
            next_screen = screens[(i % #screens) + 1]
            break
        end
    end

    if next_screen then
        debug_log("Moving window to next screen: " .. next_screen:name())
        return move_window_to_screen(win, next_screen)
    end

    return false
end

-- Function to move to previous screen with position memory
local function move_to_previous_screen()
    local win = hs.window.focusedWindow()
    if not win then
        return false
    end

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        return false
    end

    -- Find current screen
    local current_screen = win:screen()
    local current_screen_id = current_screen:id()

    -- Find previous screen
    local prev_screen = nil
    for i, screen in ipairs(screens) do
        if screen:id() == current_screen_id then
            prev_screen = screens[((i - 2) % #screens) + 1]
            break
        end
    end

    if prev_screen then
        debug_log("Moving window to previous screen: " .. prev_screen:name())
        return move_window_to_screen(win, prev_screen)
    end

    return false
end

-- Function to set up screen movement hotkeys
function tiler.setup_screen_movement_keys()
    hs.hotkey.bind(settings.modifier, "p", move_to_next_screen)
    hs.hotkey.bind(settings.modifier, ";", move_to_previous_screen)
    debug_log("Screen movement keys set up")
end

------------------------------------------
-- Event Handling Functions
------------------------------------------

-- Handle window events (destruction, creation, etc.)
local function handle_window_event(win_obj, appName, event_name)
    if not win_obj or not event_name then
        return
    end

    debug_log("Window event:", event_name, "for app:", appName)

    if event_name == "windowDestroyed" and win_obj then
        local win_id = win_obj:id()

        -- Clean up all state tracking for this window
        window_state.remove_window_from_all_zones(win_id)

        -- Clean up focus tracking - safely check if table exists first
        if tiler._window_focus_idx then
            tiler._window_focus_idx[win_id] = nil
        end
    end
end

-- Handles screen configuration changes
local function handle_display_change()
    debug_log("Handling screen configuration change")

    -- Clear existing modes and zones
    tiler._modes = {}
    tiler._zone_id2zone = {} -- Clear zone mappings to rebuild

    -- Wait a moment for the OS to fully register all screens
    hs.timer.doAfter(0.2, function()
        debug_log("Initializing layouts for screens:")
        for _, screen in pairs(hs.screen.allScreens()) do
            local screen_id = screen:id()
            local screen_name = screen:name()
            debug_log("Processing screen:", screen_name, "ID:", screen_id)

            -- Check for custom configuration for this specific screen
            local mode_config
            if tiler.layouts.custom[screen_name] then
                debug_log("Using custom layout for screen:", screen_name)
                mode_config = tiler.layouts.custom[screen_name]
            else
                -- Use default configuration based on screen size
                local mode_type = layout_utils.get_mode_for_screen(screen)
                debug_log("Using default layout:", mode_type)
                mode_config = mode_type
            end

            -- Initialize mode for this screen
            init_mode(screen, mode_config)
        end

        -- Add a small delay to map windows to new zones first
        hs.timer.doAfter(0.3, function()
            debug_log("Mapping windows to new screen configuration")
            tiler.map_existing_windows()
        end)

        -- Then resize windows with another delay
        hs.timer.doAfter(0.5, function()
            debug_log("Resizing windows after screen change")
            for window_id, zone_id in pairs(tiler._window_id2zone_id) do
                local zone = tiler._zone_id2zone[zone_id]
                if zone then
                    debug_log("Resizing window", window_id, "in zone", zone_id)
                    zone_resize_window(zone, window_id)
                end
            end
        end)
    end)
end

-- Initialize event listeners
local function init_listeners()
    debug_log("Initializing event listeners")

    -- Window event filter
    tiler._window_watcher = hs.window.filter.new()
    tiler._window_watcher:setDefaultFilter{}
    tiler._window_watcher:setSortOrder(hs.window.filter.sortByFocusedLast)

    -- Subscribe to window events
    tiler._window_watcher:subscribe(hs.window.filter.windowDestroyed, handle_window_event)

    -- Subscribe to window creation for smart placement
    tiler._window_watcher:subscribe(hs.window.filter.windowCreated, function(win)
        if settings.smart_placement then
            -- Use the smart_placement utility for consistent handling
            smart_placement.place_window(win)
        end
    end)

    -- Enhanced screen change watcher
    -- Stop any existing watcher first
    if tiler._screen_watcher then
        tiler._screen_watcher:stop()
    end

    -- Create a new watcher with more robust handling
    tiler._screen_watcher = hs.screen.watcher.new(function()
        debug_log("Screen configuration change detected by screen watcher")

        -- Add a delay to allow the OS to fully register screens
        hs.timer.doAfter(0.5, function()
            -- Get a list of all screens for logging
            local screens = hs.screen.allScreens()
            local screen_info = ""
            for i, screen in ipairs(screens) do
                screen_info = screen_info .. i .. ": " .. screen:name() .. " (" .. screen:id() .. ")\n"
            end
            debug_log("Current screens:\n" .. screen_info)

            -- Call the display change handler
            handle_display_change()
        end)
    end)

    -- Start the screen watcher
    tiler._screen_watcher:start()
    debug_log("Screen watcher initialized and started")
end

------------------------------------------
-- Public API Functions
------------------------------------------

-- Function to set configuration from config.lua
function tiler.set_config()
    -- Load from config.lua
    settings = {
        debug = config.tiler.debug,
        debug_cache_stats = config.tiler.debug_cache_stats or false,
        modifier = config.tiler.modifier,
        focus_modifier = config.tiler.focus_modifier,
        flash_on_focus = config.tiler.flash_on_focus,
        smart_placement = config.tiler.smart_placement,
        margins = config.tiler.margins,
        problem_apps = config.tiler.problem_apps,
        cache = config.tiler.cache or {} -- Cache settings
    }

    -- Use custom layouts from config
    if config.tiler.custom_screens then
        tiler.layouts.custom = {}
        for screen_name, layout in pairs(config.tiler.custom_screens) do
            tiler.layouts.custom[screen_name] = layout.grid
        end
    end

    -- Configure cache sizes if specified in settings
    if settings.cache then
        tiler.configure_cache(settings.cache)
    end

    debug_log("Configuration loaded from config.lua")
    return tiler
end

-- Configure a custom layout for a screen
function tiler.configure_screen(screen_name, config)
    if not screen_name or not config then
        return tiler
    end

    debug_log("Setting custom configuration for screen:", screen_name)
    tiler.layouts.custom[screen_name] = config

    -- If the screen is currently connected, apply the config immediately
    for _, screen in pairs(hs.screen.allScreens()) do
        if screen:name() == screen_name then
            init_mode(screen, config)
            break
        end
    end

    return tiler
end

-- Map windows to zones based on their positions, with proper screen handling
function tiler.map_existing_windows()
    debug_log("Mapping existing windows to zones")

    -- Get all visible windows
    local all_windows = hs.window.allWindows()
    local mapped_count = 0

    -- Track zones by screen for better reporting
    local screen_mapped = {}

    for _, win in ipairs(all_windows) do
        -- Skip windows that are already mapped
        local win_id = win:id()
        if tiler._window_id2zone_id[win_id] then
            debug_log("Window", win_id, "already mapped to zone", tiler._window_id2zone_id[win_id])
            goto continue
        end

        -- Skip non-standard or minimized windows
        if not win:isStandard() or win:isMinimized() then
            goto continue
        end

        -- Get window position and screen
        local win_frame = win:frame()
        local win_screen = win:screen()
        if not win_screen then
            debug_log("Window", win_id, "has no screen, skipping")
            goto continue
        end

        local screen_id = win_screen:id()
        local screen_name = win_screen:name()

        -- Find best matching zone using the zone_finder utility
        local match = zone_finder.find_best_zone_for_window(win)

        -- Assign window to best matching zone if found
        if match and match.zone and match.score > 0.5 then -- 50% match threshold
            debug_log("Mapping window", win_id, "to zone", match.zone.id, "with match score", match.score)

            -- Keep track of which screen this window was mapped on
            if not screen_mapped[screen_id] then
                screen_mapped[screen_id] = 0
            end
            screen_mapped[screen_id] = screen_mapped[screen_id] + 1

            -- Add window to zone with the matched tile index
            window_state.associate_window_with_zone(win_id, match.zone, match.tile_idx)
            mapped_count = mapped_count + 1
        end

        ::continue::
    end

    -- Log mapping results by screen
    for screen_id, count in pairs(screen_mapped) do
        local screen_name = "Unknown"
        for _, screen in pairs(hs.screen.allScreens()) do
            if screen:id() == screen_id then
                screen_name = screen:name()
                break
            end
        end
        debug_log("Mapped", count, "windows on screen", screen_name)
    end

    debug_log("Mapped", mapped_count, "windows to zones total")
    return mapped_count
end

-- Configure zone behavior
function tiler.configure_zone(zone_key, tile_configs)
    if not zone_key then
        return function()
        end
    end

    debug_log("Setting custom configuration for zone key:", zone_key)
    tiler.zone_configs[zone_key] = tile_configs

    -- Return a function that can be used to trigger a refresh
    -- (since we don't want to force a refresh on every config change)
    return function()
        handle_display_change()
    end
end

-- Force screen refresh
function tiler.refresh_screens()
    debug_log("Manually refreshing screen configuration")
    handle_display_change()
    return tiler
end

-- Initialize the window memory module if configured
function tiler.init_window_memory()
    if tiler._window_memory_initialized then
        return tiler
    end

    -- Load the window memory module
    tiler.window_memory = require("modules.window_memory")
    if not tiler.window_memory then
        debug_log("Failed to load window memory module")
        return tiler
    end

    -- Initialize it with a reference to ourselves
    tiler.window_memory.init(tiler)

    -- Verify window creation handler is set up
    tiler.check_window_creation_handler()

    -- Double-check after a short delay to catch any issues with handler registration
    hs.timer.doAfter(1, function()
        tiler.check_window_creation_handler()
    end)

    tiler._window_memory_initialized = true
    return tiler
end

function tiler.check_window_creation_handler()
    -- Check if the window creation handler is properly registered
    local handlers = tiler._window_watcher and tiler._window_watcher._fn or {}
    local has_creation_handler = false

    for event, fns in pairs(handlers) do
        if event == hs.window.filter.windowCreated then
            has_creation_handler = (#fns > 0)
            break
        end
    end

    if not has_creation_handler then
        debug_log("WARNING: No window creation handler found, adding one now")
        if tiler._window_watcher and tiler.window_memory then
            tiler._window_watcher:subscribe(hs.window.filter.windowCreated, tiler.window_memory.handle_window_created)
        end
    else
        debug_log("Window creation handler is properly registered")
    end

    return has_creation_handler
end

-- Add cache management functions to the tiler module
function tiler.reset_cache_stats()
    for _, c in pairs(cache) do
        c:reset_stats()
    end
    debug_log("Cache statistics reset")
end

function tiler.get_cache_stats()
    local stats = {}
    for name, c in pairs(cache) do
        stats[name] = c:stats()
    end
    return stats
end

-- Display cache statistics for debugging
function tiler.show_cache_stats()
    log_cache_stats()
    return tiler.get_cache_stats()
end

-- Configure cache sizes
function tiler.configure_cache(cache_settings)
    if not cache_settings then
        return tiler
    end

    for name, size in pairs(cache_settings) do
        if cache[name] then
            -- Create a new cache with the specified size
            local old_cache = cache[name]
            cache[name] = lru_cache.new(size)

            -- Copy over necessary statistics
            cache[name]._hits = old_cache._hits
            cache[name]._misses = old_cache._misses

            debug_log("Resized cache:", name, "to", size, "items")
        end
    end
    return tiler
end

-- For debugging: periodically log cache stats
local function setup_cache_monitoring()
    if settings.debug_cache_stats then
        hs.timer.doEvery(300, function() -- Every 5 minutes
            log_cache_stats()
        end)
    end
end

-- Main startup function
function tiler.start()
    debug_log("Starting Tiler v" .. tiler._version)

    -- Load configuration from config.lua
    tiler.set_config()

    -- Initialize window state
    window_state.init()

    -- Log margin settings for debugging
    if settings.debug then
        debug_log("Using margin settings: enabled=" .. tostring(settings.margins.enabled) .. ", size=" ..
                      tostring(settings.margins.size) .. ", screen_edge=" .. tostring(settings.margins.screen_edge))
    end

    -- Initialize the tiler
    init_listeners()

    -- Initialize layouts for all screens
    for _, screen in pairs(hs.screen.allScreens()) do
        local screen_name = screen:name()
        debug_log("Configuring screen:", screen_name)

        -- Check for custom configuration for this specific screen
        local mode_config
        if tiler.layouts.custom[screen_name] then
            debug_log("Using custom layout for screen:", screen_name)
            mode_config = tiler.layouts.custom[screen_name]
        else
            -- Use default configuration based on screen size
            local mode_type = layout_utils.get_mode_for_screen(screen)
            debug_log("Using default layout:", mode_type)
            mode_config = mode_type
        end

        init_mode(screen, mode_config)
    end

    -- Add keyboard shortcut to toggle debug mode
    hs.hotkey.bind({"ctrl", "cmd", "shift"}, "D", function()
        settings.debug = not settings.debug
        debug_log("Debug mode: " .. (settings.debug and "enabled" or "disabled"))
    end)

    -- Map existing windows (with slight delay to ensure layouts are fully initialized)
    hs.timer.doAfter(0.5, function()
        tiler.map_existing_windows()
    end)

    -- Initialize window memory if configured
    if config.window_memory and config.window_memory.enabled ~= false then
        tiler.init_window_memory()
    end

    -- Set up cache monitoring for debug purposes
    setup_cache_monitoring()

    debug_log("Tiler initialization complete")

    return tiler
end

-- Expose utility functions for other modules to use
tiler.window_utils = {
    is_valid_window = function(win)
        return win and win:isStandard()
    end,
    apply_frame = window_utils.apply_frame,
    is_problem_app = window_utils.is_problem_app
}

tiler.window_state = {
    get_window_zone = window_state.get_window_zone,
    associate_window_with_zone = window_state.associate_window_with_zone,
    remove_window_from_all_zones = window_state.remove_window_from_all_zones
}

tiler.zone_finder = {
    find_zone_by_id_on_screen = zone_finder.find_zone_by_id_on_screen,
    find_best_zone_for_window = zone_finder.find_best_zone_for_window
}

tiler.rect = {
    frames_match = rect.frames_match,
    calculate_overlap = rect.calculate_overlap,
    calculate_overlap_percentage = rect.calculate_overlap_percentage
}

tiler.layout_utils = {
    get_mode_for_screen = layout_utils.get_mode_for_screen,
    get_zone_tiles = layout_utils.get_zone_tiles
}

tiler.smart_placement = {
    place_window = smart_placement.place_window
}

tiler.zone_resize_window = zone_resize_window

-- Return the tiler object for configuration
return tiler
