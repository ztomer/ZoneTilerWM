-- auto_tiler.lua
-- Orchestrates the automatic tiling of all windows on the desktop.
-- It prioritizes window memory (history) and fills remaining gaps with smart placement.

local auto_tiler = {}
local hs_window = hs.window

-- Dependencies
local config = nil
local tiler = nil
local window_memory = nil
local smart_placer = nil
local zone_calculator = nil
local monitor_manager = nil
local window_actions = nil

-- Debug logging
local debug = require "debug.init"
local debug_log = debug.create_debug_log("auto_tiler")

-- State for cycling focused window behavior
local last_auto_tile_focused_id = nil
local last_cycle_index = nil
local last_zone_key = nil

-- Primary Overflow Map: Defines where windows should go if a zone is full
-- Valid for most 3-column layouts (h-left, j-center, k-right)
local ZONE_OVERFLOW_MAP = {
    ["h"] = "y", -- Left -> Top-Left (FILL THE HOLE)
    ["y"] = "j", -- Top-Left -> Center
    ["k"] = "j", -- Right -> Center
    ["j"] = "l", -- Center -> Right-Overflow
    ["u"] = "y", -- Top -> Top-Left
    ["n"] = "j", -- Bottom -> Center
    [","] = "j"  -- Bottom-Right -> Center
}

-- Determine best fit tile index based on area match
local function find_closest_tile_index(window, tiles)
    if not window or not tiles then return 1 end
    local win_frame = window:frame()
    local win_area = win_frame.w * win_frame.h

    local best_index = 1
    local min_diff = math.huge

    for i, tile in ipairs(tiles) do
        local tile_area = tile.w * tile.h
        local diff = math.abs(win_area - tile_area)
        if diff < min_diff then
            min_diff = diff
            best_index = i
        end
    end
    return best_index
end

-- Check if window should be ignored (e.g. minimized, excluded)
local function should_tile_window(window)
    if not window or not window:isStandard() or window:isMinimized() then
        return false
    end
    -- Check exclusions via window_memory or config if needed
    local app_name = window:application() and window:application():name()
    if config.window_memory and config.window_memory.excluded_apps then
        for _, ex in ipairs(config.window_memory.excluded_apps) do
            if app_name == ex then return false end
        end
    end
    return true
end


-- Check if two frames overlap
local function check_overlap(f1, f2)
    -- f2 might be a simple rect or a tagged object {frame=..., source=...}
    local r2 = f2.frame or f2
    return not (f1.x >= r2.x + r2.w or
                f1.x + f1.w <= r2.x or
                f1.y >= r2.y + r2.h or
                f1.y + f1.h <= r2.y)
end

