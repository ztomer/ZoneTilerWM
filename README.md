# ZoneTilerWM

ZoneTilerWM is a kinesthetic window manager for macOS that maps window placement to your keyboard layout. It learns your preferences to automate window arrangement, reducing cognitive load and making window management a matter of muscle memory.

## Features

* **Zone-Based Tiling**: Arrange windows in a grid-based system mapped to your keyboard.
* **Adaptive Window Memory**: Automatically places applications in their preferred zones.
* **Target Space Optimization**: Intelligently assign windows to zones to maximize screen real estate.
* **Multi-Monitor Support**: Intelligently adapts to different screen layouts and resolutions.
* **Focus Management**: Quickly switch focus between windows and monitors.
* **Application Launcher**: Bind hotkeys to launch or switch to your favorite apps.
* **Audio Device Switching**: Cycle through audio devices with a hotkey.
* **Pomodoro Timer**: A built-in Pomodoro timer to help you stay focused.
* **Dynamic Resizing**: Adjust grid lines on the fly with visual feedback.
* **Auto-Tiling**: Automatically arrange all windows into empty gaps with recursive ripple logic and top-left priority.
* **Highly Configurable**: Customize everything from keybindings to layouts in a single `config.lua` file.
* **Config Validation**: Startup checks to ensure your configuration is valid.

## Future Features

* Adaptive window sizing based on content
* Persistent layout save/load
* Support for macOS Spaces
* Window stacking in zones
* Mouse-driven zone selection
* Layout presets for workflows

---

## Installation

