-- Configuration file for Hammerspoon settings
local config = {}

-- Key combinations
config.keys = {
    mash = {"ctrl", "cmd"},
    mash_app = {"shift", "ctrl"},
    mash_shift = {"shift", "ctrl", "cmd"},
    HYPER = {"shift", "ctrl", "alt", "cmd"}
}

-- Application switcher settings
config.app_switcher = {
    -- Apps that need menu-based hiding
    hide_workaround_apps = {'Arc'},

    -- Apps that require exact mapping between launch name and display name
    special_app_mappings = {
        ["bambustudio"] = "bambu studio" -- Launch name → Display name
    },

    -- Ambiguous app pairs that should not be considered matching
    ambiguous_apps = {{'notion', 'notion calendar'}, {'notion', 'notion mail'}}
}

-- Application shortcuts with direct lowercase mapping
config.appCuts = {
    q = 'BambuStudio',
    w = 'Whatsapp',
    e = 'Finder',
    r = 'Cronometer',
    t = 'iTerm',
    a = 'Notion',
    s = 'Notion Mail',
    d = 'Notion Calendar',
    f = 'Zen',
    g = 'Gmail',
    z = 'Nimble Commander',
    x = 'Claude',
    c = 'Arc',
    v = 'Visual Studio Code',
    b = 'Spotify'
}

config.hyperAppCuts = {
    q = 'IBKR Desktop',
    w = 'Weather',
    e = 'Clock',
    r = 'Discord',
    t = 'ChatGpt',
    a = 'KeePassXC'
}

-- Pomodoro settings
config.pomodoro = {
    enable_color_bar = true,
    work_period_sec = 52 * 60, -- 52 minutes
    rest_period_sec = 17 * 60, -- 17 minutes
    indicator_height = 0.2, -- ratio from the height of the menubar (0..1)
    indicator_alpha = 0.3,
    indicator_in_all_spaces = true,
    color_time_remaining = hs.drawing.color.green,
    color_time_used = hs.drawing.color.red
}

