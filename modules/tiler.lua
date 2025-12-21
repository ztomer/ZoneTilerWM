--- The core tiling engine for ZoneTilerWM.
-- This module acts as the central coordinator, integrating various sub-modules
-- to manage window placement, focus, and state. It initializes all components,
-- binds hotkeys, and handles system-level events like window creation,
-- destruction, and screen changes.
-- @module tiler
local config = require "modules.config"
local tiler = {}
local hs_window = hs.window -- Cache for frequent use
local hs_screen = hs.screen
local hs_hotkey = hs.hotkey
local hs_timer = hs.timer
local hs_alert = hs.alert

-- Window memory integration
local window_memory = nil

-- Require new sub-modules
local monitor_manager = require "modules.monitor_manager"
local zone_calculator = require "modules.zone_calculator"
local window_state_manager = require "modules.window_state_manager"
local smart_placer = require "modules.smart_placer"
local focus_manager = require "modules.focus_manager"
local window_actions = require "modules.window_actions"
local placement_strategy = require "modules.placement_strategy"
local resize_manager = require "modules.resize_manager"
local grid_overlay = require "modules.grid_overlay"

-- Debug logging (centralized)
local debug = require "debug.init"
local debug_log = debug.create_debug_log("tiler")

-- Expose monitors for window_memory
tiler.monitors = monitor_manager -- Keep this for window_memory if it directly accesses tiler.monitors
-- Expose window_state for window_memory
tiler.window_state = window_state_manager -- Keep this for window_memory
tiler.window_actions = window_actions
tiler.smart_placer = smart_placer
tiler.zone_calculator = zone_calculator


-- Resize Mode State
local resize_mode_active = false
local resize_mode_alert_uuid = nil

-- Callback for smart tiling (AutoTiler)
local reposition_callback = nil

--- Registers a callback to be used for repositioning all windows.
function tiler.set_reposition_callback(fn)
    reposition_callback = fn
end

------------------------------------------
-- Window Utility Functions
------------------------------------------

--- Moves the currently focused window to a specified zone.
-- This is a primary user-facing function, typically bound to a hotkey.
-- @param zone_key (string) The key identifying the target zone (e.g., "1", "top_left").
-- @return (boolean) `true` if successful, `false` otherwise.
function tiler.move_window_to_zone(zone_key)
    local window = hs_window.focusedWindow()
    if not window then
        debug_log("No focused window for move_window_to_zone");
        return false
    end
    return window_actions.move_window_to_zone(window, zone_key)
end

--- Positions a window based on data from the `window_memory` module.
-- This is called during window creation or repositioning events to restore a window
-- to its last known tiled position.
-- @param window (hs.window) The window object to position.
-- @param monitor_id (string) The stable ID of the target monitor.
-- @param zone_key (string) The key of the zone to place the window in.
-- @param tile_index (number) The index of the tile within the zone.
-- @return (boolean) `true` if the window was successfully positioned, `false` otherwise.
function tiler.position_window_from_memory(window, monitor_id, zone_key, tile_index)
    return window_actions.position_window_from_memory(window, monitor_id, zone_key, tile_index)
end

--- Moves the focused window to the next or previous monitor.
-- @param direction (string) Either "next" or "previous".
-- @return (boolean) `true` if successful, `false` otherwise.
function tiler.move_window_to_monitor(direction)
    local window = hs_window.focusedWindow()
    if not window then
        return false
    end
    return window_actions.move_window_to_monitor(window, direction)
end

--- Cycles focus through windows within a specific zone.
-- If a `target_zone_key` is provided, it cycles focus among windows in that zone.
-- Otherwise, it cycles through windows in the zone of the currently focused window.
-- @param target_zone_key (string|nil) The key of the zone to focus, or `nil` to use the current window's zone.
-- @return (boolean) `true` if focus was changed, `false` otherwise.
function tiler.focus_zone_windows(target_zone_key)
    local focused_window_before_call = hs_window.focusedWindow()
    if not focused_window_before_call then
        debug_log("focus_zone_windows: No focused window to start.")
        return false
    end
    return focus_manager.cycle_windows_in_zone(focused_window_before_call, target_zone_key)
