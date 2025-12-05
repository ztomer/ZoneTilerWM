-- Configuration file for Hammerspoon settings
local config = {}

-- Key combinations
config.keys = {
    mash = {"ctrl", "cmd"},
    mash_app = {"shift", "ctrl"},
    mash_shift = {"shift", "ctrl", "cmd"},
    HYPER = {"shift", "ctrl", "alt", "cmd"},
    zen = '\\'
}

-- Audio switcher settings
config.audio_switcher = {
    devices = {"Audioengine 2+", "Bose QC35 II", "WH-1000XM6"},
    hotkey = {config.keys.HYPER, "'"},
    -- Name of the macOS Shortcut to run when the default audio device changes.
    -- The shortcut should contain its own logic to detect the device and act accordingly.
    -- An empty string "" will disable the callback.
    shortcut_callback = "SoundSourceSwitcherEx"
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
    r = 'ZTCronometer',
    t = 'Ghostty',
    a = 'Notion',
    s = 'Notion Mail',
    d = 'Notion Calendar',
    f = 'Zen',
    g = 'Gmail',
    z = 'Nimble Commander',
    x = 'Claude',
    c = 'Arc',
    v = 'Antigravity', -- Visual Studio Code
    b = 'YouTube Music'
}

config.hyperAppCuts = {
    q = 'IBKR Desktop',
    w = 'Weather',
    e = 'Clock',
    r = 'Discord',
    t = 'ChatGpt',
    a = 'KeePassXC',
    s = '',
    d = '',
    f = '',
    g = '',
    z = '',
    x = 'GeminiDesk',
    c = 'Google Chrome',
    v = 'Visual Studio Code',
    b = ''
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

-- Simplified Tiler settings
config.tiler = {
    debug = true,
    reposition_on_screen_change = true, -- or false if you want to disable it by default
    center_modals = true, -- Automatically center modal dialogs
    modifier = {"ctrl", "cmd"},
    focus_modifier = {"shift", "ctrl", "cmd"},

    margins = {
        enabled = true,
        size = 5,
        screen_edge = true
    },
    -- Apps that require special handling (Disable internal window management)
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

    -- Layout configurations - zone key -> tile definitions
    layouts = {
        -- 4x3 layout (large displays)
        ["4x3"] = {
            ["y"] = {"a1:a2", "a1", "a1:b2"},
            ["h"] = {"a1:b3", "a1:a3", "a1:c3", "a2"},
            ["n"] = {"a3", "a2:a3", "a3:b3"},
            ["u"] = {"b1:b3", "b1:b2", "b1", "b1:c1"},
            ["j"] = {"b1:c3", "b1:b3", "b2", "b1:d3"},
            ["m"] = {"b1:b3", "b2:c3", "b3"},
            ["i"] = {"d1:d3", "d1:d2", "d1"},
            ["k"] = {"c1:d3", "c1:c3", "c2"},
            [","] = {"d1:d3", "d2:d3", "d3"},
            ["o"] = {"c1:d1", "d1", "c1:d2"},
            ["l"] = {"d1:d3", "c1:d3", "b1:d3", "d2"},
            ["."] = {"d3", "d2:d3", "c3:d3"},
            ["0"] = {"b2:c2", "a1:d3", "center"}
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
            [","] = {"b2", "a2:b2"}, -- Bottom-right
            ["0"] = {"center", "a1:b2", "a1:b1"}
        },

        -- 3x2 layout
        ["3x2"] = {
            ["y"] = {"a1", "a1:a2"},
            ["h"] = {"a1:a2", "a1:b2"},
            ["n"] = {"a2", "a1:a2"},
            ["u"] = {"b1", "b1:b2"},
            ["j"] = {"b1:b2", "a1:c2"},
            ["m"] = {"b2", "b1:b2"},
            ["i"] = {"c1", "c1:c2"},
            ["k"] = {"c1:c2", "b1:c2"},
            [","] = {"c2", "c1:c2"},
            ["0"] = {"center", "b1:b2", "a1:c2"}
        },

        -- 3x3 layout
        ["3x3"] = {
            ["y"] = {"a1", "a1:a2", "a1:b1"},
            ["h"] = {"a1:a3", "a1:a2", "a2"},
            ["n"] = {"a3", "a2:a3", "a3:b3"},
            ["u"] = {"b1", "b1:b2", "a1:b1"},
            ["j"] = {"b2", "b1:b3", "a1:c3"},
            ["m"] = {"b3", "b2:b3", "a3:c3"},
            ["i"] = {"c1", "c1:c2", "b1:c1"},
            ["k"] = {"c1:c3", "c2:c3", "c2"},
            [","] = {"c3", "c2:c3", "b3:c3"},
            ["0"] = {"b2", "center", "a1:c3"}
        },

        -- Portrait layout
        ["1x3"] = {
            ["y"] = {"a1", "a1:a2"},
            ["h"] = {"a2", "a1:a3"},
            ["n"] = {"a3", "a2:a3"},
            ["0"] = {"a1:a3", "a2", "center"}
        },

        -- 1x2 layout
        ["1x2"] = {
            ["y"] = {"a1"},
            ["h"] = {"a2"},
            ["0"] = {"a1:a2", "a1", "a2"}
        },

        -- Default fallback for any layout/key not specifically defined
        ["default"] = {
            ["y"] = {"top-half"},
            ["h"] = {"left-half"},
            ["n"] = {"bottom-half"},
            ["u"] = {"top-half"},
            ["j"] = {"full"},
            ["m"] = {"bottom-half"},
            ["i"] = {"top-half"},
            ["k"] = {"right-half"},
            [","] = {"bottom-half"},
            ["0"] = {"center", "full"}
        }
    },

    -- Smart placement settings
    smart_placement = {
        enabled = true, -- Enable/disable smart placement
        cell_size = 50, -- Grid cell size for placement calculation
        exclude_apps = {"Hammerspoon", "Alfred", "Raycast"} -- Apps to exclude from smart placement
    },

    -- Focus cycling settings
    flash_on_focus = true, -- Visual feedback when cycling focus
    overlap_threshold = 0.5, -- Minimum overlap to consider window in zone (50%)
    focus_cycle_all_tiles = false, -- If true, cycles through all tiles in zone, not just current tile

    -- Timing and delay settings (in seconds)
    -- Timing and delay settings (in seconds)
    delays = {
        screen_change_reposition_sec = 0.1, -- Delay before repositioning windows after screen change
        new_window_initial_sec = 0.05, -- Initial delay after a window is created before processing
        new_window_placement_sec = 0.1, -- Secondary delay before final placement of a new window
        smart_placement_reposition_sec = 0.1, -- Delay for smart placement during repositioning events
        flash_on_focus_duration_sec = 0.2 -- Duration of the visual flash when cycling focus
    },

    -- Placement strategy: 'rotate', 'largest_free_space', or 'hybrid'
    placement_strategy = 'hybrid',

    -- Cache settings
    cache_size = {
        positions = 500, -- Window position cache size
        window_info = 200 -- Window info cache size
    }
}

-- Window handling settings
config.window_handling = {
    modal_dialog_behavior = "ignore" -- "center", "tile", or "ignore". Default: "ignore"
}

config.window_memory = {
    enabled = true, -- Enable/disable window memory
    debug = true, -- Enable debug logging
    max_preference_entries = 1000, -- Maximum number of unique app/monitor/zone/tile preferences to remember
    settle_delay_sec = 2.0, -- Time in seconds before a window position is "learned" after it stops moving
    save_interval_sec = 60, -- Time in seconds between automatic saves. Set to 0 to disable.

    -- Directory to store position cache files
    cache_dir = os.getenv("HOME") .. "/.config/ZoneTilerWM",

    -- Hotkey configuration
    hotkeys = {
        capture = {"9", {"shift", "ctrl", "alt", "cmd"}}, -- HYPER+9 to capture all window positions
        restore = {"0", {"shift", "ctrl", "alt", "cmd"}} -- HYPER+0 to restore remembered positions
    },

    -- Apps to exclude from window memory
    excluded_apps = {"System Settings", "System Preferences", "Activity Monitor", "Calculator", "Photo Booth",
                     "Hammerspoon", "KeyCastr", "Installer", "SupaSidebar"},

    -- Fallback auto-tiling settings (used when no cached position exists)
    auto_tile_fallback = true,
    default_zone = "0",
    app_zones = {
        ["Arc"] = "k",
        ["iTerm"] = "h",
        ["Visual Studio Code"] = "h",
        ["Notion"] = "j",
        ["Spotify"] = "i"
    }
}

config.layout_manager = {
    enabled = true,
    debug = true
}

-- Spaces settings (macOS Mission Control Spaces integration)
config.spaces = {
    enabled = true, -- Enable/disable Spaces feature
    debug = true, -- Enable debug logging

    -- Keyboard shortcuts for switching spaces (Ctrl+Shift+Number)
    hotkeys = {
        space_1 = {{"ctrl", "shift"}, "1"},
        space_2 = {{"ctrl", "shift"}, "2"},
        space_3 = {{"ctrl", "shift"}, "3"},
        space_4 = {{"ctrl", "shift"}, "4"},
        space_5 = {{"ctrl", "shift"}, "5"},
        space_6 = {{"ctrl", "shift"}, "6"},
        space_7 = {{"ctrl", "shift"}, "7"},
        space_8 = {{"ctrl", "shift"}, "8"},
        space_9 = {{"ctrl", "shift"}, "9"}
    },

    -- Menubar indicator settings
    menubar = {
        enabled = true, -- Show menubar indicator
        show_names = false, -- Show Space names instead of numbers
        click_to_switch = true -- Allow clicking menubar to switch spaces
    },

    -- Visual preview settings
    preview = {
        enabled = true, -- Enable visual preview of windows in spaces
        activation_mode = "hover", -- "hover" or "click"
        hover_delay = 0.3, -- Delay in seconds before showing preview on hover
        window_width = 600, -- Preview window width in pixels
        window_height = 400, -- Preview window height in pixels
        thumbnail_size = {
            width = 100, -- Individual window thumbnail width
            height = 80 -- Individual window thumbnail height
        },
        background_color = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95},
        border_color = {red = 0.3, green = 0.3, blue = 0.3, alpha = 1.0},
        active_space_color = {red = 0.2, green = 0.5, blue = 0.8, alpha = 1.0},
        drag_enabled = true -- Enable drag-and-drop between spaces
    },

    -- Layout persistence settings
    save_layouts_per_space = true, -- Save window layouts per Space per monitor
    auto_restore_layouts = true, -- Automatically restore layouts when switching Spaces
    layout_save_delay = 1.0 -- Delay in seconds before saving layout after changes
}

return config
