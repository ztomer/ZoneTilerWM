-- layout_solver.lua
-- Solves the "Which window goes to which tile" assignment problem using a cost matrix.
-- Uses Recursive Backtracking to find the globally optimal assignment, respecting spatial overlap.

local layout_solver = {}

-- Debug logging
local debug = require "debug.init"
local debug_log = debug.create_debug_log("layout_solver")

-- Dependencies
local window_memory = nil

--------------------------------------------------------------------------------
-- 1. Cost Function
--------------------------------------------------------------------------------

local WEIGHTS = {
    MEMORY_EXACT = -2000, -- Dominant bonus for exact memory match
    MEMORY_ZONE  = -500,  -- Bonus for correct zone, but wrong tile
    ASPECT_RATIO = 300,   -- Penalty multiplier for AR mismatch (Reduced to allow coverage wins)
    AREA_RATIO   = 200,   -- Penalty for size mismatch
    MOVED_DIST   = 1,     -- Low penalty for physical movement distance
    SKIP_WINDOW  = 5000,  -- Cost to leave a window unassigned
    COVERAGE     = -2000  -- Reward for maximizing screen real estate (Significantly boosted)
}

--- Calculate the cost of assigning a window to a tile.
local function calculate_assignment_cost(window, tile_rect, tile_index, zone_key, monitor_id, memory_stats)
    local cost = 0

    local win_frame = window:frame()
    local screen = window:screen()
    local screen_frame = screen and screen:frame() or {w=1920, h=1080}

    -- 1. Geometric Penalties
    local tile_ar = tile_rect.w / tile_rect.h
    local win_ar = win_frame.w / win_frame.h
    local ar_diff = math.abs(win_ar - tile_ar)
    cost = cost + (ar_diff * WEIGHTS.ASPECT_RATIO)

    local tile_area_ratio = (tile_rect.w * tile_rect.h) / (screen_frame.w * screen_frame.h)
    local win_area_ratio = (win_frame.w * win_frame.h) / (screen_frame.w * screen_frame.h)
    local area_diff = math.abs(win_area_ratio - tile_area_ratio)
    cost = cost + (area_diff * WEIGHTS.AREA_RATIO)

    -- 2. Coverage Reward
    -- Subtract cost proportional to the tile's size on screen.
    -- This makes larger tiles "cheaper" (more desirable).
    -- SCALE BY RECENCY: Recent windows (Low Index) get higher reward to capture big tiles.
    local rank = tile_index -- Wait, tile_index is useless here. We need WINDOW rank.
    -- 'memory_stats' is passed as arg 6. We need a new arg for rank.
end

-- Changing signature requires changing caller.
-- Let's redefine the signature.
local function calculate_assignment_cost(window, tile_rect, tile_index, zone_key, monitor_id, memory_stats, window_rank)
    local cost = 0

    local win_frame = window:frame()
    -- ... (Screen fetch) ...
    local screen = window:screen()
    local screen_frame = screen and screen:frame() or {w=1920, h=1080}

    -- 1. Geometric Penalties
    local tile_ar = tile_rect.w / tile_rect.h
    local win_ar = win_frame.w / win_frame.h
    local ar_diff = math.abs(win_ar - tile_ar)
    cost = cost + (ar_diff * WEIGHTS.ASPECT_RATIO)

    local tile_area_ratio = (tile_rect.w * tile_rect.h) / (screen_frame.w * screen_frame.h)
    local win_area_ratio = (win_frame.w * win_frame.h) / (screen_frame.w * screen_frame.h)
    local area_diff = math.abs(win_area_ratio - tile_area_ratio)
    cost = cost + (area_diff * WEIGHTS.AREA_RATIO)

    -- 2. Coverage Reward
    -- Subtract cost proportional to the tile's size on screen.
    -- This makes larger tiles "cheaper" (more desirable).
    -- RECENCY BOOST: Rank 1 (1.0 + 1.0) = 2.0x. Rank 5 = 1.2x.
    local recency_mult = 1.0
    if window_rank then
        recency_mult = 1.0 + (1.0 / window_rank)
    end

    cost = cost + (tile_area_ratio * WEIGHTS.COVERAGE * recency_mult)

    -- 3. Memory Bonuses
    if memory_stats then
        for rank, pref in ipairs(memory_stats) do
            if pref.zone_key == zone_key then
                if pref.tile_index == tile_index then
                    cost = cost + (WEIGHTS.MEMORY_EXACT / rank)
                else
                    cost = cost + (WEIGHTS.MEMORY_ZONE / rank)
                end
                break -- Only count best match
            end
        end
    end

    -- 3. Base "Occupancy" Cost
    -- tile_index may be a string like "4a"/"4b" when split tiles are passed in from the fallback splitter;
    -- tonumber() returns nil for those, so fall back to 0 (no occupancy bias for synthetic tiles).
    cost = cost + ((tonumber(tile_index) or 0) * 10)

    return cost
end