end

--- Toggles "Zen Mode" for the focused window, maximizing it on its current screen.
function tiler.toggle_zen_mode()
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        debug_log("No focused window for toggle_zen_mode")
        return
    end
    window_actions.toggle_zen_mode(focused_window)
end

--- Prints debugging information for a specific zone on the current monitor.
-- This includes tile calculations and the list of windows currently in that zone.
-- @param zone_key (string) The key of the zone to debug.
function tiler.debug_zone(zone_key)
    local fe = hs_window.focusedWindow()
    if not fe then
        print("No focused window to determine screen");
        return
    end
    local screen = fe:screen()
    if not screen then
        print("Focused window has no screen");
        return
    end

    local monitor_id = monitor_manager.get_id(screen)
    print("=== Debugging zone '" .. zone_key .. "' on " .. screen:name() .. " (Monitor Logical ID: " .. monitor_id ..
              ") ===")

    zone_calculator.debug_zone_tiles(monitor_id, zone_key)
    focus_manager.debug_zone_windows(monitor_id, zone_key, screen)
    focus_manager.debug_cycle_state()
end

--- Attempts to reposition a window that already exists.
-- This is primarily used after a screen change event to place windows that may have
-- been moved by the OS. It tries to place the window using, in order:
-- 1. Its persisted position from `window_memory`.
-- 2. A configured application-specific default zone.
-- 3. A global default zone.
-- 4. The `smart_placer` module as a final fallback.
-- @param window (hs.window) The window to reposition.
function tiler.attempt_reposition_existing_window(window)
    if not window or not window:isStandard() or window:isMinimized() then
        return
    end

    local app = window:application()
    local app_name = app and app:name()
    if not app_name then
        return
    end
    local screen = window:screen()
    if not screen then
        debug_log("attempt_reposition_existing_window: Window '", app_name, "' has no screen.")
        return
    end
    local monitor_id = monitor_manager.get_id(screen)
    if not zone_calculator.has_zones(monitor_id) then
        debug_log("attempt_reposition_existing_window: Zones not initialized yet for monitor ", monitor_id,
            ". Cannot place.")
        return
    end

    debug_log("Attempting to reposition existing window:", app_name, "on monitor:", monitor_id, "(", screen:name(), ")")

    -- 1. Try persisted remembered position from window_memory
    if window_memory then -- Ensure window_memory module is available
        local remembered = window_memory.get_remembered_position(app_name, monitor_id)
        if remembered and remembered.zone_key and remembered.tile_index then
            debug_log("Found remembered position for", app_name, "on monitor", monitor_id, "- Zone:",
                remembered.zone_key, "Tile:", remembered.tile_index)
            if tiler.position_window_from_memory(window, monitor_id, remembered.zone_key, remembered.tile_index) then
                debug_log("Successfully repositioned", app_name, "from memory after screen change.")
                return -- Window is tiled by persisted memory
            else
                debug_log("Failed to reposition", app_name, "from memory to", remembered.zone_key,
                    remembered.tile_index, "after screen change.")
            end
        else
            debug_log("No persisted remembered position for", app_name, "on monitor", monitor_id,
                "for screen change repositioning.")
        end
    end

    -- 2. If not repositioned from persisted memory, try app-specific or default zones (if window_memory is enabled)
    if config.window_memory and config.window_memory.enabled then
        -- Try configured app zones
        if config.window_memory.app_zones then
            local default_app_zone_key = config.window_memory.app_zones[app_name]
            if default_app_zone_key then
                debug_log("Attempting to reposition", app_name, "to configured app_zone:", default_app_zone_key,
                    "on monitor", monitor_id)
                if window_actions.move_window_to_zone(window, default_app_zone_key) then
                    debug_log("Successfully repositioned", app_name, "to app_zone:", default_app_zone_key)
                    return -- Successfully repositioned to app_zone
                end
            end
        end

        -- Try global default fallback if auto_tile_fallback is enabled
        if config.window_memory.auto_tile_fallback then
            local global_default_zone_key = config.window_memory.default_zone or "0"
            debug_log("Attempting to reposition", app_name, "to global default_zone:", global_default_zone_key,
                "on monitor", monitor_id)
            if window_actions.move_window_to_zone(window, global_default_zone_key) then
                debug_log("Successfully repositioned", app_name, "to global default_zone:", global_default_zone_key)
                return -- Successfully repositioned to default_zone
            end
        end
    end

    -- 3. Fallback to smart placement if all else fails
    if config.tiler.smart_placement and config.tiler.smart_placement.enabled then
        debug_log("Attempting smart placement for", app_name, "after screen change (memory attempt inconclusive).")
        -- smart_placer.place_window will check if the window is already in a tiler zone.
        -- A small delay might help if the OS is still moving windows.
        hs_timer.doAfter(config.tiler.delays.smart_placement_reposition_sec, function()
            smart_placer.place_window(window)
        end)
    end
