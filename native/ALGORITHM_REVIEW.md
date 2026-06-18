# ZoneTilerWM — Algorithm Sanity Review

A correctness, numerical, determinism, and robustness review of the pure-logic algorithms in `native/Sources/ZTCore/`, judged on their own merits (the Lua original has been removed; this is not a parity check). File:line citations refer to the `v2` working tree at review time.

## Summary verdict

The core algorithms are well-structured, deterministic by construction (every sort is a documented total order; the clock and offset providers are injected; dictionary iteration is replaced by sorted-key passes in all output-affecting paths), and broadly correct. The frozen golden corpora plus the behavioral unit tests give solid coverage of the happy paths and the documented tie-break rules. The defects that exist are concentrated in **numerical edge cases that are never exercised** — zero-dimension windows/screens producing `Inf`/`NaN` in cost functions (`LayoutSolver`, `SmartPlacer`, `FocusManager`), and an **unanchored grid-coordinate regex that silently accepts garbage input** (`ZoneCalculator`). None are reachable from current test/fixture inputs or from real AX frames, so the suites are green, but they are real latent defects. No determinism bugs and no crash-on-normal-input bugs were found.

## Per-algorithm findings

### LayoutSolver (`LayoutSolver.swift`)

Sound overall. The traversal order (skip-branch first, then tiles in array order; strict `<` replacement so the first-reached minimum wins ties) is faithfully implemented and the flat cost-matrix optimization is semantically identical to a per-window cost call. Empty inputs are guarded (`LayoutSolver.swift:81`) and covered by `testEmptyInputsReturnNoMoves`.

- **[Medium] Division-by-zero / `Inf` / `NaN` in the cost function for degenerate window or screen sizes.** `LayoutSolver.swift:46-51`:
  ```swift
  let tileAR = tile.rect.w / tile.rect.h
  let winAR = window.w / window.h
  ...
  let tileAreaRatio = (tile.rect.w * tile.rect.h) / (screen.w * screen.h)
  ```
  A window with `h == 0` yields `winAR == +Inf`; `abs(winAR - tileAR) * aspectRatio == Inf`, propagating to a `NaN`/`Inf` cost. A zero-area screen makes every area ratio `NaN`. Because branch-and-bound compares `currentCost >= best.minCost` (`:119`) and the leaf uses `currentCost < best.minCost` (`:112`), a `NaN` cost poisons pruning (all comparisons with `NaN` are false), degrading optimal-leaf selection and potentially returning a non-minimal assignment. No fixture exercises zero dims (14 solver fixtures, none with `w:0`/`h:0`), and the live layer only feeds real AX frames, so severity is Medium. Fix: clamp denominators (`max(h, 1)` / guard screen area `> 0`) or early-return a sentinel cost for degenerate inputs.

- **[Low] `maxChecks` cutoff (`:27,:121`) returns the best-so-far silently.** With N windows × M tiles the search is O(M^N); the 100k-check cap bounds it, but when hit it yields a possibly-suboptimal result with no signal. Intentional and a reasonable safety valve; given the AX-call perf gate (not CPU) and small real-world N, a Low nit.

- **Positive:** the `tile.idx.numericValue ?? 0` occupancy bias (`:72`) correctly handles BSP-produced string ids (`"4a"`) by contributing 0.

### ZoneCalculator (`ZoneCalculator.swift`)

Layout detection and tile geometry are correct and deterministic (sorted-key iteration with first-match-wins, `:36,:43`). Margins logic (`:149-159`) and the `linePos` clamp at grid edges (`:131-137`) are clean, and the 2x2 fallback (`:79-82`) is well guarded. The golden corpus covers the geometry.

- **[Medium] `parseGridCoords` regex is unanchored and silently parses malformed coordinates.** `ZoneCalculator.swift:167-168`:
  ```swift
  private static let gridRegex = try! NSRegularExpression(
      pattern: "([a-z])([0-9]+):?([a-z]?)([0-9]*)")
  ```
  `"abc1"` matches as column `c`, row `1` (leading `ab` skipped — unanchored); `"a1:2"` matches with an empty end-column → `ce = cs`. A typo'd config coordinate produces a plausible-but-wrong tile rather than `nil`. `createTile` dispatches named tiles before the regex (`:110-117`), so `left-half` is safe, but arbitrary grid strings are not validated. Fix: anchor the pattern (`^([a-z])([0-9]+)(?::([a-z])([0-9]+))?$`) so malformed input returns `nil`. (`testGridCoordParsing` asserts `nil` only for `"nonsense"`, which already fails the substring match — it does not cover `"abc1"`.)

