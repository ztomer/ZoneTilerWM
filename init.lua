-- Hammerspoon configuration
local config = require "modules.config"
local config_validator = require "modules.config_validator"

-- Load debug system
local debug = require "debug.init"

-- Load modules
local pom = require "modules.pomodoor"
local tiler = require "modules.tiler"
local appSwitcher = require "modules.app_switcher"
local window_memory = require "modules.window_memory"
local audio_switcher = require "modules.audio_switcher"
local layout_manager = require "modules.layout_manager"
local auto_tiler = require "modules.auto_tiler"

-- Get key combinations from config
local mash = config.keys.mash
local mash_app = config.keys.mash_app
local mash_shift = config.keys.mash_shift
local HYPER = config.keys.HYPER

--[[
  Initializes system keybindings (window hints, reload, etc.)
  Reads configuration from config.system_hotkeys
]]
local function init_system_hotkeys()
    if not config.system_hotkeys then
        return
    end

    -- Helper to resolve modifier string to actual modifier array
    local function get_mods(mod_str)
        return config.keys[mod_str] or mod_str
    end

    -- Window hints
    if config.system_hotkeys.window_hints then
        local hk = config.system_hotkeys.window_hints
        hs.hotkey.bind(get_mods(hk.mods), hk.key, hs.hints.windowHints)
    end

    -- Activity Monitor toggle
    if config.system_hotkeys.activity_monitor then
        local hk = config.system_hotkeys.activity_monitor
        hs.hotkey.bind(get_mods(hk.mods), hk.key, function()
            appSwitcher.toggle_app("Activity Monitor")
        end)
    end

    -- Hot reload configuration
    if config.system_hotkeys.reload then
        local hk = config.system_hotkeys.reload
        hs.hotkey.bind(get_mods(hk.mods), hk.key, function()
            hs.reload()
            hs.alert.show("Config reloaded!")
        end)
    end
end

--[[
  Main initialization function
]]
local function init()
    print("-------------- Loading Hammerspoon config --------------")

    -- Validate configuration
    local valid, err = config_validator.validate(config)
    if not valid then
        hs.alert.show("Config Error: " .. err, 5)
        print("Config Error: " .. err)
        return -- Stop initialization
    end

    -- Disable animation for speed
    hs.window.animationDuration = 0

    -- Initialize simplified tiler
    tiler.start()

    if config.window_memory and config.window_memory.enabled then
        window_memory.init(tiler)
        window_memory.setup_hotkeys() -- Optional, for manual capture/restore
    end

    if config.layout_manager and config.layout_manager.enabled then
        layout_manager.init(tiler)
    end

    -- Initialize Auto Tiler
    auto_tiler.init(config, tiler, window_memory, tiler.smart_placer, tiler.zone_calculator, tiler.monitors, tiler.window_actions)
    auto_tiler.setup_hotkeys()

    -- Initialize app switching
    appSwitcher.init_bindings(config.appCuts, config.hyperAppCuts, mash_app, HYPER)

    -- Initialize audio switcher
    audio_switcher.init(config, print)

    -- Initialize system hotkeys (window hints, reload, etc.)
    init_system_hotkeys()

    -- Initialize pomodoro (including its hotkeys)
    pom.init(config)

    -- Initialize debug system
    -- Note: tiler must be fully initialized before debug.init() is called
    debug.init(config, tiler, nil, nil, audio_switcher)

    -- Make debug globally accessible for console access
    _G.zt_debug = debug
    _G.zt_run_auto_tile = function() auto_tiler.tile_all_windows() end

    print("Hammerspoon configuration loaded successfully!")
    print("Debug commands available: type 'zt_debug.help()' for info")
end

-- Start the configuration
init()
