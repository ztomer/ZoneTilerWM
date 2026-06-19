# v4 — UX review backlog (from live-app review, 2026-06-19)

Captured verbatim-in-intent from the user's hands-on review. Grouped + prioritized. Tick as done.

## A. Bugs (fix first)
- [ ] **Zone HUD doesn't map to the actual zone location** — chips must sit at each zone's real
      on-screen position (the deoverlap/coords are off in the live app, not just the render).
- [x] **Focus-follows-mouse raises the wrong window** — FIXED (v1.5.2). Was the per-display filter:
      `windows(onScreen:)` keeps only windows whose *centre* is on the cursor's display, so a window
      under the cursor whose centre sat on another display (or straddled two) was dropped and FFM
      focused the window *beneath* it. Now hit-tests `AXWindowSystem.allWindows()` — the raw
      CGWindowList front-to-back order, no centre filter. 0 AX.
- [x] **No borders during minimize/unminimize** — FIXED (v1.5.2). `FocusBorderController` now observes
      AX miniaturize/deminiaturize and mutes renders for the genie animation (0.6s), so the border
      no longer chases the shrinking/growing frame.

## B. Discoverability gaps (the features work but you can't reach/configure them)
- [ ] **Command palette: no way to assign its modifier/hotkey from the UI** — add hotkey binding in
      Keys (and surface "how to open it").
- [ ] **Drag-to-snap: which modifier?** — it's the tiling modifier; surface/state it (and allow
      configuring) in the UI.
- [ ] **Keys → modifier aliases**: define + assign aliases (mash, mash_shift, HYPER, …) from the UI.

## C. Settings restructure → SIDEBAR (top tabs are getting too complex)
- [ ] Move settings from top segmented tabs to a **sidebar layout**.
- [ ] Proposed groups (user's): **Tiling**, **I/O** (keyboard layout, audio, focus-follows-mouse),
      **App Launcher** (app cuts + hyper cuts + app groups), **Pomodoro**, **Appearance**,
      **Automation**, **Keys**, **Advanced**.
- [ ] Generate **Susan-Kare / Dieter-Rams-approved sidebar icons** for each group.

## D. Settings content changes
- [ ] **Break screen** → move from Features to the **Pomodoro** tab; rename "Retro break screen" →
      just **"Break screen"** (drop "retro").
- [ ] **Scratchpad → "App groups"**: it's really grouped apps. Make it a standalone feature with a
      **per-group hotkey** assignment (multiple named groups, each its own shortcut).
- [ ] **On-device AI is just a command-palette toggle** — group the NL toggle WITH the command
      palette (already merged in code; reflect in the UI grouping).
- [ ] **Apps tab too narrow** — the app launcher + hyper apps overflow by ~20-30px (needs a little
      horizontal scroll). Widen the window / fix the layout so it fits.
- [ ] **Pomodoro: live preview** of the color bar (look + position), updating as params change.
- [ ] **Break screen: live preview** once it's on the Pomodoro tab (also fills the empty space).
- [ ] **Appearance section** (new): window borders + margins + selection overlay, with a **shared
      live preview**. Selection overlay = the on-move/on-focus highlight; add a toggle (some find
      it distracting) + an overlay color picker.

## E. New features
- [ ] **Mission Control overlay** — when Mission Control (expose) is open, overlay each window with
      a keyboard shortcut to jump to it (reuse window-hints) + a small **(x)** to close it.
- [ ] **Chrome sidebar tabs toggle** — when Chrome is in sidebar mode, ⌘S collapses/expands the tab
      strip (there's a button but no shortcut). Niche, likely short-lived; keep it cheap + isolated.

## F. Structural / housekeeping
- [ ] **Drop the `native/` folder** — there's no non-native code anymore; flatten the layout.
- [ ] **Coverage ≥ 95%?** — measure ZTCore line coverage; report; close the gap if under.

## Open design decisions (confirm before the big restructure)
1. Proceed with the sidebar restructure now, or land the bug-fixes + content tweaks first?
2. Confirm the group taxonomy above (esp. where Keys/Modifier-aliases and Layouts live).
3. Icons: generate via the Gemini asset loop, or SF Symbols to start?

## Quick answers to the review's questions
- "Which modifier for drag-to-snap?" → the **tiling modifier** (`config.tilerModifier`, e.g. ctrl+cmd),
  held during the drag. (Will surface in the UI.)
- "How to run the command palette?" → today only if you set a `command_palette` hotkey in config +
  `[command_palette] enabled`; there's **no UI to bind it yet** → fixing under B.
