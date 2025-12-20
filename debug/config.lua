--- Debug Configuration
-- Centralized configuration for all debug features
--
-- This module provides a single place to configure all debugging functionality
-- including logging levels, feature toggles, and inspection utilities.
local debug_config = {}

--- Keystroke Monitor Configuration
debug_config.keystroke_monitor = {
    enabled = false -- Set to true to enable keystroke monitoring on startup
}

--- Logger Configuration
debug_config.logger = {
    include_timestamp = false, -- Include timestamps in log output
    include_module_name = true, -- Include module name in log output
    global_level = "DEBUG", -- Global log level: "DEBUG", "INFO", "WARN", "ERROR", "NONE"
    file_logging = {
        enabled = true,
        file_path = "/tmp/zonetiler_debug.log"
    }
}

--- Inspection Configuration
debug_config.inspection = {
    enabled = true -- Enable inspection utilities
}

--- Module-Specific Debug Flags
-- These control debug logging for individual modules
debug_config.modules = {
    tiler = true, -- Tiler module debug logging
    auto_tiler = true, -- Auto tiler debug logging
    window_memory = true, -- Window memory debug logging
    layout_manager = true, -- Layout manager debug logging
    monitor_manager = false, -- Monitor manager debug logging
    zone_calculator = false, -- Zone calculator debug logging
    window_state_manager = false, -- Window state manager debug logging
    focus_manager = false, -- Focus manager debug logging
    window_actions = false, -- Window actions debug logging
    placement_strategy = false, -- Placement strategy debug logging
    smart_placer = false, -- Smart placer debug logging
    audio_switcher = false, -- Audio switcher debug logging
    space_manager = true, -- Space manager debug logging
    space_menubar = true, -- Space menubar debug logging
    space_preview = true, -- Space preview debug logging
    space_storage = true -- Space storage debug logging
}

--- Performance Monitoring
debug_config.performance = {
    enabled = false, -- Enable performance monitoring
    log_slow_operations = true, -- Log operations that take longer than threshold
    slow_operation_threshold = 0.1 -- Threshold in seconds (100ms)
}

--- Helper function to get log level number from string
-- @param level_str (string) "DEBUG", "INFO", "WARN", "ERROR", or "NONE"
-- @return (number) Log level number
function debug_config.get_log_level(level_str)
    local logger = require("debug.logger")
    local levels = {
        DEBUG = logger.LEVEL.DEBUG,
        INFO = logger.LEVEL.INFO,
        WARN = logger.LEVEL.WARN,
        ERROR = logger.LEVEL.ERROR,
        NONE = logger.LEVEL.NONE
    }
    return levels[level_str] or logger.LEVEL.DEBUG
end

return debug_config