end

------------------------------------------
-- Dynamic Resizing
------------------------------------------

local resize_modal = hs.hotkey.modal.new()

local function exit_resize_mode()
    if resize_mode_active then
        resize_mode_active = false
        resize_modal:exit()
        if resize_mode_alert_uuid then
            hs_alert.closeSpecific(resize_mode_alert_uuid)
            resize_mode_alert_uuid = nil
        end
        grid_overlay.hide() -- Hide overlay
        -- hs_alert.show("Exited Resize Mode") -- Optional, overlay hiding is enough feedback
    end
end

local function enter_resize_mode()
    if not resize_mode_active then
        resize_mode_active = true
        resize_modal:enter()
        -- resize_mode_alert_uuid = hs_alert.show("RESIZE MODE\nArrows: Move Grid Lines\nEsc: Exit", true)
        grid_overlay.show() -- Show overlay instead of alert
    end
end

local function adjust_grid(axis, index, delta)
    local win = hs_window.focusedWindow()
    if not win then return end
    local screen = win:screen()
    if not screen then return end
    local monitor_id = monitor_manager.get_id(screen)

    resize_manager.adjust(monitor_id, axis, index, delta)

    -- Refresh all windows on this screen to reflect new grid
    zone_calculator.clear_all() -- Force recalc
    zone_calculator.create_for_monitor(monitor_id, screen)

    -- Update overlay to match new grid
    grid_overlay.update()

    for _, w in ipairs(hs_window.visibleWindows()) do
        if w:screen():id() == screen:id() then
            tiler.attempt_reposition_existing_window(w)
        end
    end
end

-- Bind resize keys
resize_modal:bind({}, "escape", exit_resize_mode)
resize_modal:bind({}, "return", exit_resize_mode)

-- Adjust vertical lines (Cols)
resize_modal:bind({}, "left", function() adjust_grid("x", 1, -1) end) -- Move first divider left
resize_modal:bind({}, "right", function() adjust_grid("x", 1, 1) end) -- Move first divider right
resize_modal:bind({"shift"}, "left", function() adjust_grid("x", 2, -1) end) -- Move second divider left
resize_modal:bind({"shift"}, "right", function() adjust_grid("x", 2, 1) end) -- Move second divider right

-- Adjust horizontal lines (Rows)
resize_modal:bind({}, "up", function() adjust_grid("y", 1, -1) end)
resize_modal:bind({}, "down", function() adjust_grid("y", 1, 1) end)


------------------------------------------
-- Event Handling
------------------------------------------

--- Handles the `windowDestroyed` event.
-- Cleans up the window's state from all relevant sub-modules.
-- @param window (hs.window) The window object that was destroyed.
local function handle_window_destroyed(window)
    if window then
        local app_name = "N/A"
        -- pcall to safely get app name, as app process might be gone
        local success, app = pcall(function()
            return window:application()
        end)
        if success and app then
            app_name = app:name()
        end
        debug_log("Window destroyed:", window:id(), app_name)
        window_state_manager.cleanup(window:id())
        focus_manager.handle_window_destroyed(window:id())
    end
