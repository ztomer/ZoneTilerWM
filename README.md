# ZoneTilerWM

ZoneTilerWM is a modular and powerful tiling window manager for macOS, built on top of Hammerspoon. It combines zone-based window organization, intelligent multi-monitor support, powerful keyboard navigation, and productivity tools like an integrated Pomodoro timer.

## Implemented Features

* **Zone-Based Window Management**: Define reusable window zones using a flexible grid-based coordinate system.
* **Smart Screen Detection**: Automatically adapts to screen size, resolution, orientation, and known device patterns.
* **Multi-Screen Support**: Move and focus windows across screens with ease.
* **Focus Control**: Instantly switch focus within a zone or across monitors using intuitive shortcuts.
* **Application Switching**: Bind hotkeys to launch or toggle commonly used applications.
* **Window Memory**: Remembers window placements and restores them intelligently.
* **Pomodoro Timer**: Visual work/rest timer with screen indicators.
* **Modular Architecture**: Easy to maintain, configure, and extend.
* **Centralized Configuration**: All behavior is defined in a single `config.lua` file.

## Still TODO

* [ ] Application-aware layouts (save preferred zones per app)
* [ ] Automatically arrange windows on launch
* [ ] Dynamic resizing of rows and columns
* [ ] Zen mode (minimize all but active window)
* [ ] Adaptive window sizing based on content
* [ ] Persistent layout save/load
* [ ] Support for macOS Spaces
* [ ] Window stacking in zones
* [ ] Visual grid overlay
* [ ] Mouse-driven zone selection
* [ ] Layout presets for workflows

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
└── modules/
    ├── tiler.lua         # Core tiling orchestrator
    ├── monitor_manager.lua # Stable monitor identification
    ├── zone_calculator.lua # Zone and tile geometry calculation
    ├── window_state_manager.lua # Manages window tiler states
    ├── smart_placer.lua  # Intelligent new window placement
    ├── focus_manager.lua   # Manages focus cycling within zones
    ├── window_actions.lua  # Core window manipulation functions
    ├── window_memory.lua # Window memory and recall
    ├── app_switcher.lua  # App hotkey binding module
    ├── pomodoor.lua      # Pomodoro timer display and logic
    └── lru_cache.lua     # Helper LRU cache for window focus history
    # Note: window_state.lua is a temporary compatibility layer and will be removed.
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

* `Hyper+-` → Show window hints
* `Hyper+=` → Open Activity Monitor
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

## Credits

* Powered by [Hammerspoon](https://www.hammerspoon.org/)
* Inspired by grid-based WMs like Amethyst and yabai
* Pomodoro adapted from the Pomodoro Technique
