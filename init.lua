-- Hammerspoon configuration
local config = require "config"

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

    -- Disable animation for speed
    hs.window.animationDuration = 0

    -- Load Spoons
    hs.loadSpoon("RoundedCorners")
    spoon.RoundedCorners:start()

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

    print("Hammerspoon configuration loaded successfully!")
end

-- Start the configuration
init()