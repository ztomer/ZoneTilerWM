-- Test configuration loader
local mock_hs = require('tests.mock_hs')

-- Mock hs.configdir to point to the current directory (where config.toml is)
-- We assume the script is run from the project root
hs.configdir = os.getenv('PWD')

print('Testing config loading from: ' .. hs.configdir)

-- Require the config module
local config = require('modules.config')

-- Helper function for assertions
local function assert_eq(val, expected, msg)
    if val ~= expected then
        print(string.format("[FAIL] %s: Expected '%s', got '%s'", msg, tostring(expected), tostring(val)))
        os.exit(1)
    else
        print(string.format('[PASS] %s', msg))
    end
end

-- Test Version
assert_eq(config.version, '1.0.0', 'Config version check')

-- Test Nested Table (Tiler Keys)
-- Hotkeys are stored as raw arrays: [1] = modifier, [2] = key.
-- Consumers (modules/tiler.lua, init.lua) read them via hk[1]/hk[2], so the
-- test asserts against that array shape rather than a {mods, key} struct.
-- The "mash" modifier alias is resolved to its array form during config load.
assert_eq(config.tiler.hotkeys.placement_mode[2], 'p', 'Tiler placement mode key')
local pm_mods = config.tiler.hotkeys.placement_mode[1]
assert_eq(type(pm_mods), 'table', 'Tiler placement mode modifier resolved to array')
assert_eq(pm_mods[1], 'ctrl', 'Tiler placement mode modifier (mash -> ctrl)')
assert_eq(pm_mods[2], 'cmd', 'Tiler placement mode modifier (mash -> cmd)')

-- Test Colors (Green)
local green = config.pomodoro.color_time_remaining
assert_eq(type(green), 'table', 'Color is a table')
assert_eq(green.green, 1, 'Color green component is 1')

-- Test Home Directory Expansion
local home = os.getenv('HOME')
local expected_cache = home .. '/.config/ZoneTilerWM'
assert_eq(config.window_memory.cache_dir, expected_cache, 'Cache dir expansion')

print('All config tests passed!')