1. Download and install [Hammerspoon](https://www.hammerspoon.org/).
2. Clone this repository into `~/.hammerspoon/`.
3. Launch Hammerspoon and reload configuration.
4. Edit `config.lua` to customize zones, keybindings, and apps.

---

## Project Structure

```text
~/.hammerspoon/
├── init.lua              # Entry point
├── config.lua            # Configuration for keys, layouts, and features
├── docs/                 # Documentation
│   ├── ARCHITECTURE.md   # System design and module overview
│   ├── auto-tiling_algorithmic_design.md # Advanced tiling logic and scoring
│   ├── CONTRIBUTING.md   # Development guidelines
│   ├── GEMINI.md         # AI copilot instructions
│   ├── SPACES_RESEARCH.md # macOS Spaces implementation research
│   └── keyboard_shortcuts.md # Complete keyboard reference
├── modules/              # Core functionality modules
│   ├── tiler.lua         # Core tiling orchestrator
│   ├── monitor_manager.lua # Stable monitor identification
│   ├── zone_calculator.lua # Zone and tile geometry calculation
│   ├── window_state_manager.lua # Manages window tiler states
│   ├── smart_placer.lua  # Intelligent new window placement
│   ├── placement_strategy.lua # Determines the best tile for a window
│   ├── focus_manager.lua   # Manages focus cycling within zones
│   ├── window_actions.lua  # Core window manipulation functions
│   ├── window_memory.lua # Window memory and recall
│   ├── layout_manager.lua # Layout persistence
│   ├── app_switcher.lua  # App hotkey binding module
│   ├── audio_switcher.lua # Audio device switching
│   ├── pomodoor.lua      # Pomodoro timer display and logic
│   ├── space_manager.lua  # macOS Spaces management
│   ├── space_menubar.lua  # Spaces menubar indicator
│   ├── space_preview.lua  # Spaces visual preview
│   ├── space_storage.lua  # Spaces persistence
│   ├── storage.lua       # Generic JSON storage
│   └── lru_cache.lua     # Helper LRU cache for window focus history
├── debug/                # Debug and development tools
│   ├── README.md         # Debug system documentation
│   ├── init.lua          # Debug system entry point
│   ├── config.lua        # Debug configuration
│   ├── logger.lua        # Centralized logging system
│   ├── keystroke_monitor.lua # Keyboard event debugging
│   └── inspection.lua    # State inspection utilities
└── tests/                # Test suite
    ├── test_runner.lua   # Test harness
    ├── test_storage.lua  # Storage module tests
    ├── test_window_memory.lua # Window memory tests
    ├── test_config_validator.lua # Config validation tests
    └── mock_hs.lua       # Hammerspoon API mocks
```

---

## Grid Coordinate System

Used to define tile zones like `a1` (top-left) to `d3` (bottom-right).

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

---

## Default Keyboard Shortcuts

### Zone Window Placement (Ctrl+Cmd)

Grid is mapped to your keyboard:

```text
    y    u    i    o
    h    j    k    l
    n    m    ,    .
```

* `y` → top-left cycle
* `h` → left side zones
* `n` → bottom-left zones
* `u` → middle-top cycle
* `j` → center cycle
* `m` → bottom-middle
* `i` → top-right cycle
* `k` → right-mid
* `,` → bottom-right
* `o` → wide top-right
* `l` → wide right side
* `.` → wide bottom-right
* `0` → center/fullscreen toggle

### Move Window Across Screens

* `Ctrl+Cmd+p` → Move window to next screen
* `Ctrl+Cmd+;` → Move window to previous screen

### Focus Windows in Zones (Cycle)

* `Shift+Ctrl+Cmd+[zone key]` → Focus on windows in zone
* `Shift+Ctrl+Cmd+p` → Move focus to next screen
* `Shift+Ctrl+Cmd+;` → Move focus to previous screen

### App Launching (Shift+Ctrl)

* `Shift+Ctrl+[key]` → Toggle mapped app
* `Shift+Ctrl+/` → Display app keybindings help

### Pomodoro Timer

* `Ctrl+Cmd+9` → Start timer
* `Ctrl+Cmd+0` → Pause/reset
* `Shift+Ctrl+Cmd+0` → Reset work count

### Utility

* `Hyper+\` → Toggle Zen mode (hides all other windows)
* `Hyper+r` → Toggle Resize Mode (Arrow keys to adjust grid)
* `Hyper+-` → Show window hints
* `Hyper+=` → Open Activity Monitor
* `HYPER+Enter` → **Auto-Tile All Windows** (Ripple, Compaction, and Gap-Filling)
* `Shift+Ctrl+Cmd+R` → Reload config

---

## Configuration Overview

All settings are centralized in `config.lua`:

* Keybindings (`config.keys`)
* Application hotkeys (`config.appCuts`)
* App switching behaviors (e.g. ambiguous mappings)
* Tiling layouts per screen
* Window margin and spacing
* Pomodoro visual settings

You can define zones using coordinates (e.g., `"a1:b2"`) or names (`"center"`, `"right-half"`).

---

## Screen Detection Logic

ZoneTilerWM detects screen layouts in this order:

1. Exact match from `custom layouts`
2. Regex pattern match for common brands/models
3. Screen size (e.g., 4x3 for large 27" screens)
4. Orientation-specific logic
5. Fallback to resolution-based default

You can extend the detection logic in `config.lua` under `config.tiler.screen_detection`.

---

## Troubleshooting

* Set `config.tiler.debug = true` to debug screen detection or zone placement
* Use the Hammerspoon console to check layout messages
* Reload config: `Shift+Ctrl+Cmd+R`
* Add screen pattern or custom name if detection fails

---

## Documentation

For detailed documentation, see the [docs/](docs/) folder:

* **[Architecture Overview](docs/ARCHITECTURE.md)** - System design and data flow
* **[Contributing Guide](docs/CONTRIBUTING.md)** - Development guidelines
* **[Keyboard Reference](docs/keyboard_shortcuts.md)** - Complete shortcut list
* **[AI Copilot Guide](docs/GEMINI.md)** - Instructions for AI assistants
* **[Spaces Research](docs/SPACES_RESEARCH.md)** - macOS Spaces implementation research
* **[Native Port Plan](docs/NATIVE_PORT_PLAN.md)** - Future Swift migration roadmap

---

## Debugging

ZoneTilerWM includes a comprehensive debug system for development and troubleshooting.

### Quick Start

Access debug commands from the Hammerspoon console:

```lua
zt_debug.help()                    -- Show all available commands
zt_debug.keystroke.start()         -- Start keystroke monitor
zt_debug.inspect.debug_zone("left") -- Inspect a zone
zt_debug.enable_module("tiler")    -- Enable debug logging for a module
```

### Debug Features

* **Centralized Logging** - Module-specific debug logs with configurable levels
* **Keystroke Monitor** - Capture and log all keyboard events for debugging key bindings
* **State Inspection** - Examine zones, windows, focus state, and audio devices
* **Runtime Configuration** - Enable/disable debug features without editing files

### Configuration

Edit [debug/config.lua](debug/config.lua) to configure:

* Module-specific debug flags
* Log levels and formatting
* Keystroke monitor auto-start
* Performance monitoring

For complete documentation, see [debug/README.md](debug/README.md).

---

## Credits

* Powered by [Hammerspoon](https://www.hammerspoon.org/)
* Inspired by grid-based WMs like Amethyst and yabai
* Pomodoro adapted from the Pomodoro Technique
