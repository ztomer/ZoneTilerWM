# UI polish backlog (field feedback)

Tracking list for the settings/UI polish pass. Status: `[ ]` todo · `[~]` in progress · `[x]` done.
Keep this in sync as items land; reference the item id in commits.

## N. App launcher — custom layers (was deferred from E4)
- [x] **N1** Add **more app-launch layers** beyond the built-in two. Done via `[app_layers.<name>]`
  subtables (decoded as `[String: RawAppCuts]` → `config.appLayers`) — same TOMLEditor-addressable form
  as app groups, no `[[array]]` of tables. The agent binds every layer (binding loop + HUD palette +
  command-palette merge); the App Launcher pane renders one card per layer with a trash button, plus an
  "Add layer" row (starts on HYPER). Collision warnings (E4) already generalize. Verified live: a custom
  "Dev" layer decoded, bound ("bound 2/2 app_layers.Dev"), and rendered with its modifier + keys.
  Regression test added.
- [x] **N2** Move the **hold-to-reveal HUD** into the App Launcher (layers) panel: a "Hold-to-reveal
  HUD" card with a live palette preview (`AppLauncherHUDPreview`), a header enable toggle, and its OWN
  hold-delay (`[app_launcher_hud] enabled`/`hold_delay_ms`, decoupled from the zone HUD; agent gates via
  `reconcileAppLauncherHUD`). Verified live (preview + 200ms stepper render).
- [x] **N3** The **two built-in layers are now removable too** (kept by default as examples). Each layer
  card carries a trash button; removing `[appCuts]`/`[hyperAppCuts]` drops it from the list and unbinds
  it. Verified live: removing `[appCuts]` hid its card and the agent bound only `hyperAppCuts`.
- [x] **N4** **Per-layer enable toggle** + HUD card moved to the **top** of the App Launcher panel. Each
  layer card has a leading switch (`[<layer>] enabled`, default true); off keeps the keys but binds
  nothing (dimmed keymap, still editable) and drops the layer from the hold-to-reveal HUD. Verified live:
  toggling `[appCuts]` off dimmed its card and logged "appCuts disabled — skipping" while hyperAppCuts
  still bound. Regression test covers the `enabled` decode.

## A. Toggle-in-header (kill duplicate enable rows)
A section whose only/first control is an "Enable X" toggle should put the toggle **in the header**
(via `ToggleSection`) — a separate row that restates the title is a duplicate.

- [x] **A1** General → Startup → "Launch at login" → toggle in header.
- [x] **A2** Zone picker (HUD) → toggle in the card header (currently a separate "Show the zone picker…" row).
- [x] **A3** Drag-to-snap → toggle in the card header.
- [x] **A4** Spaces → "Show Spaces (menu bar + Exposé)" → toggle in header.
- [x] **A5** Automation → "Run shortcut on change" (audio) → add an enable/disable toggle.
- [x] **A6** App groups → toggle in header (done with E5).

## B. Window Hints & Exposé need enable toggles
- [x] **B1** Window Hints: add an enable/disable toggle (config + gate the hotkey).
- [x] **B2** Exposé / Window Grid: add an enable/disable toggle (config + gate the hotkey).

## C. Sidebar order
- [x] **C1** Move **Appearance** directly below **General**.

## D. Borders
- [x] **D1** Hazard stripes vs dashed look almost identical — make hazard **angled (trapezoid)** stripes.
- [x] **D2** Border preview swatch should render in the **selected color** AND the **selected style/type**, not hard-coded blue solid.

## E. App Launcher tab
- [x] **E1** Big empty gap in the middle — moved **App groups** out to its own new sidebar tab.
- [x] **E2** App-cuts and Hyper-app-cuts are two layers — now shown as **two stacked keymap cards at
  once** (no inner segmented tabs), each with its own modifier selector.
- [x] **E3** The app-name field is now an **`AppPickerField`** with a live fuzzy-match dropdown sourced
  from installed apps (prefix matches first). Verified live (typing "saf" → Safari).
