local config_validator = require('modules.config_validator')

-- Test 1: Valid Config
local valid_config = {
    keys = { HYPER = { 'cmd', 'alt', 'ctrl' } },
    tiler = {
        grids = {
            ['2x2'] = { cols = 2, rows = 2 },
        },
        margins = { size = 10 },
    },
    window_memory = { enabled = true },
}

local valid, err = config_validator.validate(valid_config)
if not valid then
    error('Valid config failed validation: ' .. tostring(err))
end

-- Test 2: Invalid Config (Missing keys)
local invalid_config_1 = {
    tiler = {},
}
local valid, err = config_validator.validate(invalid_config_1)
if valid then
    error('Invalid config (missing keys) passed validation')
end

-- Test 3: Invalid Config (Bad type)
local invalid_config_2 = {
    keys = { HYPER = {} },
    tiler = {
        margins = { size = '10' }, -- Should be number
    },
}
local valid, err = config_validator.validate(invalid_config_2)
if valid then
    error('Invalid config (bad type) passed validation')
end

print('ConfigValidator tests passed!')
