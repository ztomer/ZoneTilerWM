-- auto_tiler.lua
local auto_tiler = {}
local hs_window = hs.window
local hs_screen = hs.screen
local window_cache = require "modules.window_cache"
local layout_solver = require "modules.layout_solver"

local config, tiler_module, window_memory, zone_calculator, monitor_manager, window_actions = nil, nil, nil, nil, nil,
    nil
local debug = require "debug.init"
local debug_log = debug.create_debug_log("auto_tiler")

local last_auto_tile_focused_id, last_cycle_index, last_zone_key = nil, nil, nil
local current_anchor_rect = nil

-------------------------------------------------------------------------------
-- BSP Subdivider
-------------------------------------------------------------------------------
local function _subdivide_tiles_to_fit(available_tiles, required_count)
    local iters = 0
    while #available_tiles < required_count and #available_tiles > 0 and iters < 20 do
        iters = iters + 1
        local largest_idx, largest_area = 1, 0
        for i, t in ipairs(available_tiles) do
            local area = t.rect.w * t.rect.h
            if area > largest_area then
                largest_area = area;
                largest_idx = i
            end
        end
        local largest = available_tiles[largest_idx]
        if largest.rect.w < 250 and largest.rect.h < 250 then
            break
        end
        table.remove(available_tiles, largest_idx)
        local t1, t2 = {}, {}
        for k, v in pairs(largest) do
            t1[k] = v;
            t2[k] = v
        end
        t1.rect = {
            x = largest.rect.x,
            y = largest.rect.y,
            w = largest.rect.w,
            h = largest.rect.h
        }
        t2.rect = {
            x = largest.rect.x,
            y = largest.rect.y,
            w = largest.rect.w,
            h = largest.rect.h
        }
        if largest.rect.w > largest.rect.h then
            t1.rect.w = math.floor(largest.rect.w / 2)
            t2.rect.w = largest.rect.w - t1.rect.w
            t2.rect.x = largest.rect.x + t1.rect.w
        else
            t1.rect.h = math.floor(largest.rect.h / 2)
            t2.rect.h = largest.rect.h - t1.rect.h
            t2.rect.y = largest.rect.y + t1.rect.h
        end
        t1.tile_index, t2.tile_index = t1.tile_index .. "a", t2.tile_index .. "b"
        table.insert(available_tiles, t1);
        table.insert(available_tiles, t2)
    end
end

-------------------------------------------------------------------------------
-- Core Logic
-------------------------------------------------------------------------------
local function calculate_overlap_ratio(rect1, rect2)
    local r1, r2 = rect1.frame or rect1.rect or rect1, rect2.frame or rect2.rect or rect2
    if not r1 or not r2 then
        return 0
    end
    local x_overlap = math.max(0, math.min(r1.x + r1.w, r2.x + r2.w) - math.max(r1.x, r2.x))
    local y_overlap = math.max(0, math.min(r1.y + r1.h, r2.y + r2.h) - math.max(r1.y, r2.y))
    if x_overlap <= 0 or y_overlap <= 0 then
        return 0
    end
    local r1_area = r1.w * r1.h
    return r1_area == 0 and 0 or ((x_overlap * y_overlap) / r1_area)
end

