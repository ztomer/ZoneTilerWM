--- Contains the core window manipulation functions.
-- This module provides the concrete implementations for actions performed on windows,
-- such as moving them to zones, applying frames, and moving them between monitors.
-- It includes special handling for applications that do not behave correctly with
-- standard Hammerspoon APIs.
-- @module window_actions
local hs_window = hs.window
local hs_screen = hs.screen
local hs_axuielement = hs.axuielement

local window_actions = {}

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("window_actions")

-- Module state
local config = nil -- Set in init
local monitor_manager = nil -- Set in init
local zone_calculator = nil -- Set in init
local window_state_manager = nil -- Set in init
local placement_strategy = nil -- Set in init
local processed_problem_apps = {} -- Set in init
local window_memory_module = nil -- Set via setter from tiler

--- Checks if an application is in the configured list of problem applications.
-- @local
-- @param app_name (string) The name of the application.
-- @return (boolean) `true` if the app is a problem app, `false` otherwise.
local function is_problem_app(app_name)
    if not processed_problem_apps or #processed_problem_apps == 0 or not app_name then
        return false
    end
    local lower_app_name = app_name:lower()
    -- Iterate over pre-processed list of lowercase app names
    for _, problem_app_lower_name in ipairs(processed_problem_apps) do
        if problem_app_lower_name == lower_app_name then
            return true
        end
    end
    return false
end

--- Prepares a window and frame for manipulation.
-- Validates the window and frame, normalizes the frame table, and moves the window
-- to the target screen if necessary.
-- @local
-- @param window (hs.window) The window object.
-- @param frame (table) The frame to apply, with `{x, y, w, h}`.
-- @param force_screen_obj (hs.screen) If provided, ensures the window is on this screen before applying the frame.
-- @param caller_func_name_for_log (string) The name of the calling function for logging.
-- @param is_problem_app_log_detail (boolean) Whether to add extra logging for problem apps.
-- @return (table|nil) A normalized frame table or `nil` on failure.
local function _prepare_window_and_frame(window, frame, force_screen_obj, caller_func_name_for_log,
    is_problem_app_log_detail)
    if not window or not window:isStandard() then
        debug_log(caller_func_name_for_log .. ": Invalid window (nil or not standard).")
        return nil
    end
    if not frame then
        debug_log(caller_func_name_for_log .. ": Invalid frame (nil).")
        return nil
    end

    local normalized_frame = {
        x = frame.x,
        y = frame.y,
        w = frame.w or frame.width,
        h = frame.h or frame.height
    }

    if not (type(normalized_frame.x) == "number" and type(normalized_frame.y) == "number" and type(normalized_frame.w) ==
        "number" and normalized_frame.w > 0 and type(normalized_frame.h) == "number" and normalized_frame.h > 0) then
        debug_log(caller_func_name_for_log .. ": Invalid frame parameters - x,y,w,h must be numbers, w,h > 0.",
            hs.inspect(normalized_frame))
        return nil
    end

    if force_screen_obj and window:screen():id() ~= force_screen_obj:id() then
        local app_for_log = window:application()
        local app_name_for_log = app_for_log and app_for_log:name() or "UnknownApp"
        local log_prefix = is_problem_app_log_detail and "problem " or ""
        debug_log("Moving " .. log_prefix .. "window '", app_name_for_log, "' to screen: '", force_screen_obj:name(),
            "' as part of " .. caller_func_name_for_log)

        if is_problem_app_log_detail then
            local app = window:application()
            local ax_app_prep = nil
            if app then
                ax_app_prep = hs_axuielement.applicationElement(app)
            end

            if ax_app_prep then
                local was_enhanced_prep = ax_app_prep.AXEnhancedUserInterface
                local original_animation_duration_prep = hs_window.animationDuration

                ax_app_prep.AXEnhancedUserInterface = false
                hs_window.animationDuration = 0
                window:moveToScreen(force_screen_obj, false, true, 0)
                hs_window.animationDuration = original_animation_duration_prep
                ax_app_prep.AXEnhancedUserInterface = was_enhanced_prep
            else
                debug_log(caller_func_name_for_log .. ": Could not get AX element for problem app '", app_name_for_log,
                    "', moving without AX tweaks.")
                window:moveToScreen(force_screen_obj, false, true, 0)
            end
        else
            window:moveToScreen(force_screen_obj, false, true, 0)
        end
    end
    return normalized_frame
