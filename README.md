# ZoneTilerWM

ZoneTilerWM is a kinesthetic window manager for macOS that maps window placement to your keyboard layout. It learns your preferences to automate window arrangement, reducing cognitive load and making window management a matter of muscle memory.

It is a standalone native Swift app — an `LSUIElement` menubar agent in `native/` (SwiftPM), with no Hammerspoon dependency. See [native/ARCHITECTURE.md](native/ARCHITECTURE.md).

> This project began as a Hammerspoon/Lua config and was ported to Swift against the Lua as an executable spec (validated with a Lua↔Swift differential-oracle harness). Once the port reached parity it became the product and the Lua was removed; it remains in git history and on the original `.hammerspoon` `origin` remote.

## Native port (v2) status

The native agent is feature-complete, including the full settings GUI. It reads the same `config.toml` and `~/.config/ZoneTilerWM/*.json` as the Lua version.

Done and verified (differential vs Lua and/or live screenshot validation): zone tiling, auto-tile, focus cycling, working-set focus tracking, app switcher, adaptive window memory (with recency/time decay), audio switch, Pomodoro (glass menubar pill + color bar), zen mode, resize mode (zone grid-line adjustment + live overlay), window hints (app icon + keyboard-half spatial assignment), hotkey-conflict detection, config live-reload, overlays, multi-monitor navigation, and the settings GUI (6 tabs: General / Keys / Apps / Layouts / Pomodoro / Advanced, a keybind editor, a visual layout editor, and a separate analytics window with learned-placement heatmaps).

Multi-monitor: logical monitor ids are seeded from the display arrangement at startup and re-registered on connect/disconnect/rearrange (`NSApplication.didChangeScreenParametersNotification`), so zone memory and resize offsets resolve to the right display after a hot-plug. Validated live on a two-display setup.

Remaining:

- Productization polish: Developer ID signing + notarization (currently ad-hoc), launch-at-login (`SMAppService`), and first-run accessibility onboarding. The `.app` bundle + CI/CD exist (below).
- UI/performance polish tracked in [native/REVIEW.md](native/REVIEW.md). None are correctness regressions.

Develop, test, and build:

```sh
./build.sh         # build the native package (pass-through flags, e.g. ./build.sh -c release)
./run.sh           # build and launch the agent in the foreground (Ctrl-C to quit)
make verify        # swift unit + golden tests
make app           # build ZoneTilerWM.app (Release, ad-hoc signed) via xcodegen + xcodebuild
```

Current baseline: 142 Swift tests green; ~92% line coverage on the pure-logic core (`ZTCore`). The OS-adapter/UI layers are validated via live screenshot QA + the post-move AX frame readback rather than unit tests — see [native/REVIEW.md](native/REVIEW.md).

### Packaging & CI/CD

- **`.app` bundle:** `project.yml` (XcodeGen) generates `ZoneTilerWM.xcodeproj` — a thin app target that links the SwiftPM package and ships as an `LSUIElement` menubar agent (`com.zaidenstein.ZoneTilerWM`), ad-hoc signed. `make app` builds it. The generated project + `build/` are gitignored; `project.yml` is the source of truth. Installed builds read/seed config at `~/.config/ZoneTilerWM/config.toml`.
- **CI** ([.github/workflows/ci.yml](.github/workflows/ci.yml)): on push/PR, runs `make verify` + the `.app` build on a **self-hosted macOS runner** (this Mac — avoids 10×-billed hosted-macOS minutes on the private repo; no signing secrets leave the machine).
- **Release** ([.github/workflows/release.yml](.github/workflows/release.yml)): pushing a `v*` tag builds the Release `.app`, zips it, and attaches it to a GitHub Release.
- **One-time runner setup:** repo Settings → Actions → Runners → New self-hosted runner (macOS); apply the `self-hosted` + `macOS` labels. Needs `xcodegen` (`brew install xcodegen`) on PATH.

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
* **Auto-Tiling**: Automatically arrange all windows into optimal positions using a **Cost-Based Backtracking Solver** (CSP).
    *   **Recency-Weighted**: Prioritizes your most recently used windows for prime spots.
    *   **Coverage Maximization**: Aggressively fills available screen space.
    *   **Memory-Augmented**: Remembers where you like your apps.
    *   **Shape-Aware**: Matches window aspect ratios to tile shapes.
* **Highly Configurable**: Customize everything from keybindings to layouts in a single `config.toml` file.
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

