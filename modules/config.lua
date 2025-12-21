-- Configuration file for Hammerspoon settings
local config = {}

--[[
  DEBUG CONFIGURATION NOTICE

  Debug logging settings have been moved to debug/config.lua for better organization.

  To enable/disable debug logging for specific modules:
  - Edit debug/config.lua and set the module flags (e.g., tiler = true)
  - Or use runtime commands: zt_debug.enable_module("tiler")

  See debug/README.md for complete documentation.
]]

local toml = require "modules.toml"

-- Load the TOML configuration
local function load_config()
    local config_file = hs.configdir .. "/config.toml"
    local file, err = io.open(config_file, "r")
    if not file then
        print("Error: Could not open config file: " .. config_file .. " Error: " .. tostring(err))
        return nil
    end

    local content = file:read("*all")
    file:close()

    local config = toml.parse(content)

    -- Post-processing: Convert colors
    if config.pomodoro then
        if config.pomodoro.color_time_remaining == "green" then
            config.pomodoro.color_time_remaining = hs.drawing.color.green
        end
        if config.pomodoro.color_time_used == "red" then
            config.pomodoro.color_time_used = hs.drawing.color.red
        end
    end

    -- Post-processing: Expand home directory in cache_dir
    if config.window_memory and config.window_memory.cache_dir then
        config.window_memory.cache_dir = config.window_memory.cache_dir:gsub("^~", os.getenv("HOME"))
    end

    -- Post-processing: Helper function to get valid modifiers
    -- This mimics the logic that might be expected elsewhere
    -- ensuring key tables are accessible as they were before
    -- The toml parser returns array as indexed table which is compatible with Lua lists

    return config
end

local config = load_config()

if not config then
    -- Fallback or empty config to prevent crash if file missing
    return {}
end

-- Print version
print("Loaded ZoneTilerWM Configuration Version: " .. (config.version or "Unknown"))

return config