local function _pass_focused_anchor(windows_to_tile, occupied_rects_by_monitor, move_queue, processed_ids)
    current_anchor_rect = nil
    local fw = hs_window.focusedWindow()
    if not fw or not fw:isStandard() or fw:isMinimized() then
        return
    end
    local screen = fw:screen()
    if not screen then
        return
    end
    local mid = monitor_manager.get_id(screen)
    local window_id = fw:id()
    local candidates = config.tiler.auto_tile_center_zones or {"j", "center", "0"}
    local selected_zone_key = candidates[1]
    local target_index = 1
    if last_auto_tile_focused_id == window_id and last_zone_key and zone_calculator.get(mid, last_zone_key) then
        selected_zone_key = last_zone_key
        target_index = (last_cycle_index % #zone_calculator.get(mid, last_zone_key)) + 1
    end
    local tiles = zone_calculator.get(mid, selected_zone_key)
    if not tiles or not tiles[target_index] then
        return
    end
    last_auto_tile_focused_id, last_cycle_index, last_zone_key = window_id, target_index, selected_zone_key
    current_anchor_rect = tiles[target_index]
    table.insert(move_queue, {
        window = fw,
        monitor_id = mid,
        zone_key = selected_zone_key,
        tile_index = target_index,
        source = "focused",
        is_bumpable = false,
        suppress_learning = true,
        custom_rect = current_anchor_rect
    })
    table.insert(occupied_rects_by_monitor[mid], {
        frame = current_anchor_rect,
        window_id = window_id,
        is_bumpable = false
    })
    processed_ids[window_id] = true
end

local function _pass_working_set_cull(windows, mid, z_order_map)
    local t_limit = (config.tiler.working_set and config.tiler.working_set.time_limit_sec) or 1800
    local n_limit = (config.tiler.working_set and config.tiler.working_set.max_capacity) or 6
    local now, active_pool, limbo_set = os.time(), {}, {}
    for _, win in ipairs(windows) do
        local info = window_cache.get_info(win:id())
        local last_focus = info and info.last_focused_time or now
        if (now - last_focus) > t_limit then
            table.insert(limbo_set, win)
        else
            table.insert(active_pool, win)
        end
    end
    local scores, mode = {}, config.tiler.auto_tiling_mode or "usage"
    for _, win in ipairs(active_pool) do
        local app_name = win:application() and win:application():name() or ""
        local prefs = window_memory and window_memory.get_ranked_preferences(app_name, mid) or {}
        local usage = 0;
        for _, p in ipairs(prefs) do
            usage = usage + p.count
        end
        scores[win:id()] = {
            usage = usage,
            z_order = z_order_map[win:id()] or 9999
        }
    end
    table.sort(active_pool, function(a, b)
        local sa, sb = scores[a:id()], scores[b:id()]
        if mode == "usage" then
            if sa.usage ~= sb.usage then
                return sa.usage > sb.usage
            end
            return sa.z_order < sb.z_order
        else
            if sa.z_order ~= sb.z_order then
                return sa.z_order < sb.z_order
            end
            return sa.usage > sb.usage
        end
    end)
    local working_set = {};
    for i, win in ipairs(active_pool) do
        if i <= n_limit then
            table.insert(working_set, win)
        else
            table.insert(limbo_set, win)
        end
    end
    return working_set, limbo_set
end

local function _pass_greedy_memory(windows, mid, occupied_rects, move_queue, processed_ids)
    for _, win in ipairs(windows) do
        if not processed_ids[win:id()] then
            local app_name = win:application() and win:application():name() or ""
            local prefs = window_memory.get_ranked_preferences(app_name, mid)
            for _, pref in ipairs(prefs) do
                local tiles = zone_calculator.get(mid, pref.zone_key)
                if tiles and tiles[pref.tile_index] then
                    local rect = tiles[pref.tile_index]
                    local blocked = false;
                    for _, occ in ipairs(occupied_rects) do
                        if calculate_overlap_ratio(rect, occ) > 0.05 then
                            blocked = true
                            break
                        end
                    end
                    if not blocked then
                        table.insert(move_queue, {
                            window = win,
                            monitor_id = mid,
                            zone_key = pref.zone_key,
                            tile_index = pref.tile_index,
                            source = "greedy",
                            is_bumpable = true,
                            suppress_learning = true,
                            custom_rect = rect
                        })
                        table.insert(occupied_rects, {
                            frame = rect,
                            window_id = win:id()
                        })
                        processed_ids[win:id()] = true;
                        break
                    end
                end
            end
        end
    end
end

local function _pass_solver(windows, occupied_rects, move_queue, processed_ids, mid)
    local unplaced = {};
    for _, w in ipairs(windows) do
        if not processed_ids[w:id()] then
            table.insert(unplaced, w)
        end
    end
    if #unplaced == 0 then
        return
    end
    local screen = unplaced[1]:screen()
    local _, layout_key = zone_calculator.get_layout_config(screen)
    local grid_def = config.tiler.grids and layout_key and config.tiler.grids[layout_key]
    local zone_keys = {};
    if grid_def and grid_def.zones then
        for k, _ in pairs(grid_def.zones) do
            table.insert(zone_keys, k)
        end
    else
        for _, k in ipairs({"h", "j", "k", "l", "i", "u", "y", "o", "n", "m"}) do
            table.insert(zone_keys, k)
        end
    end
    local available_tiles = {}
    for _, zk in ipairs(zone_keys) do
        local tiles = zone_calculator.get(mid, zk)
        if tiles then
            for i, t in ipairs(tiles) do
                local blocked = false;
                for _, occ in ipairs(occupied_rects) do
                    if calculate_overlap_ratio(t, occ) > 0.05 then
                        blocked = true
                        break
                    end
                end
                if not blocked then
                    table.insert(available_tiles, {
                        rect = t,
                        zone_key = zk,
                        tile_index = i,
                        monitor_id = mid
                    })
                end
            end
        end
    end
    -- Sort available tiles by area (largest first) to prioritize filling more screen space
    table.sort(available_tiles, function(a, b)
        local area_a = a.rect.w * a.rect.h
        local area_b = b.rect.w * b.rect.h
        return area_a > area_b
    end)
    debug_log("Solver pass: " .. #available_tiles .. " tiles available, " .. #unplaced .. " windows to place")
    for i, t in ipairs(available_tiles) do
        local area = t.rect.w * t.rect.h
        debug_log("  tile " .. i .. ": " .. t.zone_key .. " tile " .. t.tile_index .. " area=" .. area)
    end
    if #available_tiles > 0 and #unplaced > #available_tiles then
        _subdivide_tiles_to_fit(available_tiles, #unplaced)
    end
    if #available_tiles > 0 then
        local moves = layout_solver.solve(unplaced, available_tiles, mid)
        for _, move in ipairs(moves) do
            table.insert(move_queue, {
                window = move.window,
                monitor_id = mid,
                zone_key = move.tile.zone_key,
                tile_index = move.tile.tile_index,
                source = "solver",
                is_bumpable = true,
                custom_rect = move.tile.rect
            })
            table.insert(occupied_rects, {
                frame = move.tile.rect,
                window_id = move.window:id()
            })
            processed_ids[move.window:id()] = true
        end
    end
end

local function _pass_limbo_stack(limbo_windows, mid, move_queue, processed_ids)
    local rect = current_anchor_rect or (zone_calculator.get(mid, "j") and zone_calculator.get(mid, "j")[1]) or {
        x = 0,
        y = 0,
        w = 100,
        h = 100
    }
    for _, win in ipairs(limbo_windows) do
        if not processed_ids[win:id()] then
            table.insert(move_queue, {
                window = win,
                monitor_id = mid,
                zone_key = "limbo",
                tile_index = 1,
                source = "limbo",
                is_bumpable = true,
                suppress_learning = true,
                custom_rect = rect
            })
            processed_ids[win:id()] = true
        end
    end
end

local function _execute_moves(move_queue)
    local final_moves, seen = {}, {}
    for i = #move_queue, 1, -1 do
        local m = move_queue[i]
        if not seen[m.window:id()] then
            seen[m.window:id()] = true;
            table.insert(final_moves, 1, m)
        end
    end
    debug_log("Executing", #final_moves, "moves")
    for _, m in ipairs(final_moves) do
        if m.custom_rect then
            window_actions.apply_frame(m.window, m.custom_rect)
            require("modules.window_state_manager").set(m.window:id(), m.monitor_id, m.zone_key, m.tile_index, true)
        else
            window_actions.position_window_from_memory(m.window, m.monitor_id, m.zone_key, m.tile_index,
                m.suppress_learning)
        end
    end
end

local function _pass_fill_gaps(move_queue, processed_ids, occupied_rects)
    for mid, occ_rects in pairs(occupied_rects) do
        local screen = monitor_manager.get_screen(mid)
        if not screen then goto continue_monitor end

        local screen_frame = screen:frame()
        local total_screen_area = screen_frame.w * screen_frame.h

        local occupied_area = 0
        for _, occ in ipairs(occ_rects) do
            local r = occ.frame
            occupied_area = occupied_area + (r.w * r.h)
        end

        local free_area = total_screen_area - occupied_area
        if free_area < total_screen_area * 0.1 then
            debug_log("Fill gaps: only " .. math.floor(free_area / total_screen_area * 100) .. "% free, skipping")
            goto continue_monitor
        end

        debug_log("Fill gaps: " .. math.floor(free_area / total_screen_area * 100) .. "% free on monitor " .. mid)

        -- Get grid config and create boolean occupancy map
        local grid_config, layout_key = zone_calculator.get_layout_config(screen)
        if not grid_config then
            debug_log("Fill gaps: no grid config for monitor " .. mid)
            goto continue_monitor
        end

        local cols, rows = grid_config.cols, grid_config.rows
        local cell_w = screen_frame.w / cols
        local cell_h = screen_frame.h / rows

        -- Create 2D boolean grid: grid[col][row] = true if occupied
        local grid = {}
        for c = 1, cols do
            grid[c] = {}
            for r = 1, rows do
                grid[c][r] = false
            end
        end

        -- Mark occupied cells based on window positions
        for _, occ in ipairs(occ_rects) do
            local r = occ.frame
            local x1 = math.max(0, r.x - screen_frame.x)
            local y1 = math.max(0, r.y - screen_frame.y)
            local x2 = x1 + r.w
            local y2 = y1 + r.h

            local c1 = math.floor(x1 / cell_w) + 1
            local c2 = math.floor((x2 - 1) / cell_w) + 1
            local row1 = math.floor(y1 / cell_h) + 1
            local row2 = math.floor((y2 - 1) / cell_h) + 1

            c1 = math.max(1, math.min(cols, c1))
            c2 = math.max(1, math.min(cols, c2))
            row1 = math.max(1, math.min(rows, row1))
            row2 = math.max(1, math.min(rows, row2))

            for c = c1, c2 do
                for ro = row1, row2 do
                    grid[c][ro] = true
                end
            end
        end

        -- Get all tiles and check availability using grid
        local all_tiles = {}
        local zone_keys = {"h", "j", "k", "l", "i", "u", "y", "o", "n", "m"}
        for _, zk in ipairs(zone_keys) do
            local tiles = zone_calculator.get(mid, zk)
            if tiles then
                for i, t in ipairs(tiles) do
                    -- Calculate grid coords directly from tile position
                    local tx = t.x - screen_frame.x
                    local ty = t.y - screen_frame.y
                    local c1 = math.floor(tx / cell_w) + 1
                    local r1 = math.floor(ty / cell_h) + 1
                    local c2 = math.floor((tx + t.w - 1) / cell_w) + 1
                    local r2 = math.floor((ty + t.h - 1) / cell_h) + 1
                    c1 = math.max(1, math.min(cols, c1))
                    c2 = math.max(1, math.min(cols, c2))
                    r1 = math.max(1, math.min(rows, r1))
                    r2 = math.max(1, math.min(rows, r2))

                    -- Check if any cell in the tile's span is occupied
                    local is_occupied = false
                    for c = c1, c2 do
                        for ro = r1, r2 do
                            if grid[c] and grid[c][ro] then
                                is_occupied = true
                                break
                            end
                        end
                        if is_occupied then break end
                    end
                    if not is_occupied then
                        table.insert(all_tiles, {
                            rect = t,
                            zone_key = zk,
                            tile_index = i,
                            area = t.w * t.h
                        })
                    end
                end
            end
        end

        if #all_tiles == 0 then
            debug_log("Fill gaps: no available tiles found")
            goto continue_monitor
        end

        table.sort(all_tiles, function(a, b) return a.area > b.area end)

        debug_log("Fill gaps: " .. #all_tiles .. " available tiles to consider")

        -- Iterate until no more improvements possible or max iterations reached
        local max_iterations = cols * rows
        local made_improvement = true
        local iteration = 0

        while made_improvement and iteration < max_iterations do
            made_improvement = false
            iteration = iteration + 1

            -- Sort move_queue by current area ascending (smallest windows first)
            local sorted_moves = {}
            for _, m in ipairs(move_queue) do
                if m.monitor_id == mid then
                    local current_area = (m.custom_rect and m.custom_rect.w * m.custom_rect.h) or 0
                    table.insert(sorted_moves, {m = m, area = current_area})
                end
            end
            table.sort(sorted_moves, function(a, b) return a.area < b.area end)

            -- Track which tiles have been assigned to avoid conflicts
            local used_tiles = {}
            for _, sm in ipairs(sorted_moves) do
                local m = sm.m
                local current_area = sm.area

                for _, tile in ipairs(all_tiles) do
                    if not used_tiles[tile] and tile.area > current_area then
                        -- Double-check tile is still free by checking grid
                        local tx = tile.rect.x - screen_frame.x
                        local ty = tile.rect.y - screen_frame.y
                        local c1 = math.floor(tx / cell_w) + 1
                        local r1 = math.floor(ty / cell_h) + 1
                        local c2 = math.floor((tx + tile.rect.w - 1) / cell_w) + 1
                        local r2 = math.floor((ty + tile.rect.h - 1) / cell_h) + 1
                        local is_occupied = false
                        for c = c1, c2 do
                            for ro = r1, r2 do
                                if grid[c] and grid[c][ro] then
                                    is_occupied = true
                                    break
                                end
                            end
                            if is_occupied then break end
                        end
                        if is_occupied then
                            goto skip_tile
                        end

                        debug_log("Fill gaps: iter " .. iteration .. " moving " .. (m.window:application():name() or "?") ..
                            " from " .. m.zone_key .. " to " .. tile.zone_key ..
                            " (area " .. current_area .. " -> " .. tile.area .. ")")
                        m.custom_rect = tile.rect
                        m.zone_key = tile.zone_key
                        m.tile_index = tile.tile_index
                        used_tiles[tile] = true
                        sm.area = tile.area -- Update for subsequent iterations
                        made_improvement = true

                        -- Mark tile's grid cells as occupied for subsequent windows
                        for c = c1, c2 do
                            for ro = r1, r2 do
                                if grid[c] then grid[c][ro] = true end
                            end
                        end
                        break
                    end
                    ::skip_tile::
                end
            end
        end

        debug_log("Fill gaps: completed " .. iteration .. " iterations")

        ::continue_monitor::
    end
end

 -------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function auto_tiler.tile_all_windows(target_screen)
    debug_log("Starting Auto-Tile (Working Set Mode)...")
    local move_queue, processed_ids, occupied_rects = {}, {}, {}
    local screens = target_screen and {target_screen} or hs_screen.allScreens()
    
    -- Ensure zones are initialized for all screens
    for _, s in ipairs(screens) do
        local mid = monitor_manager.get_id(s)
        if not zone_calculator.get(mid, nil) then
            debug_log("Initializing zones for monitor", mid)
            zone_calculator.create_for_monitor(mid, s)
        end
    end
    
    for _, s in ipairs(screens) do
        occupied_rects[monitor_manager.get_id(s)] = {}
    end
    local windows_to_tile = {}
    for _, info in ipairs(window_cache.get_all_visible_info()) do
        local mid = info.screen_id and monitor_manager.get_id(hs_screen.find(info.screen_id))
        if mid and occupied_rects[mid] then
            table.insert(windows_to_tile, info.window)
        end
    end
    local z_map = {};
    for i, w in ipairs(hs_window.orderedWindows()) do
        if w:id() then
            z_map[w:id()] = i
        end
    end
    _pass_focused_anchor(windows_to_tile, occupied_rects, move_queue, processed_ids)
    local windows_by_monitor = {}
    for _, win in ipairs(windows_to_tile) do
        if not processed_ids[win:id()] then
            local mid = monitor_manager.get_id(win:screen())
            if mid and occupied_rects[mid] then
                windows_by_monitor[mid] = windows_by_monitor[mid] or {}
                table.insert(windows_by_monitor[mid], win)
            end
        end
    end
    for mid, monitor_windows in pairs(windows_by_monitor) do
        local working_set, limbo_set = _pass_working_set_cull(monitor_windows, mid, z_map)
        _pass_greedy_memory(working_set, mid, occupied_rects[mid], move_queue, processed_ids)
        _pass_solver(working_set, occupied_rects[mid], move_queue, processed_ids, mid)
        _pass_limbo_stack(limbo_set, mid, move_queue, processed_ids)
    end
    _pass_fill_gaps(move_queue, processed_ids, occupied_rects)
    _execute_moves(move_queue)
end

function auto_tiler.setup_hotkeys()
    if config.tiler and config.tiler.hotkeys then
        local hk = config.tiler.hotkeys
        local get_mods = function(s)
            return config.keys[s] or s
        end
        if hk.auto_tile_screen and hk.auto_tile_screen[2] ~= "" then
            hs.hotkey.bind(get_mods(hk.auto_tile_screen[1]), hk.auto_tile_screen[2], function()
                local fw = hs_window.focusedWindow()
                if fw and fw:screen() then
                    auto_tiler.tile_all_windows(fw:screen())
                end
            end)
        end
    end
end

function auto_tiler.init(cfg, _tiler, _wm, _sp, _zc, _mm, _wa)
    config, tiler_module, window_memory, zone_calculator, monitor_manager, window_actions = cfg, _tiler, _wm, _zc, _mm,
        _wa
    layout_solver.init(window_memory, config.tiler and config.tiler.solver_weights)
end

return auto_tiler
