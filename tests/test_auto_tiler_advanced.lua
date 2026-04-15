-- tests/test_auto_tiler_advanced.lua
-- Deep functional tests covering multi-monitor, deep ripples, and anchor protection.

local mock_hs = require("tests.mock_hs")
_G.hs = mock_hs

local auto_tiler = require("modules.auto_tiler")
local monitor_manager = require("modules.monitor_manager")
local zone_calculator = require("modules.zone_calculator")
local smart_placer = require("modules.smart_placer")
local window_actions = require("modules.window_actions")
local lru_cache = require("modules.lru_cache")

-- Config
local config = {
    tiler = {
        screen_detection = {
            patterns = {
                ["Screen.*"] = "4x3",
                ["DELL.*"] = "4x3"
            }
        },
        layouts = {
            ["4x3"] = {
                y = {"a1", "a3"},
                h = {"a1:b3"},
                j = {"b1:c3"},
                k = {"c1:d3"},
                ["overflow_test"] = {"z1", "z2"} -- dummy for overflow tests
            },
            ["dynamic"] = {
                p1 = {"a1"}, -- peripheral
                p2 = {"b1"}, -- closer
                p3 = {"b2:c3"} -- central
            },
            ["2x2"] = {
                j = {"a1:b2"}
            },
            ["default"] = {
                j = {"a1:b2"}
            }
        },
        grids = {
            ["4x3"] = {cols = 4, rows = 3},
            ["dynamic"] = {cols = 4, rows = 3},
            ["2x2"] = {cols = 2, rows = 2}
        },
        auto_tile_center_zones = {"j"},
        smart_placement = { enabled = true },
        debug = true
    },
    keys = {mash={"ctrl", "cmd"}, HYPER={"ctrl", "alt", "cmd", "shift"}},
    window_memory = { enabled = true },
    margins = { enabled = false }
}

-- Mocks
local window_memory = {
    get_ranked_preferences = function(app_name, mid) return {} end
}

