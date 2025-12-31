-- tests/test_auto_tiler_solver.lua
local mock_hs = require('tests.mock_hs')
local auto_tiler = require('modules.auto_tiler')

-- Mock config
local mock_config = {
    tiler = {
        layouts = {
            ['test_layout'] = {
                ['ZoneA'] = { 'a1', 'a2' },
                ['ZoneB'] = { 'b1' },
            },
        },
        auto_tile_center_zones = { 'ZoneA' },
    },
    window_memory = { excluded_apps = {} },
}

-- Mocks
local mock_mm = {
    get_id = function(s)
        return 'screen1'
    end,
}

local mock_zc = {
    get_layout_config = function(s)
        return {}, 'test_layout'
    end,
    get = function(mid, zone_key)
        if zone_key == 'ZoneA' then
            return { { x = 0, y = 0, w = 100, h = 200 }, { x = 0, y = 200, w = 100, h = 200 } }
        end -- Tall
        if zone_key == 'ZoneB' then
            return { { x = 100, y = 0, w = 200, h = 100 } }
        end -- Wide
        return {}
    end,
}

local mock_wm = {
    get_ranked_preferences = function()
        return {}
    end,
    setup_hotkeys = function() end,
}

local mock_wa = {
    position_window_from_memory = function(win, mid, zone, tile, suppress)
        print('ACTION: Move ' .. win:application():name() .. ' to ' .. zone .. ':' .. tile)
    end,
}

-- Init
auto_tiler.init(mock_config, {}, mock_wm, {}, mock_zc, mock_mm, mock_wa)

-- Helper to create mock windows
local function make_window(app_name, w, h)
    return {
        _id = app_name,
        id = function(self)
            return self._id
        end,
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
                name = function()
                    return 'Screen 1'
                end,
                id = function()
                    return 'screen1'
                end,
            }
        end,
        isStandard = function()
            return true
        end,
        isMinimized = function()
            return false
        end,
        isVisible = function()
            return true
        end,
    }
end

-- Tests
local function test_solver_integration()
    print('Test: Solver Integration')

    local wWide = make_window('WideApp', 200, 100) -- AR 2.0
    local wTall = make_window('TallApp', 100, 200) -- AR 0.5

    -- Mock global hs functions
    mock_hs.window.allWindows = function()
        return { wWide, wTall }
    end
    mock_hs.screen.allScreens = function()
        return { wWide:screen() }
    end
    mock_hs.window.focusedWindow = function()
        return nil
    end -- No focused window for this test

    -- Run
    auto_tiler.tile_all_windows()
end

test_solver_integration()