1. Clone this repository.
2. Build and launch the agent: `./run.sh` (or `./build.sh` then run `native/.build/debug/zt-agent`).
3. Grant Accessibility permission to the binary when prompted (System Settings → Privacy & Security → Accessibility) — required to move other apps' windows.
4. Edit `config.toml` to customize zones, keybindings, and apps; the agent live-reloads on save. The settings GUI (menubar → Settings…) edits the same file.

---

## Project Structure

```text
ZoneTilerWM/
├── config.toml              # Main configuration file (TOML) — read by the agent
├── build.sh / run.sh        # Build / build-and-launch helpers
├── Makefile                 # make verify (swift tests), build, probe
├── native/                  # The Swift product (SwiftPM)
│   ├── Package.swift
│   ├── ARCHITECTURE.md      # Design, layering, conventions
│   ├── REVIEW.md            # Engineering / perf / UX review + coverage
│   ├── Sources/
│   │   ├── ZTCore/          # Pure logic (no AppKit): solver, zones, placement,
│   │   │                    #   memory, auto-tiler, focus, monitor mgr, …
│   │   ├── ZTSystem/        # OS adapters: AX window control, CGWindowList enum,
│   │   │                    #   NSScreen, Carbon hotkeys, CoreAudio, TOML, config
│   │   ├── ZTUI/            # SwiftUI settings (6 tabs) + analytics window
│   │   ├── zt-agent/        # The LSUIElement menubar agent (composition root)
│   │   └── zt-probe / zt-tile / …  # small dev CLIs
│   └── Tests/               # XCTest suites + Fixtures/ (frozen golden corpus)
├── docs/                    # Design notes & references (some Hammerspoon-era history)
└── Assets/                  # App icon (light/dark) + menubar glyph
```

See [native/ARCHITECTURE.md](native/ARCHITECTURE.md) for the module map and the `ZTCore` /
`ZTSystem` / `ZTUI` layering rules.

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

* `Ctrl+Cmd+8` → Start timer
* `Ctrl+Cmd+9` → Pause
* `Shift+Ctrl+Cmd+8` → Reset work count

### Utility

* `Hyper+\` → Toggle Zen mode (hides all other windows)
* `Ctrl+Cmd+r` → Toggle Resize Mode (Arrow keys to adjust grid)
* `Hyper+-` → Show window hints
* `Hyper+=` → Open Activity Monitor
* `HYPER+Enter` → **Auto-Tile All Windows** (Ripple, Compaction, and Gap-Filling)
* `Shift+Ctrl+Cmd+R` → Reload config

---

## Configuration Overview

All settings are centralized in `config.toml`:

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

You can extend the detection logic in `config.toml` under `[tiler.screen_detection.patterns]`.

---

## Troubleshooting

* Run the agent from a terminal (`./run.sh`) to watch its stderr log — it reports each hotkey bind, tile decision, display arrangement, and any hotkey conflicts.
* Reload config: `Shift+Ctrl+Cmd+R` (or edit `config.toml` — the agent live-reloads on save).
* Add a screen pattern or custom name under `[tiler.screen_detection.patterns]` if detection fails.
* If window moves silently fail, confirm the binary still has Accessibility permission (re-signing can reset the grant).

---

## Documentation

For detailed documentation, see the [docs/](docs/) folder:

* **[Native Architecture](native/ARCHITECTURE.md)** - Design, layering (`ZTCore`/`ZTSystem`/`ZTUI`), conventions, feature status
* **[Review](native/REVIEW.md)** - Engineering (Linus/Uncle Bob), performance (Carmack), and UI/UX (Rams/Kare) review plus the code-coverage breakdown
* **[Tutorial / Getting Started](native/Sources/ZTUI/Resources/Tutorial.md)** - New-user walkthrough (also in the menubar → Tutorial)
* **[Keyboard Reference](docs/keyboard_shortcuts.md)** - Complete shortcut list
* **[SentinelOne Performance](docs/SENTINELONE_INVESTIGATION.md)** - Why AX-call count is the primary perf constraint, and how the agent minimizes it (CGWindowList reads, memoized EnhancedUI toggle)
* **[Auto-tiling Design](docs/auto-tiling_algorithmic_design.md)** - The cost-based backtracking solver and scoring
* **[Spaces Research](docs/SPACES_RESEARCH.md)** - macOS Spaces implementation research (out of scope)

Some files under `docs/` (and `native/REMAINING_PORT_PLAN.md`) are Hammerspoon-era history kept for reference.

---

## Credits

* Built with Swift + AppKit; originally prototyped on [Hammerspoon](https://www.hammerspoon.org/)
* Inspired by grid-based WMs like Amethyst and yabai
* Pomodoro adapted from the Pomodoro Technique