- **[Low] Force-unwrap on the end-column scalar.** `ZoneCalculator.swift:183`: `Int(ceChar.unicodeScalars.first!.value)` — guarded by `ceChar.isEmpty` and `ceChar` is a `[a-z]?` capture, so safe in practice, but a latent footgun if the regex changes.

- **[Low] `LuaPattern` `-` → `*?` translation (`:224`)** is a reasonable emulation of Lua's lazy quantifier; `testLuaPatternMatching` covers the patterns in use. A leading `-` would yield an invalid ICU pattern → `try?` nil → `find` false. Acceptable degradation, not a crash.

### PlacementStrategy (`PlacementStrategy.swift`)

The cleanest of the decision modules. The largest-free sort is an explicit total order (`available` desc, then `orig` asc, `:84`), the intersection-area math is correctly clamped (`:30-34`), `selfId` exclusion is handled (`:79`) and tested, and the empty-tiles guard (`:62,:72`) returns `nil`. The cycling logic for already-in-zone / all-blocked / single-tile is intricate but each branch is unit-tested.

- **[Low] `tilesEqual` uses a fixed absolute tolerance of `1.0`** (`:38`). Correct for pixel rects; an absolute (not relative) tolerance, fine because coordinates are pixel-scale. Noted, not a defect.

- **Positive:** the all-blocked path (`:91-96`) correctly handles the single-tile case (`tiles.count > 1` guard before cycling, else `tiles[0]`), avoiding a modulo bug.

### SmartPlacer (`SmartPlacer.swift`)

Scoring core is correct and deterministic (zones pre-sorted by caller, strict `>` max at `:88`). Intersection uses a disjoint guard (`:34`). The overlap multiplier `1/(1+ratio*500)` (`:85`) cannot divide by zero.

- **[Medium] `occupancyRatio = currentOverlap / areaScore` divides by tile area** (`:84`), and `areaScore = candidate.w * candidate.h` (`:63`). A zero-area candidate → `0/0 == NaN` → `finalScore == NaN`, and `NaN > maxScore` is always false, so a degenerate tile is silently never selected. Also `ar = candidate.w / candidate.h` (`:76`) is `Inf` for `h==0`. Not reachable from real zone geometry. Fix: skip non-positive-area tiles at the top of the inner loop.

- **Positive:** `maxScore` initialized to `-1.0` (`:45`) is safe because all valid scores are non-negative, so the first real tile always wins.

### AutoTiler (`AutoTiler.swift`)

The 4-pass cascade is the most complex module and is implemented carefully. Determinism is solid: monitors iterated `keys.sorted()` (`:137,:282`); the `available`/`allTiles`/`sortedMoves` sorts are total orders with explicit final tie-breaks (`:170-175,:331-335,:345-348`); the final dedup emits `sorted { windowId }` (`:213`). `overlapRatio` guards zero-area (`:82`). The 600-seed corpus plus `AutoTilerTests` cover anchor, limbo, capacity cull, and memory bias.

- **[Low] `subdivide` BSP split.** The `< 250 && < 250` break (`:260`) prevents subdividing small tiles; `floor(w/2)` with `w2 = w - w1` keeps the pair summing to the original, and for any `w >= 250` the halves are `>= 124`, so no zero-width children in practice. Sound; the 20-iteration cap (`:251`) is a magic safety bound.

- **[Low] Hardcoded limbo fallback** `ZTRect(x: 0, y: 0, w: 100, h: 100)` (`:197`) when neither an anchor nor a `"j"` zone exists. Unlikely, and limbo windows are stacked rather than tiled, so cosmetic. Consider deriving from the screen frame.