end

--- Handles the `windowCreated` event.
-- After a short delay to allow the window to initialize, it attempts to place
-- the new window in an appropriate tile. It prioritizes `window_memory` placement
-- and falls back to `smart_placer`.
-- @param window (hs.window) The window object that was created.
local function handle_window_created(window)
    debug_log("handle_window_created init:", window:id(), "App:",
        window:application() and window:application():name() or "N/A")

    -- Delay to allow window to fully initialize and be placed by the OS.
    hs_timer.doAfter(config.tiler.delays.new_window_placement_sec, function()
        if not window or not window:isStandard() or window:isMinimized() then
            -- Handle modal dialogs or other non-standard windows if configured
            if window and config.window_handling and config.window_handling.modal_dialog_behavior == "center" then
                local subrole = window:subrole()
                if subrole == "AXDialog" or subrole == "AXSystemDialog" then
                    debug_log("Centering modal dialog for app:", window:application() and window:application():name() or "N/A")
                    window:centerOnScreen()
                end
            end
            return -- Not a window we should tile
        end

        local screen = window:screen()
        if not screen then return end
        local monitor_id = monitor_manager.get_id(screen)

        -- Lazily initialize zones if a window appears on a new monitor
        if not zone_calculator.has_zones(monitor_id) then
            debug_log("handle_window_created: Zones not initialized for monitor", monitor_id, screen:name(), ". Initializing now.")
            zone_calculator.create_for_monitor(monitor_id, screen)
        end

        local app_name = window:application():name()
        debug_log("[Tiler::handle_window_created] In timer for:", app_name, "ID:", window:id())

        -- 1. Try window_memory placement
        local placed = false
        if window_memory and window_memory.should_position_window(window) then
            local remembered = window_memory.get_remembered_position(app_name, monitor_id)
            if remembered and remembered.zone_key and remembered.tile_index then
                debug_log("handle_window_created: Attempting window_memory placement for", app_name, "to zone", remembered.zone_key, "tile", remembered.tile_index)
                placed = tiler.position_window_from_memory(window, monitor_id, remembered.zone_key, remembered.tile_index)
            end
        end

        -- 2. If not placed by window_memory, try smart placement
        if not placed and config.tiler.smart_placement and config.tiler.smart_placement.enabled then
            debug_log("handle_window_created: Attempting smart placement for", app_name)
            smart_placer.place_window(window)
        end
    end)
end

--- Handles screen layout change events.
-- Re-initializes monitor configurations and zone calculations. After a delay,
-- it attempts to reposition all existing windows to fit the new screen layout.
local function handle_screen_change()
    debug_log("Screen configuration changed")

    -- Immediate updates for monitor registry and zone definitions
    monitor_manager.reinitialize_monitors(hs_screen.allScreens(), debug_log)
    zone_calculator.clear_all() -- Clear old zone calculations and layout cache
    for _, screen_obj in ipairs(hs_screen.allScreens()) do
        local monitor_id = monitor_manager.get_id(screen_obj)
        zone_calculator.create_for_monitor(monitor_id, screen_obj)
    end
    focus_manager.reset_cycle()
    debug_log("Immediately reinitialized monitors and zones. Focus cycle invalidated.")

    -- Delayed window repositioning to allow screens and windows to settle
    hs_timer.doAfter(config.tiler.delays.screen_change_reposition_sec, function()
        -- Attempt to reposition all existing windows if configured
        if config.tiler.reposition_on_screen_change then
            debug_log("Attempting to reposition windows after screen change (delayed)...")

            if reposition_callback then
                debug_log("Invoking smart reposition callback (AutoTiler)...")
                reposition_callback()
            else
                debug_log("Fallback to naive repositioning (No callback registered)...")
                for _, win in ipairs(hs_window.allWindows()) do
                    local app_name_for_log = win:application() and win:application():name() or "UnknownApp"
                    if win:isStandard() and not win:isMinimized() then
                        tiler.attempt_reposition_existing_window(win)
                    else
                        debug_log("Skipping reposition for window ID", win:id(), "(", app_name_for_log,
                            ") during screen change because it's not standard or is minimized.")
                    end
                end
            end
        else
            debug_log(
                "Skipping automatic window repositioning after screen change (config.tiler.reposition_on_screen_change is false).")
        end
    end)
