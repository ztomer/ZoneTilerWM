--- Validates the configuration table against a defined schema.
-- @module config_validator
local config_validator = {}

--- Helper to check type
local function check_type(val, expected_type, path)
    if type(val) ~= expected_type then
        return false, string.format("Expected %s at '%s', got %s", expected_type, path, type(val))
    end
    return true
end

--- Validates the config table.
---@param config table The configuration table to validate.
---@return boolean valid
---@return string|nil error_message
function config_validator.validate(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    -- Validate 'keys'
    if not config.keys then return false, "Missing 'keys' table" end
    local valid, err = check_type(config.keys, "table", "keys")
    if not valid then return false, err end

    if not config.keys.HYPER then return false, "Missing 'keys.HYPER'" end

    -- Validate 'tiler'
    if not config.tiler then return false, "Missing 'tiler' table" end
    valid, err = check_type(config.tiler, "table", "tiler")
    if not valid then return false, err end

    -- Validate 'tiler.grids'
    if config.tiler.grids then
        for k, v in pairs(config.tiler.grids) do
            if not v.cols or not v.rows then
                return false, string.format("Invalid grid definition at 'tiler.grids.%s': missing cols or rows", k)
            end
        end
    end

    -- Validate 'tiler.margins'
    if config.tiler.margins then
        if type(config.tiler.margins.size) ~= "number" then
            return false, "Expected number for 'tiler.margins.size'"
        end
    end

    -- Validate 'window_memory'
    if config.window_memory then
        if config.window_memory.enabled ~= nil and type(config.window_memory.enabled) ~= "boolean" then
             return false, "Expected boolean for 'window_memory.enabled'"
        end
    end

    return true
end

return config_validator
