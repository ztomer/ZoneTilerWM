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

**Environment caveat:** only ONE monitor is attached right now. Slice 4 (multi-monitor nav)
will be implemented to spec against the Lua but can only be **validated theoretically**
(unit tests with synthetic multi-screen snapshots); live multi-display capture is deferred
until a second display is available.

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

## Slice 4 — Multi-monitor navigation (THEORETICAL on single-monitor)

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
no-op-safe on a single monitor; `make verify` green. Live validation deferred.

---

## Slice 5 — Smaller remaining parity (batch later)

- **Window hints** — quick-jump overlay labels per window (overlay + key capture).
- **Placement-mode / zone-info overlays** — transient informational overlays.
- **ZTUI v2 editors** — keybind capture editor + visual direct-manipulation layout editor
  (currently Layouts is a read-only list; General/Memory done). Lower priority; the original
  plan marks these as the genuinely-rich views to do last.

---

## Execution order

1 → 2 → 3 → 4 → 5, one slice per commit, `make verify` green between each, visual pass where
a slice changes something on screen. Slice 1 and 3 add new differential oracles / overlay
geometry tests; slice 4 is unit-test-only until a second monitor is available.
