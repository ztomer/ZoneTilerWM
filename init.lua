-- Hammerspoon configuration
local config = require "config"
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

-- Get key combinations from config
local mash = config.keys.mash
local mash_app = config.keys.mash_app
local mash_shift = config.keys.mash_shift
local HYPER = config.keys.HYPER

--[[
  Initializes custom keybindings
]]
local function init_custom_binding()
    -- Window hints shortcut
    hs.hotkey.bind(HYPER, '-', hs.hints.windowHints)

    -- Pomodoro bindings - using function wrappers to avoid errors
    hs.hotkey.bind(mash, '9', function()
        pom.enable()
    end)
    hs.hotkey.bind(mash, '0', function()
        pom.disable()
    end)
    hs.hotkey.bind(mash_shift, '0', function()
        pom.reset_work()
    end)

    -- Activity Monitor shortcut
    hs.hotkey.bind(HYPER, "=", function()
        appSwitcher.toggle_app("Activity Monitor")
    end)

    -- Hot reload configuration
    hs.hotkey.bind(mash_shift, "R", function()
        hs.reload()
        hs.alert.show("Config reloaded!")
    end)
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

    -- Initialize app switching
    appSwitcher.init_bindings(config.appCuts, config.hyperAppCuts, mash_app, HYPER)

    -- Initialize audio switcher
    audio_switcher.init(config, print)

    -- Initialize custom keybindings
    init_custom_binding()

    -- Initialize debug system
    -- Note: tiler must be fully initialized before debug.init() is called
    debug.init(config, tiler, nil, nil, audio_switcher)

    -- Make debug globally accessible for console access
    _G.zt_debug = debug

    print("Hammerspoon configuration loaded successfully!")
    print("Debug commands available: type 'zt_debug.help()' for info")
end

-- Start the configuration
init()
