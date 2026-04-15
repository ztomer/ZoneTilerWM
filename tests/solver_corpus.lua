-- tests/solver_corpus.lua
local corpus = {}

-- Helper to make rects
local function R(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

--------------------------------------------------------------------------------
-- SCENARIO DEFINITIONS
--------------------------------------------------------------------------------

corpus.scenarios = {
    {
        name = 'Basic: 1 Wide, 1 Tall',
        description = 'One wide window (AR 2.0) and one tall window (AR 0.5) with matching slots available.',
        windows = {
            { id = 'WideApp', w = 200, h = 100 }, -- AR 2.0
            { id = 'TallApp', w = 100, h = 200 }, -- AR 0.5
        },
        tiles = {
            { zone = 'WideZone', idx = 1, rect = R(0, 0, 200, 100) },
            { zone = 'TallZone', idx = 1, rect = R(0, 200, 100, 200) },
        },
        expect = {
            assignments = {
                ['WideApp'] = 'WideZone',
                ['TallApp'] = 'TallZone',
            },
        },
    },
    {
        name = 'Overlap: LeftHalf vs LeftThird',
        description = 'Two windows available. Solver must NOT pick overlapping tiles (LeftHalf covers LeftThird).',
        windows = {
            { id = 'App1', w = 500, h = 500 },
            { id = 'App2', w = 500, h = 500 },
        },
        tiles = {
            { zone = 'LeftHalf', idx = 1, rect = R(0, 0, 500, 1000) }, -- Overlaps LeftThird
            { zone = 'LeftThird', idx = 1, rect = R(0, 0, 333, 1000) }, -- Overlapped
            { zone = 'RightHalf', idx = 1, rect = R(500, 0, 500, 1000) }, -- Safe
        },
        expect = {
            min_placed = 2,
            no_overlap = true,
        },
    },
    {
        name = 'Overlap: FullScreen vs Halves',
        description = 'Layout offers Full, Left, Right. 2 Windows. Should pick Left+Right, NOT Full+Left.',
        windows = {
            { id = 'App1', w = 500, h = 500 },
            { id = 'App2', w = 500, h = 500 },
        },
        tiles = {
            { zone = 'Full', idx = 1, rect = R(0, 0, 1000, 1000) },
            { zone = 'Left', idx = 1, rect = R(0, 0, 500, 1000) },
            { zone = 'Right', idx = 1, rect = R(500, 0, 500, 1000) },
        },
        expect = {
            min_placed = 2,
            no_overlap = true,
            assignments = {
                ['App1'] = { 'Left', 'Right' },
                ['App2'] = { 'Left', 'Right' },
            },
        },
    },
    {
        name = 'Cramming: 3 Windows, 2 Spots',
        description = '3 Windows, only Left and Right available. Should pick best 2, leave 1 unassigned.',
        windows = {
            { id = 'ImportantApp', w = 500, h = 500, memory_zone = 'Left', memory_rank = 1 },
            { id = 'NormalApp', w = 500, h = 500 },
            { id = 'LowPrio', w = 500, h = 500 },
        },
        tiles = {
            { zone = 'Left', idx = 1, rect = R(0, 0, 500, 1000) },
            { zone = 'Right', idx = 1, rect = R(500, 0, 500, 1000) },
        },
        expect = {
            min_placed = 2,
            max_placed = 2,
            assignments = {
                ['ImportantApp'] = 'Left', -- Memory binding should win
            },
        },
    },
    {
        name = 'Shape Matching vs Memory',
        description = 'App prefers ZoneA (Wide), but is currently Tall. ZoneB is Tall. Memory should strictly win over shape.',
        windows = {
            { id = 'WebBrowser', w = 100, h = 500, memory_zone = 'WideZone', memory_rank = 1 }, -- Tall shape, Memory for Wide
        },
        tiles = {
            { zone = 'WideZone', idx = 1, rect = R(0, 0, 500, 200) },
            { zone = 'TallZone', idx = 1, rect = R(0, 0, 100, 500) },
        },
        expect = {
            assignments = {
                ['WebBrowser'] = 'WideZone',
            },
        },
    },
    {
        name = 'Maximize Coverage',
        description = 'Window is small (250x250). Available: Small Tile (250x250) vs Big Tile (500x500). Should pick Big Tile to maximize utility.',
        windows = {
            { id = 'SmallApp', w = 250, h = 250 },
        },
        tiles = {
            { zone = 'SmallZone', idx = 1, rect = R(0, 0, 250, 250) },
            { zone = 'BigZone', idx = 1, rect = R(0, 0, 500, 500) },
        },
        expect = {
            assignments = {
                ['SmallApp'] = 'BigZone',
            },
        },
    },
    {
        name = 'Recency Priority',
        description = 'Two identical small windows. Available: Big Tile vs Small Tile. Recent window (Win1) should get the Big Tile.',
        windows = {
            { id = 'Win1_Recent', w = 200, h = 200 }, -- Index 1 (Most Recent)
            { id = 'Win2_Old', w = 200, h = 200 }, -- Index 2 (Old)
        },
        tiles = {
            { zone = 'BigZone', idx = 1, rect = R(0, 0, 500, 500) },
            { zone = 'SmallZone', idx = 1, rect = R(600, 0, 200, 200) },
        },
        expect = {
            assignments = {
                ['Win1_Recent'] = 'BigZone',
                ['Win2_Old'] = 'SmallZone',
            },
        },
    },
}

return corpus
