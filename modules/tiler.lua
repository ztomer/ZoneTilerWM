-- tiler.lua
local config = require "modules.config"
local tiler = {}
local hs_window = hs.window
local hs_screen = hs.screen
local hs_timer = hs.timer
local hs_hotkey = hs.hotkey
local hs_alert = hs.alert
local hs_grid = hs.grid

-- dependencies
local monitor_manager = require "modules.monitor_manager"
local zone_calculator = require "modules.zone_calculator"
local window_state_manager = require "modules.window_state_manager"
local smart_placer = require "modules.smart_placer"
local focus_manager = require "modules.focus_manager"
local window_actions = require "modules.window_actions"
local placement_strategy = require "modules.placement_strategy"

tiler.window_actions = window_actions
local window_cache = require "modules.window_cache"

-- Resize Mode State
local resize_mode_active = false
local resize_mode_alert_uuid = nil

-- Grid overlay for resize mode
local grid_overlay = require "modules.grid_overlay"

local debug = require "debug.init"
local debug_log = debug.create_debug_log("tiler")

-- Persistent references to prevent Garbage Collection
tiler._watchers = {
    window = nil,
    screen = nil,
    timers = {}
}

function tiler.start(wm_instance)
    debug_log("Starting tiler")
    local window_memory = wm_instance

    -- Initialize Foundation
    monitor_manager.init(debug_log)
    zone_calculator.init(config, config.tiler.margins, debug_log)
    window_state_manager.init(window_memory, zone_calculator, debug_log)
    placement_strategy.init(config, window_state_manager)
    window_actions.init(config, monitor_manager, zone_calculator, window_state_manager, placement_strategy, debug_log)
    smart_placer.init(config, monitor_manager, zone_calculator, window_state_manager, window_actions, debug_log)
    focus_manager.init(config, monitor_manager, zone_calculator, window_state_manager, debug_log)

    -- Window Events
    tiler._watchers.window = hs_window.filter.new()
    tiler._watchers.window:subscribe({hs.window.filter.windowCreated, hs.window.filter.windowOpened}, function(win)
        window_cache.update(win, "created")
        -- Call existing handlers here if needed
    end)
    tiler._watchers.window:subscribe(hs.window.filter.windowDestroyed, function(win)
        window_cache.update(win, "destroyed")
    end)

    -- Cache Init
    window_cache.init()
    tiler._watchers.timers.cache = hs_timer.doAfter(0.5, function()
        window_cache.refresh()
        debug_log("Window cache ready.")
    end)

    -- Startup Tiling
    if config.tiler.tile_on_startup then
        tiler._watchers.timers.startup = hs_timer.doAfter(0.6, function()
            -- Invoke your reposition_callback here (the one set by init.lua)
            if tiler.reposition_callback then
                tiler.reposition_callback()
            end
        end)
    end

    debug_log("Tiler started successfully")
    
    tiler.setup_hotkeys()
    
    tiler.zone_calculator = zone_calculator
    tiler.monitors = monitor_manager
    
    return tiler
end

function tiler.set_reposition_callback(fn)
    tiler.reposition_callback = fn
end

--- Registers all hotkeys for zone switching using config values
function tiler.setup_hotkeys()
    local modifier = config.tiler and config.tiler.modifier or "mash"
    local focus_modifier = config.tiler and config.tiler.focus_modifier or "mash_shift"
    
    local all_zone_keys = {}
    local zone_key_list_for_debug = {}
    
    -- Collect all zone keys from layouts
    if config.tiler and config.tiler.layouts then
        for layout_key, layout_config in pairs(config.tiler.layouts) do
            for zone_key, _ in pairs(layout_config) do
                if zone_key ~= "default" then
                    all_zone_keys[zone_key] = true
                end
            end
        end
    end

    for zk, _ in pairs(all_zone_keys) do
        table.insert(zone_key_list_for_debug, zk)
    end
    debug_log("Registering hotkeys for zone keys:", table.concat(zone_key_list_for_debug, ", "))
    
    -- Helper to resolve modifier string to actual modifier array
    local function get_mods(mod_str)
        return config.keys[mod_str] or mod_str
    end
    
    -- Bind zone movement and focus keys
    for zone_key_str, _ in pairs(all_zone_keys) do
        hs_hotkey.bind(get_mods(modifier), zone_key_str, function()
            tiler.move_window_to_zone(zone_key_str)
        end)
        if focus_modifier then
            hs_hotkey.bind(get_mods(focus_modifier), zone_key_str, function()
                tiler.focus_zone_windows(zone_key_str)
            end)
        end
    end
    
    -- Additional hotkeys from config
    if config.tiler and config.tiler.hotkeys then
        local hk = config.tiler.hotkeys
        
        -- Placement mode - move to next screen
        if hk.placement_mode then
            hs_hotkey.bind(get_mods(hk.placement_mode[1]), hk.placement_mode[2], function()
                local focused = hs_window.focusedWindow()
                if focused then
                    window_actions.move_window_to_monitor(focused, "next")
                end
            end)
        end
        
        -- Zone info - move focus to previous screen
        if hk.zone_info then
            hs_hotkey.bind(get_mods(hk.zone_info[1]), hk.zone_info[2], function()
                local focused = hs_window.focusedWindow()
                if focused then
                    window_actions.move_window_to_monitor(focused, "previous")
                end
            end)
        end

        -- Zen mode toggle
        if hk.zen_mode then
            hs_hotkey.bind(get_mods(hk.zen_mode[1]), hk.zen_mode[2], function()
                tiler.toggle_zen_mode()
            end)
        end

        -- Resize mode toggle
        if hk.resize_mode then
            hs_hotkey.bind(get_mods(hk.resize_mode[1]), hk.resize_mode[2], function()
                if resize_mode_active then
                    exit_resize_mode()
                else
                    enter_resize_mode()
                end
            end)
        end

        -- Focus next/previous screen
        if hk.focus_next_screen then
            hs_hotkey.bind(get_mods(hk.focus_next_screen[1]), hk.focus_next_screen[2], function()
                tiler.focus_next_screen()
            end)
        end
        if hk.focus_prev_screen then
            hs_hotkey.bind(get_mods(hk.focus_prev_screen[1]), hk.focus_prev_screen[2], function()
                tiler.focus_prev_screen()
            end)
        end
    end
