-- test_auto_tiler.lua
local function print_test(name) print("[TEST] " .. name) end
local function assert_eq(a, b, msg)
    if a ~= b then
        print("FAIL: " .. (msg or "") .. " Expected " .. tostring(b) .. ", got " .. tostring(a))
        os.exit(1)
    else
        print("PASS: " .. (msg or ""))
    end
end
local function assert_true(a, msg)
    if not a then
        print("FAIL: " .. (msg or "") .. " Expected true")
        os.exit(1)
    else
        print("PASS: " .. (msg or ""))
    end
end

-- Mock HS
local mock_hs = require "tests.mock_hs"
local hs = mock_hs

-- Mock Data
local mock_screens = {}
local mock_windows = {}

mock_hs.screen.allScreens = function() return mock_screens end
mock_hs.window.allWindows = function() return mock_windows end

-- Mock Window Filter (needed by smart_placer)
mock_hs.window.filter.new = function()
    return {
        setScreens = function(self, s) return self end,
        getWindows = function() return mock_windows end,
        subscribe = function() end
    }
end
mock_hs.alert = {
    show = function(msg) print("Mock Alert: " .. msg) end
}

-- Load Modules under test
local auto_tiler = require "modules.auto_tiler"
-- Mock dependencies
local mock_tiler = {
    window_actions = {}
}
local mock_mm = {
    get_id = function(screen) return screen._id end
}
local mock_wm = {
    get_remembered_position = function(app, mid) return nil end
}
local mock_zc = {
    get = function(mid, zk) return nil end,
    get_layout_config = function() return {rows=2, cols=2}, "2x2" end
}

-- Mock Smart Placer (we use the real logic but mock its deps)
local real_smart_placer = require "modules.smart_placer"
local mock_wa = {
    position_window_from_memory = function() return true end
}
-- We init smart placer with our mocks (Deferred until config is defined)
-- real_smart_placer.init(mock_config, mock_mm, mock_zc, {}, mock_wa, function(...) end)

local mock_config = {
    tiler = {
        smart_placement = { enabled = true, exclude_apps = {} },
        layouts = {
            ["2x2"] = {
                ["1"] = {"a1"}, ["2"] = {"b1"}, ["3"] = {"a2"}, ["4"] = {"b2"}
            }
        }
    },
    window_memory = { excluded_apps = {} }
}

-- Init Smart Placer now that config is ready
real_smart_placer.init(mock_config, mock_mm, mock_zc, {}, mock_wa, function(...) end)

-- Setup Auto Tiler
auto_tiler.init(mock_config, mock_tiler, mock_wm, real_smart_placer, mock_zc, mock_mm, mock_wa)

-- Test Helpers
local function create_screen(id, name, frame)
    local s = {
        _id = id,
        _name = name,
        _frame = frame,
        name = function(self) return self._name end,
        frame = function(self) return self._frame end,
        getUUID = function(self) return self._id end,
        id = function(self) return self._id end -- Added id() method
    }
    table.insert(mock_screens, s)
    return s
end

local function create_window(id, app, screen, frame)
    local w = {
        _id = id,
        _app = app,
        _screen = screen,
        _frame = frame,
        id = function(self) return self._id end,
        title = function(self) return self._app end,
        application = function(self) return { name = function() return self._app end } end,
        screen = function(self) return self._screen end,
        frame = function(self) return self._frame end,
        isStandard = function() return true end,
        isMinimized = function() return false end
    }
    table.insert(mock_windows, w)
    return w
end

----------------------------------------------------------------
-- TESTS
----------------------------------------------------------------

-- SCENARIO 1: Memory Priority
print_test("Memory Priority")
mock_screens = {}
mock_windows = {}

local s1 = create_screen("screen1", "Main", {x=0,y=0,w=1000,h=1000})
-- Zone 1: 0,0 500x500
-- Zone 2: 500,0 500x500
mock_zc.get = function(mid, zk)
    -- Simple 2x2 simulation
    if zk == "1" then return {{x=0,y=0,w=500,h=500}} end
    if zk == "2" then return {{x=500,y=0,w=500,h=500}} end
    return nil
end

mock_wm.get_remembered_position = function(app, mid)
    if app == "AppA" then return {zone_key="1", tile_index=1} end
    return nil
end

local moved_windows = {}
mock_wa.position_window_from_memory = function(win, mid, zk, idx)
    table.insert(moved_windows, {id=win:id(), zk=zk, idx=idx})
end

local wA = create_window(1, "AppA", s1, {x=10,y=10,w=100,h=100})
local wB = create_window(2, "AppB", s1, {x=10,y=10,w=100,h=100})

auto_tiler.tile_all_windows()

