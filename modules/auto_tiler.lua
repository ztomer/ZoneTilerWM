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
local monitor_manager = nil
local window_actions = nil
local layout_solver = require "modules.layout_solver"

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

--- PASS 1: Global Solver
local function _pass_solver(windows_to_tile, occupied_rects_by_monitor, move_queue, processed_ids)
    -- Group windows by monitor to solve each monitor independently
    local windows_by_monitor = {}
    for _, win in ipairs(windows_to_tile) do
        if not processed_ids[win:id()] then
            local screen = win:screen()
            if screen then
                local mid = monitor_manager.get_id(screen)
                if not windows_by_monitor[mid] then windows_by_monitor[mid] = {} end
                table.insert(windows_by_monitor[mid], win)
            end
        end
    end

    for mid, windows in pairs(windows_by_monitor) do
        -- 1. Identify Empty Tiles
        -- Get layout key from one of the windows' screen (they are all on 'mid')
        local screen = windows[1]:screen()
        local _, layout_key = zone_calculator.get_layout_config(screen)
        local layout_defs = config.tiler.layouts[layout_key]

        if layout_defs then
            local available_tiles = {}
            for zone_key, _ in pairs(layout_defs) do
                local tiles = zone_calculator.get(mid, zone_key)
                if tiles then
                    for i, tile in ipairs(tiles) do
                        -- Check if this tile is occupied by an Anchor or Obstacle
                        local blocked = false
                        for _, entry in ipairs(occupied_rects_by_monitor[mid]) do
                             if check_overlap(tile, entry) then
                                 blocked = true
                                 break
                             end
                        end
                        if not blocked then
                            table.insert(available_tiles, {
                                rect = tile,
                                zone_key = zone_key,
                                tile_index = i,
                                monitor_id = mid
                            })
                        end
                    end
                end
            end

            -- 2. Solve
            if #available_tiles > 0 then
                local moves = layout_solver.solve(windows, available_tiles, mid)
                for _, move in ipairs(moves) do
                    table.insert(move_queue, {
                         window = move.window,
                         monitor_id = mid,
                         zone_key = move.tile.zone_key,
                         tile_index = move.tile.tile_index,
                         source = "solver_cost_"..string.format("%.1f", move.cost),
                         is_bumpable = true
                    })
                    table.insert(occupied_rects_by_monitor[mid], {
                        frame = move.tile.rect,
                        window_id = move.window:id(),
                        is_bumpable = true,
                        source = "Solved: " .. (move.window:application():name())
                    })
                    processed_ids[move.window:id()] = true
                end
            end
        end
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

    -- PASS 1: Solver (Covers Memory, Shape, and Cleanup)
    _pass_solver(windows_to_tile, occupied_rects_by_monitor, move_queue, processed_ids)

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
    layout_solver.init(window_memory)
    if tiler_module and tiler_module.set_reposition_callback then
        tiler_module.set_reposition_callback(auto_tiler.tile_all_windows)
    end
    debug_log("AutoTiler initialized")
end

return auto_tiler
