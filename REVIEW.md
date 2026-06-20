# ZoneTilerWM — Review (engineering, performance, UI/UX, algorithms, coverage)

> This is the **single consolidated review** for the native Swift port. It folds in the former
> `ALGORITHM_REVIEW.md` (now §4) and the whole-codebase 5-persona pass (now §5), which were merged
> here and removed. §1–§3 are the engineering / performance / UI / coverage review; §4 is the
> algorithm sanity review; §5 captures the later security + maintainability findings.

> **Resolution status (backlog implemented).** Every actionable finding below has since been
> addressed: AX-call caching (per-app EnhancedUI memo), the three High UI bugs (resizable
> window, commit-on-blur, Keys-tab alignment — later superseded by the three-part modifier-row
> split + appbar-mode settings window), keycap-grid scroll, solver-weight Reset-to-defaults, the
> `LayoutSolver` flat-matrix + dense-array optimization, the `ResizeModeController`/
> `WindowHintsController` extraction, the algorithm hardening guards (§4), and unit tests raising
> ZTCore line coverage to **91.7%**. The numbers in §3 below have been refreshed; the findings text
> is kept as the original review record. Current baseline: **352 Swift tests green**.

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
LayoutSolver 99% line; the suite has since grown to **352 swift tests total** as the v6/v7
features — Exposé, real Spaces, the menubar widget, automation surface — added their own units.)

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

## 4. Algorithm sanity review (correctness · numerics · determinism)

> Folded in from the former `ALGORITHM_REVIEW.md`. **All findings below have since been hardened**
> and are locked by `HardeningTests.swift` (degenerate inputs stay finite, malformed coords reject);
> the frozen golden corpora are unchanged and `swift test --sanitize=address` runs clean.

A correctness/numerical/determinism review of the pure-logic algorithms in `Sources/ZTCore/`,
judged on their own merits (not a parity check — the Lua original is gone).

**Verdict:** the core algorithms are well-structured and **deterministic by construction** — every
sort is a documented total order with a unique final tie-break (windowId / tile sortKey / zone key),
all clocks and offset providers are injected, and dictionary iteration is replaced by sorted-key
passes in every output-affecting path. No determinism defect remained even before hardening. The
defects that existed were concentrated in **numerical edge cases never exercised by real AX frames** —
unguarded division by a dimension/area assumed positive — plus one unanchored regex.

| Severity | Site | Issue (now fixed) | Fix applied |
|---|---|---|---|
| Medium | `ZoneCalculator.parseGridCoords` | Unanchored grid regex parsed malformed coords (`"abc1"`→`c1`) instead of `nil` | Anchored `^([a-z])([0-9]+)(?::([a-z])([0-9]+))?$` |
| Medium | `LayoutSolver` cost fn | `w/h` & `area/screenArea` on zero dims → `Inf`/`NaN`; a `NaN` cost defeats branch-and-bound pruning | Clamp denominators / sentinel cost for degenerate input |
| Medium | `SmartPlacer` | `overlap/area` & `w/h` on a zero-area tile → `NaN` score (silently never selected) | Skip non-positive-area tiles |
| Low | `WindowMemory.learn` | Guarded `screenW>0` but not `screenH>0` → zero height poisons `meanArea` | Added `&& screenH > 0` |

**What was already sound:** comprehensive determinism (the hardest property in this kind of port),
empty/single/boundary guards where reachable, individually unit-tested cycling state machines
(`PlacementStrategy.largestFreeTile`, `FocusManager.Cycler`), exact `WindowMemory` running-mean +
recency-decay math, the legacy on-disk decoder (String/Int/Double ids, three `count` encodings),
frozen golden corpora for `LayoutSolver` + `ZoneCalculator`, and strict-inequality edge-touch
exclusion in `Geometry`. `FocusManager.overlapPercentage` and `AutoTiler.overlapRatio` already showed
the correct guard-the-denominator pattern the others now follow.

## 5. Whole-codebase 5-persona pass (security + maintainability)

