# Welcome to ZoneTilerWM

ZoneTilerWM tiles your windows into **zones mapped to your keyboard**, so window management becomes muscle memory. Each zone lives on a key roughly where it sits on screen — top-left windows on the top-left keys, and so on.

## First run

Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility). macOS requires it for an app to move other apps' windows. The agent lives in the menubar; there's no Dock icon.

## The zone keyboard

Zones map to three letter rows plus `0`:

    y  u  i  o      top row
    h  j  k  l      home row
    n  m  ,  .      bottom row
          0         center / full screen

`j` is center, `h` left, `k` right, and `y` `o` `n` `.` the corners. The exact tiles per zone depend on the monitor's grid (Settings → Layouts).

## Tiling and focus

- **Tile the focused window:** hold the tile modifier (`⌃⌘`, "mash") and press a zone key. Press the same key again to cycle that zone's tile variations (e.g. `h` → left third → left half).
- **Focus windows in a zone:** `⇧⌃⌘` + zone key cycles focus through the windows already in that zone.
- **Auto-tile the screen:** `HYPER+Return` (HYPER = `⇧⌃⌥⌘`) arranges every window at once, using what it has learned about your habits.
- **Drag-to-snap** (opt-in): hold the tile modifier while dragging a window — it snaps into the zone under the cursor on drop. Enable under Settings → Tiling.

## Launching apps

- `⇧⌃` + key ("mash_app") launches / focuses your everyday apps.
- `HYPER` + key launches a second set (less-frequent apps).
- Edit both maps visually in Settings → **App Launcher**.

## Window features

- **Resize mode — `mash+r`:** arrow keys nudge the zone grid lines; `Esc` saves.
- **Window hints — `HYPER+-`:** labels every window; type a label to focus it.
- **Exposé:** a keyboard-driven Mission-Control replacement — every window laid out in a grid with a jump label; type a label to raise it, or use `↵` open / `⌘W` close / `⌘M` minimize / `⌘Q` quit and arrow / `hjkl` / `wasd` to move the selection. Works across all displays. Bind a hotkey (or trigger it from the command palette / CLI) under Settings.
- **Zen mode — `HYPER+\`:** hides every window except the focused one.
- **Multi-monitor:** `mash+p` / `mash+;` move the window to the next / previous display; `⇧⌃⌘+p` / `⇧⌃⌘+;` move focus between displays.

## Spaces (experimental)

ZoneTilerWM can show your real macOS **Spaces in the menubar**, grouped per monitor, with the current one filled — click a cell to switch, right-click to rename a Space. Because reading real Spaces uses a private macOS API, it's **off by default**; turn it on under Settings → **Exposé & Hints**. It's monitor-aware: connect or disconnect a display and the widget re-reads and regroups automatically.

## Command palette & natural language (opt-in)

Enable the **command palette** (Settings → Automation) for a `⌘K`-style fuzzy launcher over every action — tile, autotile, focus, audio, Pomodoro, and more. With Apple Intelligence available it doubles as a **natural-language box**: type a request ("put Safari on the left half") and it runs the matching action.

## Productivity

- **Pomodoro — `mash+8` start, `mash+9` pause, `⇧⌃⌘+8` reset:** a work timer with a menubar pill and an optional color bar.
- **Audio switch — `HYPER+'`:** cycles your output devices.
- **Window memory — `HYPER+9` save, `HYPER+0` restore:** capture and recall every window's position. ZoneTilerWM also learns where you put each app and reuses it automatically.
- **Window Analytics** (menubar) shows a heatmap of where windows land, per-app footprints, a daily-activity trend, and the full learned table.

## Settings & config

- The menubar **Settings…** window edits everything via a sidebar — General, Tiling, Layouts, Exposé & Hints, Keys, Input & Output, App Launcher, Pomodoro, Appearance, Automation, Advanced — and writes changes live.
- The config file is `~/.config/ZoneTilerWM/config.toml`. Editing it by hand live-reloads automatically — no manual reload needed. If two actions share a shortcut, the agent logs a warning and the **Keys** tab shows a conflict banner.
- **Automation:** the same actions are exposed over an MCP server, a `zonetiler://` URL scheme, a CLI, App Intents, and an `[[rules]]` engine — see Settings → Automation.
- **Launch at login:** Settings → General → Startup.
