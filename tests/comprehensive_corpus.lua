-- tests/comprehensive_corpus.lua
-- Defines a large set of "Golden Scenarios" for the layout solver.

local function R(x,y,w,h) return {x=x,y=y,w=w,h=h} end

local corpus = {}
corpus.scenarios = {
    -- ========================================================================
    -- 1. SINGLE WINDOW SCENARIOS
    -- ========================================================================
    {
        name = "Solo Work (Generic)",
        description = "Single window should default to Center/Primary zone.",
        windows = { {id="MainApp", w=800, h=600} },
        tiles = {
            { zone="Left", idx=1, rect=R(0,0,640,1080) },
            { zone="Center", idx=1, rect=R(640,0,1200,1080) }, -- Primary
            { zone="Right", idx=1, rect=R(1840,0,640,1080) }
        },
        expect = { assignments = { ["MainApp"] = "Center" } }
    },
    {
        name = "Solo Laptop (2x2)",
        description = "Single window on laptop should take Full Screen.",
        windows = { {id="MainApp", w=800, h=600} },
        tiles = {
            { zone="Full", idx=1, rect=R(0,0,1440,900) },      -- Overlaps others
            { zone="Left", idx=1, rect=R(0,0,720,900) },
            { zone="Right", idx=1, rect=R(720,0,720,900) }
        },
        expect = { assignments = { ["MainApp"] = "Full" } }
    },

    -- ========================================================================
    -- 2. DUO SCENARIOS
    -- ========================================================================
    {
        name = "Comparison (Split Screen)",
        description = "Two identical windows should split the screen 50/50.",
        windows = {
            { id="Browser1", w=800, h=1000 },
            { id="Browser2", w=800, h=1000 }
        },
        tiles = {
            { zone="Full", idx=1, rect=R(0,0,1920,1080) },
            { zone="Left", idx=1, rect=R(0,0,960,1080) },
            { zone="Right", idx=1, rect=R(960,0,960,1080) }
        },
        expect = {
            min_placed = 2,
            no_overlap = true
            -- One left, one right. Order depends on internal ID unless specified.
        }
    },
    {
        name = "Chat Mode (Main + Sidebar)",
        description = "Wide Browser + Tall Chat. Browser -> Main, Chat -> Side.",
        windows = {
            { id="Browser", w=1200, h=800 }, -- Wide
            { id="Chat", w=400, h=800 }      -- Tall/Narrow
        },
        tiles = {
            { zone="Main", idx=1, rect=R(0,0,1400,1080) },
            { zone="Side", idx=1, rect=R(1400,0,520,1080) }
        },
        expect = {
            assignments = { ["Browser"] = "Main", ["Chat"] = "Side" }
        }
    },

    -- ========================================================================
    -- 3. TRIO SCENARIOS
    -- ========================================================================
    {
        name = "The Coder (3 Cols)",
        description = "IDE, Browser, Terminal. 3 Columns ideal.",
        windows = {
            { id="IDE", w=800, h=800 },
            { id="Browser", w=800, h=800 },
            { id="Term", w=800, h=800 }
        },
        tiles = {
            { zone="Col1", idx=1, rect=R(0,0,640,1080) },
            { zone="Col2", idx=1, rect=R(640,0,640,1080) },
            { zone="Col3", idx=1, rect=R(1280,0,640,1080) },
            -- Overlapping Center options
            { zone="CenterWide", idx=1, rect=R(320,0,1280,1080) }
        },
        expect = {
            min_placed = 3,
            no_overlap = true
            -- Should NOT pick CenterWide because it blocks Col1 and Col3 (roughly), leaving only 1 spot for 2 windows?
            -- Actually CenterWide blocks Col2 and parts of 1/3.
            -- Safest is 3 Cols.
        }
    },

    -- ========================================================================
    -- 4. QUAD SCENARIOS
    -- ========================================================================
    {
        name = "The Trader (2x2 Grid)",
        description = "4 Windows. Should form a 2x2 Grid if available.",
        windows = {
            { id="Chart1", w=500, h=500 }, { id="Chart2", w=500, h=500 },
            { id="Chart3", w=500, h=500 }, { id="Chart4", w=500, h=500 }
        },
        tiles = {
            { zone="TL", idx=1, rect=R(0,0,960,540) },
            { zone="TR", idx=1, rect=R(960,0,960,540) },
            { zone="BL", idx=1, rect=R(0,540,960,540) },
            { zone="BR", idx=1, rect=R(960,540,960,540) },
            { zone="Full", idx=1, rect=R(0,0,1920,1080) }
        },
        expect = {
            min_placed = 4,
            no_overlap = true
        }
    },

    -- ========================================================================
    -- 5. EDGE CASES
    -- ========================================================================
    {
        name = "Tiny Window Priority",
        description = "1 Normal, 1 Tiny. Tiny should NOT take the Main slot.",
        windows = {
            { id="MainBrowser", w=1000, h=800 },
            { id="TinyClock", w=200, h=200 }
        },
        tiles = {
            { zone="Main", idx=1, rect=R(0,0,1400,1080) },
            { zone="Corner", idx=1, rect=R(1400,0,520,300) }
        },
        expect = {
            assignments = {
                ["MainBrowser"] = "Main",
                ["TinyClock"] = "Corner"
            }
        }
    },
    {
        name = "Mixed Orientation",
        description = "1 Tall Window, 1 Wide Window. Should map to Tall and Wide slots respectively.",
        windows = {
            { id="TallApp", w=400, h=800 },
            { id="WideApp", w=1200, h=400 }
        },
        tiles = {
            { zone="TallSlot", idx=1, rect=R(0,0,500,1000) },
            { zone="WideSlot", idx=1, rect=R(500,0,1400,500) },
            { zone="SquareSlot", idx=1, rect=R(500,500,500,500) }
        },
        expect = {
            assignments = {
                ["TallApp"] = "TallSlot",
                ["WideApp"] = "WideSlot"
            }
        }
    },
    {
        name = "Overcrowded (5 Windows, 4 Slots)",
        description = "5 Windows, only 2x2 grid available. Should drop the old/least-compatible one.",
        windows = {
            { id="Win1", w=500, h=500 }, { id="Win2", w=500, h=500 },
            { id="Win3", w=500, h=500 }, { id="Win4", w=500, h=500 },
            { id="Win5_Old", w=500, h=500 } -- Should be dropped or Last
        },
        tiles = {
            { zone="TL", idx=1, rect=R(0,0,500,500) },
            { zone="TR", idx=1, rect=R(500,0,500,500) },
            { zone="BL", idx=1, rect=R(0,500,500,500) },
            { zone="BR", idx=1, rect=R(500,500,500,500) }
        },
        expect = {
            max_placed = 4,
            min_placed = 4
            -- Assignments are tricky because Recency is tied to Index.
            -- Win1..4 are "more recent" than Win5 if passed in order.
            -- So Win5 should be the one unassigned.
        }
    },

    -- ========================================================================
    -- 6. NON-STANDARD DISPLAYS
    -- ========================================================================
    {
        name = "Ultrawide (21:9)",
        description = "3 Windows on Ultrawide. Should map to Left/Center/Right thirds.",
        windows = {
            { id="Win1", w=1000, h=1400 },
            { id="Win2", w=1000, h=1400 },
            { id="Win3", w=1000, h=1400 }
        },
        tiles = {
            { zone="Left", idx=1, rect=R(0,0,1146,1440) },   -- 33% of 3440
            { zone="Center", idx=1, rect=R(1146,0,1148,1440) },
            { zone="Right", idx=1, rect=R(2294,0,1146,1440) },
            { zone="CenterWide", idx=1, rect=R(860,0,1720,1440) } -- 50% Center
        },
        expect = {
            min_placed = 3,
            no_overlap = true
            -- Should avoid CenterWide because it limits us to 2 windows max (Left+Right overlap).
            -- 3 Windows fits better in 3 cols.
        }
    },
    {
        name = "Vertical Monitor (9:16)",
        description = "3 Windows on Vertical. Should stack Top/Mid/Bot.",
        windows = {
            { id="TopApp", w=1000, h=600 },
            { id="MidApp", w=1000, h=600 },
            { id="BotApp", w=1000, h=600 }
        },
        tiles = {
            { zone="Top", idx=1, rect=R(0,0,1080,640) },
            { zone="Mid", idx=1, rect=R(0,640,1080,640) },
            { zone="Bot", idx=1, rect=R(0,1280,1080,640) },
            { zone="TopHalf", idx=1, rect=R(0,0,1080,960) } -- Overlaps Mid
        },
        expect = {
            min_placed = 3,
            no_overlap = true
        }
    },

    -- ========================================================================
    -- 7. CONFLICT RESOLUTION
    -- ========================================================================
    {
        name = "Memory Trumps Imperfect Fit",
        description = "App A remembers Zone 1 (but fits Shape 2 better). Memory should win.",
        windows = {
            { id="MemApp", w=500, h=1000, memory_zone="Zone1", memory_rank=1 } -- Tall, but remembers Zone1
        },
        tiles = {
            { zone="Zone1", idx=1, rect=R(0,0,1000,500) }, -- Wide (Bad Shape Fit, Good Memory)
            { zone="Zone2", idx=1, rect=R(0,500,500,1000) } -- Tall (Good Shape Fit, No Memory)
        },
        expect = {
            assignments = { ["MemApp"] = "Zone1" }
        }
    },

    -- ========================================================================
    -- 8. AGGRESSIVE COVERAGE
    -- ========================================================================
    {
        name = "Coverage vs Shape (Force Fill)",
        description = "Square Window (500x500). Option A: Square Tile (Small, 25%). Option B: Wide Tile (Big, 50%). User wants B.",
        windows = {
            { id="SquareApp", w=500, h=500 }
        },
        tiles = {
            { zone="SmallSquare", idx=1, rect=R(0,0,500,500) },   -- 0.25 Area. AR Match. Cost = low.
            { zone="BigWide", idx=1, rect=R(0,0,1000,500) }       -- 0.50 Area. AR Mismatch (2.0 vs 1.0). Cost = Penalty - Reward.
        },
        expect = {
            assignments = { ["SquareApp"] = "BigWide" }
        }
    }
}

return corpus
