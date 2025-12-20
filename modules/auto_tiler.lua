-- auto_tiler.lua
-- Orchestrates the automatic tiling of all windows on the desktop.
-- Implements a multi-pass approach: Focused Anchor -> Memory/Ripple -> Compaction -> Smart Fallback.

local auto_tiler = {}
local hs_window = hs.window
local hs_screen = hs.screen

-- Dependencies
local config = nil
local tiler_module = nil
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

-- State for dynamic overflow mapping
local dynamic_overflow_cache = {} -- mid -> {layout_key -> overflow_map}

-------------------------------------------------------------------------------
-- Internal Helper Utilities
-------------------------------------------------------------------------------

--- Calculates the centroid (center point) of a zone.
-- @local
local function _get_zone_centroid(monitor_id, zone_key)
    local tiles = zone_calculator.get(monitor_id, zone_key)
    if not tiles or #tiles == 0 then return nil end
    local cx, cy = 0, 0
    for _, t in ipairs(tiles) do cx = cx + (t.x + t.w/2) cy = cy + (t.y + t.h/2) end
    return {x = cx / #tiles, y = cy / #tiles}
end

--- Builds a dynamic overflow map based on proximity to center.
-- Windows flow from peripheral zones to more central zones.
-- @local
local function _get_dynamic_overflow_map(monitor_id, layout_key)
    if dynamic_overflow_cache[monitor_id] and dynamic_overflow_cache[monitor_id][layout_key] then
        return dynamic_overflow_cache[monitor_id][layout_key]
    end

    local zones_defs = config.tiler.layouts[layout_key]
    if not zones_defs then return {} end

    local screen = nil
    for _, s in ipairs(hs_screen.allScreens()) do
        if monitor_manager.get_id(s) == monitor_id then screen = s break end
    end
    if not screen then return {} end

    local frame = screen:frame()
    local mx, my = frame.x + frame.w/2, frame.y + frame.h/2
    local zone_data = {}

    for zk, _ in pairs(zones_defs) do
        local centroid = _get_zone_centroid(monitor_id, zk)
        if centroid then
            local dist_to_center = math.sqrt((centroid.x - mx)^2 + (centroid.y - my)^2)
            table.insert(zone_data, {key = zk, centroid = centroid, centrality = -dist_to_center})
        end
    end

    local overflow_map = {}
    for _, z1 in ipairs(zone_data) do
        local best_neighbor = nil
        local min_dist = math.huge
        for _, z2 in ipairs(zone_data) do
            if z1.key ~= z2.key and z2.centrality > z1.centrality then
                local d = math.sqrt((z1.centroid.x - z2.centroid.x)^2 + (z1.centroid.y - z2.centroid.y)^2)
                if d < min_dist then min_dist = d best_neighbor = z2.key end
            end
        end
        overflow_map[z1.key] = best_neighbor
    end

    dynamic_overflow_cache[monitor_id] = dynamic_overflow_cache[monitor_id] or {}
    dynamic_overflow_cache[monitor_id][layout_key] = overflow_map
    return overflow_map
end

--- Resolves the overflow zone for a given zone key.
-- @local
local function get_overflow_zone(monitor_id, layout_key, zone_key)
    if config.tiler and config.tiler.overflow_map and config.tiler.overflow_map[zone_key] then
        return config.tiler.overflow_map[zone_key]
    end
    local dynamic = _get_dynamic_overflow_map(monitor_id, layout_key)
    return dynamic[zone_key]
end

--- Checks if two frames overlap.
-- @local
local function check_overlap(f1, f2)
    local r2 = f2.frame or f2.rect or f2
    local r1 = f1.frame or f1.rect or f1
    return not (r1.x >= r2.x + r2.w or
                r1.x + r1.w <= r2.x or
                r1.y >= r2.y + r2.h or
                r1.y + r1.h <= r2.y)
end

--- Check if window should be managed by auto-tiler.
-- @local
local function should_tile_window(window)
    if not window or not window:isStandard() or window:isMinimized() then
        return false
    end
    local app_name = window:application() and window:application():name()
    if config.window_memory and config.window_memory.excluded_apps then
        for _, ex in ipairs(config.window_memory.excluded_apps) do
            if app_name == ex then return false end
        end
    end
    return true
end

--- Determine best fit tile index based on area match
-- @local
local function find_closest_tile_index(window, tiles)
    if not window or not tiles then return 1 end
    local win_frame = window:frame()
    local win_area = win_frame.w * win_frame.h
    local best_index = 1
    local min_diff = math.huge
    for i, tile in ipairs(tiles) do
        local tile_area = tile.w * tile.h
        local diff = math.abs(win_area - tile_area)
        if diff < min_diff then min_diff = diff best_index = i end
    end
    return best_index
end

-------------------------------------------------------------------------------
-- Ripple Engine
-------------------------------------------------------------------------------

--- Recursive function to free up a tile by moving its current occupant.
-- @local
local function try_ripple_move(monitor_id, layout_key, zone_key, target_tile_index, occupied_on_monitor, all_windows_map, depth)
    depth = depth or 0
    if depth > 5 then return false, {}, {} end

    local tiles = zone_calculator.get(monitor_id, zone_key)
    if not tiles then return false, {}, {} end

    -- Check Overflow
    if not tiles[target_tile_index] then
        local overflow_zone = get_overflow_zone(monitor_id, layout_key, zone_key)
        if overflow_zone then
            debug_log("Zone " .. zone_key .. " full. Overflowing to " .. overflow_zone)
            return try_ripple_move(monitor_id, layout_key, overflow_zone, 1, occupied_on_monitor, all_windows_map, depth + 1)
        end
        return false, {}, {}
    end

    local target_rect = tiles[target_tile_index]
    local blocking_entry = nil
    for _, entry in ipairs(occupied_on_monitor) do
        if check_overlap(target_rect, entry) then
            if not entry.is_bumpable then return false, {}, {} end
            blocking_entry = entry
            break
        end
    end

    if not blocking_entry then return true, {}, {} end

    -- Attempt to move the blocker to the NEXT tile
    local next_tile_index = target_tile_index + 1
    local success, sub_moves, sub_occupied = try_ripple_move(monitor_id, layout_key, zone_key, next_tile_index, occupied_on_monitor, all_windows_map, depth + 1)

    if success then
        local dest_zone = zone_key
        local dest_tile_idx = next_tile_index
        local dest_tiles = zone_calculator.get(monitor_id, dest_zone)
        local dest_rect = dest_tiles[dest_tile_idx]

        if not dest_rect then
             -- Overflow path (should match what recursion did)
             local overflow_zone = get_overflow_zone(monitor_id, layout_key, zone_key)
             if overflow_zone then
                 dest_zone = overflow_zone
                 dest_tile_idx = 1
                 local oz_tiles = zone_calculator.get(monitor_id, overflow_zone)
                 dest_rect = oz_tiles and oz_tiles[1]
             end
        end

        if not dest_rect then return false, {}, {} end

        local blocker_win = all_windows_map[blocking_entry.window_id]
        if not blocker_win then return false, {}, {} end

        table.insert(sub_moves, 1, {
            window = blocker_win, monitor_id = monitor_id, zone_key = dest_zone, tile_index = dest_tile_idx,
            source = "rippled_from_" .. zone_key .. "_" .. target_tile_index
        })
        table.insert(sub_occupied, 1, {
            frame = dest_rect, window_id = blocker_win:id(), is_bumpable = true,
            source = "Rippled: " .. (blocker_win:application():name() or "?")
        })

        return true, sub_moves, sub_occupied
    end

    return false, {}, {}
end

-------------------------------------------------------------------------------
-- Stage Passes
-------------------------------------------------------------------------------

--- PASS 0: Focused Window Anchor.
local function _pass_focused_anchor(windows_to_tile, occupied_rects_by_monitor, move_queue, processed_ids)
    local fw = hs_window.focusedWindow()
    if not fw or not should_tile_window(fw) then return end

    local screen = fw:screen()
    if not screen then return end
    local mid = monitor_manager.get_id(screen)
    local window_id = fw:id()

    -- Determine candidates
    local candidates = {}
    if config.tiler.auto_tile_center_zones then
        candidates = config.tiler.auto_tile_center_zones
    else
        local deduced = auto_tiler.find_center_covering_zones(mid, screen)
        local excludes = config.tiler.auto_tile_deduction_excludes or {}
        local ex_set = {}
        for _, ex in ipairs(excludes) do ex_set[ex] = true end
        for _, k in ipairs(deduced) do if not ex_set[k] then table.insert(candidates, k) end end
    end
    if #candidates == 0 then candidates = {"j", "a1"} end

    local selected_zone_key = nil
    local target_index = 1

    -- Cycling check
    if last_auto_tile_focused_id == window_id and last_zone_key and zone_calculator.get(mid, last_zone_key) then
        selected_zone_key = last_zone_key
        target_index = (last_cycle_index % #zone_calculator.get(mid, last_zone_key)) + 1
        debug_log("Pass 0: Cycling focused window in zone", selected_zone_key, "to index", target_index)
    else
        -- Best fit
        local min_diff = math.huge
        local win_frame = fw:frame()
        local win_area = win_frame.w * win_frame.h
        for _, key in ipairs(candidates) do
            local tiles = zone_calculator.get(mid, key)
            if not tiles then goto next_candidate end
            for i, tile in ipairs(tiles) do
                local diff = math.abs(win_area - (tile.w * tile.h))
                if diff < min_diff then min_diff = diff selected_zone_key = key target_index = i end
            end
            ::next_candidate::
        end
    end

    selected_zone_key = selected_zone_key or candidates[1]
    local tiles = zone_calculator.get(mid, selected_zone_key)
    if not tiles or not tiles[target_index] then return end

    last_auto_tile_focused_id = window_id
    last_cycle_index = target_index
    last_zone_key = selected_zone_key

    table.insert(move_queue, {
        window = fw, monitor_id = mid, zone_key = selected_zone_key, tile_index = target_index,
        source = "focused", is_bumpable = false, suppress_learning = true
    })
    table.insert(occupied_rects_by_monitor[mid], {
        frame = tiles[target_index], window_id = window_id, is_bumpable = false,
        source = "Pass 0: " .. (fw:application():name() or "Focused")
    })
    processed_ids[window_id] = true
    debug_log("Pass 0: Focused window", fw:application():name(), "-> Center (", selected_zone_key, ")")
end

--- PASS 1: Preference Ranking and Ripple/Bump.
local function _pass_preferences_and_ripples(windows_to_tile, occupied_rects_by_monitor, move_queue, processed_ids, all_win_map)
    local MAX_RANK = 5
    local remaining = {}
    for _, win in ipairs(windows_to_tile) do if not processed_ids[win:id()] then table.insert(remaining, win) end end

    for rank = 1, MAX_RANK do
        if #remaining == 0 then break end
        local still_unplaced = {}
        for _, win in ipairs(remaining) do
            local app_name = win:application() and win:application():name() or "?"
            local screen = win:screen()
            if not screen then goto next_win end
            local mid = monitor_manager.get_id(screen)
            local _, layout_key = zone_calculator.get_layout_config(screen)

            local prefs = window_memory and window_memory.get_ranked_preferences(app_name, mid)
            local pref = (prefs and prefs[rank])
            local tiles = (pref and zone_calculator.get(mid, pref.zone_key))
            local target_rect = (tiles and tiles[pref.tile_index])

            if not target_rect then
                table.insert(still_unplaced, win)
                goto next_win
            end

            -- Ripple check
            local success, r_moves, r_occ = try_ripple_move(mid, layout_key, pref.zone_key, pref.tile_index, occupied_rects_by_monitor[mid], all_win_map, 1)
            if not success then
                table.insert(still_unplaced, win)
                goto next_win
            end

            -- CLEANUP STALE OCCUPATIONS
            for _, rm in ipairs(r_moves) do
                local rid = rm.window:id()
                for i = #occupied_rects_by_monitor[mid], 1, -1 do
                    if occupied_rects_by_monitor[mid][i].window_id == rid then
                        table.remove(occupied_rects_by_monitor[mid], i)
                    end
                end
            end

            for _, rm in ipairs(r_moves) do table.insert(move_queue, rm) end
            for _, ro in ipairs(r_occ) do table.insert(occupied_rects_by_monitor[mid], ro) end

            table.insert(move_queue, {
                window = win, monitor_id = mid, zone_key = pref.zone_key, tile_index = pref.tile_index,
                source = "memory_rank_" .. rank, is_bumpable = true
            })
            table.insert(occupied_rects_by_monitor[mid], {
                frame = target_rect, window_id = win:id(), is_bumpable = true,
                source = "Pass 1: " .. app_name .. " (Rank " .. rank .. ")"
            })
            processed_ids[win:id()] = true
            debug_log("Rank", rank, ": Assigned", app_name, "to", pref.zone_key .. ":" .. pref.tile_index)

            ::next_win::
        end
        remaining = still_unplaced
    end
    return remaining
end

--- PASS 1.5: Compaction (Gravity).
local function _pass_compaction(occupied_rects_by_monitor, move_queue, all_win_map)
    local all_screens = hs_screen.allScreens()
    for mid, occupied_list in pairs(occupied_rects_by_monitor) do
        local screen = nil
        for _, s in ipairs(all_screens) do if monitor_manager.get_id(s) == mid then screen = s break end end
        if not screen then goto next_monitor end

        local _, layout_key = zone_calculator.get_layout_config(screen)
        local zones_defs = layout_key and config.tiler.layouts[layout_key]
        if not zones_defs then goto next_monitor end

        for zone_key, _ in pairs(zones_defs) do
            local tiles = zone_calculator.get(mid, zone_key)
            if not tiles or #tiles < 2 then goto next_zone end

            local occ1, occ2 = nil, nil
            for _, occ in ipairs(occupied_list) do
                if check_overlap(tiles[1], occ) then occ1 = occ end
                if check_overlap(tiles[2], occ) then occ2 = occ end
            end

            if not occ1 and occ2 and occ2.is_bumpable then
                local win = all_win_map[occ2.window_id]
                if win then
                    debug_log("Compaction: Moving", (win:application():name() or "?"), "from", zone_key .. ":2 to index 1")
                    table.insert(move_queue, {
                        window = win, monitor_id = mid, zone_key = zone_key, tile_index = 1,
                        source = "compaction_gravity", is_bumpable = true
                    })
                    table.insert(occupied_list, {
                        frame = tiles[1], window_id = win:id(), is_bumpable = true,
                        source = "Compacted: " .. (win:application():name() or "?")
                    })
                end
            end
            ::next_zone::
        end
        ::next_monitor::
    end
end

--- PASS 2: Greedy Clean-up (Smart Placer).
local function _pass_smart_cleanup(remaining_windows, occupied_rects_by_monitor, move_queue, processed_ids)
    debug_log("Pass 2 cleanup: processing", #remaining_windows, "windows")
    for _, win in ipairs(remaining_windows) do
        if processed_ids[win:id()] then goto next_win end

        local screen = win:screen()
        local mid = screen and monitor_manager.get_id(screen)
        local virtual = mid and occupied_rects_by_monitor[mid]

        if not virtual then goto next_win end

        local best = smart_placer.find_best_tile(win, virtual)
        if best then
            table.insert(move_queue, {
                window = win, monitor_id = mid, zone_key = best.zone_key, tile_index = best.tile_index,
                source = "smart_cleanup", is_bumpable = true, suppress_learning = true
            })
            table.insert(occupied_rects_by_monitor[mid], {
                frame = best.tile, window_id = win:id(), is_bumpable = true,
                source = "Pass 2: " .. (win:application():name() or "Cleanup")
            })
            processed_ids[win:id()] = true
            debug_log("Pass 2 Cleanup: Assigned", (win:application():name() or "?"), "to", best.zone_key)
        end
        ::next_win::
    end
end

--- FINAL: Execute moves.
local function _execute_moves(move_queue)
    local final_moves = {}
    local seen = {}
    for i = #move_queue, 1, -1 do
        local m = move_queue[i]
        local wid = m.window:id()
        if not seen[wid] then
            seen[wid] = true
            table.insert(final_moves, 1, m)
        else
            debug_log("Skipping redundant move for", (m.window:application():name() or "?"), "(superseded)")
        end
    end
    debug_log("Executing", #final_moves, "moves")
    for _, m in ipairs(final_moves) do
        window_actions.position_window_from_memory(m.window, m.monitor_id, m.zone_key, m.tile_index, m.suppress_learning)
    end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Geometric deduction for center zones.
function auto_tiler.find_center_covering_zones(monitor_id, screen)
    local frame = screen:frame()
    local cx, cy = frame.x + frame.w / 2, frame.y + frame.h / 2
    local _, layout_key = zone_calculator.get_layout_config(screen)
    local defs = config.tiler.layouts[layout_key] or {}
    local candidates = {}
    for zk, _ in pairs(defs) do
        local tiles = zone_calculator.get(monitor_id, zk)
        if tiles then
            for _, t in ipairs(tiles) do
                if cx >= t.x and cx <= t.x+t.w and cy >= t.y and cy <= t.y+t.h then
                    local dist = math.sqrt((cx - (t.x+t.w/2))^2 + (cy - (t.y+t.h/2))^2)
                    table.insert(candidates, {key = zk, dist = dist})
                    break
                end
            end
        end
    end
    table.sort(candidates, function(a,b) return a.dist < b.dist end)
    local keys = {}
    for _, c in ipairs(candidates) do table.insert(keys, c.key) end
    return keys
end

--- Auto-tiles windows on the currently focused screen only.
function auto_tiler.tile_focused_screen()
    local fw = hs_window.focusedWindow()
    if not fw then return end
    local screen = fw:screen()
    if not screen then return end
    auto_tiler.tile_all_windows(screen)
end

--- Main Tiling Entry Point.
-- @param target_screen (hs.screen|nil) If provided, only tile windows on this screen.
function auto_tiler.tile_all_windows(target_screen)
    debug_log("Starting Auto-Tile " .. (target_screen and ("Screen: " .. target_screen:name()) or "All Windows") .. "...")
    local all_windows = hs_window.allWindows()
    local all_screens = hs_screen.allScreens()

    local windows_to_tile = {}
    local occupied_rects_by_monitor = {}
    local move_queue = {}
    local processed_ids = {}
    local all_win_map = {}

    -- Filter monitors if target_screen is provided
    local monitors_to_process = all_screens
    if target_screen then
        monitors_to_process = {target_screen}
    end

    -- Preparation
    for _, s in ipairs(monitors_to_process) do occupied_rects_by_monitor[monitor_manager.get_id(s)] = {} end

    for _, win in ipairs(all_windows) do
        local wid = win:id()
        all_win_map[wid] = win
        local win_screen = win:screen()
        local mid = win_screen and monitor_manager.get_id(win_screen)

        -- Only process if it's on a monitor we are interested in
        if mid and occupied_rects_by_monitor[mid] then
            if should_tile_window(win) then
                table.insert(windows_to_tile, win)
            elseif win:isVisible() and win:isStandard() then
                table.insert(occupied_rects_by_monitor[mid], {
                    frame = win:frame(), window_id = wid, is_bumpable = false,
                    source = "Obstacle: " .. (win:application():name() or "Unknown")
                })
                debug_log("Marked obstacle:", (win:application():name() or "Unknown"))
            end
        end
    end

    -- PASS 0: Focus Anchor
    _pass_focused_anchor(windows_to_tile, occupied_rects_by_monitor, move_queue, processed_ids)

    -- PASS 1: Preferences & Ripples
    local remaining = _pass_preferences_and_ripples(windows_to_tile, occupied_rects_by_monitor, move_queue, processed_ids, all_win_map)

    -- PASS 1.5: Compaction
    _pass_compaction(occupied_rects_by_monitor, move_queue, all_win_map)

    -- PASS 2: Smart Cleanup
    _pass_smart_cleanup(remaining, occupied_rects_by_monitor, move_queue, processed_ids)

    -- EXECUTION
    _execute_moves(move_queue)
    debug_log("Auto-Tile complete.")
end

function auto_tiler.setup_hotkeys()
    if config.tiler and config.tiler.hotkeys then
        local hk = config.tiler.hotkeys
        if hk.auto_tile_screen and hk.auto_tile_screen.key ~= "" then
            hs.hotkey.bind(config.keys[hk.auto_tile_screen.mods] or hk.auto_tile_screen.mods, hk.auto_tile_screen.key, auto_tiler.tile_focused_screen)
            debug_log("Bound Auto-Tile Screen hotkey")
        end
        if hk.auto_tile_global and hk.auto_tile_global.key ~= "" then
            hs.hotkey.bind(config.keys[hk.auto_tile_global.mods] or hk.auto_tile_global.mods, hk.auto_tile_global.key, auto_tiler.tile_all_windows)
            debug_log("Bound Auto-Tile Global hotkey")
        end
    end
end

function auto_tiler.init(cfg, _tiler, _wm, _sp, _zc, _mm, _wa)
    config, tiler_module, window_memory, smart_placer, zone_calculator, monitor_manager, window_actions = cfg, _tiler, _wm, _sp, _zc, _mm, _wa
    if tiler_module and tiler_module.set_reposition_callback then
        tiler_module.set_reposition_callback(auto_tiler.tile_all_windows)
    end
    debug_log("AutoTiler initialized")
end

return auto_tiler
