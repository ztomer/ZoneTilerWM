# UI polish backlog (field feedback)

Tracking list for the settings/UI polish pass. Status: `[ ]` todo · `[~]` in progress · `[x]` done.
Keep this in sync as items land; reference the item id in commits.

## A. Toggle-in-header (kill duplicate enable rows)
A section whose only/first control is an "Enable X" toggle should put the toggle **in the header**
(via `ToggleSection`) — a separate row that restates the title is a duplicate.

- [x] **A1** General → Startup → "Launch at login" → toggle in header.
- [x] **A2** Zone picker (HUD) → toggle in the card header (currently a separate "Show the zone picker…" row).
- [x] **A3** Drag-to-snap → toggle in the card header.
- [x] **A4** Spaces → "Show Spaces (menu bar + Exposé)" → toggle in header.
- [x] **A5** Automation → "Run shortcut on change" (audio) → add an enable/disable toggle.
- [ ] **A6** App groups → toggle in header (see E5).

## B. Window Hints & Exposé need enable toggles
- [x] **B1** Window Hints: add an enable/disable toggle (config + gate the hotkey).
- [x] **B2** Exposé / Window Grid: add an enable/disable toggle (config + gate the hotkey).

## C. Sidebar order
- [x] **C1** Move **Appearance** directly below **General**.

## D. Borders
- [x] **D1** Hazard stripes vs dashed look almost identical — make hazard **angled (trapezoid)** stripes.
- [x] **D2** Border preview swatch should render in the **selected color** AND the **selected style/type**, not hard-coded blue solid.

## E. App Launcher tab
- [ ] **E1** Big empty gap in the middle — move **App groups** out to its own new tab to fill it.
- [ ] **E2** App-cuts and Hyper-app-cuts are two layers — show **both** at once (we have the space; no inner tabs).
- [ ] **E3** The app-name field should be an **app selector** with fuzzy matching from the installed-app list.
- [ ] **E4** Allow adding **more layers** (custom modifier), **warn on key collisions** across layers.
- [ ] **E5** App groups and Scratchpad are mutually exclusive → **remove Scratchpad**, add enable toggle to App groups header.

## F. Dock Previews
- [ ] **F1** Put the **preview first** (above the controls); drop the redundant "Preview" header/caption.
- [ ] **F2** The preview should show the **dock in its current position** with **two windows** for the app.
- [ ] **F3** App name is redundant — replace it with the **window name**; traffic lights stay (functional).
- [ ] **F4** Verify hover previews actually trigger live ("not sure it works at all").

## G. Zones editor
- [ ] **G1** "Grid" + "Edit grid" both shown but Edit-grid doesn't actually edit the grid — clarify/fix.

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
