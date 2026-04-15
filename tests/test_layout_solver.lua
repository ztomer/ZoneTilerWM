-- tests/test_layout_solver.lua
local mock_hs = require('tests.mock_hs')
local layout_solver = require('modules.layout_solver')

-- Mock window_memory
local mock_memory = {}
function mock_memory.get_ranked_preferences(app, mid)
    return {}
end

layout_solver.init(mock_memory)

-- Helpers
local function make_window(app_name, w, h)
    return {
        _id = app_name,
        application = function()
            return {
                name = function()
                    return app_name
                end,
            }
        end,
        frame = function()
            return { x = 0, y = 0, w = w, h = h }
        end,
        screen = function()
            return {
                frame = function()
                    return { x = 0, y = 0, w = 1000, h = 1000 }
                end,
            }
        end,
    }
end

local function make_tile(zone, idx, w, h)
    return {
        rect = { x = 0, y = 0, w = w, h = h },
        zone_key = zone,
        tile_index = idx,
        monitor_id = 'test_screen',
    }
end

-- TEST 1: Shape Matching
-- Wide Window should go to Wide Tile, Tall Window to Tall Tile
local function test_shape_matching()
    print('Test 1: Shape Matching')

    local w1 = make_window('WideApp', 800, 400) -- AR = 2.0
    local w2 = make_window('TallApp', 400, 800) -- AR = 0.5

    local t1 = make_tile('ZoneA', 1, 400, 800) -- Tall Tile
    local t2 = make_tile('ZoneB', 1, 800, 400) -- Wide Tile

    -- Note: Solver receives list of windows and list of tiles.
    -- Order doesn't matter for the set, but inputs are ordered lists.
    local windows = { w1, w2 }
    local tiles = { t1, t2 }

    local moves = layout_solver.solve(windows, tiles, 'test_screen')

    local passed = true
    for _, m in ipairs(moves) do
        local app = m.window:application():name()
        local zone = m.tile.zone_key

        if app == 'WideApp' and zone ~= 'ZoneB' then
            print('FAIL: WideApp went to ' .. zone .. ' (expected ZoneB)')
            passed = false
        elseif app == 'TallApp' and zone ~= 'ZoneA' then
            print('FAIL: TallApp went to ' .. zone .. ' (expected ZoneA)')
            passed = false
        end
    end

    if passed then
        print('PASS')
    end
end

-- TEST 2: Memory Override
-- Window prefers a specific tile heavily, overriding shape match
local function test_memory_override()
    print('Test 2: Memory Override')

    -- Mock memory to prefer ZoneA for WideApp
    mock_memory.get_ranked_preferences = function(app, mid)
        if app == 'WideApp' then
            return { { zone_key = 'ZoneA', tile_index = 1, count = 100 } } -- ZoneA is Tall!
        end
        return {}
    end

    local w1 = make_window('WideApp', 800, 400) -- AR = 2.0
    local w2 = make_window('TallApp', 400, 800) -- AR = 0.5

    local t1 = make_tile('ZoneA', 1, 400, 800) -- Tall Tile
    local t2 = make_tile('ZoneB', 1, 800, 400) -- Wide Tile -- Perfect geometric fit for WideApp

    local moves = layout_solver.solve({ w1, w2 }, { t1, t2 }, 'test_screen')

    local passed = true
    for _, m in ipairs(moves) do
        local app = m.window:application():name()
        local zone = m.tile.zone_key

        if app == 'WideApp' and zone ~= 'ZoneA' then
            print('FAIL: WideApp should have preferred ZoneA due to memory, but got ' .. zone)
            passed = false
        end
    end

    if passed then
        print('PASS')
    end
end

test_shape_matching()
test_memory_override()
