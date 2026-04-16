--- Manages focus cycling for windows within zones.
-- @module focus_manager
local hs_window = hs.window
local hs_timer = hs.timer
local hs_canvas = hs.canvas

local focus_manager = {}

local window_cache = require "modules.window_cache"

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("focus_manager")

-- Module state
local config = nil
local monitor_manager = nil
local zone_calculator = nil
local window_state_manager = nil

local current_focus_cycle_manager = {
    zone_key = nil,
    monitor_id_logical = nil,
    window_ids_in_order = {},
    current_idx_in_cycle_list = 0
}

local current_flash = nil
local current_flash_timer = nil

--- Calculates the percentage of rect1 that is covered by rect2.
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
local function collect_zone_windows(monitor_id, zone_key, screen_obj, zone_tiles_for_this_zone, cached_z_map)
    local zone_windows_collected = {}
    local overlap_threshold = config.tiler.overlap_threshold or 0.5

    if not screen_obj or not zone_tiles_for_this_zone or #zone_tiles_for_this_zone == 0 then
        return zone_windows_collected
    end

    local windows_on_screen = window_cache.get_for_screen_with_cache(screen_obj:id())
    local added_window_ids = {}

    -- Only generate Z-order map if the caller didn't provide one (prevents double-dipping on validation)
    local z_order_map = cached_z_map
    if not z_order_map then
        z_order_map = {}
        for i, w in ipairs(hs_window.orderedWindows()) do
            z_order_map[w:id()] = i
        end
    end

    -- Phase 1: Add explicitly assigned windows
    for _, info in ipairs(windows_on_screen) do
        local win_id = info.window:id()
        local pos = window_state_manager.get(win_id)
        if pos and pos.monitor_id == monitor_id and pos.zone_key == zone_key then
            table.insert(zone_windows_collected, {
                window = info.window,
                window_id = win_id,
                app_name = info.app_name,
                tile_index = pos.tile_index,
                explicit = true,
                z_order = z_order_map[win_id] or 999999
            })
            added_window_ids[win_id] = true
        end
    end

    -- Phase 2: Add windows by overlap
    for _, info in ipairs(windows_on_screen) do
        local win = info.window
        local win_id = win:id()
        if not added_window_ids[win_id] then
            local win_frame = win:frame()
            for tile_idx, tile_frame in ipairs(zone_tiles_for_this_zone) do
                local overlap = calculate_overlap_percentage(win_frame, tile_frame)
                if overlap >= overlap_threshold then
                    table.insert(zone_windows_collected, {
                        window = win,
                        window_id = win_id,
                        app_name = info.app_name,
                        tile_index = tile_idx,
                        explicit = false,
                        z_order = z_order_map[win_id] or 999999,
                        overlap_debug = overlap
                    })
                    added_window_ids[win_id] = true
                    break
                end
            end
        end
    end
    return zone_windows_collected
end

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