end

--- Applies a frame to a standard window with animations disabled.
-- @local
-- @param window (hs.window) The window to modify.
-- @param frame (table) The frame to apply `{x, y, w, h}`.
-- @param force_screen_obj (hs.screen|nil) If provided, moves the window to this screen before setting the frame.
-- @return (boolean) `true` on success, `false` on failure.
local function apply_frame(window, frame, force_screen_obj)
    local valid_frame = _prepare_window_and_frame(window, frame, force_screen_obj, "apply_frame", false)
    if not valid_frame then
        return false
    end

    local saved_duration = hs_window.animationDuration
    hs_window.animationDuration = 0
    debug_log(string.format("apply_frame: Setting frame for '%s': x=%.0f y=%.0f w=%.0f h=%.0f",
        window:application():name() or "Unknown",
        valid_frame.x, valid_frame.y, valid_frame.w, valid_frame.h))
    local success = window:setFrame(valid_frame)
    hs_window.animationDuration = saved_duration

    if not success then
        debug_log("apply_frame: setFrame failed for window", window:application():name())
    end
    return success
end

--- Applies a frame to a "problem" application, using accessibility workarounds.
-- This temporarily disables `AXEnhancedUserInterface` to prevent unwanted side effects.
-- @local
-- @param window (hs.window) The window to modify.
-- @param frame (table) The frame to apply `{x, y, w, h}`.
-- @param app_name (string) The name of the application for logging.
-- @param force_screen_obj (hs.screen|nil) If provided, moves the window to this screen first.
-- @return (boolean) `true` on success, `false` on failure.
local function apply_frame_to_problem_app(window, frame, app_name, force_screen_obj)
    local valid_frame = _prepare_window_and_frame(window, frame, force_screen_obj, "apply_frame_to_problem_app", true)
    if not valid_frame then
        return false
    end

    debug_log("Using accessibility API for problem app:", app_name)

    local app = window:application()
    local ax_app = nil
    if app then
        ax_app = hs_axuielement.applicationElement(app)
    end

    local was_enhanced -- Keep nil if ax_app is nil
    local original_animation_duration = hs_window.animationDuration

    if ax_app then
        was_enhanced = ax_app.AXEnhancedUserInterface
        ax_app.AXEnhancedUserInterface = false
    else
        local app_name_for_log = app and app:name() or "UnknownApp"
        debug_log("apply_frame_to_problem_app: Could not get AX element for '", app_name_for_log,
            "'. Proceeding without AXEnhancedUserInterface tweak.")
    end
    hs_window.animationDuration = 0
    local success = window:setFrame(valid_frame)
    hs_window.animationDuration = original_animation_duration
    if ax_app then
        ax_app.AXEnhancedUserInterface = was_enhanced
    end

    return success
end

--- Applies a calculated tile frame to a window, dispatching to the correct frame application function.
-- @local
-- @param window (hs.window) The window to apply the tile to.
-- @param tile (table) The tile frame `{x, y, w, h}`.
-- @param screen_obj (hs.screen) The screen the tile belongs to.
-- @return (boolean) `true` on success, `false` on failure.
local function apply_tile(window, tile, screen_obj)
    if not window or not window:isStandard() or not tile then
        debug_log("apply_tile: Invalid window or tile.")
        return false
    end
    local app_name = window:application():name()
    if is_problem_app(app_name) then
        return apply_frame_to_problem_app(window, tile, app_name, screen_obj)
    else
        return apply_frame(window, tile, screen_obj)
    end
end

