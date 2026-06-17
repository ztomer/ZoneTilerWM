# ZoneTilerWM v2 — Review (engineering, performance, UI/UX, coverage)

> **Resolution status (backlog implemented).** Every actionable finding below has since been
> addressed: AX-call caching (per-app EnhancedUI memo), the three High UI bugs (resizable
> window, commit-on-blur, Keys-tab alignment), keycap-grid scroll, solver-weight
> Reset-to-defaults, the `LayoutSolver` flat-matrix + dense-array optimization, the
> `ResizeModeController`/`WindowHintsController` extraction, and unit tests raising ZTCore line
> coverage to **91.7%**. The numbers in §3 below have been refreshed; the findings text is kept
> as the original review record.

Read-only review of the native Swift port as of branch `v2`. The Lua/Hammerspoon
implementation remains the executable spec; this judges the port on engineering quality,
hot-path performance, UI/UX, and test coverage. Findings cite `file:line` and are graded
[High] / [Medium] / [Low].

Summary verdict: the headless core is disciplined and faithful — the layering boundary is
provably held, determinism is engineered rather than hoped for, and the hot path keeps
value-snapshot discipline. Crucially, the dominant performance constraint on the target
machine is **AX-call count, not CPU** — SentinelOne hooks and analyzes every Accessibility
call (up to seconds each) — and the port handles this correctly by reading all window state
through CGWindowList (zero AX) and touching AX only to mutate; the two solver micro-opts are
second-order against that. The real debt is in the agent shell and UI: the highest-value perf
lever is the per-move `AXEnhancedUserInterface` toggle (extra hooked AX calls), plus an
`AgentController` god-object and several UI alignment/commit inconsistencies in the settings
forms. Code coverage does **not** meet the >95% bar (see §3) and structurally cannot at the
adapter layer headless.

---

## 1. Engineering & performance review (Linus · Uncle Bob · Carmack)

### Linus — taste & data structures

The core is good-taste by Linus's standard: tie-breaks are total orders expressed as data
(sorted key lists, comparator chains), not special-case branches; value structs over
inheritance.

- **[Positive]** `Geometry.swift` / `Models.swift` — flat value structs, `rectsOverlap` a
  single `@inlinable` boolean. `TileIndex` as an enum with a `sortKey`/`numericValue`
  accessor models the Lua "number-or-string tile id" in the type instead of scattering
  `type(x)==` checks.
- **[Positive]** No speculative generality in ZTCore. `MonitorManager`,
  `WindowFocusTracker`, `ResizeManager` are plain `final class` holding a dictionary and a
  few methods — no protocols, no generics. The "abstraction earned only at the OS boundary"
  rule is honored.
- **[Positive]** "Don't break userspace" is engineered: `WindowMemory.SaveData`
  (`WindowMemory.swift:217–276`) tolerates three legacy on-disk shapes and coerces legacy
  numeric `monitor_id`; `TOMLEditor` does surgical comment-preserving edits.
- **[Low]** `PlacementStrategy.largestFreeTile` (`PlacementStrategy.swift:69–123`) — nesting
  depth 4 and literal Lua index arithmetic (`tiles[(cti % count) + 1 - 1]`). Faithful port,
  pinned bit-for-bit by `diff_strategy`; leave it while the diff is green, but it is the
  function a maintainer will fear.
- **[Low]** `AutoTiler.fillGaps` (`AutoTiler.swift:276–370`) — 95 lines, nesting depth 5
  (faithful `_pass_fill_gaps` port). Acceptable under the parity constraint.

### Uncle Bob — boundaries, SOLID, testability

Clean. Layering and SRP are real, not aspirational. (Note: the project rule is that
dependency-inversion is earned only at the OS boundary, so adding protocols *inside* ZTCore
would be a defect, not an improvement — the code correctly does not.)

- **[Positive]** The OS boundary is exactly where it should be: `WindowSystem`,
  `ScreenProvider`, `Storage` are protocols in ZTCore; `AXWindowSystem`, `NSScreenProvider`,
  `JSONFileStorage` conform in ZTSystem; the leaf algorithms never see a protocol. The clock
  is injected for determinism.