-- Tiler settings
config.tiler = {
    debug = true,
    debug_cache_stats = true, -- Enable periodic logging of cache statistics
    modifier = {"ctrl", "cmd"},
    focus_modifier = {"shift", "ctrl", "cmd"},
    flash_on_focus = true,
    smart_placement = true,

    -- Cache settings
    cache = {
        tile_positions = 128, -- Size of tile position cache
        zone_tiles = 64, -- Size of zone tiles cache
        screen_modes = 8, -- Size of screen mode detection cache
        window_positions = 512 -- Size of window position cache
    },

    margins = {
        enabled = true,
        size = 5,
        screen_edge = true
    },

    problem_apps = {"Firefox", "Zen"},

    -- Screen detection configuration
    screen_detection = {
        -- Special screen name patterns and corresponding layout type
        patterns = {
            ["DELL.*U32"] = "4x3", -- Dell 32-inch monitors
            ["DELL U3223QE"] = "4x3", -- Exact match
            ["LG.*QHD"] = "1x3", -- LG QHD in portrait mode
            ["Built[-]?in"] = "2x2", -- MacBook built-in displays
            ["Color LCD"] = "2x2", -- MacBook displays
            ["internal"] = "2x2", -- Internal displays
            ["MacBook"] = "2x2" -- MacBook displays
        },

        -- Size-based layout selection
        sizes = {
            large = {
                min = 27,
                layout = "4x3"
            }, -- 27" and larger - 4x3 grid
            medium = {
                min = 24,
                max = 26.9,
                layout = "3x3"
            }, -- 24-26" - 3x3 grid
            standard = {
                min = 20,
                max = 23.9,
                layout = "3x2"
            }, -- 20-23" - 3x2 grid
            small = {
                max = 19.9,
                layout = "2x2"
            } -- Under 20" - 2x2 grid
        },

        -- Portrait mode detection
        portrait = {
            large = {
                min = 23,
                layout = "1x3"
            }, -- 23" and larger in portrait
            small = {
                max = 22.9,
                layout = "1x2"
            } -- Under 23" in portrait
        }
    },

    -- Grid specifications
    grids = {
        ["4x3"] = {
            cols = 4,
            rows = 3
        },
        ["3x3"] = {
            cols = 3,
            rows = 3
        },
        ["3x2"] = {
            cols = 3,
            rows = 2
        },
        ["2x2"] = {
            cols = 2,
            rows = 2
        },
        ["1x3"] = {
            cols = 1,
            rows = 3
        },
        ["1x2"] = {
            cols = 1,
            rows = 2
        }
    },

    -- Custom layouts for specific screens (by exact name)
    custom_screens = {
        ["DELL U3223QE"] = {
            grid = {
                cols = 4,
                rows = 3
            },
            layout = "4x3"
        },
        ["LG IPS QHD"] = {
            grid = {
                cols = 1,
                rows = 3
            },
            layout = "1x3"
        }
    },

    -- Layout configurations - key bindings for each layout type
    layouts = {
        -- 4x3 layout (large displays)
        ["4x3"] = {
            ["y"] = {"a1:a2", "a1", "a1:b2"},
            ["h"] = {"a1:b3", "a1:a3", "a1:c3", "a2"},
            ["n"] = {"a3", "a2:a3", "a3:b3"},
            ["u"] = {"b1:b3", "b1:b2", "b1"},
            ["j"] = {"b1:c3", "b1:b3", "b2", "b1:d4"},
            ["m"] = {"b1:b3", "b2:c3", "b3"},
            ["i"] = {"d1:d3", "d1:d2", "d1"},
            ["k"] = {"c1:d3", "c1:c3", "c2"},
            [","] = {"d1:d3", "d2:d3", "d3"},
            ["o"] = {"c1:d1", "d1", "c1:d2"},
            ["l"] = {"d1:d3", "c1:d3", "b1:d3", "d2"},
            ["."] = {"d3", "d2:d3", "c3:d3"}
        },

        -- 2x2 layout (small displays, laptop)
        ["2x2"] = {
            ["y"] = {"a1", "a1:a2", "a1:b1"}, -- Top-left
            ["h"] = {"a1:a2", "a1:b2"}, -- Left tile
            ["n"] = {"a2", "a2:b2"}, -- Bottom-left
            ["u"] = {"a1:b1", "b1"}, -- Top tile
            ["j"] = {"a1:b2"}, -- Center (full screen)
            ["m"] = {"a2:b2", "b2"}, -- Bottom tile
            ["i"] = {"b1", "a1:b1"}, -- Top-right
            ["k"] = {"b1:b2", "b2"}, -- Right tile
            ["0"] = {"a1:b2", "a1:b1", "a2:b2"}, -- Fullscreen variants
            [","] = {"b2", "a2:b2"} -- Bottom-right
        },

        -- Portrait layout
        ["1x3"] = {
            ["y"] = {"a1", "a1:a2"},
            ["h"] = {"a2", "a1:a3"},
            ["n"] = {"a3", "a2:a3"},
            ["0"] = {"a1:a3", "a2", "a1"}
        },
        -- 1x2 layout
        ["1x2"] = {
            ["y"] = {"a1"},
            ["h"] = {"a2"},
            ["0"] = {"a1:a2", "a1", "a2"}
        },
        -- Default fallback for any layout/key not specifically defined
        ["default"] = {
            ["default"] = {"full", "center", "left-half", "right-half", "top-half", "bottom-half"}
        }
    }
}

-- Window memory settings
config.window_memory = {
    enabled = true, -- Enable/disable window memory
    debug = true, -- Enable debug logging

    -- Directory to store position cache files
    cache_dir = os.getenv("HOME") .. "/.config/tiler",
    -- Hotkey configuration
    hotkeys = {
        capture = {"9", config.keys.HYPER}, -- HYPER+9 to capture all window positions
        apply = {"0", config.keys.HYPER} -- HYPER+0 to apply remembered positions
    },

    -- Apps to exclude from window memory
    excluded_apps = {"System Settings", "System Preferences", "Activity Monitor", "Calculator", "Photo Booth",
                     "Hammerspoon", "KeyCastr", "Installer"},

    -- Fallback auto-tiling settings (used when no cached position exists)
    auto_tile_fallback = true,
    default_zone = "center",
    app_zones = {
        ["Arc"] = "k",
        ["iTerm"] = "h",
        ["Visual Studio Code"] = "h",
        ["Notion"] = "j",
        ["Spotify"] = "i"
    }
}

return config
