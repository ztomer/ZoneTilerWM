# ZoneTilerWM

A modular and powerful window management system for macOS that includes window tiling, application switching, and productivity tools.

## Features

- **Grid-based Window Management**: Organize windows in a customizable grid layout
- **Screen-aware Layouts**: Automatically detects screen size and orientation for optimal layouts
- **Multiple Screen Support**: Seamlessly manage windows across multiple displays
- **Application Switching**: Quick keyboard shortcuts for launching and toggling applications
- **Pomodoro Timer**: Built-in productivity timer with visual feedback
- **Window Margins**: Configurable spacing between windows and screen edges
- **Focus Control**: Quickly focus and cycle through windows in specific zones
- **Smart Window Mapping**: Automatically detect and place existing windows in zones
- **Cross-Screen Navigation**: Move windows and focus between screens with keyboard shortcuts
- **Modular Architecture**: Easily maintainable with centralized configuration
- **Centralized Configuration**: All settings in one config.lua file

## Project Structure

```text
~/.hammerspoon/
├── init.lua              # Main initialization file
├── config.lua            # Central configuration
└── modules/
    ├── pomodoor.lua      # Pomodoro timer module
    ├── tiler.lua         # Window management module
    ├── app_switcher.lua  # Application switching module
    ├── lru_cache.lua     # Least Recently Used cache implementation
    └── window_memory.lua # Window position memory system
```

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/)
2. Clone this repository to `~/.hammerspoon/`
3. Restart Hammerspoon

## Default Keyboard Shortcuts

### Window Management (Ctrl+Cmd)

The keyboard layout maps directly to screen positions:

```text
    y    u    i    o    p
    h    j    k    l    ;
    n    m    ,    .    /
```

Each key corresponds to a specific zone on the screen grid:

#### Left Side Keys (Left Side of Screen)

- `y`: Top-left region cycling: full height of left column → top-left cell
- `h`: Left side cycling: left two columns → left column → left three columns
- `n`: Bottom-left cycling: bottom-left cell → bottom half of left column

#### Middle Keys (Middle of Screen)

- `u`: Middle-top cycling: middle column → top half of middle column → top-middle cell
- `j`: Middle cycling: middle-right columns → middle column → middle cell
- `m`: Bottom-middle cycling: right-middle column → bottom half of middle column → bottom-middle cell

#### Right Side Keys (Right Side of Screen)

- `i`: Top-right cycling: right column → top half of right column → top-right cell
- `k`: Right side cycling: two rightmost columns → right column → middle-right cell
- `,`: Bottom-right cycling: bottom-right cell → bottom half of right column
- `o`: Top-right cycling: top-right cell → top-right two cells wide
- `l`: Right side cycling: right column → right two columns → right half
- `.`: Bottom-right cycling: bottom-right two cells wide → bottom-right cell

#### Special Positions

- `0`: Center cycling: center quarter → center two-thirds → full screen

### Window Movement Between Screens

- `Ctrl+Cmd+p`: Move current window to the next screen
- `Ctrl+Cmd+;`: Move current window to the previous screen

### Focus Management

- `Shift+Ctrl+Cmd+[zone key]`: Focus on windows in that zone (cycles through windows)
- `Shift+Ctrl+Cmd+p`: Move focus to next screen
- `Shift+Ctrl+Cmd+;`: Move focus to previous screen

### App Switching (Shift+Ctrl)

- `Shift+Ctrl+[key]`: Launch or toggle application based on key bindings in config.lua
- `Shift+Ctrl+/`: Display help with keyboard shortcuts

### Pomodoro Timer

- `Ctrl+Cmd+9`: Start pomodoro timer
- `Ctrl+Cmd+0`: Pause/reset pomodoro timer
- `Shift+Ctrl+Cmd+0`: Reset work count

### Utility Functions

- `Hyper+- (minus)`: Display window hints
- `Hyper+= (equals)`: Launch Activity Monitor
- `Shift+Ctrl+Cmd+R`: Reload configuration

## Customization

All customization is done through the `config.lua` file, which serves as the single source of truth for all settings.

### Key Combinations

```lua
config.keys = {
    mash = {"ctrl", "cmd"},
    mash_app = {"shift", "ctrl"},
    mash_shift = {"shift", "ctrl", "cmd"},
    HYPER = {"shift", "ctrl", "alt", "cmd"}
}
```

### App Switcher Configuration

```lua
config.app_switcher = {
    -- Apps that need menu-based hiding
    hide_workaround_apps = {'Arc'},

    -- Apps that require exact mapping between launch name and display name
    special_app_mappings = {
        ["bambustudio"] = "bambu studio" -- Launch name → Display name
    },

    -- Ambiguous app pairs that should not be considered matching
    ambiguous_apps = {
        {'notion', 'notion calendar'},
        {'notion', 'notion mail'}
    }
}

-- Application shortcuts
config.appCuts = {
    q = 'BambuStudio',
    w = 'Whatsapp',
    e = 'Finder',
    -- Add more apps here
}
```

### Window Management Configuration