- **[Low] `fillGaps` is O(iter · moves · tiles)** with `iter` bounded by `cols*rows` (`:337`). Trivial for realistic grids; CPU is not the perf gate. The grid-span occupancy math (`:299-303,:307-313`) correctly uses `x2-1`/`y2-1` to avoid off-by-one over-counting at tile boundaries — a subtle detail done right.

- **Positive:** the `cull` comparator (`:228-239`) is a proper total order in both `"usage"` and `"session"` modes with `a.id < b.id` as final tie-break; the capacity split (`:241-243`) is a clean `i < capacity` partition.

### WindowMemory (`WindowMemory.swift`)

Correct running-mean update (`stats.meanAR = (meanAR*n + newAR)/(n+1)`, `:133-134`), tested numerically in `testRunningMeanAndCount`. Recency decay `count * 0.5^(Δt/halfLife)` (`:184`) is correct, uses `max(0, now - lastSeen)`, and `weight == count` when `now` is nil. Ranking, `preferredTile`, `preferredZone` iterate sorted keys with documented tie-breaks (`:153,:165,:194-197`). The legacy on-disk decode (`:217-285`) handles String/Int/Double monitor ids and three legacy `count` encodings tolerantly. Save/load round-trips deterministically (sorted arrays).

- **[Low] Learn guard checks `screenW > 0` but not `screenH > 0`.** `WindowMemory.swift:126-130`: if `screenH == 0` (but `screenW > 0`), `newAreaRatio == +Inf` folds into `meanArea`, permanently poisoning that stat. The comment notes this was a deliberate Lua-parity port; with parity no longer a constraint, it is now a latent defect. Severity Low (screen height is never zero from a real `NSScreen`). Fix: add `&& p.screenH > 0`.

- **Positive:** `flushAll` commits `pending.keys.sorted()` (`:117`), removing any dictionary-order nondeterminism in the timestamped commit path.

### FocusManager (`FocusManager.swift`)

Zone-window collection (explicit phase then overlap phase, first-matching-tile-wins, `:61-76`) and the intuitive-order sort (tile asc, explicit-first, z-order asc, windowId tie-break — a full total order, `:78-83`) are correct and tested. The `Cycler` rebuild conditions and 1-based stepping (`:103-124`) are covered.

- **[Low] `overlapPercentage` divides by `r1.w * r1.h` but guards `r1.w <= 0 || r1.h <= 0`** (`:42-46`) — correct, prevents the division-by-zero. Called out as the *correct* handling of the edge the other modules miss.

- **[Low] `Cycler` rebuild check builds two `Set`s per call** (`Set(freshOrder) != Set(order)`, `:108`). Allocates on every focus-cycle keystroke; negligible. Nit.

### Supporting (`ScreenNav`, `GridCells`, `WindowFocusTracker`, `MonitorManager`, `Geometry`)

All sound.

- **`ScreenNav`** — deterministic ordering (`:14`), correct modular wrap with the `+ count` guard for `.previous` (`:25`), bounds-checked remembered-placement (`:38`). Fully tested.
- **`GridCells`** — `Span.init` normalizes `lo<=hi` (`:12-13`); `columnIndex` validates a single lowercase letter before the `asciiValue` force-unwrap (`:18-20`), so the `!` is safe; `parse` validates `r >= 1`. This is the editor's *anchored, validating* parser — worth aligning `ZoneCalculator.parseGridCoords` to the same rigor.
- **`WindowFocusTracker`** — clock always injected; `prune` filters by live set. No defects.
- **`MonitorManager`** — first-seen logical-id assignment; `uuid(forId:)` is O(n) over the registry but order-stable (ids unique). Sound.
- **`Geometry.rectsOverlap`** — edge-touching excluded via strict inequalities. Correct.

## Cross-cutting observations

**Determinism — clean.** Every place that previously risked an unstable sort or hash-order iteration has been converted to an explicit total-order comparator with a unique final tie-break (windowId, tile sortKey, or zone key): `LayoutSolver` traversal, `PlacementStrategy` largest-free, `AutoTiler` available/allTiles/sortedMoves/dedup, `WindowMemory` ranking/save, `FocusManager` ordering, `ScreenNav`. All clocks and offset/state providers are injected. No unseeded randomness, no wall-clock reads inside the algorithms. **No remaining determinism defect.**

