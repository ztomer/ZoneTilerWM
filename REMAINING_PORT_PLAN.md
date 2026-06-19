# ZoneTilerWM v2 — Remaining Native Parity Plan

Status as of commit `415eec2` (branch `v2`). The pure `ZTCore` algorithmic IP, all
headless adapters, the live hotkey features (zone tiling, auto-tile-screen, focus cycling,
app switcher, adaptive memory, audio switch, Pomodoro, zen mode, activity monitor),
overlays, and the Settings GUI v1 are **done and verified** (`make verify` green: 84 swift
tests + 8 differential harnesses + lua runner). This document is the ordered plan for the
remaining event-driven / multi-monitor glue.

**Ground rules (unchanged):** all work on local `v2`, never push. `make verify` green before
any slice is "done". Lua/Hammerspoon is ground truth for ALL behavior incl. coordinator
decisions — new decision paths get a Lua-diffed oracle. Visual features get a user-POV
screenshot pass + a deterministic test. Stage only the slice's files when committing.

**Environment update:** a second display is now attached, so Slice 4 (multi-monitor nav) and
monitor identity have been **validated live** — see Slice 4 below. The earlier single-monitor
caveat is resolved.

---

## Slice 1 — Window-cache passive focus tracking (working-set cull parity)

**SCOPE CORRECTION (Lua audit, before implementing):** the Lua does **NOT** auto-tile on
new windows. `modules/tiler.lua:55-61` subscribes to windowCreated/Opened/Destroyed but the
callbacks only call `window_cache.update(...)` (the `:57` comment "Call existing handlers
here if needed" is a no-op stub). `window_cache.lua`'s focus watcher updates each window's
`last_focused_time`. Auto-tiling fires only on the manual hotkey / `tile_on_startup`. So
"auto-place new windows" would be a NEW feature, which violates Lua-is-ground-truth — dropped.

**The real parity gap** (found at `native/Sources/ZTCore/TilerCoordinator.swift:161`): the
live agent builds every `AutoTiler.Window` with `lastFocusedTime: now`, so `now - lastFocused
== 0` for all windows and the **age-based working-set cull never fires live**. The Lua's
`auto_tiler.lua:128-136` culls windows whose `last_focused_time` is older than
`working_set.time_limit_sec` (default 1800s), reading it from `window_cache`. The ported
`AutoTiler` already implements the cull correctly *given* real timestamps — that's exactly
what `diff_autotiler.sh` exercises with per-window `last_focused_time` in its scenarios. The
agent just isn't supplying real times.

**Goal:** port `window_cache.lua`'s passive focus-time tracking so the live auto-tile feeds
true per-window `lastFocusedTime`, making the working-set cull behave like the Lua.

**Implementation (no new oracle needed — the decision is already diff_autotiler-verified):**
- `ZTCore`: pure `WindowFocusTracker` keyed by window id (`Int` / CGWindowID):
  `record(id:at:)`, `recordIfAbsent(id:at:)`, `lastFocused(id:) -> Int?`, `forget(id:)`,
  `prune(keepingIds:)`. Unit-tested.
- `TilerCoordinator`: own a `WindowFocusTracker`; add `noteFocusedWindow(now:)` (stamp the
  current focused window) and `seedFocusTimes(now:)` (stamp all currently-enumerated windows
  if absent — mirrors `window_cache.refresh` baseline). In `autoTileScreen`, replace
  `lastFocusedTime: now` with `tracker.lastFocused(id:) ?? now` (matches Lua
  `info and info.last_focused_time or now`).
- `zt-agent`: at startup, `seedFocusTimes(now:)` once after building the coordinator; a ~1s
  `Timer` calls `noteFocusedWindow(now:)` (poll granularity is negligible vs the 1800s
  threshold; the Lua is event-driven but the cull outcome is identical within seconds).
  Prune dead ids opportunistically on auto-tile.

**Tests:**
- `WindowFocusTrackerTests`: record/overwrite, recordIfAbsent doesn't clobber, prune, lazy
  default.
- `TilerCoordinatorTests` (FakeWindowSystem): seed old focus time for a window + recent for
  another, run `autoTileScreen`, assert the stale window is culled from the move set exactly
  as the Lua would (the cull threshold honored end-to-end through the coordinator).

**User-POV validation:** N/A on screen (timing behavior). The deterministic coordinator test
is the assertion. Optionally log the culled set when debugging.

**Done when:** tracker + coordinator tests green; live auto-tile honors focus age; existing
`diff_autotiler` still green; `make verify` green.

---

## Slice 2 — Config live-reload

**Goal:** editing `config.toml` (by hand or via the Settings GUI) re-applies without
restarting the agent. Replaces `hs.reload`.

**Lua ground truth:** the Lua reloads the whole Hammerspoon config; native does a targeted
re-wire (don't restart the process).

**Native technique:**
- `DispatchSource.makeFileSystemObjectSource(fileDescriptor:, eventMask: [.write, .rename,
  .delete])` on the config path; re-arm after atomic-rename (editors/`TOMLEditor` replace the
  inode). ~150ms debounce.
- On fire: re-read → `ConfigLoader.load` → `ConfigValidator`; if valid, atomically swap the
  agent's config and **re-bind hotkeys / reconfigure** the coordinator, Pomodoro, app
  switcher, audio, overlays. If invalid, keep the old config and surface the error (log +
  optional menubar flash) — never half-apply.
- **Self-write suppression:** the Settings GUI writing the file must not trigger a reload
  storm. Use a suppress-window flag around app-originated writes + a content-hash equality
  check (ignore a change whose hash matches what we just wrote). This is the trap called out
  in the original plan.

**Tests:** ZTSystem test for the watcher debounce + self-write suppression (hash equality);
ConfigValidator already covers reject-invalid. Manual: edit a hotkey in `config.toml`, confirm
the new binding works and the old one stops, without restart.

**Done when:** hand-edit reload works live; GUI save does NOT cause a reload; invalid config
is rejected with the old one intact; `make verify` green.

---

## Slice 3 — Resize mode

**Goal:** a modal resize interaction — enter mode, arrows nudge/resize the focused window on
the grid, escape exits — with a grid overlay shown while active.

**Lua ground truth:** `modules/resize_manager.lua` (already ported to `ResizeManager` in
`ZTCore`, headless-tested) + the modal hotkey handling + `grid_overlay`. Port the modal
bind-set push/pop and the overlay.

**Native technique:**
- `HotkeyBinder` push/pop of a binding set (a "modal" = swap the active Carbon hotkey table:
  on enter, bind arrows/escape; on exit, restore the normal set). The `CarbonHotkeyBinder`
  may need an explicit modal stack API.
- `GridOverlayView` in `ZTSystem` — a borderless click-through `NSWindow` (same pattern as
  `FlashOverlay`/`PomodoroBar`) drawing the active grid cells; shown on enter, hidden on exit.
- Drive frame changes through the existing `WindowSystem.move(...)` and `ResizeManager` math.

**User-POV validation:** enter resize mode, screenshot the grid overlay renders at correct
scale over the real screen; arrow → window resizes to the next grid cell (AX readback).
Deterministic test: grid-overlay rect math (a pure layout function like `PomodoroBar.layout`)
+ ResizeManager step assertions (already unit-tested).

**Done when:** overlay renders correctly (screenshot), arrows resize on grid (AX readback),
escape exits and restores normal hotkeys; `make verify` green.

**DONE (coherent design, per user choice).** The Lua resize mode was internally inconsistent
(modal arrows called `hs.grid.pushWindow*` on hs.grid's default grid, while the overlay +
`resize_manager` were about zone grid-line offsets; `resize_manager.adjust` was unwired). Built
the coherent version: resize mode adjusts the **zone** grid-line offsets via the ported
`ResizeManager`. Arrows nudge the interior line nearest the focused window (±2%, clamped ±40%),
the cyan overlay redraws live, ESC exits and persists `grid_offsets.json`. Required wiring the
offsets into placement: `TilerCoordinator` now takes a monitor-aware `offsetProvider` (keyed by
logical monitor id) instead of a fixed zero provider, so tiles reflect the offsets. Pieces:
`GridLines` (ZTCore, pure: line positions + nearest-interior-index, tested), `GridOverlay`
(ZTSystem, flipped NSView), `CarbonHotkeyBinder.register/unbind` (modal add/remove without
clobbering the main set). Validated live (screenshots: overlay + line shift) + deterministic
tests (GridLinesTests; coordinator offset→boundary). NOTE: adjusting offsets does not auto-
re-tile open windows (matches the Lua resize_manager — offsets apply on the next tile); live
re-tile-on-adjust deferred as a nicety.

---

## Slice 4 — Multi-monitor navigation (now live-validated on two displays)

**Goal:** `focus-next-screen` / `focus-prev-screen` and `move-window-to-monitor` hotkeys.

**Lua ground truth:** `modules/monitor_manager.lua` (ported to `MonitorManager`, uuid→logical
id) + the focus/move-to-screen actions in `focus_manager` / `window_actions`. Port the
ordering (screens sorted by position) + the move-and-reposition behavior.

**Native technique:** `MonitorManager` + `ScreenProvider` already give ordered screens.
focus-next/prev = pick the next screen in order, focus its frontmost window. move-to-monitor
= move the focused window to the target screen, re-placing it (preserve relative zone or
re-run placement, matching the Lua).

**Validation caveat — single monitor:** can't capture multi-display behavior live now. Cover
with **deterministic unit tests over synthetic 2–3 screen snapshots** (ordering, wrap-around,
target selection, re-placement rect). Add a differential oracle if the move-to-monitor
*decision* is non-trivial (diff vs the Lua focus/monitor logic). Mark the live screenshot
validation as deferred-until-second-display in the arch doc.

**Done when:** unit tests over synthetic multi-screen snapshots green; hotkeys bound and
no-op-safe on a single monitor; `make verify` green. (Live validation has since been completed
on two displays — see below.)

**DONE (unit-test only).** `ScreenNav` (ZTCore, pure): deterministic screen order (by x then
y), next/previous wrap index math, and the move-to-monitor placement cascade (remembered app
position → default zone "0"/"j" tile 1 → untiled; strategy 2 "maintain live tiler state"
omitted — native tracks no per-window tiler state). `TilerCoordinator.focusScreen(_:)` (focus
the frontmost same-app window on the target screen, matching the Lua) +
`moveFocusedToMonitor(_:)`. Agent binds placement_mode→move-next, zone_info→move-previous,
focus_next/prev_screen. Tests: ScreenNavTests + coordinator tests over synthetic 2-screen
snapshots.

**Live validation DONE (two displays attached).** Verified on a DELL U3223QE (main) + a
portrait Display. Found and fixed a real multi-monitor defect in the process: logical monitor
ids were assigned **lazily** (on the first tile/move op), so whichever display you acted on
first stole id 1 — but the registry is in-memory and re-derived each launch (like Lua's
`monitor_manager.init`), and the on-disk `window_positions.json` numbers the main display as 1.
The result was zone memory and resize offsets resolving to the *wrong* display after a
(re)connect. Fix (agent-side; the `MonitorManager` policy was already correct):

- `seedMonitors()` registers every screen in `NSScreen` enumeration order at startup, before
  any op, so main == 1 deterministically (logged: `2 display(s): 1=DELL U3223QE 3360x1890,
  2= 1066x1600`).
- `setupScreenWatch()` re-registers on `NSApplication.didChangeScreenParametersNotification`
  (connect / disconnect / rearrange / resolution), preserving existing ids and giving a new
  display a stable id at once. Zones recompute live per op, so nothing else is cached to
  invalidate.

Two coordinator regression tests pin it (lazy mis-keys a secondary-first tile; seeding keys it
right regardless of op order).

---

## Config-feature gaps (from a settings audit)

The settings panel exposes every config feature the v2 agent actually consumes, organized
(0e6b68d) into 6 coherent tabs (Rams/Kare — consolidate, don't shatter into single-purpose
tabs): **General** (config, tiling, keyboard layout, margins, audio) · **Keys** (zone/focus
modifiers + tiling/system actions) · **Apps** (launcher keyboard) · **Layouts** (monitors→grid→
zones + default-zone-per-app) · **Pomodoro** (settings + its own keys) · **Advanced** (window
memory + exclusions + solver weights + learned-placements data). Each feature's keybindings live
with the feature; the reusable HotkeyRowView makes that possible.

**Decoded but NOT yet wired in the agent** (so deliberately not exposed — wire the behavior
first, then add UI): `window_memory.default_zone`, `window_memory.auto_tile_fallback`,
`window_memory.settle_delay_sec` (agent passes settleEnabled:true, ignores the value),
`window_memory.save_interval_sec` (saves on-learn, no interval timer).
(`window_memory.app_zones` — DONE, bda08b8: wired as the auto-tile default-zone fallback +
editor. NB: this is new behavior; the Lua never applied app_zones either.)

**Lua config the v2 agent doesn't model at all** (port the feature before any UI):
`reposition_on_screen_change`, `center_modals` / `window_handling.modal_dialog_behavior`,
`auto_tile_deduction_excludes`, `tiler.flash_on_focus` (always on), `overlap_threshold`
(hardcoded 0.5), `focus_cycle_all_tiles`, `[tiler.advanced]` (applescript movement / window
cache / enterprise_mode / debug_logging), `[tiler.delays]`, `[tiler.cache_size]`,
`[window_memory.hotkeys]` capture/restore, `[layout_manager]`, `[tiler.screen_detection]` rule
editing (per-monitor override covers the common case).

## Slice 5 — Smaller remaining parity (batch later)

- **Window hints** — DONE. Port of `hs.hints.windowHints`: `WindowHints` (ZTCore, pure
  home-row label assignment, capped at the alphabet) + `HintOverlay` (ZTSystem, yellow badge
  per window) + an agent key-capture modal (type a label → focus that window, ESC cancels).
  Bound from `system_hotkeys.window_hints`. Live-validated (badges render centered per window;
  typing a label focuses + dismisses).
- **Config reload hotkey** — DONE. `system_hotkeys.reload` now bound to the in-process
  reloadFromDisk() (completes parity with the Lua's reload hotkey; complements Slice 2's
  watcher + menu item).
- **Hotkey-conflict detection** — DONE (beyond Lua; the Lua silently lets the last Carbon
  bind win). `HotkeyConflicts` (ZTSystem, pure `find([Binding]) -> [Conflict]`) +
  `LoadedConfig.allBindings()`/`hotkeyConflicts()` group every bind (zone tile/focus, app
  launchers, tiler/pomodoro/system actions, audio) by normalized modifier-set+key and report
  combos with >1 action. Surfaced non-blocking: agent logs them on startup + after each
  reload; the Keys tab shows a `ConflictBanner`. On the real config it flags `mash_shift+0`
  (Focus-zone-0 vs Pomodoro reset) and a Discord-vs-resize_mode clash. Unit-tested
  (`HotkeyConflictsTests`, incl. real-config).
- **Placement-mode / zone-info overlays** — N/A: in the Lua these hotkeys ARE move-to-monitor
  (next/previous), already done in Slice 4. Not separate overlays.
- **ZTUI settings** — DONE and then redesigned per feedback. IA: **General / Keybinds /
  Layouts / Analytics**.
  - General: fully actionable — Config Reveal/Open, working-set stepper, margins toggle + size
    stepper, grouped form.
  - Keybinds: each action = name | modifier-alias picker | key recorder | ⌃⌘K preview (modifier
    and key decoupled); Tile/Focus modifier pickers.
  - Apps (own tab): a **visual keyboard render** — each keycap shows the app it launches for the
    selected modifier group (App launcher / Hyper apps), mapped keys tinted; click a key to
    assign/change (Set) or clear (Remove). Full add/remove via TOMLEditor setOrAppend/removeKey.
  - A **modifier legend** (alias → glyphs) replaces per-row glyph expansion; alias pickers show
    names only.
  - **Keyboard layout** is auto-detected (TIS input source → qwerty/dvorak/colemak) and
    overridable in General → Input ([ui] keyboard_layout). Both the Apps keyboard and the
    **Layouts zone map** render from it — zones now sit on the physical keyboard, each keycap
    showing the zone mapped to that key + a mini-grid of its first tile.
  - Layouts: **monitor → grid → zones** hierarchy — monitors list with auto-detected grid +
    override picker (persists to custom_screens) + Edit-zones; **visual zone previews**
    (mini-grid per zone, first tile highlighted); click-two-cells tile editor for the selected
    zone.
  - Analytics: the learned-placements table (read-only) moved out of the editable tabs.
  - Writes go through the surgical `TOMLEditor` (now with `setOrAppend` + `removeSection`,
    tested); saves trigger Slice 2's live reload. Pure logic (`GridCells`, `Keybinding`)
    unit-tested; all four tabs validated by screenshots. Caveat: while recording a key the
    agent's global hotkeys stay active, so a captured combo fires its current action once
    (cosmetic; new binding applies on save).

---

## Execution order

1 → 2 → 3 → 4 → 5, one slice per commit, `make verify` green between each, visual pass where
a slice changes something on screen. Slice 1 and 3 add new differential oracles / overlay
geometry tests; slice 4 is unit-test-only until a second monitor is available.
