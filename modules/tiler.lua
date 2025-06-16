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
    debug_log("Attempting to reposition existing window:", app_name, "on monitor:", monitor_id, "(", screen:name(), ")")

    -- 1. Try remembered position from window_memory (via window_state_manager)
    if window_memory then -- Ensure window_memory module is available
        -- Use window_memory's own function to get the persisted remembered position
        local remembered = window_memory.get_remembered_position(app_name, monitor_id)
        if remembered and remembered.zone_key and remembered.tile_index then
            debug_log("Found remembered position for", app_name, "on monitor", monitor_id, "- Zone:",
                remembered.zone_key, "Tile:", remembered.tile_index)
            if tiler.position_window_from_memory(window, monitor_id, remembered.zone_key, remembered.tile_index) then
                debug_log("Successfully repositioned", app_name, "from memory after screen change.")
                return -- Window is tiled by memory
            else
                debug_log("Failed to reposition", app_name, "from memory to", remembered.zone_key,
                    remembered.tile_index, "after screen change.")
            end
        else
            debug_log("No remembered position for", app_name, "on monitor", monitor_id,
                "for screen change repositioning.")
        end
    end

    -- 2. If not tiled by memory, and smart_placer is enabled, try smart_placer
    if config.tiler.smart_placement and config.tiler.smart_placement.enabled then
        debug_log("Attempting smart placement for", app_name, "after screen change (memory attempt inconclusive).")
        -- smart_placer.place_window will check if the window is already in a tiler zone.
        -- A small delay might help if the OS is still moving windows.
        hs_timer.doAfter(0.1, function()
            smart_placer.place_window(window)
        end)
    end
end
------------------------------------------
-- Event Handling
------------------------------------------

local function handle_window_destroyed(window)
    if window then
        debug_log("Window destroyed:", window:id(), window:application() and window:application():name() or "N/A")
        window_state_manager.cleanup(window:id())
        focus_manager.handle_window_destroyed(window:id())
    end
end

local function handle_window_created(window)
    -- 1. Let window_memory attempt to place the new window based on its rules (async)
    debug_log("handle_window_created init:", window:id(), "App:",
        window:application() and window:application():name() or "N/A")

    if window_memory and window_memory.on_window_created then
        window_memory.on_window_created(window)
    end

    -- 2. Handle smart placement if enabled (async, runs after window_memory's attempt)
    -- smart_placer.place_window itself will check if the window was already tiled by window_memory.
    if config.tiler.smart_placement and config.tiler.smart_placement.enabled then
        debug_log("handle_window_created smart placement enabled for window:", window:id(), "App:",
            window:application() and window:application():name() or "N/A")

        if window and window:isStandard() then
            -- Delay to allow window to fully initialize AND for window_memory's async part to potentially run.
            -- window_memory.on_window_created now has an internal 0.5s + 0.1s timer.
            -- This delay should be longer.
            hs_timer.doAfter(0.8, function()
                -- Recheck window state
                local app_name_for_debug = window:application() and window:application():name() or "UnknownApp"
                debug_log("[SmartPlacer via Tiler] In timer for:", app_name_for_debug, "ID:", window:id(),
                    "isStandard:", window:isStandard(), "isMinimized:", window:isMinimized())
                if window:isStandard() and not window:isMinimized() then
                    smart_placer.place_window(window)
                else
                    debug_log("[SmartPlacer via Tiler] Window", app_name_for_debug,
                        "not standard or minimized at 0.8s. Aborting smart placement.")
                end
            end)
        end
    end
end

local function handle_screen_change()
    debug_log("Screen configuration changed")
    hs_timer.doAfter(0.5, function() -- Delay to allow screens to settle
        monitor_manager.reinitialize_monitors(hs_screen.allScreens(), debug_log)
        zone_calculator.clear_all() -- Clear old zone calculations
        for _, screen_obj in ipairs(hs_screen.allScreens()) do
            local monitor_id = monitor_manager.get_id(screen_obj)
            zone_calculator.create_for_monitor(monitor_id, screen_obj)
        end
        focus_manager.reset_cycle()
        debug_log("Reinitialized monitors and zones. Focus cycle invalidated.")

        -- Attempt to reposition all existing windows if configured
        if config.tiler.reposition_on_screen_change then
            debug_log("Attempting to reposition windows after screen change...")
            for _, win in ipairs(hs_window.allWindows()) do
                if win:isStandard() and not win:isMinimized() then
                    tiler.attempt_reposition_existing_window(win)
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
    window_state_manager.init(window_memory, debug_log) -- window_memory might be nil initially
    smart_placer.init(config, window_state_manager, debug_log)
    window_actions.init(config, monitor_manager, zone_calculator, window_state_manager, tiler.processed_problem_apps,
        debug_log)
    focus_manager.init(config, monitor_manager, zone_calculator, window_state_manager, debug_log)

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
    debug_log("Window memory integration enabled")
end

return tiler
