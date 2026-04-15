-- tests/run_corpus.lua
local layout_solver = require('modules.layout_solver')
local corpus = require('tests.solver_corpus')

-- Mocks
local mock_mm = {
    get_id = function()
        return 'test_screen'
    end,
}

local MockWindow = {}
MockWindow.__index = MockWindow

function MockWindow.new(def)
    local self = setmetatable({}, MockWindow)
    self._def = def
    self._id = def.id
    return self
end
function MockWindow:frame()
    return { w = self._def.w, h = self._def.h }
end
function MockWindow:screen()
    return {
        frame = function()
            return { x = 0, y = 0, w = 1000, h = 1000 }
        end,
    }
end
function MockWindow:application()
    return {
        name = function()
            return self._def.id
        end,
    }
end
function MockWindow:id()
    return self._id
end

local GLOBAL_MEMORY = {}

-- Init Solver
layout_solver.init({
    get_ranked_preferences = function(app_name, mid)
        return GLOBAL_MEMORY[app_name] or {}
    end,
})

--------------------------------------------------------------------------------
-- ASSERTIONS
--------------------------------------------------------------------------------
local function check_overlap(r1, r2)
    return not (r1.x >= r2.x + r2.w or r1.x + r1.w <= r2.x or r1.y >= r2.y + r2.h or r1.y + r1.h <= r2.y)
end

local function run_scenario(scen)
    print('\n----------------------------------------------------------------')
    print('RUNNING: ' .. scen.name)
    print('DESC:    ' .. scen.description)

    -- 1. Setup Data
    local windows = {}
    GLOBAL_MEMORY = {}

    for _, wdef in ipairs(scen.windows) do
        table.insert(windows, MockWindow.new(wdef))
        if wdef.memory_zone then
            GLOBAL_MEMORY[wdef.id] = {
                { zone_key = wdef.memory_zone, tile_index = 1, count = 10 },
            }
        end
    end

    local tiles = {}
    for _, tdef in ipairs(scen.tiles) do
        table.insert(tiles, {
            rect = tdef.rect,
            zone_key = tdef.zone,
            tile_index = tdef.idx,
            monitor_id = 'test_mid',
        })
    end

    -- 2. Solve
    local moves = layout_solver.solve(windows, tiles, 'test_mid')

    -- 3. Verify
    local passed = true
    local reasons = {}

    local assigned_zones = {}
    local assigned_rects = {}

    for _, m in ipairs(moves) do
        local app = m.window:application():name()
        assigned_zones[app] = m.tile.zone_key
        table.insert(assigned_rects, m.tile.rect)
        print('  -> Assigned ' .. app .. ' to ' .. m.tile.zone_key)
    end

    -- Check Min Placed
    if scen.expect.min_placed and #moves < scen.expect.min_placed then
        passed = false
        table.insert(reasons, 'Expected at least ' .. scen.expect.min_placed .. ' placements, got ' .. #moves)
    end

    -- Check Max Placed
    if scen.expect.max_placed and #moves > scen.expect.max_placed then
        passed = false
        table.insert(reasons, 'Expected at most ' .. scen.expect.max_placed .. ' placements, got ' .. #moves)
    end

    -- Check Assignments
    if scen.expect.assignments then
        for app, expected_zone in pairs(scen.expect.assignments) do
            local actual = assigned_zones[app]
            local match = false
            if type(expected_zone) == 'table' then
                for _, z in ipairs(expected_zone) do
                    if z == actual then
                        match = true
                        break
                    end
                end
            else
                match = (actual == expected_zone)
            end

            if not match then
                passed = false
                table.insert(
                    reasons,
                    'App ' .. app .. ' expected in ' .. tostring(expected_zone) .. ', got ' .. tostring(actual)
                )
            end
        end
    end

    -- Check Overlaps
    if scen.expect.no_overlap then
        for i = 1, #assigned_rects do
            for j = i + 1, #assigned_rects do
                if check_overlap(assigned_rects[i], assigned_rects[j]) then
                    passed = false
                    table.insert(reasons, 'Found Overlap between assigned tiles!')
                end
            end
        end
    end

    if passed then
        print('RESULT: PASS')
        return true
    else
        print('RESULT: FAIL')
        for _, r in ipairs(reasons) do
            print('  - ' .. r)
        end
        return false
    end
end

local total = 0
local passes = 0
for _, scen in ipairs(corpus.scenarios) do
    total = total + 1
    if run_scenario(scen) then
        passes = passes + 1
    end
end

print('\n================================================================')
print(string.format('SUMMARY: Passed %d / %d scenarios', passes, total))
print('================================================================')

if passes < total then
    os.exit(1)
else
    os.exit(0)
end