function focus_manager.cycle_windows_in_zone(focused_window_before_call, target_zone_key)
    if not focused_window_before_call then
        return false
    end

    local focused_window_id_before_call = focused_window_before_call:id()

    -- STRICT CACHE USAGE: Do not call isStandard/isMinimized on the raw object.
    local fw_info = window_cache.get_info(focused_window_id_before_call)
    if not fw_info or not fw_info.isStandard or fw_info.isMinimized then
        debug_log("cycle_windows_in_zone: No valid focused window to start.")
        return false
    end

    local current_screen_obj = focused_window_before_call:screen()
    if not current_screen_obj then
        return false
    end

    local current_monitor_id = monitor_manager.get_id(current_screen_obj)

    -- Pull cached name, preventing AX leak in logging
    debug_log(string.format("=== Focus zone '%s' on %s ===", target_zone_key, current_monitor_id))
    debug_log(string.format("Window focused before call: %s (ID: %s)", fw_info.app_name or "?",
        focused_window_id_before_call))

    local needs_rebuild = false
    if target_zone_key ~= current_focus_cycle_manager.zone_key or current_monitor_id ~=
        current_focus_cycle_manager.monitor_id_logical or #current_focus_cycle_manager.window_ids_in_order == 0 then
        needs_rebuild = true
    else
        local zone_tiles_for_check = zone_calculator.get(current_monitor_id, target_zone_key)
        if not zone_tiles_for_check or #zone_tiles_for_check == 0 then
            needs_rebuild = true
        else
            -- We reuse the Z-map here to ensure we only call orderedWindows() once per cycle evaluation
            local actual_windows_in_zone_now = collect_zone_windows(current_monitor_id, target_zone_key,
                current_screen_obj, zone_tiles_for_check)

            if #actual_windows_in_zone_now ~= #current_focus_cycle_manager.window_ids_in_order then
                needs_rebuild = true
            else
                local actual_ids_set = {}
                for _, zw in ipairs(actual_windows_in_zone_now) do
                    actual_ids_set[zw.window_id] = true
                end

                for _, id_in_stored_list in ipairs(current_focus_cycle_manager.window_ids_in_order) do
                    if not actual_ids_set[id_in_stored_list] then
                        needs_rebuild = true
                        break
                    end
                end
            end

            if not needs_rebuild then
                local focused_is_in_zone_currently = false
                for _, id_in_list in ipairs(current_focus_cycle_manager.window_ids_in_order) do
                    if id_in_list == focused_window_id_before_call then
                        focused_is_in_zone_currently = true
                        break
                    end
                end
                if not focused_is_in_zone_currently then
                    needs_rebuild = true
                end
            end
        end
    end

    if needs_rebuild then
        current_focus_cycle_manager.zone_key = target_zone_key
        current_focus_cycle_manager.monitor_id_logical = current_monitor_id
        current_focus_cycle_manager.window_ids_in_order = {}
        current_focus_cycle_manager.current_idx_in_cycle_list = 0

        local zone_tiles = zone_calculator.get(current_monitor_id, target_zone_key)
        if not zone_tiles or #zone_tiles == 0 then
            return false
        end

        local collected_windows = collect_zone_windows(current_monitor_id, target_zone_key, current_screen_obj,
            zone_tiles)
        if #collected_windows == 0 then
            return false
        end

        sort_zone_windows_for_intuitive_order(collected_windows)

        for _, zw in ipairs(collected_windows) do
            table.insert(current_focus_cycle_manager.window_ids_in_order, zw.window_id)
        end

        local initial_focus_target_idx_in_new_list = 0
        for i, id_in_list in ipairs(current_focus_cycle_manager.window_ids_in_order) do
            if id_in_list == focused_window_id_before_call then
                initial_focus_target_idx_in_new_list = i
                break
            end
        end
        current_focus_cycle_manager.current_idx_in_cycle_list = initial_focus_target_idx_in_new_list
    end

    if #current_focus_cycle_manager.window_ids_in_order == 0 then
        return false
    end

    local num_windows_in_cycle = #current_focus_cycle_manager.window_ids_in_order
    current_focus_cycle_manager.current_idx_in_cycle_list = (current_focus_cycle_manager.current_idx_in_cycle_list %
                                                                num_windows_in_cycle) + 1

    local window_id_to_focus =
        current_focus_cycle_manager.window_ids_in_order[current_focus_cycle_manager.current_idx_in_cycle_list]

    -- STRICT CACHE USAGE: Fetch the target window info from the cache to avoid AX calls on focus
    local target_info = window_cache.get_info(window_id_to_focus)

    if target_info and target_info.isStandard and not target_info.isMinimized and target_info.window then
        debug_log(string.format("Cycling to window %d of %d: %s (ID: %s)",
            current_focus_cycle_manager.current_idx_in_cycle_list, num_windows_in_cycle, target_info.app_name or "?",
            window_id_to_focus))
        target_info.window:focus()

        if config.tiler.flash_on_focus then
            if current_flash then
                current_flash:delete();
                current_flash = nil
            end
            if current_flash_timer then
                current_flash_timer:stop();
                current_flash_timer = nil
            end

            local frame = target_info.window:frame()
            current_flash = hs_canvas.new(frame):appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {
                    red = 0.5,
                    green = 0.5,
                    blue = 1.0,
                    alpha = 0.3
                },
                frame = {
                    x = 0,
                    y = 0,
                    w = frame.w,
                    h = frame.h
                }
            })
            current_flash:show()

            local delay = tonumber(config.tiler.delays.flash_on_focus_duration_sec) or 0.2
            current_flash_timer = hs_timer.doAfter(delay, function()
                if current_flash then
                    current_flash:delete();
                    current_flash = nil
                end
                current_flash_timer = nil
            end)
        end
        return true
    else
        focus_manager.reset_cycle()
        return false
    end
end

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
            focus_manager.reset_cycle()
        end
    end
end

function focus_manager.reset_cycle()
    current_focus_cycle_manager.zone_key = nil
    current_focus_cycle_manager.monitor_id_logical = nil
    current_focus_cycle_manager.window_ids_in_order = {}
    current_focus_cycle_manager.current_idx_in_cycle_list = 0
end

function focus_manager.debug_zone_windows(monitor_id, zone_key, screen_obj)
    local zone_tiles = zone_calculator.get(monitor_id, zone_key)
    if not zone_tiles then
        return
    end
    local zone_windows = collect_zone_windows(monitor_id, zone_key, screen_obj, zone_tiles)
    sort_zone_windows_for_intuitive_order(zone_windows)
end

function focus_manager.debug_cycle_state()
    print(hs.inspect(current_focus_cycle_manager))
end

function focus_manager.init(cfg, mm, zc, wsm, log_func)
    config = cfg
    monitor_manager = mm
    zone_calculator = zc
    window_state_manager = wsm
    debug_log = log_func or debug_log
end

return focus_manager
