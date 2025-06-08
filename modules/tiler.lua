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
        local message = table.concat(args, " ")
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
    -- Notify window_memory of new window
    if window_memory and window_memory.on_window_created then
        window_memory.on_window_created(window)
    end

    -- Handle smart placement if enabled
    if config.tiler.smart_placement and config.tiler.smart_placement.enabled then
        if window and window:isStandard() then
            -- Delay to allow window to fully initialize
            hs_timer.doAfter(0.2, function()
                if window:isStandard() then -- Recheck, might have closed or changed
                    smart_placer.place_window(window)
                end
            end)
        end
    end
end

local function handle_screen_change()
    debug_log("Screen configuration changed")
    hs_timer.doAfter(0.5, function() -- Delay to allow screens to settle
        monitor_manager.reinitialize_monitors(hs_screen.allScreens(), debug_log)
        for _, screen_obj in ipairs(hs_screen.allScreens()) do
            local monitor_id = monitor_manager.get_id(screen_obj)
            zone_calculator.create_for_monitor(monitor_id, screen_obj)
        end
        focus_manager.reset_cycle()
        debug_log("Reinitialized monitors and zones. Focus cycle invalidated.")
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
    local window_filter_events = {hs_window.filter.windowDestroyed, hs_window.filter.windowCreated}
    local window_watcher = hs_window.filter.new(window_filter_events)
    window_watcher:subscribe(hs_window.filter.windowDestroyed, handle_window_destroyed)
    window_watcher:subscribe(hs_window.filter.windowCreated, handle_window_created)

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
