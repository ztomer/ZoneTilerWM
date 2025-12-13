--- Debug Module Initialization
-- Main entry point for all debugging functionality
--
-- This module initializes and configures all debug features including:
-- - Centralized logging
-- - Keystroke monitoring
-- - Inspection utilities
--
-- Usage:
--   local debug = require("debug.init")
--   debug.init(config, tiler, zone_calculator, focus_manager, audio_switcher)
--
--   -- Access debug features:
--   debug.keystroke.start()
--   debug.inspect.debug_zone("left")
--   debug.log.info("Something happened")
local debug = {}

-- Load debug modules
local debug_config = require("debug.config")
local logger = require("debug.logger")
local keystroke_monitor = require("debug.keystroke_monitor")
local inspection = require("debug.inspection")

-- Module state
local initialized = false

--- Initialize the debug system
-- @param config (table) The main configuration table
-- @param tiler_module (table) The tiler module instance
-- @param zone_calc_module (table) The zone_calculator module instance
-- @param focus_mgr_module (table) The focus_manager module instance
-- @param audio_module (table) The audio_switcher module instance (optional)
function debug.init(config, tiler_module, zone_calc_module, focus_mgr_module, audio_module)
    if initialized then
        print("⚠️  Debug system already initialized")
        return
    end

    print("Initializing debug system...")

    -- Configure logger
    logger.global_level = debug_config.get_log_level(debug_config.logger.global_level)
    if debug_config.logger.include_timestamp then
        logger.enable_timestamps()
    else
        logger.disable_timestamps()
    end
    if debug_config.logger.include_module_name then
        logger.enable_module_names()
    else
        logger.disable_module_names()
    end

    -- Initialize inspection utilities
    if debug_config.inspection.enabled then
        inspection.init(tiler_module, zone_calc_module, focus_mgr_module, audio_module)
    end

    -- Start keystroke monitor if enabled
    if debug_config.keystroke_monitor.enabled then
        keystroke_monitor.start()
    end

    initialized = true
    print("✓ Debug system initialized")
end

--- Expose debug modules
debug.config = debug_config
debug.logger = logger
debug.keystroke = keystroke_monitor
debug.inspect = inspection

--- Create a logger for a specific module
-- Convenience function that respects debug_config.modules settings
-- @param module_name (string) The module name
-- @return (table) Logger instance
function debug.create_logger(module_name)
    local enabled = debug_config.modules[module_name]
    if enabled == nil then
        enabled = false -- Default to disabled for unknown modules
    end
    return logger.new(module_name, enabled)
end

--- Create a simple debug_log function (backward compatible)
-- @param module_name (string) The module name
-- @return (function) A logging function
function debug.create_debug_log(module_name)
    local enabled = debug_config.modules[module_name]
    if enabled == nil then
        enabled = false
    end
    return logger.create_debug_log(enabled, module_name)
end

--- Enable debug logging for a specific module
-- @param module_name (string) The module name
function debug.enable_module(module_name)
    debug_config.modules[module_name] = true
    print("✓ Debug logging enabled for " .. module_name)
end

--- Disable debug logging for a specific module
-- @param module_name (string) The module name
function debug.disable_module(module_name)
    debug_config.modules[module_name] = false
    print("✓ Debug logging disabled for " .. module_name)
end

--- Print help information about debug commands
function debug.help()
    print([[
=== ZoneTilerWM Debug System ===

Keystroke Monitor:
  debug.keystroke.start()        - Start monitoring keystrokes
  debug.keystroke.stop()         - Stop monitoring keystrokes
  debug.keystroke.is_running()   - Check if monitor is running

Inspection:
  debug.inspect.debug_zone(zone_key)
  debug.inspect.debug_zone_tiles([monitor_id], zone_key)
  debug.inspect.debug_zone_windows([monitor_id], zone_key)
  debug.inspect.debug_cycle_state()
  debug.inspect.log_audio_devices()
  debug.inspect.help()           - Show inspection command help

Logging:
  debug.enable_module(name)      - Enable debug logging for module
  debug.disable_module(name)     - Disable debug logging for module
  debug.logger.set_global_level(level) - Set global log level

Available modules:
  tiler, window_memory, layout_manager, monitor_manager,
  zone_calculator, window_state_manager, focus_manager,
  window_actions, placement_strategy, smart_placer,
  audio_switcher, space_manager, space_menubar,
  space_preview, space_storage

Configuration:
  Edit debug/config.lua to change default debug settings

Help:
  debug.help()                   - Show this help message
]])
end

return debug
