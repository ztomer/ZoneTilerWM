--[[
Simplified Zone Tiler for Hammerspoon
====================================

Hierarchy: Monitor → Zone → Tile
- Each monitor has unique stable ID
- Each zone is a collection of tiles (window positions)
- Cross-monitor movement preserves zone+tile or uses cache
]] local config = require "config"
local tiler = {}
local hs_window = hs.window -- Cache for frequent use
local hs_screen = hs.screen
local hs_hotkey = hs.hotkey
local hs_timer = hs.timer

-- Window memory integration
local window_memory = nil

-- Require new sub-modules
local monitor_manager = require "modules.monitor_manager"
local zone_calculator = require "modules.zone_calculator"
local window_state_manager = require "modules.window_state_manager"
local smart_placer = require "modules.smart_placer"
local focus_manager = require "modules.focus_manager"
local window_actions = require "modules.window_actions"

-- Debug logging
local function debug_log(...)
    if tiler.debug then
        local args = {...}
        local string_args = {}
        for i, v in ipairs(args) do
            string_args[i] = tostring(v)
        end
        local message = table.concat(string_args, " ")
        print("[Tiler] " .. message)
    end
end

-- Expose monitors for window_memory
tiler.monitors = monitor_manager -- Keep this for window_memory if it directly accesses tiler.monitors
-- Expose window_state for window_memory
tiler.window_state = window_state_manager -- Keep this for window_memory

------------------------------------------
-- Window Utility Functions
------------------------------------------

-- Move window to zone/tile
function tiler.move_window_to_zone(zone_key)
    local window = hs_window.focusedWindow()
    if not window then
        debug_log("No focused window for move_window_to_zone");
        return false
    end
    return window_actions.move_window_to_zone(window, zone_key)
end

-- Position window from memory (called by window_memory)
function tiler.position_window_from_memory(window, monitor_id, zone_key, tile_index)
    return window_actions.position_window_from_memory(window, monitor_id, zone_key, tile_index)
end

-- Move window to next/previous monitor
function tiler.move_window_to_monitor(direction)
    local window = hs_window.focusedWindow()
    if not window then
        return false
    end
    return window_actions.move_window_to_monitor(window, direction)
end

-- Main focus cycling function
function tiler.focus_zone_windows(target_zone_key)
    local focused_window_before_call = hs_window.focusedWindow()
    if not focused_window_before_call then
        debug_log("focus_zone_windows: No focused window to start.")
        return false
    end
    return focus_manager.cycle_windows_in_zone(focused_window_before_call, target_zone_key)
end

-- Debug function to inspect a specific zone
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

-- Attempt to reposition an existing window, e.g., after a screen change
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
-- Event Handling
------------------------------------------

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

local function handle_window_created(window)
    -- 1. Let window_memory attempt to place the new window based on its rules (async)
    debug_log("handle_window_created init:", window:id(), "App:",
        window:application() and window:application():name() or "N/A")

    -- 1. If window_memory is enabled and has a position, use that.
    -- 2. Otherwise, use smart placement (if enabled).
    hs_timer.doAfter(config.tiler.delays.new_window_initial_sec, function()
        local screen = window:screen()
        local monitor_id = screen and monitor_manager.get_id(screen)

        if not screen then
            return
        end

        if not zone_calculator.has_zones(monitor_id) then
            -- This can happen if a window is created on a new monitor before the screen_watcher event fires.
            -- We can initialize them lazily here.
            debug_log("handle_window_created: Zones not initialized for monitor", monitor_id, screen:name(),
                ". Initializing now.")
            zone_calculator.create_for_monitor(monitor_id, screen)
        end

        if window and window:isStandard() then
            -- Delay to allow window to fully initialize AND for window_memory's async part to potentially run.
            -- window_memory.on_window_positioned has its own settle_delay_sec.
            -- This delay should be longer.
            hs_timer.doAfter(config.tiler.delays.new_window_placement_sec, function()
                -- Recheck window state
                local app_name = window:application() and window:application():name() or "UnknownApp"
                debug_log("[Tiler::handle_window_created] In final timer for:", app_name, "ID:", window:id(),
                    "isStandard:", window:isStandard(), "isMinimized:", window:isMinimized(), "monitor:",
                    monitor_id or "N/A")

                if window:isStandard() and not window:isMinimized() and monitor_id then
                    local placed = false

                    -- 1. Try window_memory placement if available
                    if window_memory and window_memory.should_position_window(window) then
                        local remembered = window_memory.get_remembered_position(app_name, monitor_id)
                        if remembered and remembered.zone_key and remembered.tile_index then
                            debug_log("handle_window_created: Attempting window_memory placement for", app_name,
                                "to zone", remembered.zone_key, "tile", remembered.tile_index)
                            placed = tiler.position_window_from_memory(window, monitor_id, remembered.zone_key,
                                remembered.tile_index)
                        end
                    end

                    -- 2. If not placed by window_memory, try smart placement
                    if not placed and config.tiler.smart_placement and config.tiler.smart_placement.enabled then
                        debug_log("handle_window_created: Attempting smart placement for", app_name)
                        smart_placer.place_window(window)
                    end
                end
            end)
        elseif window and config.window_handling and config.window_handling.modal_dialog_behavior == "center" then
            -- Handle non-standard windows, like modal dialogs
            local subrole = window:subrole()
            if subrole == "AXDialog" or subrole == "AXSystemDialog" then
                local app_name = window:application() and window:application():name() or "N/A"
                debug_log("Centering modal dialog for app:", app_name, "Title:", window:title())
                -- Center on its current screen. The small delay from new_window_initial_sec helps ensure
                -- the window has been placed by the OS before we move it.
                window:centerOnScreen()
            end
        elseif window and config.window_handling and config.window_handling.modal_dialog_behavior == "tile" then
            -- Treat modal dialogs as regular windows and apply tiling
            local subrole = window:subrole()
            if subrole == "AXDialog" or subrole == "AXSystemDialog" then
                local app_name = window:application() and window:application():name() or "N/A"
                smart_placer.place_window(window)
            end
        elseif window and config.tiler.center_modals then
            -- Handle non-standard windows, like modal dialogs
            local subrole = window:subrole()
            if subrole == "AXDialog" or subrole == "AXSystemDialog" then
                local app_name = window:application() and window:application():name() or "N/A"
                debug_log("Centering modal dialog for app:", app_name, "Title:", window:title())
                -- Center on its current screen. The small delay from new_window_initial_sec helps ensure
                -- the window has been placed by the OS before we move it.
                window:centerOnScreen()
            end
        end
    end)
