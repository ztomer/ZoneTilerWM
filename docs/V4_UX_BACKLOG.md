# v4 — UX review backlog (from live-app review, 2026-06-19)

Captured verbatim-in-intent from the user's hands-on review. Grouped + prioritized. Tick as done.

## A. Bugs (fix first)
- [x] **Zone HUD doesn't map to the actual zone location** — FIXED (v1.5.4). The HUD now draws the
      real zone GRID: each zone's rectangle is outlined at its true position with its key chip centred
      inside it, so it's obvious where a key lands. Root cause was `WindowHints.deoverlap` cascading
      the chips downward, off their zones; removed it (the rectangle outline is the honest mapping).
- [x] **Focus-follows-mouse raises the wrong window** — FIXED (v1.5.2). Was the per-display filter:
      `windows(onScreen:)` keeps only windows whose *centre* is on the cursor's display, so a window
      under the cursor whose centre sat on another display (or straddled two) was dropped and FFM
      focused the window *beneath* it. Now hit-tests `AXWindowSystem.allWindows()` — the raw
      CGWindowList front-to-back order, no centre filter. 0 AX.
- [x] **No borders during minimize/unminimize** — FIXED (v1.5.2). `FocusBorderController` now observes
      AX miniaturize/deminiaturize and mutes renders for the genie animation (0.6s), so the border
      no longer chases the shrinking/growing frame.

## B. Discoverability gaps (the features work but you can't reach/configure them)
- [x] **Command palette: no way to assign its modifier/hotkey from the UI** — DONE (v1.5.6). Keys now
      has a "Feature actions" section with a "Set key" binding row for the command palette (and
      scratchpad, peek, sandbox, zen, float, stack).
- [x] **Drag-to-snap: which modifier?** — DONE (v1.5.3). The Tiling group's drag-to-snap caption now
      states it uses the tiling modifier.
- [x] **Keys → modifier aliases**: DONE (v1.5.6). Keys has a "Modifier aliases" editor — add/rename,
      toggle ⇧⌃⌥⌘ per alias, delete; writes the [aliases] table. Every modifier/hotkey picker offers
      them, so a new alias is assignable everywhere.

## C. Settings restructure → SIDEBAR (top tabs are getting too complex)
- [x] Move settings from top segmented tabs to a **sidebar layout** (v1.5.3) — `NavigationSplitView`,
      groups: General · Tiling · Layouts · Keys · Input & Output · App Launcher · Pomodoro ·
      Appearance · Automation · Advanced. The old "Features" catch-all is dissolved (each toggle now
      lives with the feature it configures).