> Folded in from the former `docs/REVIEW_5_PERSONA.md` (a v1.5.15 review across Linus / Uncle Bob /
> Carmack / Rams+Kare / Security). The engineering, perf, and UI lenses agree with §1–§2 above; this
> records the lens that section didn't — **security** — plus the two cross-cutting Majors.

- **Security — no blockers.** The attack surface is small and local: the MCP/CLI/URL front-ends only
  ever build an `ActionRequest` (no shell-out, no arbitrary code path), the Unix-domain socket is
  user-scoped, and read-only resources are answered from CGWindowList + config + the learned store with
  **no window titles** leaving the process. Config is TOML parsed by TOMLKit (no `eval`). The one item
  to keep honest: the `zonetiler://` URL scheme and Apple-Event entry points must continue to route
  through `ActionParser` (reject-by-default) rather than ever interpreting free text.
- **Major (resolved): version-string duplication** across 3 places → single-sourced via `ZTVersion` +
  `./bump.sh` (commit `5285627`).
- **Major (standing): the `main.swift` / `AgentController` god-object** — still the top maintainability
  debt; tracked in §1 (Uncle Bob) and the roadmap's tech-debt list.
- **Modal hotkey safety** (a 5-persona concern) — addressed for Exposé via the modal safety-timeout
  (commit `4ea5d62`); the same pattern should cover any future capture-the-keyboard modal.

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

## 6. Post-refactor review — 2026-06-20 (Linus · Uncle Bob · Carmack)

Three-lens review of the 500-LOC split + public `SpacesProvider` commit (`ebfd36a`). Verdict: ships
clean, no high-risk defects. Findings and resolutions:

- **[Linus, High → FIXED] Settings-search keyword landmine.** ~200 hand-maintained keyword strings in
  one array, no validation → silent search misses when a setting is added. Relocated each pane's
  keywords to a `static let searchKeywords` on that pane's own view struct (co-located with its
  controls); `SettingsView` references them.
- **[Carmack, Medium → FIXED] Double CGWindowList scan in the resolve path.** `resolveWindow` →
  `windowID(of:pid:)` enumerated twice. Threaded the single snapshot through (`onScreen:` param).
- **[Linus, Medium → FIXED] AX tie-breaker comment overclaimed** "frontmost = focused" for arbitrary
  windows. Comment now states the heuristic's actual limit (correct for the *focused* window only;
  only `_AXUIElementGetWindow` resolves it reliably).
- **[Carmack, Low → FIXED] `PublicSpacesProvider.onScreenMarkerID()` rescanned per read.** Now cached,
  invalidated only on `activeSpaceDidChange` / new marker (zero-AX, but removes redundant scans).
- **[Carmack, High → OPEN] `AXEnhancedUserInterface` toggles on *every* move** (`AXWindowSystem`),
  including native-AX apps — the single highest-value AX-cost lever under SentinelOne (= item 5 above).
  Deferred: needs a live check that Firefox/Zen still move once gated by bundle id.
- **[Linus + Uncle Bob, follow-up] God-object split is organizational, not SRP.** `AgentController`
  across `main.swift` + `+Setup` + `+Runtime` is readable but still one object; the real fix is
  extracting cohesive sub-controllers (`HotkeyManager`/`ConfigManager`/`LayoutManager`). Not a blocker.
- **Praise (all three):** `SpacesProvider` is a correct OS-boundary abstraction with two honest impls;
  `MissionControlView`(+`Mouse`) boundaries are clean; layering verified (no backwards deps); the
  AX-via-CGWindowList strategy remains fundamentally right. (Note: making `AgentController` members
  `internal` was *required* by the cross-file split — Swift `private`/`fileprivate` are file-scoped —
  not a gratuitous regression.)

### Round 2 (adversarial verify) — same day

A second, adversarial pass independently **re-verified** the four fixes above (all OK) and the whole
refactor: bootstrap order preserved, the **single-thread-on-main invariant holds** (every hotkey /
timer / notification / file-watch / IPC source runs on or hops to main), **no retain cycles**, and the
`internal`-ization breaks no real invariant. It also found two genuine defects in `PublicSpacesProvider`:

- **[High → FIXED] Space pinning was wrong.** The marker used `collectionBehavior = [.ignoresCycle]`,
  which only affects Cmd-` cycling — it does NOT pin a window to its Space. Added `.stationary` (the
  flag that actually keeps the window on its creation Space). Without it the marker could migrate to the
  active Space and corrupt current-Space detection.
- **[High → DOCUMENTED] Multi-display Space attribution.** A new Space is assigned to the display under
  the cursor (`NSEvent.mouseLocation`) at switch time; during a swipe the cursor can be on a different
  display than the one that changed Spaces, mis-attributing the Space. Correct on single-display; the
  robust multi-display fix needs the display that actually changed (no public API) — flagged in code +
  the public-path "needs live validation" note. Defense-in-depth: pinned the Space-change observer to
  `queue: .main`.
- **[Low] Markers are never torn down** (small leak; harmless) and a theoretical `windowNumber`
  cross-process collision — left as documented low-risk.

### Round 3 (edge-case hunt) — same day

Boundary/degenerate/race hunt across the Spaces subsystem, settings search, the Exposé/hints modals,
and the AX resolve path. Re-confirmed clean: the Exposé hot-plug observer (reentrancy-safe, removed in
`exit()`), double/triple `exit()` (idempotent), the hints guards, and `SpaceSwitcher.plan` edge inputs.
Real defects found and **fixed**:

- **[High] AX zero-frame match.** `windowID(of:pid:)` (public path) fell through to a pid+frame match
  even when `frame(of:)` returned a degenerate/zero rect (AX read failed / mid-animation) — matching
  whatever sat near the origin. Now fails closed (`guard width>1, height>1`).
- **[High] EnhancedUI pid-reuse + non-restore.** The per-pid `enhancedUICache` could hand a recycled
  pid a quit app's toggle state → wrong AX dance on a new app. Now invalidated on
  `didLaunchApplicationNotification`. Also `defer`-restore the toggle so an app is never left stuck
  with EnhancedUI off if `setFrame` bails.
- **[High] Public Spaces transient-empty read** collapsed the cached current-Space to nil during a
  Space transition (same class as the old "widget vanished" bug). Now the cache is kept on an empty
  on-screen read and retried.
- **[Med] Public Spaces disconnected-display markers** stayed in the list (stale windowNumber could
  false-match). Now pruned on `didChangeScreenParametersNotification`.
- **[Med] Empty display-UUID collision.** A failed `CGDisplayCreateUUIDFromDisplayID` collapsed two
  displays into the `""` group (mis-grouping + name-key collision). Now falls back to a stable
  per-screen key.
- **[Low/UX] Settings search** showed a detail pane the filtered sidebar no longer listed. The detail
  now shows the first match when the selection is filtered out; removed an orphan "liquid glass"
  keyword from Appearance (moved to the Exposé pane, where the material actually lives).

Left as documented (benign): a dropped menubar click in the instant the provider identity flips
(experimental toggle) — already a safe no-op; and the inherent CG-snapshot-vs-AX-enumeration race in
`resolveWindow` (a window closing mid-resolve → nil, the correct failure).

### Round 4 (perf · arch · code · security · races) — same day

A broad whole-system pass across all six dimensions.

- **Security — SAFE (no findings).** The IPC socket is `0o700` (owner-only) with a 1 MB read cap and a
  2 s recv timeout; every entry point (URL scheme, MCP, CLI, NL, `[[rules]]`, display presets) routes
  through `ActionParser` reject-by-default — unknown verbs/params are dropped, nothing is `eval`'d.
  External commands use `Process.arguments` (never `/bin/sh`), so the audio-Shortcut name and app names
  can't inject. Sync/state writes use hardcoded filenames (no path traversal); NL model output and
  config rules are re-validated through `ActionParser` before they run. The only standing properties
  are by-design: any same-UID process can drive the socket (intended; local-user trust model).
- **Architecture / code — clean.** Layering verified mechanically (ZTCore imports no AppKit; no
  backwards deps). No dead code / TODO / FIXME / disabled tests. Force-unwraps all on guaranteed-safe
  paths. The two-value-type window model (`WindowSnapshot` vs `LiveWindow`/`AutoTiler.Window` vs
  `OnScreenWindow`…) is intentional, not a merge candidate. Protocols are all earned (1–2 impls each).
  Nit (not taken): overlay alpha/color literals could be one `OverlayTheme` enum.
- **Races — single-thread-on-main invariant holds.** Config-reload-mid-hotkey is safe (weak-self +
  atomic config swap). Modal reentrancy is safe (the `active` gate + the 0.3 s deferred refresh; Carbon
  can't re-enter a handler). IPC is bounded by the 2 s timeout. **Fixed [Low]:** a rapid second
  menubar click could let the first click's 0.13 s deferred un-flash repaint stale groups — added a
  click-generation guard. (The Exposé "stale selection after close" the panel flagged is a non-issue:
  `mutateSelected` advances the selection to a live neighbour before the refresh.)
- **Perf — AX strategy remains optimal** (all reads 0-AX via CGWindowList; AX only to mutate). Idle
  timers are 0-AX. One zero-AX CPU note left as-is: `TilerCoordinator.moveWindow` scans once per screen
  to locate a window (the `WindowSystem` protocol has no all-windows read; not worth expanding the
  protocol for a CPU-only, non-hot path). The standing top AX-cost lever is still the per-move
  `AXEnhancedUserInterface` toggle gating (item 5 / §6, deferred pending the live Firefox check).

### Round 5 (fresh territory: core algorithms, coords, TOML, hotkeys, MCP, build) — same day

Aimed at code NOT touched in rounds 1–4. The ZTCore algorithms came back **all VERIFIED** (every
output-affecting sort is a total order with a unique tie-break; division guards present in
`LayoutSolver`/`SmartPlacer`/`WindowMemory`/`FocusManager`; `ZoneCalculator` regex anchored; AutoTiler
fill-gaps/BSP math correct; running-mean + recency-decay exact; all clocks injected). Findings:

- **[High — FALSE POSITIVE, not changed] Multi-display coordinate flip.** A reviewer flagged
  `CoordConvert.nsFrame` flipping against `CGMainDisplayID().height` for all displays as a bug.
  Verified it's **correct**: this is a *global* CG→NS transform; both coordinate systems are anchored
  to the main display's origin, so the flip constant is the main height regardless of which display the
  rect is on (its own x/y encode the display). The proposed "fix" would break secondary-display
  overlays that work today (and the live-validated Exposé all-monitors panels).
- **[Med — FIXED] KeyMap F-key gap.** Only `f1`/`f2` were mapped; a config binding `f3`–`f20` returned
  `nil` and silently failed to bind. Added `f3`–`f20`.
- **[Med — FIXED] Carbon `InstallEventHandler` silent failure.** Its status was unchecked; if it ever
  failed, *no* hotkey would fire with no signal. Now logged to stderr.
- **[Med — left, cosmetic] `TOMLEditor.setOrAppend`** inserts a new key right after the section header
  (above a leading comment). Valid TOML, key-order-irrelevant — not worth the corruption risk of
  changing the surgical config writer.
- **[High — already tracked] `project.yml` doesn't thread `ZT_PRIVATE_APIS`**, so `make app` builds
  MAS-clean (no experimental features). This is the deferred build-variant work (ROADMAP §B4), not a
  new bug; the `build_*.sh` scripts pass the flag correctly.
- **VERIFIED correct:** MCP tool schema ↔ ActionParser catalog (no drift), `HotkeyConflicts` modifier
  canonicalization, the IPC 1 MB cap + 2 s timeout. Left as low/theoretical: `zt-mcp`'s stdin
  `readLine` has no size cap (trusted client) and `CarbonHotkeyBinder.nextID` could wrap after 2³²
  registrations.

**Convergence:** across five rounds the yield fell from structural (R1) → one real bug each (R2 pinning,
R3 degenerate-input cluster) → ~nothing (R4) → two minor completeness fixes + a false positive (R5).
The codebase is thoroughly reviewed; the core algorithms are clean.