-- Recursive function to try and free up a specific tile by moving its current occupant
-- to the next available slot OR an overflow zone.
--- @return success boolean, list of new_moves (to be added to queue), list of new_occupied entries
local function try_ripple_move(monitor_id, zone_key, target_tile_index, occupied_on_monitor, all_windows_map, depth)
    depth = depth or 0
    if depth > 5 then return false, {}, {} end -- Prevent infinite recursion

    local tiles = zone_calculator.get(monitor_id, zone_key)
    if not tiles then return false, {}, {} end

    -- If target_tile_index is out of bounds for THIS zone, check overflow
    if not tiles[target_tile_index] then
        local overflow_zone = ZONE_OVERFLOW_MAP[zone_key]
        if overflow_zone then
            -- Try to ripple into the overflow zone's first tile
            debug_log("Zone " .. zone_key .. " full. Overflowing to " .. overflow_zone)
            return try_ripple_move(monitor_id, overflow_zone, 1, occupied_on_monitor, all_windows_map, depth + 1)
        else
            return false, {}, {} -- No overflow defined, stuck.
        end
    end

    local target_rect = tiles[target_tile_index]
    local blocking_entry = nil

    -- Find WHO is blocking this rect
    for _, entry in ipairs(occupied_on_monitor) do
        if check_overlap(target_rect, entry) then
            if not entry.is_bumpable then
                return false, {}, {} -- Blocked by unmovable object (e.g. Focused Window)
            end
            blocking_entry = entry
            break
        end
    end

    if not blocking_entry then
        -- It's actually free! No ripple needed.
        return true, {}, {}
    end

    -- Attempt to move the blocker to the NEXT tile
    local next_tile_index = target_tile_index + 1

    -- Recursively check if we can move into next slot (or overflow)
    local can_move_blocker, sub_moves, sub_occupied = try_ripple_move(monitor_id, zone_key, next_tile_index, occupied_on_monitor, all_windows_map, depth + 1)

    if can_move_blocker then
        local dest_zone = zone_key
        local dest_tile_idx = next_tile_index
        local dest_rect = tiles[next_tile_index]

        if not dest_rect then
             -- We must have overflowed
             local overflow_zone = ZONE_OVERFLOW_MAP[zone_key]
             if overflow_zone then
                 dest_zone = overflow_zone
                 dest_tile_idx = 1
                 local oz_tiles = zone_calculator.get(monitor_id, overflow_zone)
                 dest_rect = oz_tiles and oz_tiles[1]
             end
        end

        if not dest_rect then return false, {}, {} end -- Should have been caught by recursive call failing

        local blocker_win = all_windows_map[blocking_entry.window_id]
        if not blocker_win then return false, {}, {} end

        local new_move = {
            window = blocker_win,
            monitor_id = monitor_id,
            zone_key = dest_zone,
            tile_index = dest_tile_idx,
            source = "rippled_from_" .. zone_key .. "_" .. target_tile_index
        }

        local new_occ = {
            frame = dest_rect,
            source = "Rippled: " .. (blocker_win:application():name() or "?"),
            window_id = blocker_win:id(),
            is_bumpable = true
        }

        table.insert(sub_moves, 1, new_move)
        table.insert(sub_occupied, 1, new_occ)

        return true, sub_moves, sub_occupied
    end

    return false, {}, {}
end

--- Finds zones that have at least one tile covering the center of the screen,
-- sorted by how close their centroid is to the screen center.
-- @param monitor_id string The ID of the monitor.
-- @param screen hs.screen The screen object.
-- @return table List of unique zone keys, sorted by "centerness".
local function find_center_covering_zones(monitor_id, screen)
    local frame = screen:frame()
    local cx = frame.x + frame.w / 2
    local cy = frame.y + frame.h / 2

    -- Get the layout utilized by this screen to know which zones to check
    local _, layout_key = zone_calculator.get_layout_config(screen)
    if not layout_key then return {} end

    local layout_defs = config.tiler.layouts[layout_key]
    if not layout_defs then return {} end

    local candidates = {}

    for zone_key, _ in pairs(layout_defs) do
        local tiles = zone_calculator.get(monitor_id, zone_key)
        if tiles then
            local overlapping = false
            local min_dist = math.huge -- Initialize min_dist for this zone

            for _, tile in ipairs(tiles) do
                local t_cx = tile.x + tile.w / 2
                local t_cy = tile.y + tile.h / 2
                local dist = math.sqrt((cx - t_cx)^2 + (cy - t_cy)^2)

                if dist < min_dist then
                    min_dist = dist
                end

                if cx >= tile.x and cx <= tile.x + tile.w and
                   cy >= tile.y and cy <= tile.y + tile.h then
                    overlapping = true
                end
            end

            if overlapping then
                table.insert(candidates, {key = zone_key, dist = min_dist})
            end
        end
    end

    -- Sort by distance (closest tile first), then alphabetical for stability
    table.sort(candidates, function(a, b)
        if math.abs(a.dist - b.dist) < 1.0 then -- Treat close distances as equal
            return a.key < b.key
        end
        return a.dist < b.dist
    end)

    local result_keys = {}
    for _, c in ipairs(candidates) do
        table.insert(result_keys, c.key)
    end

    return result_keys
end