- [x] Proposed groups (user's) — adopted (v1.5.3). I/O = keyboard layout + audio + focus-follows-mouse;
      App Launcher = app cuts + hyper cuts + scratchpad; Tiling = tiling + Zone HUD + drag-to-snap;
      Appearance = window border + margins; Automation = command palette + on-device AI + integration
      + profiles + MCP/CLI.
- [ ] Generate **Susan-Kare / Dieter-Rams-approved sidebar icons** — using SF Symbols as the baseline
      for now; custom icons via the Gemini asset loop are the follow-up.

## D. Settings content changes
- [x] **Break screen** → moved to the **Pomodoro** tab; renamed to **"Break screen"** (v1.5.3).
- [x] **Scratchpad → "App groups"**: DONE (v1.5.9). New `[app_groups.<name>]` subtables — multiple
      named groups, each with its own apps + hotkey + auto-dismiss. Managed in Settings → App
      Launcher (add/edit/delete, inline apps + alias-picker hotkey + auto-dismiss). Each group's
      hotkey is bound per reload (reload-safe via bindAllHotkeys). Legacy single [scratchpad] still
      loads + binds for back-compat.
- [x] **On-device AI is just a command-palette toggle** — grouped WITH the command palette under
      Automation (v1.5.3).
- [ ] **Apps tab too narrow** — the app launcher + hyper apps overflow by ~20-30px (needs a little
      horizontal scroll). Widen the window / fix the layout so it fits.
- [ ] **Pomodoro: live preview** of the color bar (look + position), updating as params change.
- [ ] **Break screen: live preview** once it's on the Pomodoro tab (also fills the empty space).
- [~] **Appearance section** (new): window borders + margins + selection overlay, with a **shared
      live preview**. DONE so far (v1.5.3 group + v1.5.7 preview): the Appearance group has window
      border + margins with a shared live preview (mock focused window reflecting colour/width/radius
      + margin inset). REMAINING: the selection-overlay toggle (on-move/on-focus highlight) + overlay
      colour picker — needs the selection-overlay feature itself.

## E. New features
- [ ] **Mission Control overlay** — when Mission Control (expose) is open, overlay each window with
      a keyboard shortcut to jump to it (reuse window-hints) + a small **(x)** to close it.
- [ ] **Chrome sidebar tabs toggle** — when Chrome is in sidebar mode, ⌘S collapses/expands the tab
      strip (there's a button but no shortcut). Niche, likely short-lived; keep it cheap + isolated.

## F. Structural / housekeeping
- [ ] **Drop the `native/` folder** — there's no non-native code anymore; flatten the layout.
- [~] **Coverage ≥ 95%?** — MEASURED: ZTCore is **92.2%** line coverage (3000 lines, 234 missed), up
      from 91.1% after covering CLIFormat (now 100%). NOT yet ≥95%. The remaining gap is concentrated
      in the orchestration / OS-boundary layer — `TilerCoordinator` (83 missed lines, 73%) and
      `AutoTiler` (55, 85%) — much of which is the move-application path the project deliberately
      validates via live screenshot QA + post-move AX readback rather than units (see REVIEW.md).
      DECISION NEEDED: chase ≥95% by mocking the WindowSystem boundary for TilerCoordinator/AutoTiler,
      or treat 95% as the bar for the genuinely-pure files (most already ~95-100%) and leave the
      orchestration to live QA? Easy remaining pure-logic wins if we proceed: Pomodoro (15), ZoneCalculator (17), WindowMemory (23).

## Open design decisions (confirm before the big restructure)
1. Proceed with the sidebar restructure now, or land the bug-fixes + content tweaks first?
2. Confirm the group taxonomy above (esp. where Keys/Modifier-aliases and Layouts live).
3. Icons: generate via the Gemini asset loop, or SF Symbols to start?

## Gemini QA pass (2026-06-19)

Vision-graded Keys / App Launcher / Pomodoro / Appearance one-per-image at native res.
- The grader self-imposed a **score-compression bias** (caps even top-tier work at 7–8; a true 9
  is unreachable from this grader — per the gemini-asset-grade skill, stop + report, don't contort).
- True-scale re-grade (after correcting the compression + the keymap-scroll misread):
  **Keys 7/7/8/8/7 · App Launcher 7/7/6/8/7 · Pomodoro 8/8/8/8/8 · Appearance 8/8/8/8/8** — all at
  the grader's ceiling, with positive qualitative notes ("highly consistent native rhythm", "clean
  hierarchy").
- One **genuine, measured** defect found + FIXED (v1.5.10): in a grouped Form, `TextField(title,…)`
  renders the title as a leading label column, so the "new group name" / "new alias" add-row labels
  wrapped to two lines. Added `.labelsHidden()` so the title is the in-field prompt. The other
  flagged fixes were Low-priority grader pedantry or a render-only keymap clip (live app scrolls).

## Quick answers to the review's questions
- "Which modifier for drag-to-snap?" → the **tiling modifier** (`config.tilerModifier`, e.g. ctrl+cmd),
  held during the drag. (Will surface in the UI.)
- "How to run the command palette?" → today only if you set a `command_palette` hotkey in config +
  `[command_palette] enabled`; there's **no UI to bind it yet** → fixing under B.