--- Checks if two tile rects overlap.
local function check_overlap(r1, r2)
    return not (r1.x >= r2.x + r2.w or
                r1.x + r1.w <= r2.x or
                r1.y >= r2.y + r2.h or
                r1.y + r1.h <= r2.y)
end

--------------------------------------------------------------------------------
-- 2. Global Solver (Recursive Backtracking)
--------------------------------------------------------------------------------
-- Finds the assignment that minimizes TOTAL cost.
-- Complexity: O(M^N) worst case, but N (windows) is small (<10).

local MAX_SOLUTIONS_TO_CHECK = 100000

local function solve_recursive(windows, tiles, win_idx, current_assignments, current_cost, best_state, occupied_rects)
    -- Base Case: All windows processed
    if win_idx > #windows then
        if current_cost < best_state.min_cost then
            best_state.min_cost = current_cost
            best_state.assignments = {}
            for w, t in pairs(current_assignments) do best_state.assignments[w] = t end
        end
        return
    end

    -- Branch & Bound: Pruning
    if current_cost >= best_state.min_cost then return end

    -- Safety break
    best_state.checks = best_state.checks + 1
    if best_state.checks > MAX_SOLUTIONS_TO_CHECK then return end

    local cost_matrix = best_state.cost_matrix

    -- Option A: Skip this window (Unassigned)
    -- We incur the SKIP_WINDOW penalty. Useful if no valid tiles remain.
    solve_recursive(windows, tiles, win_idx + 1, current_assignments, current_cost + WEIGHTS.SKIP_WINDOW, best_state, occupied_rects)

    -- Option B: Try every available tile
    for t_idx, tile in ipairs(tiles) do
        -- 1. Check Spatial Overlap with currently assigned tiles in this branch
        local overlaps = false
        for _, rect in ipairs(occupied_rects) do
            if check_overlap(tile.rect, rect) then
                overlaps = true
                break
            end
        end

        if not overlaps then
            -- 2. Assign
            local cost = cost_matrix[win_idx][t_idx]

            table.insert(occupied_rects, tile.rect)
            current_assignments[win_idx] = t_idx

            solve_recursive(windows, tiles, win_idx + 1, current_assignments, current_cost + cost, best_state, occupied_rects)

            -- 3. Backtrack
            current_assignments[win_idx] = nil
            table.remove(occupied_rects) -- Pop
        end
    end
end

--------------------------------------------------------------------------------
-- 3. Optimization API
--------------------------------------------------------------------------------

function layout_solver.solve(windows, tiles, monitor_id)
    if #windows == 0 or #tiles == 0 then return {} end

    -- 1. Pre-calculate costs (NxM Matrix)
    local cost_matrix = {}
    for i, win in ipairs(windows) do
        cost_matrix[i] = {}
        local app_name = win:application():name()
        local memory_stats = window_memory and window_memory.get_ranked_preferences(app_name, monitor_id)
        for j, tile in ipairs(tiles) do
            -- Pass 'i' as window_rank (Windows are sorted by Z-order/Recency)
            local cost = calculate_assignment_cost(win, tile.rect, tile.tile_index, tile.zone_key, monitor_id, memory_stats, i)
            cost_matrix[i][j] = cost
        end
    end

    -- 2. Solve Backtracking
    local best_state = {
        min_cost = math.huge,
        assignments = {},
        checks = 0,
        cost_matrix = cost_matrix
    }

    -- Optimization: Sort windows?
    -- Actually, solving largest/most-constrained windows first helps pruning.
    -- But indices match cost_matrix, so we'd need to map. Keeping it simple for now (Input Order).

    solve_recursive(windows, tiles, 1, {}, 0, best_state, {})

    -- 3. Convert to Moves
    local moves = {}
    if best_state.assignments then
        for win_idx, tile_idx in pairs(best_state.assignments) do
            table.insert(moves, {
                window = windows[win_idx],
                tile = tiles[tile_idx],
                cost = cost_matrix[win_idx][tile_idx]
            })
            -- debug_log(string.format("Assigned %s -> %s:%d (Cost: %.1f)",
            --    windows[win_idx]:application():name(),
            --    tiles[tile_idx].zone_key,
            --    tiles[tile_idx].tile_index,
            --    cost_matrix[win_idx][tile_idx]))
        end
    end

    if best_state.checks >= MAX_SOLUTIONS_TO_CHECK then
         debug_log("WRN: Solver hit check limit ("..MAX_SOLUTIONS_TO_CHECK..")")
    end

    return moves
end

--- Update internal weights from config
local function update_weights(new_weights)
    if not new_weights then return end
    for k, v in pairs(new_weights) do
        -- Convert config keys (lowercase) to internal keys (uppercase)
        local key = string.upper(k)
        if WEIGHTS[key] then
            WEIGHTS[key] = v
        end
    end
end

--- Initialize the solver module.
---@param wm_module table The window_memory module.
---@param config_weights table|nil Optional table of weights from config.
function layout_solver.init(wm_module, config_weights)
    window_memory = wm_module
    if config_weights then
        update_weights(config_weights)
    end
    debug_log("Layout Solver initialized (Backtracking)")
end

return layout_solver
