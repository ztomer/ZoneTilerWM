-- tests/test_auto_tiler_functional.lua
-- Comprehensive functional tests for auto_tiler logic.

local mock_hs = require("tests.mock_hs")
_G.hs = mock_hs

local auto_tiler = require("modules.auto_tiler")
local monitor_manager = require("modules.monitor_manager")
local zone_calculator = require("modules.zone_calculator")
local smart_placer = require("modules.smart_placer")
local window_actions = require("modules.window_actions")
local lru_cache = require("modules.lru_cache")

-- Mocks and Config
local config = {
    tiler = {
        layouts = {
            ["4x3"] = {
                y = {"a1", "a3"},
                h = {"a1:b3"},
                j = {"b1:c3"},
                k = {"c1:d3"},
                u = {"b1:c1"},
                n = {"a3:b3"},
                [","] = {"c3:d3"},
                ["0"] = {"a1:d3"}
            }
        },
        grids = {
            ["4x3"] = {cols = 4, rows = 3}
        },
        auto_tile_deduction_excludes = {"0"},
        smart_placement = { enabled = true }
    },
    keys = {mash={"ctrl", "cmd"}, HYPER={"ctrl", "alt", "cmd", "shift"}},
    window_memory = { enabled = true },
    margins = { enabled = false }
}

-- Mock Window Memory
local window_memory = {
    get_ranked_preferences = function(app_name, mid) return {} end
}

-- Setup helper
local function setup_env()
    -- Reset mocks
    local windows = {}
    mock_hs.window.allWindows = function() return windows end
    mock_hs.window.focusedWindow = function() return nil end
    mock_hs.inspect = function(val) return tostring(val) end
    mock_hs.geometry = {
        intersectionRect = function(r1, r2)
            -- Simple intersection check for tests
            local x1 = math.max(r1.x, r2.x)
            local y1 = math.max(r1.y, r2.y)
            local x2 = math.min(r1.x + r1.w, r2.x + r2.w)
            local y2 = math.min(r1.y + r1.h, r2.y + r2.h)
            if x1 < x2 and y1 < y2 then
                return {x=x1, y=y1, w=x2-x1, h=y2-y1, area = (x2-x1)*(y2-y1)}
            else
                return {x=0, y=0, w=0, h=0, area=0}
            end
        end,
        rect = function(x,y,w,h) return {x=x,y=y,w=w,h=h} end
    }

    -- Mock screen
    local screen = {
        id = function() return 1 end,
        frame = function() return {x=0,y=0,w=3840,h=2160} end,
        name = function() return "DELL U3223QE" end,
        getUUID = function() return "mock-uuid" end
    }
    mock_hs.screen.allScreens = function() return {screen} end
    mock_hs.screen.find = function() return screen end

    -- Initialize modules
    monitor_manager.init(print)
    zone_calculator.init(config, config.margins, print)

    local mock_wsm = {
        get=function() end,
        set=function() end,
        get_windows_in_zone=function() return {} end,
        cleanup=function() end
    }

    local placement_strategy = require("modules.placement_strategy")
    placement_strategy.init(config, {}, mock_wsm, print)

    window_actions.init(config, monitor_manager, zone_calculator, mock_wsm, placement_strategy, {}, print)
    smart_placer.init(config, monitor_manager, zone_calculator, mock_wsm, window_actions, print)
    auto_tiler.init(config, {set_reposition_callback=function() end}, window_memory, smart_placer, zone_calculator, monitor_manager, window_actions)

    -- Create zones for the mock monitor
    local mid = monitor_manager.get_id(screen)
    zone_calculator.create_for_monitor(mid, screen)

    return screen
end

local function create_win(id, app_name, focused, frame)
    local win = {
        id = function() return id end,
        application = function() return { name = function() return app_name end } end,
        isStandard = function() return true end,
        isMinimized = function() return false end,
        isVisible = function() return true end,
        screen = function() return mock_hs.screen.allScreens()[1] end,
        frame = function() return frame or {x=0,y=0,w=100,h=100} end,
        setFrame = function(self, f) self._f = f return true end,
        raise = function() end,
        focus = function() end,
        title = function() return app_name end
    }
    if focused then mock_hs.window.focusedWindow = function() return win end end
    table.insert(mock_hs.window.allWindows(), win)
    return win
end

-- TEST 1: Focused window placement
local function test_focused_placement()
    print("[Test] Focused placement...")
    setup_env()
    local win = create_win(1, "CotEditor", true)

    auto_tiler.tile_all_windows()

    -- Focused window should be in zone j (center) based on geometric deduction
    assert(win._f ~= nil, "Focused window should have been moved")
    -- Check if it's center-ish. Zone j:1 in 4x3 is roughly x=965 width=1910
    assert(win._f.x > 0, "Focused window should not be at edge")
    print("  OK")
end

-- TEST 2: Ripple logic
local function test_ripple()
    print("[Test] Ripple moves...")
    setup_env()

    -- Create two windows that both want y:1
    local win1 = create_win(1, "App1", false)
    local win2 = create_win(2, "App2", false)

    -- Mock memory such that App1 and App2 both prefer y:1
    window_memory.get_ranked_preferences = function(app_name, mid)
        return {{zone_key="y", tile_index=1}}
    end

    auto_tiler.tile_all_windows()

    local y1 = zone_calculator.get(1, "y")[1]
    local y2 = zone_calculator.get(1, "y")[2]

    local frames = {win1._f, win2._f}
    local has_y1 = false
    local has_y2 = false

    for _, f in ipairs(frames) do
        if f then
            if math.abs(f.y - y1.y) < 1 then has_y1 = true end
            if math.abs(f.y - y2.y) < 1 then has_y2 = true end
        end
    end

    assert(has_y1, "One window should be at y:1")
    assert(has_y2, "One window should have rippled to y:2")
    print("  OK")
end

-- TEST 3: Compaction
local function test_compaction()
    print("[Test] Compaction (Gravity)...")
    setup_env()

    -- Create a window that prefers y:2 but y:1 is empty
    local win = create_win(1, "App", false)
    window_memory.get_ranked_preferences = function(app_name, mid)
        return {{zone_key="y", tile_index=2}}
    end

    auto_tiler.tile_all_windows()

    -- Should be moved to y:1 by compaction
    local y1 = zone_calculator.get(1, "y")[1]
    assert(math.abs(win._f.y - y1.y) < 1, "Window should have compacted to y:1")
    print("  OK")
end

-- TEST 4: Smart Placement (No Memory)
local function test_smart_placement()
    print("[Test] Smart placement (fallback)...")
    setup_env()

    -- Window with no memory
    local win = create_win(1, "NewApp", false)
    window_memory.get_ranked_preferences = function() return {} end

    auto_tiler.tile_all_windows()

    assert(win._f ~= nil, "Window should be placed by smart placer")
    print("  OK")
end

-- Run all tests
local function run_tests()
    local success, err = pcall(test_focused_placement)
    if not success then print("FAILED: " .. tostring(err)) os.exit(1) end

    success, err = pcall(test_ripple)
    if not success then print("FAILED: " .. tostring(err)) os.exit(1) end

    success, err = pcall(test_compaction)
    if not success then print("FAILED: " .. tostring(err)) os.exit(1) end

    success, err = pcall(test_smart_placement)
    if not success then print("FAILED: " .. tostring(err)) os.exit(1) end

    print("\nALL PASS")
end

run_tests()