```lua
config.tiler = {
    debug = true,
    modifier = {"ctrl", "cmd"},

    -- Window margin settings
    margins = {
        enabled = true,
        size = 5,
        screen_edge = true
    },

    -- Screen detection configuration
    screen_detection = {
        -- Special screen name patterns and their preferred layouts
        patterns = {
            ["DELL.*U32"] = { cols = 4, rows = 3 },  -- Dell 32-inch monitors
            ["LG.*QHD"] = { cols = 1, rows = 3 },    -- LG QHD in portrait mode
        },

        -- Size-based layouts (screen diagonal in inches)
        sizes = {
            large = { min = 27, layout = "4x3" },      -- 27" and larger - 4x3 grid
            medium = { min = 24, max = 26.9, layout = "3x3" },  -- 24-26" - 3x3 grid
            standard = { min = 20, max = 23.9, layout = "3x2" }, -- 20-23" - 3x2 grid
            small = { max = 19.9, layout = "2x2" }     -- Under 20" - 2x2 grid
        },

        -- Portrait mode layouts
        portrait = {
            large = { min = 23, layout = "1x3" },     -- 23" and larger in portrait - 1x3 grid
            small = { max = 22.9, layout = "1x2" }    -- Under 23" in portrait - 1x2 grid
        }
    },

    -- Custom layouts for specific screens (exact name match)
    layouts = {
        custom = {
            ["DELL U3223QE"] = { cols = 4, rows = 3 },
            ["LG IPS QHD"] = { cols = 1, rows = 3 }
        }
    },

    -- Default zone configurations
    default_zone_configs = {
        ["y"] = {"a1:a2", "a1", "a1:b2"},
        ["h"] = {"a1:b3", "a1:a3", "a1:c3", "a2"},
        -- More zone configurations...
    },

    -- Portrait mode zone configurations
    portrait_zones = {
        ["y"] = {"a1", "a1:a2"},
        ["h"] = {"a2", "a1:a3"},
        -- Additional settings...
    }
}
```

### Pomodoro Settings

```lua
config.pomodoro = {
    enable_color_bar = true,
    work_period_sec = 52 * 60,  -- 52 minutes
    rest_period_sec = 17 * 60,  -- 17 minutes
    indicator_height = 0.2,
    indicator_alpha = 0.3,
    indicator_in_all_spaces = true,
    color_time_remaining = hs.drawing.color.green,
    color_time_used = hs.drawing.color.red
}
```

## Screen Detection

The system uses a multi-stage process to detect the appropriate layout for each screen:

1. **Exact Name Match**: Check if the screen name matches a layout in `layouts.custom`
2. **Pattern Match**: Check if the screen name matches any pattern in `screen_detection.patterns`
3. **Size Detection**: Extract screen size from name and match against `sizes` or `portrait` settings
4. **Resolution Fallback**: If other methods fail, determine layout based on resolution

For custom monitor layouts, you can add new entries to the pattern detection:

```lua
config.tiler.screen_detection.patterns["YOUR_PATTERN"] = { cols = 3, rows = 2 }
```

## Grid Coordinate System

The tiler uses a grid coordinate system with alphabetic columns and numeric rows:

```text
    a    b    c    d
  +----+----+----+----+
1 | a1 | b1 | c1 | d1 |
  +----+----+----+----+
2 | a2 | b2 | c2 | d2 |
  +----+----+----+----+
3 | a3 | b3 | c3 | d3 |
  +----+----+----+----+
```

You can define regions using:

1. String coordinates like `"a1"` (single cell) or `"a1:b2"` (rectangle from a1 to b2)
2. Named positions like `"center"`, `"left-half"`, `"top-half"`, etc.
3. Table coordinates like `{1,1,2,2}` for programmatic definitions

## Troubleshooting

If windows are not positioning correctly:

1. **Enable Debug Mode**: Set `config.tiler.debug = true` in config.lua
2. **Check Screen Detection**: See if your screen is being correctly identified in the Hammerspoon console
3. **Add Pattern Match**: Add a pattern for your monitor to `screen_detection.patterns`
4. **Reload Configuration**: Use `Cmd+Ctrl+Shift+R`
5. **Check Console**: Examine the Hammerspoon console for error messages

## Planning

- [x] Focus on Zone keyboard shortcut (Switch to the topmost window in a zone and cycle through them)
- [x] Cross-screen focus navigation (Move focus between screens with keyboard shortcuts)
- [x] Smart window mapping (Automatically detect and map existing windows to appropriate zones)
- [x] Modular architecture (Split functionality into separate modules with central configuration)
- [x] Centralized configuration (All settings in one config.lua file)
- [ ] Application-aware layouts (Save preferred zones for specific applications)
- [ ] Automatically arrange windows based on predefined layouts
- [ ] Dynamic row and column resizing
- [ ] Zen mode (minimize all windows other than the active one)
- [ ] Automatic window resizing based on content
- [ ] Save and load window layouts
- [ ] Support for Mac spaces
- [ ] Window stacking within zones (keep multiple windows in a single zone and cycle through them)
- [ ] Grid visualization overlay (display the grid layout temporarily when positioning windows)
- [ ] Mouse-based zone selection (Shift+drag to select a custom zone)
- [ ] Zone presets (quickly switch between different zone layouts)

## Credits

- Built with [Hammerspoon](https://www.hammerspoon.org/)
- Window Tiler inspired by grid layout systems
- Pomodoro timer based on the Pomodoro Technique®