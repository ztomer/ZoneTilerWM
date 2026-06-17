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

local toml = require('modules.toml')

-- Load the TOML configuration
local function load_config()
    local config_file = hs.configdir .. '/config.toml'
    local file, err = io.open(config_file, 'r')
    if not file then
        -- stderr so headless tooling (oracles) keep stdout clean for JSON
        io.stderr:write('Error: Could not open config file: ' .. config_file .. ' Error: ' .. tostring(err) .. '\n')
        return nil
    end

    local content = file:read('*all')
    file:close()

    local config = toml.parse(content)

    -- Post-processing: Convert colors
    if config.pomodoro then
        if config.pomodoro.color_time_remaining == 'green' then
            config.pomodoro.color_time_remaining = hs.drawing.color.green
        end
        if config.pomodoro.color_time_used == 'red' then
            config.pomodoro.color_time_used = hs.drawing.color.red
        end
    end

    -- Post-processing: Expand home directory in cache_dir
    if config.window_memory and config.window_memory.cache_dir then
        config.window_memory.cache_dir = config.window_memory.cache_dir:gsub('^~', os.getenv('HOME'))
    end

    -- Post-processing: Global Alias Resolution
    if config.aliases then
        local aliases = config.aliases

        -- Aliases for backward compatibility access to [keys]
        -- This ensures any code still referencing config.keys works
        config.keys = aliases

        local function resolve_recursively(tbl)
            for k, v in pairs(tbl) do
                -- Skip resolving inside the aliases/keys table itself
                if tbl == aliases or tbl == config.keys then
                -- do nothing
                elseif type(v) == 'table' then
                    resolve_recursively(v)
                elseif type(v) == 'string' then
                    if aliases[v] then
                        tbl[k] = aliases[v]
                    end
                end
            end
        end

        resolve_recursively(config)
    end

    -- ensuring key tables are accessible as they were before
    -- The toml parser returns array as indexed table which is compatible with Lua lists

    return config
end

local config = load_config()

if not config then
    -- Fallback or empty config to prevent crash if file missing
    return {}
end

-- Version banner to stderr (keeps stdout clean for headless tooling / oracles)
io.stderr:write('Loaded ZoneTilerWM Configuration Version: ' .. (config.version or 'Unknown') .. '\n')

return config