--- Moves a given window to a specified zone.
-- It finds the best available tile in the target zone using the `placement_strategy`
-- and then applies it to the window.
-- @param window (hs.window) The window to move.
-- @param zone_key (string) The key of the target zone.
-- @return (boolean) `true` on success, `false` on failure.
function window_actions.move_window_to_zone(window, zone_key)
    if not window or not window:isStandard() then
        debug_log("move_window_to_zone: Invalid window");
        return false
    end

    local window_id = window:id()
    local screen_obj = window:screen()
    if not screen_obj then
        debug_log("move_window_to_zone: Window has no screen.");
        return false
    end
    local monitor_id = monitor_manager.get_id(screen_obj)

    debug_log("Moving window", window_id, "(", window:application():name(), ") to zone", zone_key, "on monitor",
        monitor_id)

    local current_pos = window_state_manager.get(window_id)
    local zone_tiles = zone_calculator.get(monitor_id, zone_key)

    if not zone_tiles or #zone_tiles == 0 then
        debug_log("No tiles found for zone", zone_key, "on monitor", monitor_id, "(", screen_obj:name(), ")")
        -- Try to create zones for this monitor if they are missing (e.g., screen just connected)
        if not zone_calculator.get(monitor_id, nil) then -- Check if monitor has any zones initialized
            debug_log("Zones not initialized for monitor", monitor_id, screen_obj:name(), ". Initializing now.")
            zone_calculator.create_for_monitor(monitor_id, screen_obj)
            zone_tiles = zone_calculator.get(monitor_id, zone_key)
            if not zone_tiles or #zone_tiles == 0 then
                debug_log("Still no tiles after re-initialization for zone", zone_key)
                return false
            end
        else
            debug_log("Zone key", zone_key, "specifically not found for monitor", monitor_id)
            return false
        end
    end

    local grid_config, _ = zone_calculator.get_layout_config(screen_obj)
    local zone_windows = window_state_manager.get_windows_in_zone(monitor_id, zone_key)
    local tile_to_apply = placement_strategy.find_best_tile(window, zone_key, zone_windows, {
        grid = grid_config
    }, zone_tiles)

    if not tile_to_apply then
        debug_log("No suitable tile found by placement strategy for zone", zone_key)
        return false
    end

    -- Find the index of the chosen tile to store in window_state
    local tile_index_to_apply = 1
    for i, tile in ipairs(zone_tiles) do
        if tile == tile_to_apply then
            tile_index_to_apply = i
            break
        end
    end

    if apply_tile(window, tile_to_apply, screen_obj) then
        window_state_manager.set(window_id, monitor_id, zone_key, tile_index_to_apply)
        debug_log("Applied tile", tile_index_to_apply, "of zone", zone_key, "to window", window:application():name())
        return true
    end
    debug_log("Failed to apply tile for window", window:application():name())
    return false
end

--- Positions a window to a specific tile from a `window_memory` entry.
-- @param window (hs.window) The window to position.
-- @param monitor_id (string) The ID of the target monitor.
-- @param zone_key (string) The key of the target zone.
-- @param tile_index (number) The index of the tile within the zone.
-- @param suppress_learning (boolean|nil) If true, prevents this position from being learned.
-- @return (boolean) `true` on success, `false` on failure.
function window_actions.position_window_from_memory(window, monitor_id, zone_key, tile_index, suppress_learning)
    if not window or not window:isStandard() then
        debug_log("position_window_from_memory: Invalid window.");
        return false
    end

    local screen_obj = monitor_manager.get_screen(monitor_id)
    if not screen_obj then
        debug_log("Could not find screen for monitor ID:", monitor_id)
        return false
    end

    local zone_tiles = zone_calculator.get(monitor_id, zone_key)
    if not zone_tiles or not zone_tiles[tile_index] then
        debug_log("Could not find tile", tile_index, "in zone", zone_key, "on monitor", monitor_id)
        return false
    end

    local tile = zone_tiles[tile_index]
    if apply_tile(window, tile, screen_obj) then
        window_state_manager.set(window:id(), monitor_id, zone_key, tile_index, suppress_learning)
        debug_log("Positioned window from memory: zone", zone_key, "tile", tile_index)
        return true
    end

    return false
end

