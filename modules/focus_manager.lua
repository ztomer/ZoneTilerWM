--- Manages focus cycling for windows within zones.
-- This module is responsible for determining which windows belong to a zone,
-- maintaining an ordered list for focus cycling, and handling the logic for
-- moving focus from one window to the next within that cycle.
-- @module focus_manager
local hs_window = hs.window
local hs_timer = hs.timer
local hs_canvas = hs.canvas
local hs_geometry = hs.geometry

local focus_manager = {}

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("focus_manager")

-- Module state
local config = nil -- Set in init
local monitor_manager = nil -- Set in init
local zone_calculator = nil -- Set in init
local window_state_manager = nil -- Set in init

-- Manages the state of the current focus cycle.
local current_focus_cycle_manager = {
    zone_key = nil, -- The zone key for the active cycle (e.g., "h")
    monitor_id_logical = nil, -- The logical monitor ID for the cycle
    window_ids_in_order = {}, -- An ordered array of window IDs for the current cycle
    current_idx_in_cycle_list = 0 -- 0 means "uninitialized" or "before the first window"
    -- Otherwise, it's the 1-based index of the last window focused in this cycle
}

-- Singleton to manage the flash capability
local current_flash = nil
local current_flash_timer = nil



--- Gets the Z-order (stacking order) of a window.
-- @local
-- @param window (hs.window) The window to check.
-- @return (number) The stacking order index. Lower is higher on screen.
local function get_window_z_order(window)
    local ordered_windows = hs_window.orderedWindows()
    for i, w in ipairs(ordered_windows) do
        if w:id() == window:id() then
            return i -- Lower number means more on top
        end
    end
    return 999999 -- Should not happen for a valid window
end

--- Calculates the percentage of rect1 that is covered by rect2.
-- @local
-- @param rect1 (table) The first rectangle `{x, y, w, h}`.
-- @param rect2 (table) The second rectangle `{x, y, w, h}`.
-- @return (number) The percentage of overlap (0.0 to 1.0).
local function calculate_overlap_percentage(rect1, rect2)
    if not rect1 or not rect2 or rect1.w <= 0 or rect1.h <= 0 then
        return 0
    end
    local x_overlap = math.max(0, math.min(rect1.x + rect1.w, rect2.x + rect2.w) - math.max(rect1.x, rect2.x))
    local y_overlap = math.max(0, math.min(rect1.y + rect1.h, rect2.y + rect2.h) - math.max(rect1.y, rect2.y))
    local overlap_area = x_overlap * y_overlap
    return overlap_area / (rect1.w * rect1.h)
end

--- Collects all windows that belong to a specific zone.
-- A window belongs to a zone if it is explicitly assigned to it via `window_state_manager`
-- or if it significantly overlaps with one of the zone's tiles.
-- @local
-- @param monitor_id (string) The ID of the monitor.
-- @param zone_key (string) The key of the zone.
-- @param screen_obj (hs.screen) The screen object.
-- @param zone_tiles_for_this_zone (table) A list of tile frames for the zone.
-- @return (table) A list of window information tables.
local function collect_zone_windows(monitor_id, zone_key, screen_obj, zone_tiles_for_this_zone)
    local zone_windows_collected = {}
    local overlap_threshold = config.tiler.overlap_threshold or 0.5

    if not screen_obj then
        debug_log("collect_zone_windows: screen_obj is nil for monitor_id", monitor_id, "zone_key", zone_key)
        return zone_windows_collected
    end
    if not zone_tiles_for_this_zone or #zone_tiles_for_this_zone == 0 then
        debug_log("collect_zone_windows: No tiles provided for zone", zone_key, "on monitor", monitor_id)
        return zone_windows_collected
    end

    local windows_on_screen = {}
    for _, win in ipairs(hs_window.allWindows()) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == screen_obj:id() then
            table.insert(windows_on_screen, win)
        end
    end

    local added_window_ids = {} -- To track IDs already added to zone_windows_collected

    -- Phase 1: Add explicitly assigned windows
    for _, win in ipairs(windows_on_screen) do
        local win_id = win:id()
        local pos = window_state_manager.get(win_id)
        if pos and pos.monitor_id == monitor_id and pos.zone_key == zone_key then
            table.insert(zone_windows_collected, {
                window = win,
                window_id = win_id,
                app_name = win:application():name(),
                tile_index = pos.tile_index,
                explicit = true,
                z_order = get_window_z_order(win)
            })
            added_window_ids[win_id] = true
        end
    end

    -- Phase 2: Add windows by overlap (if not already added explicitly)
    for _, win in ipairs(windows_on_screen) do
        local win_id = win:id()
        if not added_window_ids[win_id] then
            for tile_idx, tile_frame in ipairs(zone_tiles_for_this_zone) do
                local overlap = calculate_overlap_percentage(win:frame(), tile_frame)
                if overlap >= overlap_threshold then
                    table.insert(zone_windows_collected, {
                        window = win,
                        window_id = win_id,
                        app_name = win:application():name(),
                        tile_index = tile_idx,
                        explicit = false,
                        z_order = get_window_z_order(win),
                        overlap_debug = overlap
                    })
                    added_window_ids[win_id] = true -- Mark as added
                    break -- Associate with the first overlapping tile found
                end
            end
        end
    end
    return zone_windows_collected