local function setup_env(screens_info)
    -- Reset mocks
    local windows = {}
    mock_hs.window.allWindows = function() return windows end
    mock_hs.window.focusedWindow = function() return nil end
    mock_hs.inspect = function(val) return tostring(val) end
    mock_hs.geometry = {
        intersectionRect = function(r1, r2)
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

    local screens = {}
    for i, s_info in ipairs(screens_info or {{id=1, uuid="m1"}}) do
        local screen = {
            id = function() return s_info.id end,
            frame = function() return s_info.frame or {x=0,y=0,w=3840,h=2160} end,
            name = function() return "Screen " .. tostring(i) end,
            getUUID = function() return s_info.uuid or ("uuid-" .. tostring(i)) end
        }
        table.insert(screens, screen)
    end
    mock_hs.screen.allScreens = function() return screens end
    mock_hs.screen.find = function(id)
        for _, s in ipairs(screens) do if s:id() == id then return s end end
        return screens[1]
    end

    monitor_manager.init(function() end)
    zone_calculator.init(config, config.margins, function() end)

    local mock_wsm = {
        get=function() end, set=function() end, get_windows_in_zone=function() return {} end, cleanup=function() end
    }

    local placement_strategy = require("modules.placement_strategy")
    placement_strategy.init(config, {}, mock_wsm, function() end)

    window_actions.init(config, monitor_manager, zone_calculator, mock_wsm, placement_strategy, {}, function() end)
    smart_placer.init(config, monitor_manager, zone_calculator, mock_wsm, window_actions, function() end)
    auto_tiler.init(config, {set_reposition_callback=function() end}, window_memory, smart_placer, zone_calculator, monitor_manager, window_actions)

    for _, s in ipairs(screens) do
        zone_calculator.create_for_monitor(monitor_manager.get_id(s), s)
    end
end

local function create_win(id, app_name, screen_idx, frame)
    local screen = mock_hs.screen.allScreens()[screen_idx or 1]
    local win = {
        _f = frame or {x=0,y=0,w=100,h=100}
    }
    win.id = function() return id end
    win.application = function() return { name = function() return app_name end } end
    win.isStandard = function() return true end
    win.isMinimized = function() return false end
    win.isVisible = function() return true end
    win.screen = function() return screen end
    win.frame = function() return win._f end
    win.setFrame = function(_, f) win._f = f return true end
    win.moveToScreen = function(_, s) win._s = s return true end
    win.raise = function() end
    win.focus = function() end
    win.title = function() return app_name end

    table.insert(mock_hs.window.allWindows(), win)
    return win
end

-- TEST: Multi-Monitor Independent Tiling
local function test_multi_monitor()
    print("[Test] Multi-monitor independence...")
    setup_env({
        {id=1, uuid="m1", frame={x=0, y=0, w=1000, h=1000}},
        {id=2, uuid="m2", frame={x=1000, y=0, w=1000, h=1000}}
    })

    local w1 = create_win(1, "App1", 1) -- Screen 1
    local w2 = create_win(2, "App2", 2) -- Screen 2

    window_memory.get_ranked_preferences = function(app, mid)
        return {{zone_key="y", tile_index=1}}
    end

    auto_tiler.tile_all_windows()

    assert(w1._f.x < 1000, "W1 should be on Monitor 1")
    assert(w2._f.x >= 1000, "W2 should be on Monitor 2")
    print("  OK")
end

-- TEST: Deep Ripple (A -> B -> C)
local function test_deep_ripple()
    print("[Test] Deep Ripple (Chain of 3)...")
    setup_env()

    local w1 = create_win(1, "App1")
    local w2 = create_win(2, "App2")
    local w3 = create_win(3, "App3")

    -- Everyone wants y:1
    window_memory.get_ranked_preferences = function(app, mid)
        return {{zone_key="y", tile_index=1}}
    end

    auto_tiler.tile_all_windows()

    -- We expect them to be at y:1, y:2, and y:3 (overflow dependent)
    -- But our mock config only has y:1 and y:2.
    -- y:1 -> y:2 -> j:1 (overflow)

    local y_tiles = zone_calculator.get(1, "y")
    local j_tiles = zone_calculator.get(1, "j")

    local frames = {w1._f, w2._f, w3._f}
    local has_y1, has_y2, has_j1 = false, false, false

    for i, f in ipairs(frames) do
        print(string.format("  Win%d final frame: x=%d y=%d", i, f.x, f.y))
        if math.abs(f.x - y_tiles[1].x) < 2 and math.abs(f.y - y_tiles[1].y) < 2 then has_y1 = true end
        if math.abs(f.x - y_tiles[2].x) < 2 and math.abs(f.y - y_tiles[2].y) < 2 then has_y2 = true end
        if math.abs(f.x - j_tiles[1].x) < 2 and math.abs(f.y - j_tiles[1].y) < 2 then has_j1 = true end
    end

    assert(has_y1, "Missing y:1")
    assert(has_y2, "Missing y:2 (first ripple)")
    assert(has_j1, "Missing j:1 (second ripple overflow)")
    print("  OK")
end

-- TEST: Anchor Protection (Focused window cannot be bumped)
local function test_anchor_protection()
    print("[Test] Anchor Protection...")
    setup_env()

    -- W1 is focused and anchored in j:1
    local w1 = create_win(1, "FocusedApp")
    mock_hs.window.focusedWindow = function() return w1 end

    -- W2 wants j:1
    local w2 = create_win(2, "BumperApp")
    window_memory.get_ranked_preferences = function(app, mid)
        if app == "BumperApp" then return {{zone_key="j", tile_index=1}} end
        return {}
    end

    auto_tiler.tile_all_windows()

    -- W1 must stay in j:1
    local j1 = zone_calculator.get(1, "j")[1]
    assert(w1._f.x == j1.x and w1._f.y == j1.y, "Focused anchor was evicted!")
    -- W2 should have been pushed elsewhere (either smart place or next index)
    assert(not (w2._f.x == j1.x and w2._f.y == j1.y), "BumperApp managed to overlap anchor!")
    print("  OK")
end

-- TEST: Queue Optimization (Ripple + Compaction)
local function test_optimization()
    print("[Test] Move Queue Optimization...")
    setup_env()

    -- App1 is at y:2
    -- App2 moves to y:1, bumping App1 to y:2
    -- But then App2 is moved elsewhere (focus?), leaving y:1 empty
    -- Compaction should move App1 back to y:1
    -- We want to ensure window_actions is only called ONCE for App1's final spot.

    local call_count = 0
    local original_pos = window_actions.position_window_from_memory
    window_actions.position_window_from_memory = function(...)
        call_count = call_count + 1
        return original_pos(...)
    end

    local w1 = create_win(1, "App1")
    window_memory.get_ranked_preferences = function(app)
        return {{zone_key="y", tile_index=2}}
    end

    auto_tiler.tile_all_windows()

    -- In this simple run, App1 should just be at y:1 (Compaction)
    assert(call_count == 1, "Redundant moves executed! Count: " .. call_count)
    print("  OK")
end

-- TEST: Dynamic Overflow (Peripheral -> Central)
local function test_dynamic_overflow()
    print("[Test] Dynamic Overflow (p1 -> p2 -> p3)...")
    -- 1. Update config FIRST
    config.tiler.screen_detection.patterns["Screen.*"] = "dynamic"

    -- 2. Setup env (restarts monitor_manager and zone_calculator)
    setup_env({
        {id=1, uuid="m1", frame={x=0, y=0, w=1000, h=1000}}
    })

    local w1 = create_win(1, "App1")
    local w2 = create_win(2, "App2")
    local w3 = create_win(3, "App3")

    -- Everyone wants p1:1
    window_memory.get_ranked_preferences = function(app, mid)
        return {{zone_key="p1", tile_index=1}}
    end

    auto_tiler.tile_all_windows()

    -- p1 is full (1 tile).
    -- If dynamic overflow works, w2 should be in p2 and w3 in p3.
    -- Currently it should FAIL to overflow from p1 because p1 is not in DEFAULT_OVERFLOWS.

    local mid = monitor_manager.get_id(mock_hs.screen.allScreens()[1])
    local p1_tiles = zone_calculator.get(mid, "p1")
    local p2_tiles = zone_calculator.get(mid, "p2")
    local p3_tiles = zone_calculator.get(mid, "p3")

    local f1, f2, f3 = w1._f, w2._f, w3._f

    assert(f1.x == p3_tiles[1].x and f1.y == p3_tiles[1].y, "W1 should have rippled to p3")
    assert(f2.x == p2_tiles[1].x and f2.y == p2_tiles[1].y, "W2 should have rippled to p2")
    assert(f3.x == p1_tiles[1].x and f3.y == p1_tiles[1].y, "W3 should be in p1")

    -- This is where it will fail currently (Pass 1 won't place them, Pass 2 might)
    -- But we want to ensure Pass 1 (Ripple) handles the overflow.
    -- For now, let's just see where they end up.

    local is_f2_in_p2 = math.abs(f2.x - p2_tiles[1].x) < 2 and math.abs(f2.y - p2_tiles[1].y) < 2
    local is_f3_in_p3 = math.abs(f3.x - p3_tiles[1].x) < 2 and math.abs(f3.y - p3_tiles[1].y) < 2

    if not is_f2_in_p2 or not is_f3_in_p3 then
        print("  FAILED (Expected): Windows did not overflow logically to p2/p3")
        print("  W2 is at:", f2.x, f2.y, "Target P2:", p2_tiles[1].x, p2_tiles[1].y)
        print("  W3 is at:", f3.x, f3.y, "Target P3:", p3_tiles[1].x, p3_tiles[1].y)
    else
        print("  OK")
    end
end

-- TEST: Screen Isolation (Tile only focused screen)
local function test_screen_isolation()
    print("[Test] Screen Isolation...")
    -- 1. Reset layout pattern to something known
    config.tiler.screen_detection.patterns["Screen.*"] = "4x3"

    setup_env({
        {id=1, uuid="m1", frame={x=0, y=0, w=1000, h=1000}},
        {id=2, uuid="m2", frame={x=1000, y=0, w=1000, h=1000}}
    })

    -- W1 on Monitor 1 (Initial frame)
    local w1 = create_win(1, "App1", 1, {x=100, y=100, w=100, h=100})
    -- W2 on Monitor 2 (Initial frame)
    local w2 = create_win(2, "App2", 2, {x=1100, y=100, w=100, h=100})

    -- W2 is focused
    mock_hs.window.focusedWindow = function() return w2 end

    -- Preferences: Both want y:1 on their respective screens
    window_memory.get_ranked_preferences = function(app, mid)
        return {{zone_key="y", tile_index=1}}
    end

    -- Call Local Tile
    auto_tiler.tile_focused_screen()

    -- W2 should have moved
    local j1_m2 = zone_calculator.get(2, "j")[1]
    assert(math.abs(w2._f.x - j1_m2.x) < 2, "W2 should have anchored to center on Monitor 2")

    -- W1 should NOT have moved
    assert(w1._f.x == 100 and w1._f.y == 100, "W1 was incorrectly tiled despite being on a different screen!")

    print("  OK")
end

-- Run
local function run()
    local tests = {test_multi_monitor, test_deep_ripple, test_anchor_protection, test_optimization, test_dynamic_overflow, test_screen_isolation}
    for _, t in ipairs(tests) do t() end
    print("\nADVANCED TESTS PASS")
end

run()
