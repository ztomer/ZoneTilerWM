--- Centralized Debug Logger
-- Provides consistent, configurable logging across all modules
--
-- Features:
-- - Multiple log levels (DEBUG, INFO, WARN, ERROR)
-- - Module-specific enable/disable
-- - Timestamp formatting
-- - Color-coded output (when supported)
-- - Prefix formatting for readability
--
-- Usage:
--   local logger = require("debug.logger")
--   local log = logger.new("my_module", config.my_module.debug)
--   log("This is a debug message")
--   log.info("This is an info message")
--   log.warn("This is a warning")
--   log.error("This is an error")
local logger = {}

--- Log levels
logger.LEVEL = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    NONE = 999
}

--- Global log level (can be overridden per module)
logger.global_level = logger.LEVEL.DEBUG

--- Whether to include timestamps in log output
logger.include_timestamp = false

--- Whether to include module name in log output
logger.include_module_name = true

--- File logging configuration
logger.file_logging_enabled = false
logger.log_file_path = nil

--- Configure file logging
-- @param path (string) The path to the log file
-- @param enable (boolean) Whether to enable file logging
function logger.configure_file_logging(path, enable)
    logger.log_file_path = path
    logger.file_logging_enabled = enable
end

--- Internal function to write to file
local function write_to_file(message)
    if logger.file_logging_enabled and logger.log_file_path then
        local file = io.open(logger.log_file_path, "a")
        if file then
            file:write(message .. "\n")
            file:close()
        end
    end
end

--- Creates a new logger instance for a specific module
-- @param module_name (string) The name of the module
-- @param enabled (boolean) Whether debug logging is enabled for this module (default: true)
-- @param level (number) The minimum log level (default: logger.LEVEL.DEBUG)
-- @return (table) A logger instance with log(), info(), warn(), error() functions
function logger.new(module_name, enabled, level)
    if enabled == nil then
        enabled = true
    end

    level = level or logger.LEVEL.DEBUG

    local log_instance = {}

    --- Format a log message with optional prefix
    local function format_message(level_name, ...)
        local parts = {}

        -- Add timestamp if enabled
        if logger.include_timestamp then
            table.insert(parts, os.date("%Y-%m-%d %H:%M:%S"))
        end

        -- Add module name if enabled
        if logger.include_module_name and module_name then
            table.insert(parts, "[" .. module_name .. "]")
        end

        -- Add level name
        if level_name then
            table.insert(parts, "[" .. level_name .. "]")
        end

        -- Add the actual message
        local args = {...}
        for i, v in ipairs(args) do
            if type(v) == "table" then
                -- Use hs.inspect for tables
                table.insert(parts, hs.inspect(v))
            else
                table.insert(parts, tostring(v))
            end
        end

        return table.concat(parts, " ")
    end

    --- Main logging function (DEBUG level)
    -- @param ... Messages to log
    function log_instance.log(...)
        if not enabled or level > logger.LEVEL.DEBUG or logger.global_level > logger.LEVEL.DEBUG then
            return
        end
        local Msg = format_message(nil, ...)
        io.stderr:write(Msg .. "\n")
        write_to_file(Msg)
    end

    -- Shorthand for log()
    setmetatable(log_instance, {
        __call = function(_, ...)
            log_instance.log(...)
        end
    })

    --- INFO level logging
    -- @param ... Messages to log
    function log_instance.info(...)
        if not enabled or level > logger.LEVEL.INFO or logger.global_level > logger.LEVEL.INFO then
            return
        end
        local Msg = format_message("INFO", ...)
        io.stderr:write(Msg .. "\n")
        write_to_file(Msg)
    end

    --- WARN level logging
    -- @param ... Messages to log
    function log_instance.warn(...)
        if not enabled or level > logger.LEVEL.WARN or logger.global_level > logger.LEVEL.WARN then
            return
        end
        local Msg = format_message("WARN", ...)
        io.stderr:write(Msg .. "\n")
        write_to_file(Msg)
    end

    --- ERROR level logging
    -- @param ... Messages to log
    function log_instance.error(...)
        if not enabled or level > logger.LEVEL.ERROR or logger.global_level > logger.LEVEL.ERROR then
            return
        end
        local Msg = format_message("ERROR", ...)
        io.stderr:write(Msg .. "\n")
        write_to_file(Msg)
    end

    --- Enable logging for this instance
    function log_instance.enable()
        enabled = true
    end

    --- Disable logging for this instance
    function log_instance.disable()
        enabled = false
    end

    --- Set log level for this instance
    -- @param new_level (number) The new log level
    function log_instance.set_level(new_level)
        level = new_level
    end

    --- Check if logging is enabled
    -- @return (boolean) Whether logging is enabled
    function log_instance.is_enabled()
        return enabled
    end

    return log_instance
end

--- Creates a simple debug log function (backward compatible)
-- This function mimics the behavior of the old debug_log functions
-- @param enabled (boolean) Whether debug logging is enabled
-- @param module_name (string) Optional module name for prefix
-- @return (function) A logging function
function logger.create_debug_log(enabled, module_name)
    local log_instance = logger.new(module_name, enabled)
    return function(...)
        log_instance.log(...)
    end
end

--- Set global log level for all loggers
-- @param level (number) The new global log level
function logger.set_global_level(level)
    logger.global_level = level
end

--- Enable timestamps for all loggers
function logger.enable_timestamps()
    logger.include_timestamp = true
end

--- Disable timestamps for all loggers
function logger.disable_timestamps()
    logger.include_timestamp = false
end

--- Enable module names for all loggers
function logger.enable_module_names()
    logger.include_module_name = true
end

--- Disable module names for all loggers
function logger.disable_module_names()
    logger.include_module_name = false
end

return logger