end

--- Moves the currently focused window to the next/previous monitor.
function tiler.move_window_to_monitor(direction)
    local focused = hs_window.focusedWindow()
    if not focused then
        debug_log("move_window_to_monitor: No focused window")
        return false
    end
    return window_actions.move_window_to_monitor(focused, direction)
end

--- Moves the currently focused window to a specified zone.
function tiler.move_window_to_zone(zone_key)
    local focused_window = hs_window.focusedWindow()
    if not focused_window then
        debug_log("No focused window for move_window_to_zone")
        return false
    end
    return window_actions.move_window_to_zone(focused_window, zone_key)
end

--- Cycles focus through windows within a specific zone.
function tiler.focus_zone_windows(target_zone_key)
    local focused_window_before_call = hs_window.focusedWindow()
    if not focused_window_before_call then
        debug_log("focus_zone_windows: No focused window to start.")
        return
    end
    return focus_manager.cycle_windows_in_zone(focused_window_before_call, target_zone_key)
end

--- Toggles "Zen Mode" for the focused window, maximizing it on its current screen.
function tiler.toggle_zen_mode()
    local focused_window = hs_window.focusedWindow()
    if not focused_window then
        debug_log("No focused window for toggle_zen_mode")
        return
    end
    window_actions.toggle_zen_mode(focused_window)
end

--- Focus the next screen.
function tiler.focus_next_screen()
    local current = hs_window.focusedWindow()
    if current then
        local current_screen = current:screen()
        local all_screens = hs_screen.allScreens()
        local current_idx = 0
        for i, s in ipairs(all_screens) do
            if s:id() == current_screen:id() then
                current_idx = i
                break
            end
        end
        local next_idx = (current_idx % #all_screens) + 1
        local next_screen = all_screens[next_idx]
        local windows = current:application():allWindows()
        for _, w in ipairs(windows) do
            if w:screen():id() == next_screen:id() then
                w:focus()
                return
            end
        end
    end
end

--- Focus the previous screen.
function tiler.focus_prev_screen()
    local current = hs_window.focusedWindow()
    if current then
        local current_screen = current:screen()
        local all_screens = hs_screen.allScreens()
        local current_idx = 0
        for i, s in ipairs(all_screens) do
            if s:id() == current_screen:id() then
                current_idx = i
                break
            end
        end
        local prev_idx = (current_idx - 2 + #all_screens) % #all_screens + 1
        local prev_screen = all_screens[prev_idx]
        local windows = current:application():allWindows()
        for _, w in ipairs(windows) do
            if w:screen():id() == prev_screen:id() then
                w:focus()
                return
            end
        end
    end
end

------------------------------------------
-- Resize Mode
------------------------------------------
local resize_modal = hs_hotkey.modal.new()

local function exit_resize_mode()
    if resize_mode_active then
        resize_mode_active = false
        resize_modal:exit()
        if resize_mode_alert_uuid then
            hs_alert.closeSpecific(resize_mode_alert_uuid)
            resize_mode_alert_uuid = nil
        end
        grid_overlay.hide()
    end
end

local function enter_resize_mode()
    if not resize_mode_active then
        resize_mode_active = true
        resize_modal:enter()
        resize_mode_alert_uuid = hs_alert.show("Resize Mode: Arrow keys to move, ESC to exit", 2)
        grid_overlay.show()
    end
end

-- Resize mode: Arrow keys to move windows around the grid
resize_modal:bind('', 'left', function()
    hs_grid.pushWindowLeft()
end)
resize_modal:bind('', 'right', function()
    hs_grid.pushWindowRight()
end)
resize_modal:bind('', 'up', function()
    hs_grid.pushWindowUp()
end)
resize_modal:bind('', 'down', function()
    hs_grid.pushWindowDown()
end)
resize_modal:bind('', 'escape', function()
    exit_resize_mode()
end)

return tiler