--- Moves a window to the next or previous monitor.
-- It attempts to place the window intelligently on the target monitor using a series of strategies:
-- 1. Use the window's remembered position for that app on the target monitor.
-- 2. Maintain the window's current zone and tile index if possible.
-- 3. Fall back to a default zone (e.g., "0").
-- 4. If all else fails, simply move the window to the screen without tiling.
-- @param window (hs.window) The window to move.
-- @param direction (string) "next" or "previous".
-- @return (boolean) `true` on success, `false` on failure.
function window_actions.move_window_to_monitor(window, direction)
    if not window or not window:isStandard() then
        debug_log("move_window_to_monitor: Invalid window.");
        return false
    end

    local window_id = window:id()
    local app_name = window:application():name()
    local current_screen_obj = window:screen()
    if not current_screen_obj then
        debug_log("move_window_to_monitor: Window has no screen.");
        return false
    end
    local current_monitor_id = monitor_manager.get_id(current_screen_obj)

    local all_screens = hs_screen.allScreens()
    if #all_screens < 2 then
        debug_log("move_window_to_monitor: Only one screen available.");
        return false
    end

    local current_screen_idx_in_list = -1
    for i, s in ipairs(all_screens) do
        if s:id() == current_screen_obj:id() then
            current_screen_idx_in_list = i
            break
        end
    end
    if current_screen_idx_in_list == -1 then
        debug_log("move_window_to_monitor: Could not find current screen in list.");
        return false
    end

    local target_screen_idx
    if direction == "next" then
        target_screen_idx = (current_screen_idx_in_list % #all_screens) + 1
    else -- "previous"
        target_screen_idx = (current_screen_idx_in_list - 2 + #all_screens) % #all_screens + 1
    end
    local target_screen_obj = all_screens[target_screen_idx]
    local target_monitor_id = monitor_manager.get_id(target_screen_obj)

    debug_log("Moving window", app_name, "from monitor", current_monitor_id, "to monitor", target_monitor_id, "(",
        target_screen_obj:name(), ")")

    -- Check if zones exist for target monitor, create if not
    if not zone_calculator.get(target_monitor_id, nil) then -- Check if monitor has any zones initialized
        debug_log("Initializing zones for target monitor", target_monitor_id, target_screen_obj:name())
        zone_calculator.create_for_monitor(target_monitor_id, target_screen_obj)
    end

    -- Strategy 1: Try remembered position for this app on the target monitor
    local remembered_pos = window_state_manager.get_app_memory(app_name, target_monitor_id)
    if remembered_pos then
        local zone_tiles = zone_calculator.get(target_monitor_id, remembered_pos.zone_key)
        if zone_tiles and zone_tiles[remembered_pos.tile_index] then
            if apply_tile(window, zone_tiles[remembered_pos.tile_index], target_screen_obj) then
                window_state_manager.set(window_id, target_monitor_id, remembered_pos.zone_key,
                    remembered_pos.tile_index)
                debug_log("Moved", app_name, "to remembered position on monitor", target_monitor_id)
                return true
            end
        end
    end

    -- Strategy 2: Try to maintain the current zone/tile position on the target monitor
    local current_tiler_pos = window_state_manager.get(window_id)
    if current_tiler_pos then
        local zone_tiles = zone_calculator.get(target_monitor_id, current_tiler_pos.zone_key)
        if zone_tiles then
            -- Try the same tile index, but clamp to the number of tiles available in the target zone
            local tile_idx_to_try = math.min(current_tiler_pos.tile_index, #zone_tiles)
            if zone_tiles[tile_idx_to_try] and apply_tile(window, zone_tiles[tile_idx_to_try], target_screen_obj) then
                window_state_manager.set(window_id, target_monitor_id, current_tiler_pos.zone_key, tile_idx_to_try)
                debug_log("Moved", app_name, "to equivalent zone/tile on monitor", target_monitor_id)
                return true
            end
        end
    end

    -- Strategy 3: Last resort - move to a default zone (e.g., "0" or "j") on target monitor
    local default_zone_keys = {"0", "j"} -- Common default zone keys
    for _, dz_key in ipairs(default_zone_keys) do
        local zone_tiles = zone_calculator.get(target_monitor_id, dz_key)
        if zone_tiles and zone_tiles[1] then
            if apply_tile(window, zone_tiles[1], target_screen_obj) then
                window_state_manager.set(window_id, target_monitor_id, dz_key, 1)
                debug_log("Moved", app_name, "to default zone '", dz_key, "' on monitor", target_monitor_id)
                return true
            end
        end
    end

    -- If all else fails, just move it to the screen without tiling
    debug_log("Could not find suitable tile, moving window", app_name, "to screen", target_screen_obj:name(),
        "without tiling.")
    if is_problem_app(app_name) then
        debug_log("Applying AX tweaks for problem app '", app_name, "' during final moveToScreen fallback.")
        local app = window:application()
        local ax_app = nil
        if app then
            ax_app = hs_axuielement.applicationElement(app)
        end

        local was_enhanced -- Keep nil if ax_app is nil
        local original_animation_duration = hs_window.animationDuration

        if ax_app then
            was_enhanced = ax_app.AXEnhancedUserInterface
            ax_app.AXEnhancedUserInterface = false
        else
            local app_name_for_log = app and app:name() or "UnknownApp"
            debug_log("move_window_to_monitor fallback: Could not get AX element for '", app_name_for_log,
                "'. Proceeding without AXEnhancedUserInterface tweak.")
        end
        hs_window.animationDuration = 0
        window:moveToScreen(target_screen_obj)
        hs_window.animationDuration = original_animation_duration
        if ax_app then
            ax_app.AXEnhancedUserInterface = was_enhanced
        end
    else
        window:moveToScreen(target_screen_obj)
    end
    window_state_manager.cleanup(window_id) -- Clean up tiler state if not successfully tiled
    return true
end

--- Toggles Zen Mode.
-- When entering Zen Mode, all windows except the focused one are minimized.
-- When exiting, it restores the minimized windows.
-- @param focused_win (hs.window) The window to focus for Zen Mode.
function window_actions.toggle_zen_mode(focused_win)
    if not focused_win then
        debug_log("Zen: No focused window, aborting.")
        return
    end

    local original_animation_duration = hs.window.animationDuration
    hs.window.animationDuration = 0

    if window_state_manager.is_zen_mode_active() then
        -- EXITING ZEN MODE
        debug_log("Zen: Deactivating...")
        local windows_to_unminimize, zen_window = window_state_manager.deactivate_zen_mode()

        for _, win in ipairs(windows_to_unminimize) do
            pcall(function()
                win:unminimize()
            end)
        end

        -- After a delay to let windows restore, focus the original zen window.
        hs.timer.doAfter(0.05, function()
            if zen_window then
                zen_window:focus()
            end
        end)
        debug_log("Zen: Deactivated, unminimized " .. #windows_to_unminimize .. " windows.")

    else
        -- ENTERING ZEN MODE
        debug_log("Zen: Activating for window: " .. focused_win:title())
        local visible_windows = hs.window.visibleWindows()
        local windows_to_minimize = {}

        for _, win in ipairs(visible_windows) do
            if win:id() ~= focused_win:id() then
                table.insert(windows_to_minimize, win)
            end
        end

        for _, win in ipairs(windows_to_minimize) do
            pcall(function()
                win:minimize()
            end)
        end

        window_state_manager.activate_zen_mode(windows_to_minimize, focused_win)
        debug_log("Zen: Activated, minimized " .. #windows_to_minimize .. " windows.")
    end

    hs.window.animationDuration = original_animation_duration
end

--- Initializes the `window_actions` module.
-- @param cfg (table) The main configuration table.
-- @param mm (table) The `monitor_manager` module.
-- @param zc (table) The `zone_calculator` module.
-- @param wsm (table) The `window_state_manager` module.
-- @param ps (table) The `placement_strategy` module.
-- @param problem_apps_list (table) A list of lowercase application names that require special handling.
-- @param log_func (function) The logging function to use.
function window_actions.init(cfg, mm, zc, wsm, ps, problem_apps_list, log_func)
    config = cfg
    monitor_manager = mm
    zone_calculator = zc
    window_state_manager = wsm
    placement_strategy = ps
    processed_problem_apps = problem_apps_list
    debug_log = log_func or debug_log
    debug_log("WindowActions initialized")
end

--- Injects the `window_memory` module as a dependency.
-- @param wm (table) The initialized `window_memory` module.
function window_actions.set_window_memory_module(wm)
    window_memory_module = wm
    debug_log("WindowMemory module reference set in WindowActions")
end

return window_actions
