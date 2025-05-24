-- App switching module for Hammerspoon
local config = require "config"
local appSwitcher = {}

-- Cache frequently accessed functions
local appLaunchOrFocus = hs.application.launchOrFocus

-- Get app switcher settings from config
local hide_workaround_apps = config.app_switcher.hide_workaround_apps
local special_app_mappings = config.app_switcher.special_app_mappings
local ambiguous_apps = config.app_switcher.ambiguous_apps

--[[
  Determines if two app names are ambiguous (one might be part of another)

  @param app_name (string) First application name to compare
  @param title (string) Second application name to compare
  @return (boolean) true if the app names are known to be ambiguous, false otherwise
]]
local function ambiguous_app_name(app_name, title)
    -- Some application names are ambiguous - may be part of a different app name or vice versa.
    -- this function disambiguates some known applications.
    for _, tuple in ipairs(ambiguous_apps) do
        if (app_name == tuple[1] and title == tuple[2]) or (app_name == tuple[2] and title == tuple[1]) then
            return true
        end
    end

    return false
end

--[[
  Toggles an application between focused and hidden states

  @param app (string) The name of the application to toggle
]]
function appSwitcher.toggle_app(app)
    -- Get information about currently focused app and target app
    local front_app = hs.application.frontmostApplication()
    local front_app_name = front_app:name()
    local front_app_lower = front_app_name:lower()
    local target_app_name = app
    local target_app_lower = app:lower()

    -- Check if the front app is the one we're trying to toggle
    local switching_to_same_app = false

    -- Handle special app mappings (launch name ≠ display name)
    if special_app_mappings[target_app_lower] == front_app_lower or (target_app_lower == front_app_lower) then
        switching_to_same_app = true
    end

    -- Check if they're related apps with different naming conventions
    if not ambiguous_app_name(front_app_lower, target_app_lower) then
        if string.find(front_app_lower, target_app_lower) or string.find(target_app_lower, front_app_lower) then
            switching_to_same_app = true
        end
    end

    if switching_to_same_app then
        -- Handle apps that need special hiding via menu
        for _, workaround_app in ipairs(hide_workaround_apps) do
            if front_app_name == workaround_app then
                front_app:selectMenuItem("Hide " .. front_app_name)
                return
            end
        end

        -- Normal hiding
        front_app:hide()
        return
    end

    -- Not on target app, so launch or focus it
    appLaunchOrFocus(target_app_name)
end

--[[
  Displays help screen with keyboard shortcuts
]]
function appSwitcher.display_help(appCuts, hyperAppCuts)
    local help_text = nil

    if not help_text then
        local t = {"Keyboard shortcuts\n", "--------------------\n"}

        for key, app in pairs(appCuts) do
            table.insert(t, "Control + CMD + " .. key .. "\t :\t" .. app .. "\n")
        end

        for key, app in pairs(hyperAppCuts) do
            table.insert(t, "HYPER + " .. key .. "\t:\t" .. app .. "\n")
        end

        help_text = table.concat(t)
    end

    hs.alert.show(help_text, 2)
end

--[[
  Initializes application shortcut keybindings
]]
function appSwitcher.init_bindings(appCuts, hyperAppCuts, mash_app, HYPER)
    for key, app in pairs(appCuts) do
        hs.hotkey.bind(mash_app, key, function()
            appSwitcher.toggle_app(app)
        end)
    end

    for key, app in pairs(hyperAppCuts) do
        hs.hotkey.bind(HYPER, key, function()
            appSwitcher.toggle_app(app)
        end)
    end

    -- Help binding
    hs.hotkey.bind(mash_app, ';', function()
        appSwitcher.display_help(appCuts, hyperAppCuts)
    end)
end

return appSwitcher
