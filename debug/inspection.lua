--- Debug Inspection Utilities
-- Provides inspection functions for debugging ZoneTilerWM state
--
-- This module consolidates all debug inspection functions that were
-- previously scattered across different modules.
--
-- Usage:
--   local inspection = require("debug.inspection")
--   inspection.init(tiler, zone_calculator, focus_manager, audio_switcher)
--   inspection.debug_zone("left")
--   inspection.debug_cycle_state()
local inspection = {}

-- Module references (set during init)
local tiler = nil
local zone_calculator = nil
local focus_manager = nil
local audio_switcher = nil

--- Initialize the inspection module with required module references
-- @param tiler_module (table) The tiler module instance
-- @param zone_calc_module (table) The zone_calculator module instance
-- @param focus_mgr_module (table) The focus_manager module instance
-- @param audio_module (table) The audio_switcher module instance (optional)
function inspection.init(tiler_module, zone_calc_module, focus_mgr_module, audio_module)
    tiler = tiler_module
    zone_calculator = zone_calc_module
    focus_manager = focus_mgr_module
    audio_switcher = audio_module
end

--- Prints debugging information for a specific zone on the current monitor
-- @param zone_key (string) The zone identifier (e.g., "left", "right", "center")
function inspection.debug_zone(zone_key)
    if not tiler then
        print("ERROR: Inspection module not initialized. Call inspection.init() first.")
        return
    end

    if not zone_key then
        print("ERROR: zone_key is required")
        return
    end

    -- Get current monitor
    local screen = hs.mouse.getCurrentScreen()
    if not screen then
        print("ERROR: Could not get current screen")
        return
    end

    local monitor_id = screen:getUUID()
    print("=== DEBUG ZONE: " .. zone_key .. " on monitor " .. monitor_id .. " ===")

    -- Call tiler's debug function
    if tiler.debug_zone then
        tiler.debug_zone(zone_key)
    else
        print("ERROR: tiler.debug_zone not available")
    end
end

--- Prints tile calculations for a specific zone
-- @param monitor_id (string) The monitor UUID (optional, uses current screen if nil)
-- @param zone_key (string) The zone identifier
function inspection.debug_zone_tiles(monitor_id, zone_key)
    if not zone_calculator then
        print("ERROR: Inspection module not initialized. Call inspection.init() first.")
        return
    end

    if not zone_key then
        print("ERROR: zone_key is required")
        return
    end

    -- Use current screen if monitor_id not provided
    if not monitor_id then
        local screen = hs.mouse.getCurrentScreen()
        if not screen then
            print("ERROR: Could not get current screen")
            return
        end
        monitor_id = screen:getUUID()
    end

    print("=== DEBUG ZONE TILES: " .. zone_key .. " on monitor " .. monitor_id .. " ===")

    -- Call zone_calculator's debug function
    if zone_calculator.debug_zone_tiles then
        zone_calculator.debug_zone_tiles(monitor_id, zone_key)
    else
        print("ERROR: zone_calculator.debug_zone_tiles not available")
    end
end

--- Prints debugging information about windows within a zone
-- @param monitor_id (string) The monitor UUID (optional, uses current screen if nil)
-- @param zone_key (string) The zone identifier
function inspection.debug_zone_windows(monitor_id, zone_key)
    if not focus_manager then
        print("ERROR: Inspection module not initialized. Call inspection.init() first.")
        return
    end

    if not zone_key then
        print("ERROR: zone_key is required")
        return
    end

    -- Use current screen if monitor_id not provided
    local screen_obj = nil
    if not monitor_id then
        screen_obj = hs.mouse.getCurrentScreen()
        if not screen_obj then
            print("ERROR: Could not get current screen")
            return
        end
        monitor_id = screen_obj:getUUID()
    else
        -- Find screen by UUID
        for _, screen in ipairs(hs.screen.allScreens()) do
            if screen:getUUID() == monitor_id then
                screen_obj = screen
                break
            end
        end
    end

    if not screen_obj then
        print("ERROR: Could not find screen with UUID " .. monitor_id)
        return
    end

    print("=== DEBUG ZONE WINDOWS: " .. zone_key .. " on monitor " .. monitor_id .. " ===")

    -- Call focus_manager's debug function
    if focus_manager.debug_zone_windows then
        focus_manager.debug_zone_windows(monitor_id, zone_key, screen_obj)
    else
        print("ERROR: focus_manager.debug_zone_windows not available")
    end
end

--- Prints the current internal state of the focus cycle manager
function inspection.debug_cycle_state()
    if not focus_manager then
        print("ERROR: Inspection module not initialized. Call inspection.init() first.")
        return
    end

    print("=== DEBUG FOCUS CYCLE STATE ===")

    -- Call focus_manager's debug function
    if focus_manager.debug_cycle_state then
        focus_manager.debug_cycle_state()
    else
        print("ERROR: focus_manager.debug_cycle_state not available")
    end
end

--- Logs all available audio output devices
function inspection.log_audio_devices()
    if not audio_switcher then
        print("ERROR: Audio switcher module not available")
        return
    end

    print("=== AUDIO OUTPUT DEVICES ===")

    -- Call audio_switcher's log function
    if audio_switcher.log_devices then
        audio_switcher.log_devices()
    else
        print("ERROR: audio_switcher.log_devices not available")
    end
end

--- Prints help information about available inspection commands
function inspection.help()
    print([[
=== Debug Inspection Commands ===

Zone Inspection:
  inspection.debug_zone(zone_key)
    - Prints debugging information for a specific zone
    - Example: inspection.debug_zone("left")

  inspection.debug_zone_tiles([monitor_id], zone_key)
    - Prints tile calculations for a zone
    - Example: inspection.debug_zone_tiles(nil, "center")

  inspection.debug_zone_windows([monitor_id], zone_key)
    - Prints windows within a zone
    - Example: inspection.debug_zone_windows(nil, "right")

Focus Manager:
  inspection.debug_cycle_state()
    - Prints the current focus cycle state

Audio:
  inspection.log_audio_devices()
    - Lists all audio output devices

Help:
  inspection.help()
    - Shows this help message
]])
end

return inspection