- **[Positive]** File-level SRP is consistent; every ZTCore file names its Lua source.
  `FocusManager.Cycler` separates stateful cycling from pure `collectZoneWindows`.
- **[Medium]** `AgentController` (`zt-agent/main.swift`, ~650 LOC) is a god-object
  composition root: menubar agent + hotkey orchestrator + resize-mode modal + window-hints
  modal + Pomodoro UI + config-reload controller + glyph renderer. Resize-mode (~8 fields,
  6 methods) and window-hints (~4 fields, 5 methods) are each a coherent sub-controller that
  could extract to its own type. Highest-value SOLID cleanup, but it lives in the
  adapter/UI layer (covered by visual validation, not diffing), so maintainability debt, not
  a defect.
- **[Low]** `TilerCoordinator.init` has 9 parameters (several optional) — a parameter-object
  candidate. Minor.

### Carmack — hot-path performance

**The real hot path is AX call *count*, not CPU.** On the target machine SentinelOne hooks,
logs, and analyzes every Accessibility (AX) API call — historically up to 1–2 seconds per
`setFrame` — so the dominant cost of any user operation is the number of AX round-trips it
makes, and whether that number scales with window count. CPU-side concerns (solver node count,
allocations) are second-order against a single hooked AX call. The two `LayoutSolver` findings
below are real but minor; the performance gate that actually matters is AX-calls-per-operation.

**On that gate, the native port is correct by design — and strictly better than the Lua.**
`AXWindowSystem` reads all window geometry / z-order / occupancy through
`CGWindowListCopyWindowInfo` (`onScreenWindows()`, `AXWindowSystem.swift:153`): **zero AX
calls, no Accessibility permission, off the hooked path, independent of window count.** AX is
touched only to *mutate* (`move`/`focus`/`setMinimized`) and to read the single focused element
(`focusedWindow`). So a tile op costs ~1 AX read (focused) + ~4–6 AX writes (resolve + EnhancedUI
toggle + position + size) and the occupancy scan over every other window is **free**. The Lua
needed `modules/window_cache.lua` precisely because `hs.window.allWindows()` was per-window AX;
the native CGWindowList enumeration removes that whole class of cost. This is the most important
performance fact about the port and it is handled well. (See `docs/SENTINELONE_INVESTIGATION.md`.)

- **[Medium, AX] `applyFrame`/`moveFocusedWindow` toggle `AXEnhancedUserInterface` on *every*
  move** (`AXWindowSystem.swift:73–80,108–116`) — 1 AX read + up to 2 AX writes per move. Firefox
  / Zen-class non-native-AX apps require it, but on a SentinelOne machine those 2–3 extra hooked
  AX calls per move are the costliest knob in the system. Gating the toggle to known-quirky apps
  (by bundle id) would drop native-AX-app moves to just the 2 setFrame writes — verify Firefox
  still moves before doing so. This is a higher-value perf lever than either solver finding.
- **[Low, AX] `resolveWindow` re-runs `onScreenWindows()`** (`AXWindowSystem.swift:122`) even when
  the caller (e.g. `moveFocusedToZone`) just enumerated. CGWindowList is cheap (no AX), so this is
  CPU not AX cost — minor, but threading the snapshot through would avoid the duplicate.

The remaining items are CPU-side and second-order under the AX constraint above:

- **[Medium]** `LayoutSolver.solve` cost matrix is a nested `[[Double]]`
  (`LayoutSolver.swift:86`), not the flat/contiguous preallocated matrix the architecture
  doc promises. That is `n` separate heap buffers + a pointer indirection per
  `costMatrix[i][j]`, and it is read in the backtracking inner loop (`:131`). A single
  `[Double]` of `n*m` indexed `i*m+j` would be one allocation and cache-contiguous. Doesn't
  dominate at realistic sizes (≤~12×~20) but is the one spot where the stated perf invariant
  is not met.
- **[Medium]** The assignment is held as `[Int:Int]` and fully copied on each improving leaf
  (`best.assignments = current`, `LayoutSolver.swift:109`), with dictionary hashing on every
  inner-loop set/clear (`:130–132`). A `[Int]` indexed by window (sentinel for "skipped")
  removes both the copy cost and the hashing.