end

local function handle_screen_change()
    debug_log("Screen configuration changed")

    -- Immediate updates for monitor registry and zone definitions
    monitor_manager.reinitialize_monitors(hs_screen.allScreens(), debug_log)
    zone_calculator.clear_all() -- Clear old zone calculations
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
            for _, win in ipairs(hs_window.allWindows()) do
                local app_name_for_log = win:application() and win:application():name() or "UnknownApp"
                if win:isStandard() and not win:isMinimized() then
                    tiler.attempt_reposition_existing_window(win)
                else
                    debug_log("Skipping reposition for window ID", win:id(), "(", app_name_for_log,
                        ") during screen change because it's not standard or is minimized.")
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

function tiler.start()
    debug_log("Starting tiler")

    tiler.debug = config.tiler.debug
    tiler.margins = config.tiler.margins

    -- Set default delay values if not provided in config.lua
    if not config.tiler.delays then
        config.tiler.delays = {}
    end
    if config.tiler.delays.screen_change_reposition_sec == nil then
        config.tiler.delays.screen_change_reposition_sec = 0.1
    end
    if config.tiler.delays.new_window_initial_sec == nil then
        config.tiler.delays.new_window_initial_sec = 0.05
    end
    if config.tiler.delays.new_window_placement_sec == nil then
        config.tiler.delays.new_window_placement_sec = 0.1
    end
    if config.tiler.delays.smart_placement_reposition_sec == nil then
        config.tiler.delays.smart_placement_reposition_sec = 0.1
    end
    if config.tiler.delays.flash_on_focus_duration_sec == nil then
        config.tiler.delays.flash_on_focus_duration_sec = 0.2
    end

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
    window_actions.init(config, monitor_manager, zone_calculator, window_state_manager, tiler.processed_problem_apps,
        debug_log)
    window_state_manager.init(window_memory, debug_log) -- window_memory might be nil initially
    smart_placer.init(config, monitor_manager, zone_calculator, window_state_manager, window_actions, debug_log)
    focus_manager.init(config, monitor_manager, zone_calculator, window_state_manager, debug_log)

    -- remove center modals, no longer necessary
    config.tiler.center_modals = nil

    for _, screen_obj in ipairs(hs_screen.allScreens()) do
        local monitor_id = monitor_manager.get_id(screen_obj)
        zone_calculator.create_for_monitor(monitor_id, screen_obj)
    end

    local modifier = config.tiler.modifier
    local focus_modifier = config.tiler.focus_modifier

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

    hs_hotkey.bind(modifier, "p", function()
        tiler.move_window_to_monitor("next")
    end)
    hs_hotkey.bind(modifier, ";", function()
        tiler.move_window_to_monitor("previous")
    end)

    -- Watch for window events
    -- Subscribe to both windowCreated and windowOpened for new windows, as some apps might trigger one more reliably.
    local window_watcher = hs_window.filter.new() -- Watch all windows for the specified events.
    -- The callback for these events is (windowObject, applicationNameString, eventTypeString)
    window_watcher:subscribe({hs.window.filter.windowCreated, hs.window.filter.windowOpened}, handle_window_created)
    window_watcher:subscribe(hs_window.filter.windowDestroyed, handle_window_destroyed)

    local screen_watcher = hs.screen.watcher.new(handle_screen_change):start()

    debug_log("Tiler started successfully")
    return tiler
end

-- Set window_memory reference (called from init)
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