**Numerical — the weak spot.** The recurring pattern is *unguarded division by a dimension or area assumed positive*: `LayoutSolver:46-51`, `SmartPlacer:76,84`, `WindowMemory:128-129` (height). Each produces `Inf`/`NaN` on degenerate input, and in `LayoutSolver` a `NaN` cost defeats branch-and-bound pruning. Unreachable from real AX frames (always positive), which is why every suite is green, but genuine latent defects. `FocusManager` and `AutoTiler.overlapRatio` show the correct pattern (guard the denominator) — the others should follow.

**Performance — not a concern given the AX-call gate.** `LayoutSolver` is O(M^N) bounded by `maxChecks`; `AutoTiler.fillGaps` is O(cols·rows·moves·tiles). Both are CPU, not AX calls, and operate on tiny N. The flat-cost-matrix / dense-assignment refactor is a legitimate cache/alloc win with identical semantics. No accidental quadratics in genuinely hot paths.

## Prioritized issues

| Severity | file:line | Issue | Suggested fix |
|---|---|---|---|
| Medium | `ZoneCalculator.swift:167-168` | Unanchored grid regex parses malformed coords (`"abc1"`→`c1`, `"a1:2"`→single cell) instead of returning nil | Anchor: `^([a-z])([0-9]+)(?::([a-z])([0-9]+))?$` |
| Medium | `LayoutSolver.swift:46-51` | `w/h` and `area/screenArea` divide by assumed-positive dims; zero dims → `Inf`/`NaN`, and `NaN` cost defeats B&B pruning | Clamp denominators or early-return sentinel cost for degenerate input |
| Medium | `SmartPlacer.swift:76,84` | `w/h` and `overlap/area` divide by tile area; zero-area tile → `NaN` score | Skip non-positive-area tiles at top of inner loop |
| Low | `WindowMemory.swift:126-130` | Learn guard checks `screenW>0` but not `screenH>0`; zero screen height poisons `meanArea` | Add `&& p.screenH > 0` |
| Low | `ZoneCalculator.swift:183` | `unicodeScalars.first!` force-unwrap on end-column | Make it a guard for robustness |
| Low | `AutoTiler.swift:197` | Hardcoded `100×100` limbo fallback rect | Derive from screen frame or document |
| Low | `FocusManager.swift:108` | `Set(freshOrder) != Set(order)` allocates two sets per cycle | Compare arrays directly or cache the set |

## What's sound

- **Determinism is comprehensive and correct** — the hardest property to get right in this kind of port, done thoroughly (comparators at `LayoutSolver.swift:8-9`, `PlacementStrategy.swift:84`, `AutoTiler.swift:170-175,331-335,345-348`, `WindowMemory.swift:194-197`, `FocusManager.swift:78-83`).
- **Empty / single / boundary inputs are guarded where reachable:** `LayoutSolver:81`, `PlacementStrategy:62,72`, `ScreenNav:22,38`, `ZoneCalculator:79-82` (2x2 fallback), `AutoTiler:80`, `FocusManager:42`.
- **The intricate cycling state machines** (`PlacementStrategy.largestFreeTile`, `FocusManager.Cycler`) are each individually unit-tested, and the assertions match the code's actual branches.
- **`WindowMemory` running-mean math is exact** (verified against hand-computed values), the recency decay is correctly formulated and clamped, and the legacy decoder robustly handles String/Int/Double ids and three legacy `count` encodings.
- **`LayoutSolver` and `ZoneCalculator` carry frozen golden corpora** baked into `swift test`, so the documented tie-break and geometry rules are regression-locked.
- **`Geometry.rectsOverlap` and the intersection helpers** consistently use strict inequalities for edge-touch exclusion and clamp negative overlaps to zero.

---

*None of the Medium findings are reachable from real window/screen frames or the current configs; they are latent (degenerate-input) defects. If hardened, the natural place is a small guard at each division site plus anchoring the grid regex — all low-risk, none affecting the golden corpora.*
