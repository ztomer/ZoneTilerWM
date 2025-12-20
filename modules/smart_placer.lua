-- smart_placer.lua
-- Contains the logic for intelligently placing new windows in empty tiles.
local hs_window = hs.window

local smart_placer = {}

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("smart_placer")

-- Module state
local config = nil -- Set in init
local monitor_manager = nil -- Set in init
local zone_calculator = nil -- Set in init
local window_state_manager = nil -- Set in init
local window_actions = nil -- Set in init

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
function smart_placer.find_best_tile(window, occupied_frames_override)
    if not window or not window:isStandard() or window:isMinimized() then
        return nil
    end

    if not config.tiler.smart_placement or not config.tiler.smart_placement.enabled then
        return nil
    end

    -- Exclude configured apps from smart placement
    local app_name = window:application() and window:application():name()
    if app_name and config.tiler.smart_placement.exclude_apps then
        for _, excluded_app in ipairs(config.tiler.smart_placement.exclude_apps) do
            if app_name == excluded_app then
                debug_log("Skipping smart placement for excluded app:", app_name)
                return nil
            end
        end
    end

    local screen = window:screen()
    if not screen then
        return nil
    end

    local monitor_id = monitor_manager.get_id(screen)

    -- If no override provided, use live window state
    local occupied_frames = occupied_frames_override
    if not occupied_frames then
        -- Skip if window is already in a tiler-managed zone (only check this if we aren't simulating)
        if window_state_manager and window_state_manager.get and window_state_manager.get(window:id()) then
            debug_log("Skipping smart placement, window already in a zone:", app_name)
            return nil
        end

        local all_windows_on_screen = hs_window.filter.new(false):setScreens(screen:name()):getWindows()
        occupied_frames = {}
        for _, win in ipairs(all_windows_on_screen) do
            if win:id() ~= window:id() then
                table.insert(occupied_frames, win:frame())
            end
        end
    end

    -- 2. Get layout for this monitor to know which zones and tiles are available
    local _, layout_key = zone_calculator.get_layout_config(screen)
    if not layout_key then
        debug_log("Smart placer: could not determine layout key for monitor", monitor_id)
        return nil
    end

    local layout_zones = config.tiler.layouts[layout_key]
    if not layout_zones then
        debug_log("Smart placer: no layout found for key", layout_key)
        return nil
    end

    -- 3. Iterate through all zones and their tiles to find the largest free one
    local best_tile_data = nil
    local max_area = -1

    -- Fallback: Track the tile with the least overlap if we can't find an empty one
    local best_fallback_data = nil
    local min_overlap_area = math.huge

    -- Sort keys for deterministic iteration (prefer top-left / alphabetical)
    local sorted_keys = {}
    for k, _ in pairs(layout_zones) do table.insert(sorted_keys, k) end
    table.sort(sorted_keys)

    for _, zone_key in ipairs(sorted_keys) do
        -- Skip "default" zone which is a fallback
        if zone_key ~= "default" then
            local zone_tiles = zone_calculator.get(monitor_id, zone_key)
            if zone_tiles then
                for i = 1, #zone_tiles do
                    local candidate_tile = zone_tiles[i]

                    -- Calculate Total Overlap
                    local current_overlap = 0
                    local current_collisions = {}
                    for _, occupied_obj in ipairs(occupied_frames) do
                        local occupied_frame = occupied_obj.frame or occupied_obj
                        local intersect = hs.geometry.intersectionRect(candidate_tile, occupied_frame)
                        if intersect then
                            local area = intersect.w * intersect.h
                            -- Ignore very small bleeds (shadows, alignment artifacts)
                            local overlap_pct = area / (candidate_tile.w * candidate_tile.h)
                            if overlap_pct > 0.01 or area > 50 then
                                current_overlap = current_overlap + area
                                table.insert(current_collisions, occupied_obj)
                            end
                        end
                    end

                    -- Calculate Base Smart Score (Area + Position)
                    local area_score = candidate_tile.w * candidate_tile.h
                    local tc_x = candidate_tile.x + candidate_tile.w/2
                    local tc_y = candidate_tile.y + candidate_tile.h/2
                    local diag = math.sqrt(screen:frame().w^2 + screen:frame().h^2)
                    local dist = math.sqrt(tc_x^2 + tc_y^2)
                    local closeness = 1.0 - (dist / diag) -- 0 to 1
                    local screen_area = screen:frame().w * screen:frame().h
                    local position_score = screen_area * closeness

                    -- Combine fit and flow (40% fitting area, 60% positional priority)
                    local base_score = (area_score * 0.4) + (position_score * 0.6)

                    -- Apply Index Penalty (Prefer tile 1 over tile 2)
                    local index_penalty = (1.1 - (math.min(i, 10) * 0.05))
                    local ranked_score = base_score * index_penalty

                    -- Apply Aspect Ratio and Coverage Penalties
                    local ar = candidate_tile.w / candidate_tile.h
                    if ar < 0.4 or ar > 3.5 then ranked_score = ranked_score * 0.5 end

                    -- Continuous Coverage Penalty: We prefer smaller tiles over larger ones
                    -- to keep the grid as open as possible for other windows.
                    local coverage = area_score / screen_area
                    ranked_score = ranked_score * (1.1 - coverage)

                    -- APPLY OVERLAP PENALTY
                    -- We use a steep, non-clipping penalty.
                    -- A tile with 0% overlap gets 1.0x score.
                    -- A tile with 1% overlap (occupancy_ratio = 0.01) gets 1/(1+5) = ~0.16x score.
                    -- A tile with 100% overlap gets 1/(1+500) = ~0.002x score.
                    -- This ensures that ANY empty tile (even a tiny one) beats ANY occupied tile (even a huge one).
                    local occupancy_ratio = current_overlap / area_score
                    local overlap_multiplier = 1.0 / (1.0 + (occupancy_ratio * 500))

                    local final_score = ranked_score * overlap_multiplier

                    if final_score > max_area then
                        max_area = final_score
                        best_tile_data = {
                            monitor_id = monitor_id,
                            zone_key = zone_key,
                            tile_index = i,
                            tile = candidate_tile,
                            collisions = current_collisions,
                            overlap_ratio = occupancy_ratio
                        }
                    end
                end
            end
        end
    end

    if best_tile_data then
        if best_tile_data.overlap_ratio > 0.1 then
            debug_log(string.format("Smart placer picked tile %s:%d with %.1f%% occupancy (Fallback mode)",
                best_tile_data.zone_key, best_tile_data.tile_index, best_tile_data.overlap_ratio * 100))
        else
            debug_log(string.format("Smart placer assigned window to empty tile: %s:%d",
                best_tile_data.zone_key, best_tile_data.tile_index))
        end
        return best_tile_data
    end

    debug_log("Smart placer could not find any suitable tile for window after exhaustive search.")
    return nil
end

function smart_placer.place_window(window)
    local best = smart_placer.find_best_tile(window)
    if best then
        return window_actions.position_window_from_memory(window, best.monitor_id, best.zone_key, best.tile_index)
    end
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