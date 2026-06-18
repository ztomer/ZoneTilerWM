# ZoneTilerWM — Tutorial

ZoneTilerWM tiles your windows into **zones mapped to your keyboard**, so window
management becomes muscle memory. Each zone lives on a key in roughly the spot it
occupies on screen — top-left windows on the top-left keys, and so on.

## First run

Grant **Accessibility** permission when prompted (System Settings → Privacy &
Security → Accessibility). macOS requires it for an app to move other apps'
windows. The agent lives in the menubar; there's no Dock icon.

## The zone keyboard

Zones map to three letter rows plus `0`:

```
    y  u  i  o          top row
    h  j  k  l          home row
    n  m  ,  .          bottom row
              0         center / full screen
```

`j` is the center, `h` the left, `k` the right, and the corners (`y` `o` `n` `.`)
the corners. The exact tiles per zone depend on the monitor's grid (see Settings →
Layouts).

## Tiling and focus

- **Tile the focused window:** hold the tile modifier (**`⌃⌘`**, "mash") and press a
  zone key. Press the **same key again** to cycle through that zone's tile
  variations (e.g. `h` → left third → left half).
- **Focus windows in a zone:** **`⇧⌃⌘` + zone key** cycles focus through the windows
  already in that zone.
- **Auto-tile the screen:** **`HYPER+Return`** (`HYPER` = `⇧⌃⌥⌘`) arranges every
  window on the screen at once, using what it has learned about your habits.

## Launching apps

- **`⇧⌃` + key** ("mash_app") launches / focuses your everyday apps.
- **`HYPER` + key** launches a second set (less-frequent apps).
- **`⇧⌃+/`** shows the app-shortcut help.

Edit both maps visually in Settings → **Apps**.

## More features

- **Resize mode — `mash+r`:** arrow keys nudge the zone grid lines; `Esc` saves.
- **Window hints — `HYPER+-`:** labels every window; type a label to focus it.
- **Zen mode — `HYPER+\`:** hides every window except the focused one.
- **Pomodoro — `mash+8` start, `mash+9` pause, `⇧⌃⌘+8` reset:** a work timer with a
  menubar pill and an optional color bar.
- **Audio switch — `HYPER+'`:** cycles your output devices.
- **Multi-monitor:** `mash+p` / `mash+;` move the window to the next / previous
  display; `⇧⌃⌘+p` / `⇧⌃⌘+;` move *focus* between displays.

## Learning & analytics

ZoneTilerWM learns where you put each app and reuses it. The menubar **Window
Analytics** window shows a heatmap of where windows land, per-app footprints, a
daily-activity trend, and the full learned table.

## Settings & config

- The menubar **Settings…** window edits everything (General, Keys, Apps, Layouts,
  Pomodoro, Advanced) and writes changes live.
- The config file is `~/.config/ZoneTilerWM/config.toml`. Editing it by hand
  live-reloads too. If two actions share a shortcut, the agent logs a warning and
  the **Keys** tab shows a conflict banner.
- **Launch at login:** Settings → General → Startup.