end

------------------------------------------
-- Initialization
------------------------------------------

--- Starts the tiler engine.
--- Setup tiler hotkeys
-- Registers all hotkeys for zone switching, placement, zen mode, etc.
-- Reads configuration from config.tiler.hotkeys and config.tiler.modifier
function tiler.setup_hotkeys()
    local modifier = config.tiler.modifier
    local focus_modifier = config.tiler.focus_modifier

    -- Collect all zone keys from layouts
    local all_zone_keys = {}
    if config.tiler.layouts then
        for _, layout_config in pairs(config.tiler.layouts) do
            for zone_key, _ in pairs(layout_config) do
                if zone_key ~= "default" then
                    all_zone_keys[zone_key] = true
                end
            end
        end
    end

    local zone_key_list_for_debug = {}
    for zk, _ in pairs(all_zone_keys) do
        table.insert(zone_key_list_for_debug, zk)
    end
    debug_log("Registering hotkeys for zone keys:", table.concat(zone_key_list_for_debug, ", "))

    -- Bind zone movement and focus keys
    for zone_key_str, _ in pairs(all_zone_keys) do
        hs_hotkey.bind(modifier, zone_key_str, function()
            tiler.move_window_to_zone(zone_key_str)
        end)
        if focus_modifier then
            hs_hotkey.bind(focus_modifier, zone_key_str, function()
                tiler.focus_zone_windows(zone_key_str)
            end)
        end
    end

    -- Helper to resolve modifier string to actual modifier array
    local function get_mods(mod_str)
        return config.keys[mod_str] or mod_str
    end

    -- Tiler-specific hotkeys from config
    if config.tiler.hotkeys then
        local hk = config.tiler.hotkeys

        -- Placement mode (move to next monitor)
        if hk.placement_mode then
            hs_hotkey.bind(get_mods(hk.placement_mode.mods), hk.placement_mode.key, function()
                tiler.move_window_to_monitor("next")
            end)
        end

        -- Zone info (move to previous monitor - keeping legacy behavior)
        if hk.zone_info then
            hs_hotkey.bind(get_mods(hk.zone_info.mods), hk.zone_info.key, function()
                tiler.move_window_to_monitor("previous")
            end)
        end

        -- Zen mode toggle
        if hk.zen_mode then
            hs_hotkey.bind(get_mods(hk.zen_mode.mods), hk.zen_mode.key, function()
                tiler.toggle_zen_mode()
            end)
        end

        -- Resize mode toggle
        if hk.resize_mode then
            hs_hotkey.bind(get_mods(hk.resize_mode.mods), hk.resize_mode.key, function()
                if resize_mode_active then
                    exit_resize_mode()
                else
                    enter_resize_mode()
                end
            end)
        end
    end
end

