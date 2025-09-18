-- placement_strategy.lua
-- Determines the best tile for a window based on a chosen strategy.

local placement_strategy = {}

-- Module state
local config = nil
local tiler_utils = nil
local window_state_manager = nil
local log = function(...) end -- Placeholder, will be set in init

-- Forward declarations for strategy functions
local find_by_rotation
local find_largest_free_tile
local find_by_hybrid_strategy

-- Helper function to check if two rectangles intersect
local function rectangles_intersect(r1, r2)
    return not (r2.x >= r1.x + r1.w or
        r2.x + r2.w <= r1.x or
        r2.y >= r1.y + r1.h or
        r2.y + r2.h <= r1.y)
end

--- Initializes the module.
-- @param cfg The main configuration table.
-- @param utils A table of utility functions from the tiler.
-- @param wsm The window_state_manager module.
-- @param log_func A logging function.
function placement_strategy.init(cfg, utils, wsm, log_func)
    config = cfg
    tiler_utils = utils
    window_state_manager = wsm
    log = log_func or log
    log("placement_strategy initialized")
end

--- Finds the best tile for a new window in a given zone based on the configured strategy.
-- @param window The window to place.
-- @param zone_key The key of the zone to place the window in.
-- @param zone_windows A list of windows currently in the zone.
-- @param zone A table representing the zone, containing grid dimensions and tiles.
-- @param all_tiles_in_zone A list of all possible tiles for the zone.
-- @return A tile frame (e.g., {x, y, w, h}), or nil if no space is found.
function placement_strategy.find_best_tile(window, zone_key, zone_windows, zone, all_tiles_in_zone)
    local strategy = config.tiler.placement_strategy or "rotate"
    log("Using placement strategy: ", strategy)

    if strategy == "hybrid" then
        return find_by_hybrid_strategy(window, zone_key, zone_windows, zone, all_tiles_in_zone)
    elseif strategy == "largest_free_space" then
        return find_largest_free_tile(window, all_tiles_in_zone)
    elseif strategy == "rotate" then
        return find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    else
        log("Unknown placement strategy: ", strategy, ". Defaulting to 'rotate'.")
        return find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    end
end

--- Strategy: A hybrid approach that uses largest_free_space for initial placement and rotate for cycling.
-- @param window The window to place.
-- @param zone_key The key of the zone to place the window in.
-- @param zone_windows A list of windows currently in the zone.
-- @param zone A table representing the zone, containing grid dimensions.
-- @param all_tiles_in_zone A list of all possible tiles for the zone.
-- @return A tile frame or nil.
find_by_hybrid_strategy = function(window, zone_key, zone_windows, zone, all_tiles_in_zone)
    local current_pos = window_state_manager.get(window:id())

    if current_pos and current_pos.zone_key == zone_key then
        -- Window is already in the target zone, so we rotate.
        return find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    else
        -- Window is new to this zone, so find the largest free space.
        return find_largest_free_tile(window, all_tiles_in_zone)
    end
end

--- Strategy: Find the next available tile by rotation.
-- This is the classic tiling behavior where windows fill up predefined slots in order.
-- @param window The window to place.
-- @param zone_key The key of the zone to place the window in.
-- @param zone_windows A list of windows currently in the zone.
-- @param all_tiles_in_zone A list of all possible tiles for the zone.
-- @return A tile frame or nil.
find_by_rotation = function(window, zone_key, zone_windows, all_tiles_in_zone)
    if not all_tiles_in_zone or #all_tiles_in_zone == 0 then
        log("Rotation strategy: No tiles available in this zone.")
        return nil
    end

    local num_tiles = #all_tiles_in_zone
    local current_pos = window_state_manager.get(window:id())

    if current_pos and current_pos.zone_key == zone_key then
        -- Window is already in the target zone, so we cycle to the next tile.
        local next_tile_index = (current_pos.tile_index % num_tiles) + 1
        log("Rotation strategy: Cycling window to tile", next_tile_index)
        return all_tiles_in_zone[next_tile_index]
    else
        -- Window is new to this zone.
        local num_windows = #zone_windows
        if num_windows >= num_tiles then
            log("Rotation strategy: All tiles are likely occupied.")
            local tile_index = (num_windows % num_tiles) + 1
            return all_tiles_in_zone[tile_index]
        else
            return all_tiles_in_zone[num_windows + 1]
        end
    end
end

--- Strategy: Find the largest free predefined tile in the zone.
-- @param window The window to place.
-- @param all_tiles_in_zone A list of all possible tiles for the zone.
-- @return A tile frame or nil.
find_largest_free_tile = function(window, all_tiles_in_zone)
    if not all_tiles_in_zone or #all_tiles_in_zone == 0 then
        log("Largest-free-space strategy: No tiles available in this zone.")
        return nil
    end

    local screen = window:screen()
    if not screen then
        log("Largest-free-space strategy: Window has no screen.")
        return find_by_rotation(window, nil, {}, all_tiles_in_zone) -- fallback
    end

    local filter = hs.window.filter.new()
    filter:setScreens(screen:name())
    local all_windows_on_screen = filter:getWindows()
    local occupied_frames = {}
    for _, win in pairs(all_windows_on_screen) do
        if win:id() ~= window:id() then
            table.insert(occupied_frames, win:frame())
        end
    end

    local best_tile = nil
    local max_area = -1

    for _, candidate_tile in ipairs(all_tiles_in_zone) do
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
            end
        end
    end

    if best_tile then
        log("Largest-free-space strategy: Found best tile.")
        return best_tile
    else
        log("Largest-free-space strategy: No free tiles found, falling back to rotation.")
        return find_by_rotation(window, nil, {}, all_tiles_in_zone)
    end
end

return placement_strategy