- **[Low]** Accidental O(n²) overlap scans in `recurse` (`:123–127`), `AutoTiler` passes
  (`:149,166`), and `largestFreeTile` (`:76–83`). Bounded by tiles×windows (~tens), so the
  right tradeoff — a spatial index would be premature. Named so the bound is a conscious
  decision.
- **[Positive]** No witness-table dispatch in the leaf algorithms: `LayoutSolver`,
  `PlacementStrategy`, `SmartPlacer`, `ZoneCalculator` are `enum` namespaces of `static`
  functions over concrete value structs. The cost function is precomputed into the matrix
  before recursion, not recomputed per branch. Protocol dispatch lives only in
  `TilerCoordinator`, O(once per op).

### Layering boundary check (mechanical)

`grep -rn "import AppKit|ApplicationServices|Cocoa|Carbon" Sources/ZTCore/` → no matches.
Every ZTCore file imports only `Foundation` (or nothing). The substring matches in
`Geometry`/`Keybinding`/`ScreenProvider`/`ZoneCalculator` are all inside `//` comments
documenting where conversion happens. `ZoneCalculator` uses `NSRegularExpression`
(Foundation, not AppKit). **Verdict: PASS, cleanly.** Coordinate convention (top-left CG
end-to-end, flip only in `NSScreenProvider.snapshot`) is held.

### Top engineering findings

| Lens | Severity | file:line | Issue | Fix |
|---|---|---|---|---|
| Carmack (AX) | Medium | `AXWindowSystem.swift:73,108` | EnhancedUI toggle on *every* move = 2–3 extra hooked AX calls/move under SentinelOne (the real cost) | Gate the toggle to known-quirky apps by bundle id; verify Firefox still moves |
| Carmack | Low | `LayoutSolver.swift:86` | Cost matrix `[[Double]]` despite doc's flat-contiguous claim (CPU-side, second-order under the AX constraint) | Single `[Double]` of `n*m`, index `i*m+j` |
| Carmack | Low | `LayoutSolver.swift:97,109,130` | Assignment `[Int:Int]` — full copy per improving leaf + hashing (CPU-side, second-order) | `[Int]` window→tile, `-1` = skip |
| Uncle Bob | Medium | `zt-agent/main.swift` | `AgentController` god-object also implements resize-mode + window-hints modals + glyph | Extract `ResizeModeController` / `WindowHintsController` |
| Linus | Low | `PlacementStrategy.swift:69–123` | `largestFreeTile` nesting 4 + literal Lua `+ 1 - 1` index math | Leave while diff green; if touched, go 0-based with per-branch tests first |
| Linus | Low | `AutoTiler.swift:276–370` | `fillGaps` 95 lines, nesting 5 | Acceptable under parity; extract helpers if modified |

---

## 2. UI/UX review (Dieter Rams · Susan Kare)

### Rams — restraint, hierarchy, consistency

- **[Positive]** Overlay lifecycle is exemplary — the strongest Rams-aligned aspect.
  `FlashOverlay.flash` self-cancels via a `DispatchWorkItem` (`Overlay.swift:172`); grid/hint
  overlays are torn down on mode exit (`main.swift:597,546`); the Pomodoro bar hides unless
  `isActive && enableColorBar` (`main.swift:443–449`); the menubar item is `withLength: 0`
  until active. Nothing persists when idle.
- **[Positive]** The menubar menu is minimal: title, Settings, Window Analytics, Reload
  Config, Quit. No sprawl.
- **[Medium]** `AdvancedSettings` (`FeatureSettings.swift:199–233`) exposes 7 raw solver
  weights with one caption and **no Reset-to-defaults** — a bad edit strands the user. This
  is the one place the GUI risks "a control panel of every toggle." Correctly quarantined
  under Advanced, but add a reset affordance.
- **[Low–Medium]** Information hierarchy: the General tab hosts Config, Tiling, Input,
  Margins *and* the entire Audio section (`SettingsView.swift:347`). Audio switching is
  homeless and makes General the longest scroll; Pomodoro/Window Memory got their own
  tabs/sections.