-- This function performs all necessary initializations:
-- - Sets up configuration and default values.
-- - Initializes all sub-modules (`monitor_manager`, `zone_calculator`, etc.).
-- - Creates zones for all currently available monitors.
-- - Binds all hotkeys for window movement, focus, and other actions.
-- - Subscribes to window and screen events.
-- @return (table) The `tiler` module table.
function tiler.start()
    debug_log("Starting tiler")

    tiler.debug = config.tiler.debug
    tiler.margins = config.tiler.margins

    -- Set default delay values if not provided in config.lua
    if not config.tiler.delays then
        config.tiler.delays = {}
    end
    config.tiler.delays.screen_change_reposition_sec = config.tiler.delays.screen_change_reposition_sec or 0.1
    config.tiler.delays.new_window_placement_sec = config.tiler.delays.new_window_placement_sec or 0.15
    config.tiler.delays.smart_placement_reposition_sec = config.tiler.delays.smart_placement_reposition_sec or 0.1
    config.tiler.delays.flash_on_focus_duration_sec = config.tiler.delays.flash_on_focus_duration_sec or 0.2

    -- Pre-process problem apps list for efficient lookup
    tiler.processed_problem_apps = {}
    if config.tiler.problem_apps then
        for _, name in ipairs(config.tiler.problem_apps) do
            table.insert(tiler.processed_problem_apps, name:lower())
        end
    end

    -- Initialize sub-modules
    monitor_manager.init(debug_log)
    zone_calculator.init(config, tiler.margins, debug_log)
    window_state_manager.init(window_memory, zone_calculator, debug_log) -- window_memory might be nil initially

    local tiler_utils = {
        get_tile_for_window = function(win)
            return window_state_manager.get_tile(win:id())
        end,
        get_grid_coords_for_tile = function(tile, window)
            local screen = window:screen()
            if not screen then return nil end
            local grid_config, _ = zone_calculator.get_layout_config(screen)
            if not grid_config then return nil end
            return zone_calculator.get_grid_coords_for_tile(screen, tile, grid_config.rows, grid_config.cols)
        end,
        create_tile_from_grid_coords = function(grid_coords, window)
            local screen = window:screen()
            if not screen then return nil end
            local grid_config, _ = zone_calculator.get_layout_config(screen)
            if not grid_config then return nil end
            return zone_calculator.create_tile_from_grid_coords(screen, grid_coords, grid_config.rows, grid_config.cols)
        end
    }
    placement_strategy.init(config, tiler_utils, window_state_manager, debug_log)

    window_actions.init(config, monitor_manager, zone_calculator, window_state_manager, placement_strategy, tiler.processed_problem_apps,
        debug_log)
    smart_placer.init(config, monitor_manager, zone_calculator, window_state_manager, window_actions, debug_log)
    focus_manager.init(config, monitor_manager, zone_calculator, window_state_manager, debug_log)

    -- Setup all hotkeys
    tiler.setup_hotkeys()

    -- Watch for window events
    local window_watcher = hs_window.filter.new()
    window_watcher:subscribe({hs.window.filter.windowCreated, hs.window.filter.windowOpened}, handle_window_created)
    window_watcher:subscribe(hs.window.filter.windowDestroyed, handle_window_destroyed)

    local screen_watcher = hs.screen.watcher.new(handle_screen_change):start()

    -- Initialize zones for all currently connected screens (Crucial for startup)
    debug_log("Initializing zones for all screens...")
    for _, screen in ipairs(hs_screen.allScreens()) do
        local monitor_id = monitor_manager.get_id(screen)
        zone_calculator.create_for_monitor(monitor_id, screen)
    end

    -- Automatically tile all existing windows on startup if configured
    if config.tiler.tile_on_startup then
        debug_log("Tiling all existing windows on startup...")

        hs_timer.doAfter(0.5, function()
             if reposition_callback then
                debug_log("Startup: Invoking smart reposition callback...")
                reposition_callback()
            else
                debug_log("Startup: Fallback to naive repositioning...")
                for _, win in ipairs(hs_window.allWindows()) do
                    if win:isStandard() and not win:isMinimized() then
                        tiler.attempt_reposition_existing_window(win)
                    end
                end
            end
        end)
    end

    debug_log("Tiler started successfully")
    return tiler
end


--- Injects the `window_memory` module as a dependency.
-- This is called from `init.lua` after `window_memory` has been initialized,
-- breaking a potential circular dependency.
-- @param wm (table) The initialized `window_memory` module.
function tiler.set_window_memory(wm)
    window_memory = wm
    if window_state_manager and window_state_manager.set_window_memory_module then
        window_state_manager.set_window_memory_module(wm)
    end
    if window_actions and window_actions.set_window_memory_module then
        window_actions.set_window_memory_module(wm)
    end
    debug_log("Window memory integration enabled")
end

return tiler