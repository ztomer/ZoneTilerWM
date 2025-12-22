-- App switching module for Hammerspoon
local config = require "modules.config"
local appSwitcher = {}

-- Cache frequently accessed functions
local appLaunchOrFocus = hs.application.launchOrFocus

-- Get app switcher settings from config
local hide_workaround_apps = config.app_switcher.hide_workaround_apps
local special_app_mappings = config.app_switcher.special_app_mappings
local ambiguous_apps = config.app_switcher.ambiguous_apps

-- Pre-process ambiguous_apps for efficient and case-insensitive lookup
local processed_ambiguous_pairs = {}
if ambiguous_apps then
    for _, tuple in ipairs(ambiguous_apps) do
        if type(tuple) == "table" and tuple[1] and tuple[2] and type(tuple[1]) == "string" and type(tuple[2]) ==
            "string" then
            local app1_lower = tuple[1]:lower()
            local app2_lower = tuple[2]:lower()
            local key
            if app1_lower < app2_lower then
                key = app1_lower .. "||" .. app2_lower
            else
                key = app2_lower .. "||" .. app1_lower
            end
            processed_ambiguous_pairs[key] = true
        end
    end
end

local processed_special_app_mappings = {}
if special_app_mappings then
    for key, value in pairs(special_app_mappings) do
        if type(key) == "string" and type(value) == "string" then
            processed_special_app_mappings[key:lower()] = value:lower()
        end
    end
end

--[[
  Determines if two app names are ambiguous (one might be part of another)

  @param app_name (string) First application name to compare
  @param title (string) Second application name to compare
  @return (boolean) true if the app names are known to be ambiguous, false otherwise
]]
local function ambiguous_app_name(app_name_lower, title_lower)
    -- Some application names are ambiguous - may be part of a different app name or vice versa.
    -- this function disambiguates some known applications.
    if not next(processed_ambiguous_pairs) then
        return false
    end -- Empty or nil

    local key
    if app_name_lower < title_lower then
        key = app_name_lower .. "||" .. title_lower
    else
        key = title_lower .. "||" .. app_name_lower
    end
    return processed_ambiguous_pairs[key] == true
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
    if processed_special_app_mappings[target_app_lower] == front_app_lower or (target_app_lower == front_app_lower) then
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
function appSwitcher.init_bindings(appCuts, hyperAppCuts)
    -- Helper to resolve modifier string options
    local function get_mods(mod_entry)
        -- Handle string alias "HYPER" (if somehow passed as string)
        if type(mod_entry) == "string" and config.keys[mod_entry] then
             return config.keys[mod_entry]
        end

        -- Handle table array ["HYPER"] or ["mash_app"]
        -- Case 1: Pre-resolved nested alias (Global Resolution result: [ {mods} ])
        if type(mod_entry) == "table" and #mod_entry == 1 and type(mod_entry[1]) == "table" then
            return mod_entry[1]
        end

        -- Case 2: Standard alias wrapper that wasn't resolved globally? (Shouldn't happen with string aliases, but defensive)
        if type(mod_entry) == "table" and #mod_entry == 1 and type(mod_entry[1]) == "string" and config.keys[mod_entry[1]] then
            return config.keys[mod_entry[1]]
        end

        return mod_entry
    end

    local function bind_group(group_table)
        if not group_table then return end

        -- Extract modifier, default to empty if missing (safety)
        local raw_mod = group_table.modifier
        if not raw_mod then
            print("Warning: No 'modifier' key found in app shortcuts group")
            return
        end

        local mods = get_mods(raw_mod)

        for key, app in pairs(group_table) do
            if key ~= "modifier" and app and app:match("%S") then
                hs.hotkey.bind(mods, key, function()
                    appSwitcher.toggle_app(app)
                end)
            end
        end
    end

    bind_group(appCuts)
    bind_group(hyperAppCuts)

    -- Help binding (revisit this: where should help be bound? reusing mash_app from config for now or defining explicitly?)
    -- Assuming a standard fallback for help or keeping it tied to one of the modifiers.
    -- For now, let's look up mash_app from config directly since we aren't passing it in.
    local mash_app = config.keys.mash_app
    hs.hotkey.bind(mash_app, ';', function()
        appSwitcher.display_help(appCuts, hyperAppCuts)
    end)
end

return appSwitcher
