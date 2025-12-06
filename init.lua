-- Hammerspoon configuration
local config = require "config"
local config_validator = require "modules.config_validator"

-- Load modules
local pom = require "modules.pomodoor"
local tiler = require "modules.tiler"
local appSwitcher = require "modules.app_switcher"
local window_memory = require "modules.window_memory"
local audio_switcher = require "modules.audio_switcher"
local layout_manager = require "modules.layout_manager"

-- Load Spaces modules
local space_storage = require "modules.space_storage"
local space_manager = require "modules.space_manager"
local space_preview = require "modules.space_preview"
local space_menubar = require "modules.space_menubar"

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

    -- Load Spoons
    -- hs.loadSpoon("RoundedCorners")
    -- spoon.RoundedCorners:start()

    -- Initialize simplified tiler
    tiler.start()

    if config.window_memory and config.window_memory.enabled then
        window_memory.init(tiler)
        window_memory.setup_hotkeys() -- Optional, for manual capture/restore
    end

    if config.layout_manager and config.layout_manager.enabled then
        layout_manager.init(tiler)
    end

    -- Initialize Spaces (macOS Mission Control integration)
    if config.spaces and config.spaces.enabled then
        print("Initializing Spaces support...")

        -- Initialize storage first
        space_storage.init(config, print)

        -- Initialize core space manager
        space_manager.init(config, tiler, tiler.monitor_manager, window_memory, space_storage, print)

        -- Initialize preview (must be before menubar for hover to work)
        if config.spaces.preview and config.spaces.preview.enabled then
            space_preview.init(config, space_manager, tiler.window_state, print)
            print("Space preview enabled")
        end

        -- Initialize menubar indicator
        local preview_module = (config.spaces.preview and config.spaces.preview.enabled) and space_preview or nil
        space_menubar.init(config, space_manager, preview_module, print)

        -- Spaceman approach: Monitor keypresses without blocking them
        -- Use eventtap (like NSEvent.addGlobalMonitorForEvents) to detect space switches
        -- Return false to let Mission Control receive the keypress
        -- Poll after 200ms to detect the actual space change

        -- Build shortcut lookup table
        local space_shortcuts = {}
        if config.spaces.hotkeys then
            for space_num = 1, 9 do
                local hotkey_name = "space_" .. space_num
                local hotkey_config = config.spaces.hotkeys[hotkey_name]
                if hotkey_config then
                    local mods_str = table.concat(hotkey_config[1], "+")
                    local key_combo = mods_str .. "+" .. hotkey_config[2]
                    space_shortcuts[key_combo] = space_num
                end
            end
        end

        -- Event tap to monitor (not block) space switch shortcuts
        local space_tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
            local flags = event:getFlags()
            local keycode = event:getKeyCode()
            local key = hs.keycodes.map[keycode]

            -- Build modifier+key string
            local mods = {}
            if flags.ctrl then table.insert(mods, "ctrl") end
            if flags.shift then table.insert(mods, "shift") end
            if flags.alt then table.insert(mods, "alt") end
            if flags.cmd then table.insert(mods, "cmd") end

            local key_combo = table.concat(mods, "+") .. "+" .. (key or "")
            local space_num = space_shortcuts[key_combo]

            if space_num then
                print("🎯 Detected Space " .. space_num .. " shortcut: " .. key_combo)

                -- Poll after Mission Control animation to update state
                hs.timer.doAfter(0.2, function()
                    space_manager.get_current_space()  -- This updates the state
                end)
            end

            -- CRITICAL: Return false to pass event through to Mission Control!
            return false
        end)

        space_tap:start()
        print("✓ Space shortcut monitor started (passthrough mode)")

        print("Spaces support initialized")
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
