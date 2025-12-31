-- Simple Test Runner
-- local lfs = require "lfs" -- Removed dependency

-- Color codes
local GREEN = '\27[32m'
local RED = '\27[31m'
local RESET = '\27[0m'

local function run_test_file(file)
    print('Running ' .. file .. '...')
    local chunk, err = loadfile(file)
    if not chunk then
        print(RED .. 'Failed to load ' .. file .. ': ' .. err .. RESET)
        return false
    end

    local success, msg = pcall(chunk)
    if success then
        print(GREEN .. 'PASS: ' .. file .. RESET)
        return true
    else
        print(RED .. 'FAIL: ' .. file .. '\n' .. msg .. RESET)
        return false
    end
end

-- Mock hs global before requiring modules
require('tests.mock_hs')

-- Add project root to package.path
package.path = package.path .. ';./?.lua;./modules/?.lua'

local files = {
    'tests/test_storage.lua',
    'tests/test_config_load.lua',
    'tests/test_window_memory.lua',
    'tests/test_config_validator.lua',
}

local passed = 0
local failed = 0

for _, file in ipairs(files) do
    if run_test_file(file) then
        passed = passed + 1
    else
        failed = failed + 1
    end
end

print('\n' .. string.rep('-', 20))
print('Tests Passed: ' .. passed)
print('Tests Failed: ' .. failed)

if failed > 0 then
    os.exit(1)
else
    os.exit(0)
end
