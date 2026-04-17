--- Determines the best tile for a window based on a chosen strategy.
local placement_strategy = {}

-- Standardize logging: Import it directly, stop passing it via init!
local debug = require("debug.init")
local debug_log = debug.create_debug_log("placement_strategy")

-- Module state
local config = nil
local window_state_manager = nil

-- Checks if two rectangles intersect
local function rectangles_intersect(r1, r2)
    return not (r2.x >= r1.x + r1.w or r2.x + r2.w <= r1.x or r2.y >= r1.y + r1.h or r2.y + r2.h <= r1.y)
end

-- Calculate intersection area between two rectangles
local function rectangle_intersection_area(r1, r2)
    local x_overlap = math.max(0, math.min(r1.x + r1.w, r2.x + r2.w) - math.max(r1.x, r2.x))
    local y_overlap = math.max(0, math.min(r1.y + r1.h, r2.y + r2.h) - math.max(r1.y, r2.y))
    return x_overlap * y_overlap
end

-- Check if two rectangles are approximately equal (within tolerance)
local function rectangles_equal(r1, r2, tolerance)
    tolerance = tolerance or 1.0
    return math.abs(r1.x - r2.x) < tolerance and math.abs(r1.y - r2.y) < tolerance
end

function placement_strategy.init(cfg, utils, wsm, log_func)
    config = cfg
    window_state_manager = wsm
    log = log_func or function()
    end
    debug_logging = (config and config.tiler and config.tiler.advanced and config.tiler.advanced.debug_logging) or false
    log('placement_strategy initialized')
end

function placement_strategy.find_best_tile(window, zone_key, zone_windows, zone, all_tiles_in_zone)
    local strategy = (config and config.tiler and config.tiler.placement_strategy) or 'rotate'
    debug_log('Using placement strategy: ', strategy)

    if strategy == 'largest_free_space' then
        local current_pos = window_state_manager.get(window:id())
        local already_in_zone = current_pos and current_pos.zone_key == zone_key
        return placement_strategy.find_largest_free_tile(window, all_tiles_in_zone, already_in_zone)
    elseif strategy == 'rotate' or strategy == 'hybrid' then
        return placement_strategy.find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    else
        debug_log('Unknown placement strategy: ', strategy, ". Defaulting to 'rotate'.")
        return placement_strategy.find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    end
end

-- Rotation strategy - cycles through tiles
function placement_strategy.find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    if not all_tiles_in_zone or #all_tiles_in_zone == 0 then
        debug_log('Rotation strategy: No tiles available in this zone.')
        return nil
    end

    local num_tiles = #all_tiles_in_zone
    local current_pos = window_state_manager.get(window:id())

    -- Always cycle: use current tile_index + 1, or start at 1
    local current_tile = (current_pos and current_pos.tile_index) or 0
    local next_tile_index = (current_tile % num_tiles) + 1
    debug_log('Rotation: current=', current_tile, ' next=', next_tile_index)
    return all_tiles_in_zone[next_tile_index]
end

-- Largest free space - finds tile with maximum usable space (tile area minus overlap)
function placement_strategy.find_largest_free_tile(window, all_tiles_in_zone, already_in_zone)
    if not all_tiles_in_zone or #all_tiles_in_zone == 0 then
        debug_log('Largest-free-space strategy: No tiles available in this zone.')
        return nil
    end

    local screen = window:screen()
    if not screen then
        debug_log('Largest-free-space strategy: Window has no screen.')
        return placement_strategy.find_by_rotation(window, nil, {}, all_tiles_in_zone)
    end

    -- Use cache
    local window_cache = require("modules.window_cache")
    local all_windows = window_cache.get_for_screen_with_cache(screen:id())

    local current_frame = window:frame()

    -- Calculate available space for each tile (tile area minus overlap with other windows)
    local tile_options = {}
    for _, candidate_tile in ipairs(all_tiles_in_zone) do
        local tile_area = candidate_tile.w * candidate_tile.h
        local overlap = 0

        -- Sum up overlap with all OTHER windows
        for _, info in ipairs(all_windows) do
            if info.window:id() ~= window:id() then
                overlap = overlap + rectangle_intersection_area(candidate_tile, info.frame)
            end
        end

        local available_space = tile_area - overlap
        table.insert(tile_options, {
            tile = candidate_tile,
            area = tile_area,
            available = available_space
        })
    end

    -- Sort by available space (largest first)
    table.sort(tile_options, function(a, b)
        return a.available > b.available
    end)

    -- Helper to compare tiles
    local function tiles_equal(t1, t2)
        return math.abs(t1.x - t2.x) < 1.0 and
               math.abs(t1.y - t2.y) < 1.0 and
               math.abs(t1.w - t2.w) < 1.0 and
               math.abs(t1.h - t2.h) < 1.0
    end

    -- Find which tile the window is currently at (in the original zone_tiles order)
    local current_tile_idx = nil
    for i, tile in ipairs(all_tiles_in_zone) do
        if tiles_equal(tile, current_frame) then
            current_tile_idx = i
            break
        end
    end

    -- When all tiles have negative available space (overlap > tile_area),
    -- fall back to cycling from current position instead of blindly returning tile 1
    if tile_options[1].available <= 0 then
        if current_tile_idx and #all_tiles_in_zone > 1 then
            local next_idx = (current_tile_idx % #all_tiles_in_zone) + 1
            debug_log('Largest-free-space: all tiles blocked, cycling from tile ', current_tile_idx, ' to ', next_idx)
            return all_tiles_in_zone[next_idx]
        else
            return all_tiles_in_zone[1]
        end
    end

    -- If already in this zone, pick the next best (cycle through available space)
    if already_in_zone and #tile_options > 1 then
        local state_pos = window_state_manager.get(window:id())

        -- Find current tile in the sorted list by comparing with current_frame
        local current_in_options = nil
        for i, v in ipairs(tile_options) do
            if tiles_equal(v.tile, current_frame) then
                current_in_options = i
                break
            end
        end

        if current_in_options then
            local next_idx = (current_in_options % #tile_options) + 1
            local selected_tile = tile_options[next_idx].tile
            if tiles_equal(selected_tile, current_frame) then
                -- Selected tile same as current, try to find a different one
                for skip = 1, #tile_options - 1 do
                    local try_idx = ((next_idx + skip - 1) % #tile_options) + 1
                    if try_idx ~= current_in_options and not tiles_equal(tile_options[try_idx].tile, current_frame) then
                        debug_log('Largest-free-space: cycling to index ', try_idx, ' to avoid same position')
                        return tile_options[try_idx].tile
                    end
                end
            end
            return selected_tile
        else
            -- Fallback: use tile_index from state
            if state_pos and state_pos.tile_index then
                local idx_from_state = state_pos.tile_index
                if idx_from_state >= 1 and idx_from_state <= #all_tiles_in_zone then
                    return all_tiles_in_zone[idx_from_state]
                end
            end
        end
    elseif not already_in_zone and #tile_options > 1 then
        -- Entering a new zone - skip tiles that match current position
        if current_tile_idx then
            local next_idx = (current_tile_idx % #all_tiles_in_zone) + 1
            debug_log('Largest-free-space: entering new zone, current matches tile ', current_tile_idx,
                      ', cycling to ', next_idx)
            return all_tiles_in_zone[next_idx]
        end
    end

    -- Default: return tile with most available space
    return tile_options[1].tile
end

--- Initializes the placement strategy dependencies.
function placement_strategy.init(cfg, wsm)
    config = cfg
    window_state_manager = wsm
end

return placement_strategy
