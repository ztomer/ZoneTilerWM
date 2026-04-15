-- Reproduction script for ambiguous apps regression
-- Run with: lua tests/repro_ambiguous_apps.lua

-- 1. Setup Mock Environment
local mock_hs = require("tests.mock_hs")
_G.hs = mock_hs

-- Mock hs.application
local current_front_app = nil
local launch_or_focus_called_with = nil
local hide_called_for = nil
local menu_item_called_for = nil

mock_hs.application = {
    frontmostApplication = function()
        return current_front_app
    end,
    launchOrFocus = function(name)
        launch_or_focus_called_with = name
        return true
    end,
    infoForBundlePath = function() return {} end,
    get = function(name) return nil end,
}

-- Mock App Object
local function createApp(name)
    return {
        name = function() return name end,
        hide = function() hide_called_for = name end,
        selectMenuItem = function(self, item) menu_item_called_for = item end,
        activate = function() end,
        isFrontmost = function() return current_front_app and current_front_app:name() == name end
    }
end

-- 2. Load Modules
-- Ensure package path is correct
if not string.find(package.path, "?.lua") then
    package.path = package.path .. ";./?.lua"
end

-- We need to mock modules.config because loading real config might fail or be complicated
package.loaded["modules.config"] = {
    app_switcher = {
        hide_workaround_apps = {},
        ambiguous_apps = {
            {"notion", "notion calendar"},
            {"notion", "notion mail"}
        },
        special_app_mappings = {}
    },
    keys = {
        mash_app = {"shift", "ctrl"}
    }
}

local app_switcher = require("modules.app_switcher")

-- 3. Test Cases

local function run_test(test_name, setup_fn, action_fn, check_fn)
    print("Running check: " .. test_name)
    -- Reset state
    launch_or_focus_called_with = nil
    hide_called_for = nil
    menu_item_called_for = nil

    setup_fn()
    action_fn()

    local success, msg = check_fn()
    if success then
        print("[PASS] " .. test_name)
    else
        print("[FAIL] " .. test_name .. ": " .. msg)
        os.exit(1)
    end
end

print("=== Starting Ambiguous Apps Reproduction Tests ===")

-- Case 1: Front is "Notion", Toggle "Notion Calendar"
-- Expected: Launch "Notion Calendar". Should NOT hide Notion.
run_test(
    "Front: Notion, Action: Toggle Notion Calendar",
    function()
        current_front_app = createApp("Notion")
    end,
    function()
        app_switcher.toggle_app("Notion Calendar")
    end,
    function()
        if hide_called_for then
            return false, "Notion was hidden! (Incorrect substring match?)"
        end
        if launch_or_focus_called_with ~= "Notion Calendar" then
            return false, "Did not launch Notion Calendar. called with: " .. tostring(launch_or_focus_called_with)
        end
        return true
    end
)

-- Case 2: Front is "Notion Calendar", Toggle "Notion"
-- Expected: Launch "Notion". Should NOT hide Notion Calendar.
run_test(
    "Front: Notion Calendar, Action: Toggle Notion",
    function()
        current_front_app = createApp("Notion Calendar")
    end,
    function()
        app_switcher.toggle_app("Notion")
    end,
    function()
        if hide_called_for then
            return false, "Notion Calendar was hidden! (Ambiguity ignored?)"
        end
        if launch_or_focus_called_with ~= "Notion" then
            return false, "Did not launch Notion. called with: " .. tostring(launch_or_focus_called_with)
        end
        return true
    end
)

-- Case 3: Front is "Notion Calendar", Toggle "Notion Calendar"
-- Expected: Hide "Notion Calendar".
run_test(
    "Front: Notion Calendar, Action: Toggle Notion Calendar",
    function()
        current_front_app = createApp("Notion Calendar")
    end,
    function()
        app_switcher.toggle_app("Notion Calendar")
    end,
    function()
        if hide_called_for ~= "Notion Calendar" then
            return false, "Notion Calendar was not hidden."
        end
        if launch_or_focus_called_with then
            return false, "Should not have launched anything."
        end
        return true
    end
)


-- Case 4: Front is "Notion " (trailing space), Toggle "Notion Calendar"
-- Expected: Launch "Notion Calendar". Should NOT hide Notion.
run_test(
    "Front: 'Notion ' (WS), Action: Toggle Notion Calendar",
    function()
        current_front_app = createApp("Notion ")
    end,
    function()
        app_switcher.toggle_app("Notion Calendar")
    end,
    function()
        if hide_called_for then
            return false, "Notion (with space) was hidden! Ambiguity check failed."
        end
        if launch_or_focus_called_with ~= "Notion Calendar" then
            return false, "Did not launch Notion Calendar."
        end
        return true
    end
)