- **[Positive]** Sensible bounded defaults (working-set 1–12, Pomodoro work 1–120 / rest
  1–60, bar 5–100%); keyboard layout defaults to "Auto (detected)". Disabled-state
  discipline is good (margin/Pomodoro sub-controls grey out when their toggle is off).

### Kare — glyphs, icons, hints, legibility

- **[Positive]** Window hints are the standout work (`makeBadge`, `Overlay.swift:114–153`):
  `[app icon] [KEY] [name]` — recognition + action + confirmation. The uppercase monospace
  key (18pt bold) is the dominant element; name truncates at 170px; badges are spatially
  placed by mapping each window's normalized center to a keyboard-half key
  (`main.swift:507–513`) so the hint key mirrors where the window sits.
- **[Positive]** Menubar glyph (`main.swift:638–684`) is a deliberate non-template 2×2 grid
  with an amber accent matching the app icon, re-rendered on light/dark theme change — not a
  default SF Symbol. One [Low] risk: amber-on-white at 18px has low luminance contrast; worth
  a real-scale check.
- **[Positive]** Pomodoro pill (`main.swift:27–68`) uses real `NSVisualEffectView` vibrancy
  + monospaced-digit font so the countdown stays width-stable.
- **[Positive]** Layout-editor keycaps carry an 8×6px mini grid-shape preview of each zone
  (`EditorViews.swift:408–421`) — the affordance *is* the information.
- **[Low–Medium]** 8pt keycap app-name captions (`EditorViews.swift:281`) and 8–9pt
  analytics heatmap text are at the legibility floor on non-Retina externals; the full name
  shows only after selecting the key.

### Specific alignment / warping issues

1. **[High]** Hotkey-row label/picker widths disagree across the Keys tab: `HotkeyRowView`
   defaults `labelWidth = 190` (`EditorViews.swift:123`), `modifierRow` hardcodes `150`
   (`:202`) with a 180 picker (`:207`), Action rows use a 130 picker (`:139`), and the
   Pomodoro tab passes `labelWidth: 120` (`FeatureSettings.swift:174`). The Modifiers and
   Actions groups visibly misalign vertically. → Standardize one label width + one picker
   width.
2. **[High]** Two edit fields silently drop edits — they commit only `.onSubmit` with no Save
   button and no on-blur commit: solver weights (`FeatureSettings.swift:228`) and existing
   per-app default-zone rows (`:148`). Adjacent sections (audio devices, excluded apps) *do*
   have Save buttons, so it is inconsistent within the same screen. → Commit on blur
   (`FocusState`) or add Save buttons for parity.
3. **[Medium]** Settings window size mismatch: `SettingsView.body` wants `680×560`
   (`SettingsView.swift:280`) but the window opens at `560×460`
   (`SettingsWindow.swift:22`) and is not resizable → content clipped on open. → Set content
   size to 680×560 (or add `.resizable`).
4. **[Medium→High]** `AppShortcutsView` keycap grid (~580–750px for a 10–13 key row) overflows
   the 560px window with no horizontal scroll (`EditorViews.swift:233–289`). → Widen window
   + wrap keycaps in a scroll/clip.
5. **[Low]** Two source-of-truth window sizes for Analytics (`AnalyticsView` min
   `600×640` vs controller `660×720`); placeholder-as-label on `labelsHidden()` device/app
   fields (cosmetic).

### Top UI/UX findings

| Lens | Severity | file:line | Issue | Fix |
|---|---|---|---|---|
| Rams | High | `SettingsWindow.swift:22` vs `SettingsView.swift:280` | Window 560×460 < view's 680×560 → clipped, not resizable | Match content size or add `.resizable` |
| Rams | High | `FeatureSettings.swift:148,228` | Solver-weight / existing app-zone edits commit only on `.onSubmit`; clicking away loses them | Commit on blur or add Save button |
| Rams | High | `EditorViews.swift:123,202,207` | Hotkey row label/picker widths differ → vertical misalignment on Keys tab | One label width + one picker width |
| Kare/Rams | Med→High | `EditorViews.swift:233–289` | Apps keycap grid overflows the 560px window, no horizontal scroll | Widen window; scroll/clip keycaps |
| Rams | Medium | `FeatureSettings.swift:199–233` | 7 raw solver weights, no Reset-to-defaults | Add reset; consider disclosure |