function auto_tiler.tile_all_windows()
    debug_log("Starting Auto-Tile All Windows...")

    local all_windows = hs_window.allWindows()
    local windows_to_tile = {}

    -- State for the batch operation
    -- monitor_id -> list of occupied rects (frames)
    local occupied_rects_by_monitor = {}

    -- List of moves to execute: { window, monitor_id, zone_key, tile_index }
    local move_queue = {}
    local processed_window_ids = {}

    -- Initialize occupied rects map for all monitors
    local all_screens = hs.screen.allScreens()
    for _, screen in ipairs(all_screens) do
        local mid = monitor_manager.get_id(screen)
        occupied_rects_by_monitor[mid] = {}
    end

    -- Pre-filter windows and build initial occupied map
    for _, win in ipairs(all_windows) do
        local mid_for_win = nil
        local screen = win:screen()
        if screen then
            mid_for_win = monitor_manager.get_id(screen)
        end

        if should_tile_window(win) then
            table.insert(windows_to_tile, win)
        elseif mid_for_win and win:isVisible() and win:isStandard() then
            -- If we are NOT tiling it, but it's visible and standard, it's an obstacle
            if not occupied_rects_by_monitor[mid_for_win] then
                occupied_rects_by_monitor[mid_for_win] = {}
            end
            table.insert(occupied_rects_by_monitor[mid_for_win], {
                frame = win:frame(),
                source = "Obstacle: " .. (win:application():name() or "Unknown")
            })
            debug_log("Marked obstacle: " .. (win:application():name() or "Unknown"))
        end
    end



    -- Create map of all windows for easy lookup by ID
    local all_windows_map = {}
    for _, w in ipairs(all_windows) do
        all_windows_map[w:id()] = w
    end

    -- PASS 0: Focused Window (Highest Priority)
    local focused_window = hs.window.focusedWindow()
    if focused_window then

        -- Find the focused window in our list
        for _, win in ipairs(windows_to_tile) do
            if win:id() == focused_window:id() then
                local screen = win:screen()
                if screen then
                    local mid = monitor_manager.get_id(screen)

                    -- Determine candidates: Configured OR Geometric
                    local candidates_set = {}
                    local center_zone_candidates = {}

                    -- Helper to add to unique list
                    local function add_candidate(key)
                        if not candidates_set[key] then
                            table.insert(center_zone_candidates, key)
                            candidates_set[key] = true
                        end
                    end

                    -- 1. Use Configured Zones if present (Exclusive)
                    if config.tiler.auto_tile_center_zones then
                        debug_log("Using configured center zones (ignoring geometric deduction).")
                        for _, k in ipairs(config.tiler.auto_tile_center_zones) do
                            add_candidate(k)
                        end
                    else
                        -- 2. Use Geometrically Deduced Zones (minus exclusions)
                        -- Since they are sorted by closeness to center, we only want the BEST matches.
                        local deduced = find_center_covering_zones(mid, screen)
                        local excludes = config.tiler.auto_tile_deduction_excludes or {}
                        local excludes_set = {}
                        for _, ex in ipairs(excludes) do excludes_set[ex] = true end

                        -- Filter exclusions first
                        local valid_deduced = {}
                        for _, k in ipairs(deduced) do
                            if not excludes_set[k] then
                                table.insert(valid_deduced, k)
                            else
                                debug_log("Excluding deduced zone '" .. k .. "' based on config exclusion.")
                            end
                        end

                        -- Take top 1 (and any others that are effectively first, though our sorting is strict)
                        -- Actually, let's take just the first valid one, as it's the "most center".
                        if #valid_deduced > 0 then
                            add_candidate(valid_deduced[1])
                            debug_log("Selected primary deduced zone: " .. valid_deduced[1])
                        end
                    end

                    -- 3. Fallback (only if absolutely nothing found)
                    if #center_zone_candidates == 0 then
                        debug_log("No center zones found/configured. Using fallback.")
                        center_zone_candidates = {"j", "a1"} -- Minimal fallback without "0" if possible
                    end

                    debug_log("Auto-Tile Focus Candidates for " .. win:title() .. ": " .. hs.inspect(center_zone_candidates))
                    local selected_zone_key = nil
                    local selected_tile_index = 1

                    -- If we are already cycling a specific window/zone, stick to it
                    if last_auto_tile_focused_id == win:id() and last_zone_key and zone_calculator.get(mid, last_zone_key) then
                        selected_zone_key = last_zone_key
                    else
                         -- Search for the Zone that contains the single best fitting tile
                        local best_zone = nil
                        local global_min_diff = math.huge

                        local win_frame = win:frame()
                        local win_area = win_frame.w * win_frame.h

                        for _, key in ipairs(center_zone_candidates) do
                            local tiles = zone_calculator.get(mid, key)
                            if tiles then
                                for _, tile in ipairs(tiles) do
                                    local tile_area = tile.w * tile.h
                                    local diff = math.abs(win_area - tile_area)
                                    if diff < global_min_diff then
                                        global_min_diff = diff
                                        best_zone = key
                                    end
                                end
                            end
                        end
                        selected_zone_key = best_zone
                    end

                    if selected_zone_key then
                        local tiles = zone_calculator.get(mid, selected_zone_key)
                        if tiles then
                            local target_index = 1
                            -- Check if we are cycling the same window
                            if last_auto_tile_focused_id == win:id() and last_cycle_index and last_zone_key == selected_zone_key then
                                -- Cycle to next tile
                                target_index = (last_cycle_index % #tiles) + 1
                                debug_log("Pass 0: Cycling focused window in zone " .. selected_zone_key .. " to index " .. target_index)
                            else
                                -- First time or new window: Find best fit
                                target_index = find_closest_tile_index(win, tiles)
                                debug_log("Pass 0: Best fit for focused window in zone " .. selected_zone_key .. " is index " .. target_index)
                            end

                            if tiles[target_index] then
                                -- Update state
                                last_auto_tile_focused_id = win:id()
                                last_cycle_index = target_index
                                last_zone_key = selected_zone_key

                                table.insert(move_queue, {
                                    window = win,
                                    monitor_id = mid,
                                    zone_key = selected_zone_key,
                                    tile_index = target_index,
                                    source = "focused",
                                    suppress_learning = true -- Contextual, don't learn
                                })

                                -- Mark as occupied
                                if not occupied_rects_by_monitor[mid] then occupied_rects_by_monitor[mid] = {} end
                                table.insert(occupied_rects_by_monitor[mid], {
                                    frame = tiles[target_index],
                                    source = "Pass 0: " .. (win:application():name() or "Focused"),
                                    window_id = win:id(),
                                    is_bumpable = false -- Focused window is anchor
                                })
                                processed_window_ids[win:id()] = true
                                debug_log("Pass 0: Focused window " .. (win:application():name() or "") .. " -> Center (" .. selected_zone_key .. ")")
                            end
                        end
                    end
                end

                break -- Found and handled
            end
        end
    end

    -- PASS 1: Ranked Preference Constraint Algorithm
    -- Iterate rank levels (try 1st choice for everyone, then 2nd choice, etc.)
    local MAX_RANK = 5
    local remaining_windows = {}
    for _, win in ipairs(windows_to_tile) do
        if not processed_window_ids[win:id()] then
            table.insert(remaining_windows, win)
        end
    end

    for rank = 1, MAX_RANK do
        if #remaining_windows == 0 then break end

        local still_unplaced = {}

        for _, win in ipairs(remaining_windows) do
            local placed_in_round = false
            local app_name = win:application() and win:application():name() or "?"
            local screen = win:screen()

            if screen then
                local mid = monitor_manager.get_id(screen)

                -- Get ranked preferences on this monitor
                if window_memory then
                    local ranked_prefs = window_memory.get_ranked_preferences(app_name, mid)

                    if ranked_prefs and #ranked_prefs >= rank then
                        local pref = ranked_prefs[rank]

                        -- Verify validity and availability
                        local tiles = zone_calculator.get(mid, pref.zone_key)
                        if tiles and tiles[pref.tile_index] then
                            local target_rect = tiles[pref.tile_index]

                            -- Constraint Check
                            local is_blocked = false
                            local occupied_on_monitor = occupied_rects_by_monitor[mid]
                            if occupied_on_monitor then
                                for _, occupied_wrapper in ipairs(occupied_on_monitor) do
                                    if check_overlap(target_rect, occupied_wrapper) then
                                        is_blocked = true
                                        break
                                    end
                                end
                            end

                            -- Attempt RIPPLE if blocked
                            if is_blocked then
                                -- Try to ripple the occupant(s) to the next tile
                                local success, ripple_moves, ripple_occupations = try_ripple_move(mid, pref.zone_key, pref.tile_index, occupied_on_monitor, all_windows_map, 1)
                                if success then
                                    debug_log("Ripple SUCCESS for " .. app_name .. "! Moved " .. #ripple_moves .. " blockers.")
                                    is_blocked = false
                                    -- Add ripple moves and occupations
                                    for _, rm in ipairs(ripple_moves) do table.insert(move_queue, rm) end
                                    for _, ro in ipairs(ripple_occupations) do table.insert(occupied_rects_by_monitor[mid], ro) end
                                else
                                    debug_log("Ripple failed/blocked for " .. app_name .. " at " .. pref.zone_key .. ":" .. pref.tile_index)
                                end
                            end

                            if not is_blocked then
                                -- Success! Assign it.
                                table.insert(move_queue, {
                                    window = win,
                                    monitor_id = mid,
                                    zone_key = pref.zone_key,
                                    tile_index = pref.tile_index,
                                    source = "memory_rank_" .. rank
                                })

                                -- Mark as occupied
                                if not occupied_rects_by_monitor[mid] then occupied_rects_by_monitor[mid] = {} end
                                table.insert(occupied_rects_by_monitor[mid], {
                                    frame = target_rect,
                                    source = "Pass 1: " .. app_name .. " (Rank " .. rank .. ")",
                                    window_id = win:id(),
                                    is_bumpable = true
                                })
                                processed_window_ids[win:id()] = true
                                placed_in_round = true
                                debug_log("Rank " .. rank .. ": Assigned " .. app_name .. " to " .. pref.zone_key .. ":" .. pref.tile_index)
                            end
                        end
                    end
                end
            end

            if not placed_in_round then
                table.insert(still_unplaced, win)
            end
        end
        remaining_windows = still_unplaced
    end

    -- PASS 1.5: Compaction (Gravity)
    -- If Tile 1 is empty and Tile 2 is occupied, move Tile 2 -> Tile 1.
    for mid, occupied_list in pairs(occupied_rects_by_monitor) do
        -- Better approach: Iterate all configured zones for the screen layout
        local screen = nil
        -- Find screen for this mid (inefficient but safe)
        for _, s in ipairs(all_screens) do
            if monitor_manager.get_id(s) == mid then screen = s break end
        end

        if screen then
            local _, layout_key = zone_calculator.get_layout_config(screen)
            local zones = config.tiler.layouts[layout_key]
            if zones then
                for zone_key, _ in pairs(zones) do
                    local tiles = zone_calculator.get(mid, zone_key)
                    if tiles and #tiles >= 2 then
                        -- Check Tile 1 occupancy
                        local tile1_occ = nil
                        for _, occ in ipairs(occupied_list) do
                            if check_overlap(tiles[1], occ) then tile1_occ = occ break end
                        end

                        if not tile1_occ then
                             -- Tile 1 is EMPTY! Check Tile 2.
                            local tile2_occ = nil
                            for _, occ in ipairs(occupied_list) do
                                if check_overlap(tiles[2], occ) then tile2_occ = occ break end
                            end

                            if tile2_occ and tile2_occ.is_bumpable then
                                -- Move from 2 -> 1
                                local win = all_windows_map[tile2_occ.window_id]
                                if win then
                                    debug_log("Compaction: Moving " .. (win:application():name() or "?") .. " from " .. zone_key .. ":2 to " .. zone_key .. ":1")

                                    table.insert(move_queue, {
                                        window = win,
                                        monitor_id = mid,
                                        zone_key = zone_key,
                                        tile_index = 1,
                                        source = "compaction_gravity"
                                    })
                                    -- Update virtual occupancy (remove old, add new is hard, just add new to block others)
                                    table.insert(occupied_rects_by_monitor[mid], {
                                        frame = tiles[1],
                                        source = "Compacted: " .. (win:application():name() or "?"),
                                        window_id = win:id(),
                                        is_bumpable = true
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- PASS 2: Greedy Clean-up (Smart Placer)
    -- Anything left over gets whatever IS available
    debug_log("Pass 2 cleanup: processing " .. #remaining_windows .. " windows")
    for _, win in ipairs(remaining_windows) do
         debug_log("  Checking window: " .. win:title())
         local screen = win:screen()
         if screen then
             local mid = monitor_manager.get_id(screen)
             local virtual_occupied = occupied_rects_by_monitor[mid] or {}

             -- Find best tile using our virtual map (Fallback to least overlap if needed)
             local best = smart_placer.find_best_tile(win, virtual_occupied)

             if best then
                 table.insert(move_queue, {
                     window = win,
                     monitor_id = best.monitor_id,
                     zone_key = best.zone_key,
                     tile_index = best.tile_index,
                     source = "smart_cleanup",
                     suppress_learning = true
                 })

                 table.insert(occupied_rects_by_monitor[mid], {
                    frame = best.tile,
                    source = "Pass 2: " .. (win:application():name() or "Cleanup"),
                    window_id = win:id(),
                    is_bumpable = true
                 })
                 processed_window_ids[win:id()] = true
                 debug_log("Pass 2 Cleanup: Assigned " .. (win:application():name() or "?") .. " to " .. best.zone_key)
             end
         end
    end

    -- Optimize move queue: Keep only the LAST move for each window
    local final_moves = {}
    local seen_windows = {}
    -- Iterate backwards
    for i = #move_queue, 1, -1 do
        local move = move_queue[i]
        local win_id = move.window:id()
        if not seen_windows[win_id] then
            seen_windows[win_id] = true
            table.insert(final_moves, 1, move) -- Insert at beginning to preserve order of execution
        else
            debug_log("Skipping redundant move for " .. (move.window:application():name() or "?") .. " (superseded by later move)")
        end
    end

    -- EXECUTE MOVES
    debug_log("Executing " .. #final_moves .. " moves")
    for _, move in ipairs(final_moves) do
        window_actions.position_window_from_memory(move.window, move.monitor_id, move.zone_key, move.tile_index, move.suppress_learning)
    end
end

function auto_tiler.setup_hotkeys()
    if config.tiler and config.tiler.hotkeys and config.tiler.hotkeys.auto_tile_all then
        local hk = config.tiler.hotkeys.auto_tile_all
        local mods = config.keys[hk.mods] or hk.mods
        hs.hotkey.bind(mods, hk.key, function()
            auto_tiler.tile_all_windows()
        end)
        debug_log("Bound Auto-Tile All hotkey")
    end
end

function auto_tiler.init(cfg, _tiler_module, _window_memory, _smart_placer, _zone_calculator, _monitor_manager, _window_actions)
    config = cfg
    tiler_module = _tiler_module
    window_memory = _window_memory
    smart_placer = _smart_placer
    zone_calculator = _zone_calculator
    monitor_manager = _monitor_manager
    window_actions = _window_actions

    debug_log("AutoTiler initialized")

    -- Register ourselves as the smart repositioning engine
    if tiler_module and tiler_module.set_reposition_callback then
        debug_log("Registering AutoTiler as the tiler reposition callback")
        tiler_module.set_reposition_callback(auto_tiler.tile_all_windows)
    end
end

return auto_tiler