assert_eq(#moved_windows, 2, "Should move 2 windows")
local foundA = false
for _, m in ipairs(moved_windows) do
    if m.id == 1 then
        assert_eq(m.zk, "1", "AppA should go to zone 1 (Memory)")
        foundA = true
    end
end
assert_true(foundA, "AppA was moved")


-- SCENARIO 2: Smart Fill (AppB should avoid Zone 1)
print_test("Smart Fill Non-Overlap")
-- AppA took Zone 1 (0,0,500,500).
-- AppB (no memory) should find largest free space.
-- Available: Zone 2 (500,0,500,500), Zone 3...
-- In our mock config, we defined zones 1,2,3,4.
-- Zone 1 is occupied by AppA (from memory).
-- smart_placer should pick Zone 2 (or 3 or 4).

local foundB = false
for _, m in ipairs(moved_windows) do
    if m.id == 2 then
        assert_true(m.zk ~= "1", "AppB should NOT be in zone 1")
        print("AppB moved to " .. m.zk)
        foundB = true
    end
end
assert_true(foundB, "AppB was moved")

-- SCENARIO 3: Focused Window
print_test("Focused Window Priority")
mock_screens = {}
mock_windows = {}
moved_windows = {} -- Reset
s1 = create_screen("screen1", "Main", {x=0,y=0,w=1000,h=1000})

-- Mock Zone 0 (Center)
mock_zc.get = function(mid, zk)
    if zk == "0" then return {{x=250,y=250,w=500,h=500}} end -- Center tile
    if zk == "j" then return {{x=250,y=250,w=500,h=500}} end -- Fallback Center
    if zk == "1" then return {{x=0,y=0,w=500,h=500}} end
    return nil
end

local wC = create_window(3, "AppC", s1, {x=10,y=10,w=100,h=100})
-- Mock wC as focused
hs.window.focusedWindow = function() return wC end

auto_tiler.tile_all_windows()

local foundC = false
for _, m in ipairs(moved_windows) do
    if m.id == 3 then
        assert_eq(m.zk, "0", "AppC (Focused) should go to zone 0 (Center)")
        foundC = true
    end
end
assert_true(foundC, "AppC was moved")

-- SCENARIO 4: Cycling & Fitting
print_test("Cycling & Fitting")
mock_screens = {}
mock_windows = {}
moved_windows = {} -- Reset
s1 = create_screen("screen1", "Main", {x=0,y=0,w=1000,h=1000})

-- Mock Zone 0 with multiple tiles of different sizes
mock_zc.get = function(mid, zk)
    if zk == "0" then return {
        {x=0,y=0,w=1000,h=1000}, -- Tile 1: Huge (1M area)
        {x=250,y=250,w=500,h=500}, -- Tile 2: Medium (250k area)
        {x=0,y=0,w=100,h=100}      -- Tile 3: Tiny (10k area)
    } end
    return nil
end

-- Create focused window that matches Tile 2 size roughly (300x300 = 90k)
-- Closer to 250k than 10k or 1M?
-- 1M - 90k = 910k
-- 250k - 90k = 160k (Best)
-- 90k - 10k = 80k (Wait, 80k is smaller diff? let's adjust window size)
-- Make window 250x250 exactly -> Area 62500.
-- Tile 2: 500x500 = 250000. Diff ~187k
-- Tile 3: 100x100 = 10000. Diff ~52k. So it should pick Tile 3 (Tiny) if I use 250x250.
-- Let's make window 450x450 = 202500.
-- Tile 2 Diff: 47500.
-- Tile 1 Diff: ~800k.
-- Tile 3 Diff: ~190k.
-- Should pick Tile 2.

local wF = create_window(4, "FocusApp", s1, {x=0,y=0,w=450,h=450})
hs.window.focusedWindow = function() return wF end

-- Call 1: Best Fit
auto_tiler.tile_all_windows()
local foundF = false
for _, m in ipairs(moved_windows) do
    if m.id == 4 then
        assert_eq(m.zk, "0", "Should be zone 0")
        assert_eq(m.idx, 2, "Should pick Tile 2 (Best Fit)")
        foundF = true
    end
end
assert_true(foundF, "Best fit move executed")

-- Call 2: Cycle
moved_windows = {} -- Reset capture
auto_tiler.tile_all_windows()
foundF = false
for _, m in ipairs(moved_windows) do
    if m.id == 4 then
        assert_eq(m.zk, "0", "Should stay zone 0")
        assert_eq(m.idx, 3, "Should cycle to Tile 3")
        foundF = true
    end
end
assert_true(foundF, "Cycle move executed")

-- SCENARIO 5: Best Fit Zone Selection (Zone j vs Zone 0)
print_test("Best Fit Zone Selection")
mock_screens = {}
mock_windows = {}
moved_windows = {} -- Reset
s1 = create_screen("screen1", "Main", {x=0,y=0,w=1000,h=1000})

-- Mock Zone 0 (Big tiles only)
-- Mock Zone j (Small tiles only)
mock_zc.get = function(mid, zk)
    if zk == "0" then return {
        {x=0,y=0,w=1000,h=1000}, -- Tile 1: 1M area
    } end
    if zk == "j" then return {
        {x=0,y=0,w=100,h=100}      -- Tile 1: 10k area
    } end
    return nil
end

-- Create focused window that matches Zone j size (100x100)
local wF2 = create_window(5, "FocusAppSmall", s1, {x=0,y=0,w=100,h=100})
hs.window.focusedWindow = function() return wF2 end

-- Call 1: Should pick Zone j because it fits better (diff 0 vs diff 990k)
auto_tiler.tile_all_windows()
local foundZ = false
for _, m in ipairs(moved_windows) do
    if m.id == 5 then
        assert_eq(m.zk, "j", "Should match Zone j (Best Fit)")
        assert_eq(m.idx, 1, "Should be Tile 1")
        foundZ = true
    end
end
assert_true(foundZ, "Best Fit Zone move executed")

print("All tests passed!")
