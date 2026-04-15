--- Determines the best tile for a window based on a chosen strategy.
local placement_strategy = {}

-- Module state
local config = nil
local window_state_manager = nil
local log = function(...) end
local debug_logging = false

local function debug_log(...)
    if debug_logging then
        log(...)
    end
end

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
    log = log_func or function() end
    debug_logging = (config and config.tiler and config.tiler.advanced and config.tiler.advanced.debug_logging) or false
    log('placement_strategy initialized')
end

function placement_strategy.find_best_tile(window, zone_key, zone_windows, zone, all_tiles_in_zone)
    local strategy = (config and config.tiler and config.tiler.placement_strategy) or 'rotate'
    log('Using placement strategy: ', strategy)
    
    -- DEBUG: check window state at start
    local debug_state = window_state_manager.get(window:id())
    debug_log('find_best_tile: START - window_id=' .. window:id() .. ' zone_key=' .. zone_key .. ' state_zone=' .. (debug_state and debug_state.zone_key or 'nil') .. ' state_tile=' .. (debug_state and debug_state.tile_index or 'nil'))

    if strategy == 'hybrid' then
        local current_pos = window_state_manager.get(window:id())
        if current_pos and current_pos.zone_key == zone_key then
            return placement_strategy.find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
        else
            return placement_strategy.find_largest_free_tile(window, all_tiles_in_zone, false)
        end
    elseif strategy == 'largest_free_space' then
        local current_pos = window_state_manager.get(window:id())
        local already_in_zone = current_pos and current_pos.zone_key == zone_key
        debug_log('largest_free_space: current zone_key=' .. (current_pos and current_pos.zone_key or 'nil') .. ' target=' .. zone_key .. ' already_in_zone=' .. tostring(already_in_zone))
        return placement_strategy.find_largest_free_tile(window, all_tiles_in_zone, already_in_zone)
    elseif strategy == 'rotate' then
        return placement_strategy.find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    else
        log('Unknown placement strategy: ', strategy, ". Defaulting to 'rotate'.")
        return placement_strategy.find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    end
end

-- Rotation strategy - cycles through tiles
function placement_strategy.find_by_rotation(window, zone_key, zone_windows, all_tiles_in_zone)
    if not all_tiles_in_zone or #all_tiles_in_zone == 0 then
        log('Rotation strategy: No tiles available in this zone.')
        return nil
    end

    local num_tiles = #all_tiles_in_zone
    local current_pos = window_state_manager.get(window:id())

    -- Always cycle: use current tile_index + 1, or start at 1
    local current_tile = (current_pos and current_pos.tile_index) or 0
    local next_tile_index = (current_tile % num_tiles) + 1
    log('Rotation: current=' .. current_tile .. ' next=' .. next_tile_index)
    return all_tiles_in_zone[next_tile_index]
end

-- Largest free space - finds tile with maximum usable space (tile area minus overlap)
function placement_strategy.find_largest_free_tile(window, all_tiles_in_zone, already_in_zone)
    if not all_tiles_in_zone or #all_tiles_in_zone == 0 then
        log('Largest-free-space strategy: No tiles available in this zone.')
        return nil
    end

    local screen = window:screen()
    if not screen then
        log('Largest-free-space strategy: Window has no screen.')
        return placement_strategy.find_by_rotation(window, nil, {}, all_tiles_in_zone)
    end

    -- Use cache
    local window_cache = require("modules.window_cache")
    local all_windows = window_cache.get_for_screen_with_cache(screen:id())
    
    local current_frame = window:frame()
    log('Largest-free-space: checking ' .. #all_windows .. ' other windows, current at x=' .. current_frame.x .. ' y=' .. current_frame.y)

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
    table.sort(tile_options, function(a, b) return a.available > b.available end)
    
    debug_log('largest_free_space: after sort, tile_options:')
    for i, v in ipairs(tile_options) do
        debug_log('  tile_options[' .. i .. ']: x=' .. v.tile.x .. ' y=' .. v.tile.y .. ' w=' .. v.tile.w .. ' h=' .. v.tile.h .. ' available=' .. v.available)
    end
    
    -- Check if the best option is completely unusable (available <= 0)
    if tile_options[1].available <= 0 then
        log('Largest-free-space strategy: All tiles fully blocked, falling back to rotation.')
        return placement_strategy.find_by_rotation(window, nil, {}, all_tiles_in_zone)
    end
    
    -- If already in this zone, pick the next best (cycle through available space)
    if already_in_zone and #tile_options > 1 then
        debug_log('largest_free_space: already_in_zone=true, #tile_options=' .. #tile_options)
        
        -- Get window state position for comparison
        local state_pos = window_state_manager.get(window:id())
        debug_log('largest_free_space: window_state has zone_key=' .. (state_pos and state_pos.zone_key or 'nil') .. ' tile_index=' .. (state_pos and state_pos.tile_index or 'nil'))
        
        -- Also check tile_index_to_apply that was stored
        debug_log('largest_free_space: current_frame before comparison: x=' .. current_frame.x .. ' y=' .. current_frame.y .. ' w=' .. current_frame.w .. ' h=' .. current_frame.h)
        
        -- Find current tile in the sorted list by comparing with current_frame
        local current_in_options = nil
        for i, v in ipairs(tile_options) do
            local x_eq = math.abs(v.tile.x - current_frame.x)
            local y_eq = math.abs(v.tile.y - current_frame.y)
            local w_eq = math.abs(v.tile.w - current_frame.w)
            local h_eq = math.abs(v.tile.h - current_frame.h)
            local is_match = x_eq < 1.0 and y_eq < 1.0 and w_eq < 1.0 and h_eq < 1.0
            debug_log('largest_free_space: compare tile ' .. i .. ' tile=(' .. v.tile.x .. ',' .. v.tile.y .. ',' .. v.tile.w .. ',' .. v.tile.h .. ') frame=(' .. current_frame.x .. ',' .. current_frame.y .. ',' .. current_frame.w .. ',' .. current_frame.h .. ') xdiff=' .. x_eq .. ' ydiff=' .. y_eq .. ' wdiff=' .. w_eq .. ' hdiff=' .. h_eq .. ' match=' .. tostring(is_match))
            if is_match then
                current_in_options = i
                debug_log('largest_free_space: FOUND MATCH at index ' .. i)
                break
            end
        end
        
        if current_in_options then
            -- Pick the next one, wrap around
            local next_idx = (current_in_options % #tile_options) + 1
            debug_log('largest_free_space: smart rotation from ' .. current_in_options .. ' to ' .. next_idx)
            return tile_options[next_idx].tile
        else
            debug_log('largest_free_space: current tile NOT found - trying by tile_index from state')
            -- Fallback: use tile_index from window_state_manager
            if state_pos and state_pos.tile_index then
                local idx_from_state = state_pos.tile_index
                debug_log('largest_free_space: trying index from state=' .. idx_from_state)
                if idx_from_state >= 1 and idx_from_state <= #all_tiles_in_zone then
                    debug_log('largest_free_space: returning tile from state index')
                    return all_tiles_in_zone[idx_from_state]
                end
            end
            debug_log('largest_free_space: state fallback failed, using default')
        end
    end
    
    -- Default: return tile with most available space
    log('Largest-free-space strategy: Best tile (available=' .. tile_options[1].available .. ' out of ' .. tile_options[1].area .. ')')
    return tile_options[1].tile
end

return placement_strategy