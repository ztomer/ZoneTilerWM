# v6 — new features (#26): Mission Control overlay + Chrome ⌘S

Two features from the live review. Both gated default-off. The pure logic is unit-tested now; the
parts that need private APIs / live AX are flagged for a paired session.

## A. Mission Control overlay (window-hints over Exposé + per-window close)

**Goal:** when Mission Control (Exposé) is active, overlay each exposed window with a typed hint
label (press it to jump straight to that window) and a small (×) to close the window — reusing the
window-hints idiom.

### Done — pure layer (`ZTCore/MissionControl.swift`, 6 tests)
- `Tile { windowId, frame }` in → `Hint { windowId, label, badge, close }` out.
- Label assignment via `WindowHints.labels` (home-row first); badge centred in each tile; (×) at the
  tile's top-right, all clamped inside tiny tiles.
- `resolve(typed:)` → window id (case-insensitive), `matches(prefix:)` for two-key labels / live
  filtering, `closeHit(at:)` → window id for clicking the ×. Value-in/value-out, no OS.

### Remaining — live (needs a paired session; the risky part)
1. **Detect Mission Control is active + read the exposed tiles.** No public API. Options, in order:
   - Private **CGS/SkyLight** spaces/exposé calls (`CGSGetWindowList` + exposé state) — clean-room,
     like the SkyLight border renderer. Highest fidelity (real tile rects).
   - Heuristic fallback: watch for the Mission Control process / a Dock exposé notification and read
     `CGWindowListCopyWindowInfo` rects (may not match the animated exposé layout).
   Feed the resulting tiles into `MissionControl.hints`.
2. **Draw the overlay** above the exposé layer (window level / collection behavior) — reuse the
   window-hints overlay view for the badges; add the (×) chips.
3. **Capture keys/clicks while active:** a local event monitor; typed label → `resolve` → raise the
   window (existing `focus(windowId:)`); click in a × rect → `closeHit` → AX-close that window.
4. **Gate:** `[mission_control] enabled` (default off), bind a trigger, reconcile on reload.

**Risk:** the private-API tile read is the unknown; if it's not viable, fall back to the heuristic
or shelve. Everything downstream of the tiles is already done + tested.

## B. Chrome ⌘S — toggle the vertical tab strip

**Goal:** when Chrome is frontmost in side-tab mode, ⌘S collapses/expands the tab strip (there's a
button but no shortcut). Niche, likely short-lived — keep it cheap + isolated.

### Plan (small, needs live AX inspection)
- A frontmost-app-scoped hotkey: intercept ⌘S only while Chrome is the frontmost app (leave Save
  alone everywhere else).
- On fire, AX-press the tab-strip collapse control. Needs live inspection of Chrome's AX tree
  (Accessibility Inspector) to locate the control — the one genuinely live step.
- Gate: `[chrome_tabs] enabled` (default off); fully isolated so it can be removed cheaply later.

**Risk:** Chrome's AX tree for that control may be unstable across versions; if it can't be located
reliably, drop it (it's explicitly disposable).