---

## 3. Code coverage — verification result

Measured with `swift test --enable-code-coverage` + `xcrun llvm-cov report` (line coverage
of the XCTest binary; the 8 differential harnesses run via the separate `zt-oracle` binary
and therefore do **not** count toward these numbers, so behavioral coverage of the pure
logic is in practice higher than the line figures below).

| Layer | Region | Line | Notes |
|---|---:|---:|---|
| **ZTCore** (pure logic) | 83.4% | **91.7%** | The diffed IP. Raised from 87.5% by the backlog tests. |
| **ZTSystem** (OS adapters) | ~35% | ~41% | Dragged down by un-unit-testable AX/Carbon. |

(After the backlog: PlacementStrategy 77→92%, TilerCoordinator 76→88%, AutoTiler 75→85%,
LayoutSolver 99% line; 142 swift tests total.)

**Verdict: the >95% bar is NOT met, and is not achievable headless at the adapter layer.**

Why, and what it would take:

- **0% by design (need a live machine / GUI):** `AXWindowSystem` (0%), `CarbonHotkeyBinder`
  (0%), `KeyMap` (0%), `KeyboardLayoutDetector` (0%), `AppController` (0%), `Overlay`
  (~10%), and the entire `ZTUI` + `zt-agent` targets. These are the OS boundary the
  architecture deliberately covers via the differential oracles + visual/manual QA, not unit
  tests. They cannot reach 95% without a hosted UI/AX test rig.
- **Pure-logic gaps that COULD be raised toward 95% with unit tests** (the actionable part):
  `AutoTiler.swift` (75% line / 60% region — fill-gaps + BSP branches),
  `PlacementStrategy.swift` (77% / 68%), `TilerCoordinator.swift` (76% / 66% — the
  multi-monitor + auto-tile-with-memory paths), `Pomodoro.swift` (80%), `Models.swift`
  (91% but 73% region). `LayoutSolver` (99%), `ResizeManager` (98%), `WindowMemory` (91%),
  `ZoneCalculator` (91%), `FocusManager` (93%) are already strong.
- **ConfigLoader** (`ZTSystem`, 78% line / 56% region, 28% functions) is the one adapter that
  *is* headless-testable and under-covered — many `LoadedConfig` accessors (incl. the new
  `allBindings`/`zoneKeys`) are exercised only indirectly.

To honestly claim >95% you would either (a) scope the metric to ZTCore and add unit tests
for AutoTiler/PlacementStrategy/TilerCoordinator/ConfigLoader (reachable), or (b) stand up a
hosted XCTest target with AX/Carbon fakes and SwiftUI snapshot tests for the adapter/UI
layer (large effort). Today's reality: **69% overall, 87% pure-logic**, with the boundary
validated by 131 unit tests + 8 differential harnesses (100s of fuzz seeds each) + the Lua
spec runner, all green.

---

## Aggregate priority list

1. [High] Settings window clipping + non-resizable (`SettingsWindow.swift:22`).
2. [High] Silent edit loss on solver-weights / app-zone fields (`FeatureSettings.swift:148,228`).
3. [High] Keys-tab label/picker misalignment (`EditorViews.swift:123,202,207`).
4. [Medium] Apps keycap grid overflow (`EditorViews.swift:233–289`).
5. [Medium] AX-call perf: gate the per-move `AXEnhancedUserInterface` toggle to known-quirky
   apps to cut hooked AX calls under SentinelOne (`AXWindowSystem.swift:73,108`) — the real
   perf lever; verify Firefox still moves.
6. [Medium] `AgentController` god-object extraction (`zt-agent/main.swift`).
7. [Medium] Coverage gap in AutoTiler / PlacementStrategy / TilerCoordinator / ConfigLoader.
8. [Medium] Advanced solver weights need Reset-to-defaults (`FeatureSettings.swift:199–233`).
9. [Low] CPU-side solver flat-matrix + array-assignment (`LayoutSolver.swift:86,109`) —
   second-order under the AX constraint.

None of these are correctness regressions against the Lua spec — the differential harnesses
and unit tests are green. They are quality, performance, and polish debt.