- [x] **E4** **Key-collision warnings**: assigning a key warns if its (modifier, key) is already bound
  by another layer, a tiling/system/pomodoro hotkey, an app group, or the tiling zone keys — verified
  live (HYPER+0 → "Also system hotkey 'expose'"). The "add **more layers** (custom modifier)" part
  shipped as **N1** (below).
- [x] **E5 / A6** Removed **Scratchpad** (superseded by app groups); App groups now carry an **enable
  toggle in the header** ([ui] app_groups_enabled, gates all group hotkeys).

## F. Dock Previews
- [x] **F1** Put the **preview first** (above the controls); drop the redundant "Preview" header/caption.
- [x] **F2** The preview should show the **dock in its current position** with **two windows** for the app.
  Mock reads `DockObserver().dockEdge()` (0-AX) and orients the strip + popup accordingly.
- [x] **F3** App name is redundant — replace it with the **window name**; traffic lights stay (functional).
  Fixed in BOTH the settings mock AND the live `DockPreviewView` (dropped the app-name header row).
- [x] **F4** Verify hover previews actually trigger live. Live-tested the signed app: the Dock AX read
  returns 22 tiles, edge=right is detected correctly, and the panel renders anchored to the right-edge
  Dock with a real captured window thumbnail. (Root cause of "doesn't work": default-off + the agent
  wasn't running.) Capture + positioning + overlay all confirmed working.

## G. Zones editor
- [x] **G1** "Grid" + "Edit grid" both shown but Edit-grid doesn't actually edit the grid — clarified.
  Collapsed the redundant static "Grid: NxM" label + mislabeled "Edit grid" picker into one control,
  "Editing zones for grid: [picker]", and noted that grid rows×cols come from the monitor section.

## H. Drag-to-snap correctness
- [x] **H1** **Bug:** dragging to a zone snaps to the WRONG zone (drag to `j` → lands in `n`). Fixed:
  `DragSnap.target` now resolves against the actual per-zone tiles, not the union bounding box (which
  overlapped neighbours). Regression test added.
- [x] **H2** Let the user **cycle the zone's tiles** during a drag by **right-clicking** (counts mid-drag
  with the modifier held; offset 0 = auto-pick, each right-click steps the tile). *Needs live QA.*

## I. Settings search
- [x] **I1** Search should also match **section headers** (e.g. "window grid") and jump to that pane.
  Section-header text is indexed in each tab's `searchKeywords` (verified coverage); the sidebar
  selection now follows the top match live as you type, so it navigates straight to the pane.

## J. Analytics window
- [x] **J1** Use the selected palette (Braun **orange** + shades) instead of the old blue/multicolor.
  Heatmap ramp → muted Braun orange; bars + selection → `ZTPalette.accentColor`. *Needs live QA (no
  headless render path — analytics needs seeded placement data).*

## K. Onboarding wizard
- [x] **K1** Auto-tile shortcut shown wrong — it's **HYPER+Return**, not ⌃⌘+Return. Cheatsheet now
  derives glyphs from the live bindings (tiler modifier for picker/zone keys, HYPER for auto-tile).
- [x] **K2** Added the key missing discoverable features to onboarding: Window hints, Exposé/window
  grid, Dock previews (alongside the existing HUD / border / drag-snap / palette / window-memory).

## L. Settings titlebar / search layout
- [x] **L1** The titlebar search field **shifted position** between states (toolbar auto-justify). Fixed:
  moved `.searchable` from `.toolbar` to `.sidebar` placement so the field pins to the top of the
  sidebar column (macOS-26 Settings style) and stops jumping. Verified live — identical position in the
  just-opened and pane-selected states.

## M. Dock previews — selection feedback
- [x] **M1** On hover, **highlight both the actual on-screen window border AND the matching preview
  thumbnail**. Done: `DockPreviewView` tracks per-thumbnail hover (NSTrackingArea) → rings the hovered
  thumbnail in accent and drives a click-through `WindowHighlightOverlay` (accent outline) around the
  real window at that thumbnail's frame. Verified live — the overlay window sits at the exact hovered
  window bounds (confirmed via window-server query) and the thumbnail ring renders.
