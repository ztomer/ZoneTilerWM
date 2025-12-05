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
        space_preview.init(config, space_manager, tiler.window_state, print)

        -- Initialize menubar indicator
        space_menubar.init(config, space_manager, space_preview, print)

        -- Set up Space switching hotkeys
        if config.spaces.hotkeys then
            for space_num = 1, 9 do
                local hotkey_name = "space_" .. space_num
                local hotkey_config = config.spaces.hotkeys[hotkey_name]

                if hotkey_config then
                    hs.hotkey.bind(hotkey_config[1], hotkey_config[2], function()
                        -- Get all spaces and switch to the Nth one
                        local all_spaces = space_manager.get_all_spaces()
                        if all_spaces then
                            -- Flatten and sort spaces
                            local space_list = {}
                            for _, spaces_for_screen in pairs(all_spaces) do
                                for _, space_id in ipairs(spaces_for_screen) do
                                    table.insert(space_list, space_id)
                                end
                            end
                            table.sort(space_list)

                            -- Switch to the requested space
                            if space_list[space_num] then
                                print("Switching to Space " .. space_num)
                                space_manager.switch_to_space(space_list[space_num])
                            else
                                print("Space " .. space_num .. " does not exist")
                            end
                        end
                    end)
                    print("Bound Ctrl+Shift+" .. space_num .. " to switch to Space " .. space_num)
                end
            end
        end

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
