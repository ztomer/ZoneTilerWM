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

## Slice 1 — Live auto-place on new windows (highest value, hardest)

**Goal:** opening/closing a window re-runs the auto-tiler automatically, the way the Lua
does via Hammerspoon's `window.filter` / `hs.window.filter` subscriptions. Today auto-tiling
only fires on the manual `HYPER+return`.

**Lua ground truth:** `modules/auto_tiler.lua` (the 4-pass cascade + working-set culling) is
already ported and diffed (`diff_autotiler.sh`). What's NOT yet ported is the *trigger* —
the Lua subscribes to window-created / -destroyed / -focused events and calls the tiler.
Find the subscription wiring in `init.lua` / `modules/tiler.lua` / wherever the
`hs.window.filter` callbacks live, and treat its debounce + which-events-trigger-retile as
the spec.

**Native technique:**
- `NSWorkspace.shared.notificationCenter` for app launch/terminate is coarse; per-window
  needs AX observers: `AXObserverCreate` + `AXObserverAddNotification` for
  `kAXWindowCreatedNotification`, `kAXUIElementDestroyedNotification`,
  `kAXFocusedWindowChangedNotification`, `kAXApplicationActivatedNotification` on each
  running app's `AXUIElement` (`AXUIElementCreateApplication(pid)`).
- Need an app-lifecycle watcher (`NSWorkspace didLaunchApplicationNotification` /
  `didTerminateApplicationNotification`) to attach/detach AX observers as apps come and go.
- Debounce a burst of events (apps often emit several on open) before re-tiling — mirror the
  Lua's debounce interval.
- Respect the working-set / excluded-apps / `auto_tiling_mode` config already loaded.

**New differential oracle (required — this is a coordinator decision):**
- `tools/oracle_autoplace.lua` — given (current windows, screens, config, memory, the
  new-window event) run the real Lua trigger+auto_tiler path, emit the resulting
  assignment map.
- Swift side: a `zt-oracle autoplace` mode over the same contract.
- `tools/gen_fuzz_autoplace.lua` + `cmp_autoplace.lua` + `diff_autoplace.sh`; add to
  `make verify`'s harness loop and `tools/verify.sh`.
- Add a `ZTCore` behavioral test for the new-window→placement decision.

**Layering:** the *decision* (which zone for the new window) stays in `ZTCore`
(value-snapshot in, assignment out). The AX observer plumbing is a `ZTSystem` adapter behind
a `WindowEventSource` protocol (`onWindowCreated/Destroyed/FocusChanged` callbacks) so the
coordinator is testable with a fake event source.

**User-POV validation:** launch agent, open a fresh window (e.g. a new Finder window), screenshot
that it auto-tiled into the expected zone; deterministic assertion = post-event AX frame readback.

**Done when:** diff_autoplace green over a few hundred seeds; live new-window auto-tiles
correctly on screenshot + AX readback; `make verify` green.

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