end

--- Sorts a list of zone windows to create an intuitive cycling order.
-- The sorting priority is: tile index, then explicit assignment, then Z-order.
-- @local
-- @param zone_windows_list (table) The list of window info tables to sort.
local function sort_zone_windows_for_intuitive_order(zone_windows_list)
    table.sort(zone_windows_list, function(a, b)
        if a.tile_index ~= b.tile_index then
            return a.tile_index < b.tile_index
        end
        if a.explicit ~= b.explicit then
            return a.explicit
        end
        return a.z_order < b.z_order
    end)
end

--- Cycles focus to the next window in a given zone.
-- This is the main entry point for the focus manager. It builds or rebuilds the
-- focus cycle list as needed, then focuses the next window in the list.
-- @param focused_window_before_call (hs.window) The window that was focused when the function was called.
-- @param target_zone_key (string) The key of the zone to cycle through.
-- @return (boolean) `true` if focus was successfully changed, `false` otherwise.
function focus_manager.cycle_windows_in_zone(focused_window_before_call, target_zone_key)
    if not focused_window_before_call or not focused_window_before_call:isStandard() or
        focused_window_before_call:isMinimized() then
        debug_log("cycle_windows_in_zone: No valid focused window to start.")
        return false
    end

    local focused_window_id_before_call = focused_window_before_call:id()
    local current_screen_obj = focused_window_before_call:screen()
    if not current_screen_obj then
        debug_log("cycle_windows_in_zone: Focused window has no screen.")
        return false
    end
    local current_monitor_id = monitor_manager.get_id(current_screen_obj)

    debug_log(string.format("=== Focus zone '%s' on %s (%s) ===", target_zone_key, current_screen_obj:name(),
        current_monitor_id))
    debug_log(string.format("Window focused before call: %s (ID: %s)", focused_window_before_call:application():name(),
        focused_window_id_before_call))

    local cfcm = current_focus_cycle_manager -- shorthand

    -- Determine if the cycle needs to be rebuilt
    local needs_rebuild = false
    if target_zone_key ~= cfcm.zone_key or current_monitor_id ~= cfcm.monitor_id_logical or #cfcm.window_ids_in_order ==
        0 then
        needs_rebuild = true
        debug_log(string.format(
            "Rebuilding cycle: Zone/Monitor changed or cycle empty. Target Zone: %s, Current Cycle Zone: %s. Target Monitor: %s, Current Cycle Monitor: %s. Stored cycle items: %d",
            target_zone_key, cfcm.zone_key or "nil", current_monitor_id, cfcm.monitor_id_logical or "nil",
            #cfcm.window_ids_in_order))
    else
        -- Cycle seems to be for the same zone/monitor. Check if content is still valid.
        local zone_tiles_for_check = zone_calculator.get(current_monitor_id, target_zone_key)
        if not zone_tiles_for_check or #zone_tiles_for_check == 0 then
            debug_log("No tiles for zone " .. target_zone_key .. " during validation. Forcing rebuild.")
            needs_rebuild = true
        else
            local actual_windows_in_zone_now = collect_zone_windows(current_monitor_id, target_zone_key,
                current_screen_obj, zone_tiles_for_check)

            if #actual_windows_in_zone_now ~= #cfcm.window_ids_in_order then
                needs_rebuild = true
                debug_log(string.format("Rebuilding cycle: Number of windows in zone changed. Stored: %d, Actual: %d.",
                    #cfcm.window_ids_in_order, #actual_windows_in_zone_now))
            else
                -- Check if the window IDs match exactly
                local actual_ids_set = {}
                for _, zw in ipairs(actual_windows_in_zone_now) do
                    actual_ids_set[zw.window_id] = true
                end
                local ids_match = true
                for _, id_in_stored_list in ipairs(cfcm.window_ids_in_order) do
                    if not actual_ids_set[id_in_stored_list] then
                        ids_match = false
                        debug_log("Rebuilding cycle: A window from the stored cycle (ID: " .. id_in_stored_list ..
                                      ") is no longer in the zone.")
                        break
                    end
                end
                if not ids_match then
                    needs_rebuild = true
                end
            end

            if not needs_rebuild then
                -- If set of windows is the same, check if user manually focused a different window WITHIN the zone
                local focused_is_in_zone_currently = false
                for _, id_in_list in ipairs(cfcm.window_ids_in_order) do
                    if id_in_list == focused_window_id_before_call then
                        focused_is_in_zone_currently = true;
                        break
                    end
                end

                if not focused_is_in_zone_currently then
                    needs_rebuild = true
                    debug_log("Rebuilding cycle: Window focused before call (ID: " .. focused_window_id_before_call ..
                                  ") is not in the current cycle list. Forcing rebuild.")
                end
            end
        end
    end

    if needs_rebuild then
        debug_log(
            "Rebuilding focus cycle list for zone '" .. target_zone_key .. "' on monitor " .. current_monitor_id ..
                "...")
        cfcm.zone_key = target_zone_key
        cfcm.monitor_id_logical = current_monitor_id
        cfcm.window_ids_in_order = {}
        cfcm.current_idx_in_cycle_list = 0 -- Reset index

        local zone_tiles = zone_calculator.get(current_monitor_id, target_zone_key)
        if not zone_tiles or #zone_tiles == 0 then
            debug_log("No tiles found for zone '" .. target_zone_key .. "' on monitor " .. current_monitor_id ..
                          ". Cycle cleared.")
            return false
        end

        local collected_windows = collect_zone_windows(current_monitor_id, target_zone_key, current_screen_obj,
            zone_tiles)
        if #collected_windows == 0 then
            debug_log("No windows found in zone '" .. target_zone_key .. "'. Cycle cleared.")
            return false
        end

        sort_zone_windows_for_intuitive_order(collected_windows)

        debug_log("Sorted windows for new cycle order:")
        for i, zw in ipairs(collected_windows) do
            table.insert(cfcm.window_ids_in_order, zw.window_id)
            debug_log(string.format("  %d: %s (ID: %s, tile %d, z:%d, %s)", i, zw.app_name, zw.window_id, zw.tile_index,
                zw.z_order, zw.explicit and "explicit" or "overlap " .. (zw.overlap_debug or "")))
        end

        -- Determine starting index for the new/rebuilt cycle
        local initial_focus_target_idx_in_new_list = 0
        for i, id_in_list in ipairs(cfcm.window_ids_in_order) do
            if id_in_list == focused_window_id_before_call then
                initial_focus_target_idx_in_new_list = i
                debug_log(string.format("Window focused before call (ID: %s) found at index %d in new cycle list.",
                    focused_window_id_before_call, i))
                break
            end
        end
        cfcm.current_idx_in_cycle_list = initial_focus_target_idx_in_new_list
        if initial_focus_target_idx_in_new_list == 0 then
            debug_log(
                "Window focused before call not in new cycle list. Cycle will start from the beginning of the new list.")
        end
    end

    if #cfcm.window_ids_in_order == 0 then
        debug_log("No windows available for cycling in zone '" .. target_zone_key .. "'.")
        return false
    end

    -- Advance the cycle index
    local num_windows_in_cycle = #cfcm.window_ids_in_order
    cfcm.current_idx_in_cycle_list = (cfcm.current_idx_in_cycle_list % num_windows_in_cycle) + 1

    local window_id_to_focus = cfcm.window_ids_in_order[cfcm.current_idx_in_cycle_list]
    local window_to_focus = hs_window.get(window_id_to_focus)

    if window_to_focus and window_to_focus:isStandard() and not window_to_focus:isMinimized() then
        debug_log(string.format("Cycling to window %d of %d: %s (ID: %s)", cfcm.current_idx_in_cycle_list,
            num_windows_in_cycle, window_to_focus:application():name(), window_id_to_focus))
        window_to_focus:focus()

        if config.tiler.flash_on_focus then
            -- Cleanup any existing flash
            if current_flash then
                current_flash:delete()
                current_flash = nil
            end
            if current_flash_timer then
                current_flash_timer:stop()
                current_flash_timer = nil
            end

            local frame = window_to_focus:frame()
            current_flash = hs_canvas.new(frame):appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {
                    red = 0.5,
                    green = 0.5,
                    blue = 1.0,
                    alpha = 0.3
                },
                frame = { x = 0, y = 0, w = frame.w, h = frame.h }
            })
            current_flash:show()

            local delay = tonumber(config.tiler.delays.flash_on_focus_duration_sec) or 0.2

            -- We keep a reference to the timer to prevent GC and allow cancellation
            current_flash_timer = hs_timer.doAfter(delay, function()
                if current_flash then
                    current_flash:delete()
                    current_flash = nil
                end
                current_flash_timer = nil -- Clear timer reference
            end)
        end
        return true
    else
        debug_log(string.format(
            "Window ID %s (at new cycle index %d) to focus was not found, invalid, or not standard. Cycle may be stale.",
            window_id_to_focus, cfcm.current_idx_in_cycle_list))
        -- Invalidate cycle if the target window is gone
        focus_manager.reset_cycle()
        return false
    end
end

--- Handles the `windowDestroyed` event to invalidate the focus cycle if needed.
-- @param window_id (number) The ID of the window that was destroyed.
function focus_manager.handle_window_destroyed(window_id)
    if current_focus_cycle_manager.zone_key then
        local was_in_cycle = false
        for i = #current_focus_cycle_manager.window_ids_in_order, 1, -1 do
            if current_focus_cycle_manager.window_ids_in_order[i] == window_id then
                was_in_cycle = true
                break
            end
        end
        if was_in_cycle then
            debug_log("Destroyed window (ID: " .. window_id .. ") was part of the current focus cycle for zone '" ..
                          current_focus_cycle_manager.zone_key .. "'. Invalidating cycle.")
            focus_manager.reset_cycle()
        end
    end
end

--- Resets the internal state of the focus cycle.
-- This is called when the cycle becomes invalid, such as when a screen changes or a window is destroyed.
function focus_manager.reset_cycle()
    current_focus_cycle_manager.zone_key = nil
    current_focus_cycle_manager.monitor_id_logical = nil
    current_focus_cycle_manager.window_ids_in_order = {}
    current_focus_cycle_manager.current_idx_in_cycle_list = 0
    debug_log("Focus cycle state reset.")
end

--- Prints debugging information about the windows within a zone.
-- @param monitor_id (string) The ID of the monitor.
-- @param zone_key (string) The key of the zone to debug.
-- @param screen_obj (hs.screen) The screen object.
function focus_manager.debug_zone_windows(monitor_id, zone_key, screen_obj)
    local zone_tiles = zone_calculator.get(monitor_id, zone_key)
    if not zone_tiles then
        print("Cannot debug windows for zone '" .. zone_key .. "': Zone tiles not found.")
        return
    end

    local zone_windows = collect_zone_windows(monitor_id, zone_key, screen_obj, zone_tiles)
    sort_zone_windows_for_intuitive_order(zone_windows)

    print("\nWindows in zone '" .. zone_key .. "' (sorted for potential cycle): " .. #zone_windows)
    for i, zw in ipairs(zone_windows) do
        print(string.format("  %d: %s (ID: %s) - Tile %d, Explicit: %s, Z-Order: %d, Overlap: %.1f%%", i, zw.app_name,
            zw.window_id, zw.tile_index, tostring(zw.explicit), zw.z_order, (zw.overlap_debug or 0) * 100))
    end
end

--- Prints the current internal state of the focus cycle manager to the console.
function focus_manager.debug_cycle_state()
    print("\nCurrent Focus Cycle Manager State:")
    print(hs.inspect(current_focus_cycle_manager))
end

--- Initializes the `focus_manager` module.
-- @param cfg (table) The main configuration table.
-- @param mm (table) The `monitor_manager` module.
-- @param zc (table) The `zone_calculator` module.
-- @param wsm (table) The `window_state_manager` module.
-- @param log_func (function) The logging function to use.
function focus_manager.init(cfg, mm, zc, wsm, log_func)
    config = cfg
    monitor_manager = mm
    zone_calculator = zc
    window_state_manager = wsm
    debug_log = log_func or debug_log
    debug_log("FocusManager initialized")
end

return focus_manager
