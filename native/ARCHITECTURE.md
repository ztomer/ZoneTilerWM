# ZoneTilerWM — Native Port Architecture (v2)

This document is the canonical reference for the **native Swift port** of ZoneTilerWM.
The original is a Hammerspoon/Lua window manager (see `../docs/ARCHITECTURE.md`); v2
rebuilds it as a standalone native macOS menubar agent with no Hammerspoon dependency, at
full feature parity. v2 work lives on the `v2` branch, published to the private repo
`ZoneTilerWMv2`. It is not pushed to the original `.hammerspoon` origin.

The Lua implementation remains in the tree as the **executable specification**: every
ported module is checked for behavioral parity against it (see Differential Testing).

---

## Goals & decisions

- **Stack:** Swift + AppKit. Menubar agent (`LSUIElement`). The genuine C APIs
  (Accessibility, CoreGraphics, CoreAudio, Carbon hotkeys) are wrapped in a Swift adapter
  layer; AppKit/Cocoa pieces (NSScreen, NSStatusItem, NSWorkspace, NSAppleScript) are
  Swift-native.
- **Scope:** full feature parity (tiling, auto-tiler, window memory, Pomodoro, audio
  switcher, app switcher, grid/resize overlay, settings GUI). macOS **Spaces is out of
  scope** (not wired into the production Lua either).
- **Config:** read the existing `config.toml` as-is, with a file-watcher for live reload.
  Existing JSON state in `~/.config/ZoneTilerWM/` stays byte-compatible.

## Engineering principles

- **TDD** — `ZTCore` imports no AppKit, so the algorithmic IP is testable headless. Tests
  (and the Lua-golden fixtures) are written first; code is ported until green.
- **Dependency inversion only at the OS boundary** — protocols (`WindowSystem`, `Storage`,
  `OverlayRenderer`, …) exist where they're earned by testability or a real dual
  implementation (AX vs AppleScript). No speculative abstraction inside `ZTCore`.
- **Minimize AX calls (the *primary* perf gate)** — on SentinelOne-protected machines every
  Accessibility call is hooked, logged, and analyzed (historically 1–2 s per `setFrame`), so
  the real cost of an operation is its AX-round-trip *count*, not CPU. All reads / z-order /
  occupancy go through `CGWindowListCopyWindowInfo` (zero AX, no permission, off the hooked
  path); AX is touched only to *mutate* (move/focus/minimize) and to read the single focused
  element. AX calls therefore scale with *actions*, not *window count* — strictly better than
  the Lua, which needed `window_cache` because `hs.window.allWindows()` was per-window AX. See
  `docs/SENTINELONE_INVESTIGATION.md` and `REVIEW.md` §1.
- **Data over dispatch (CPU, second-order)** — the algorithmic core operates on flat value-type
  snapshots, never protocol existentials, to avoid witness-table dispatch / ARC churn in
  hot loops (the O(Mᴺ) solver, per-event re-tile). Cost matrices are preallocated. (Secondary
  to the AX-call gate above.)
- **Less but better (UI)** — overlays are unobtrusive and disappear when idle; the few
  shipped pixels (menubar glyph, indicators) are crisp and legible.
- **Single-threaded on main (concurrency)** — every agent callback is dispatched to the main
  thread, so there is no shared mutable state crossing threads and nothing to lock: the config
  file-watch `DispatchSource` is created with `queue: .main` (and its debounce uses
  `DispatchQueue.main.asyncAfter`); the focus + Pomodoro `Timer`s run on the main run loop; the
  `didChangeScreenParametersNotification` observer is registered with `queue: .main`; and the
  Carbon hotkey handler (plus the AX `enhancedUICache` it mutates) fires on the main run loop.
  There are no background queues, detached threads, or CoreAudio listener blocks. Keep it that
  way — new event sources must hop to main before touching `config`/`coordinator`/AppKit.
  `make verify` plus `swift test --sanitize=address` and `--sanitize=thread` (CI: the
  `Sanitizers` workflow) all run clean.

---

## Layering

```
ZTCore   — pure logic. MUST NOT import AppKit / ApplicationServices.
           Operates on value snapshots. Headless-testable; the algorithmic IP.
ZTSystem — adapter layer. AX / CGWindowList / NSScreen / Carbon / CoreAudio / NSStatusItem
           / NSWorkspace / JSON storage / config file-watch. Conforms to ZTCore protocols.
ZTUI     — SwiftUI settings (General, keybind editor, visual layout editor, memory
           inspector, onboarding). Reads AND writes config.toml. Depends on ZTCore only.
app      — LSUIElement agent; AppDelegate is the composition root (replaces init.lua).
```

### The value-snapshot vs. mutation-protocol split

Two distinct kinds of types — do not conflate:

1. **Value snapshots (what algorithms consume).** Framework-free structs in `ZTCore`,
   built once by `ZTSystem` per operation: `ZTRect` (top-left CG coords end-to-end),
   `WindowSnapshot` (id, appName, frame, isStandard, isMinimized, screenUUID, zRank),
   `ScreenSnapshot`, `TileSpec`, `MemoryPref`. No protocol dispatch in hot loops; trivially
   constructible in tests.
2. **Mutation protocols (the earned OS boundary).** `WindowSystem` (snapshot reads +
   setFrame/focus/minimize/move), `ScreenProvider`, `Storage`, `Clock`, `OverlayRenderer`,
   `HotkeyBinder`, `AudioController`, `Notifier`. `ZTSystem` conforms; `ZTCore`
   coordination calls them only to act.

### Coordinate space (most likely silent regression)

Keep `ZTRect` in **top-left CG coordinates** end-to-end (matches Lua, the AX API, and
`CGWindowList`). Convert only inside `NSScreenProvider` if reading `NSScreen.frame`
(bottom-left). One flip bug breaks every tile placement.

---

## Differential testing (historical — the engine that built the port)

> **Retired.** The Lua implementation and this differential-oracle harness (`../tools/`,
> `oracle_*.lua`, `diff_*.sh`) were removed once the port reached parity. This section is kept
> as the record of *how* the port was validated; the per-module "diff_X N/N" results in the
> Port-status table below are the frozen parity evidence. Today `make verify` runs the Swift
> tests only, and the solver/zones Swift tests assert against the frozen golden corpus now in
> `native/Tests/Fixtures/`. The Lua remains in git history + the `.hammerspoon` `origin` remote.

The Lua implementation was the spec. For each pure module we ran **both implementations on
the same inputs and diffed**, including fuzz-generated inputs, so correctness was
machine-checkable rather than judged by hand. This covered `ZTCore`; the adapter/UI layers
are covered by visual validation (below).

**Harness layout (`../tools/`):**
- `json.lua` — dependency-free Lua JSON encode/decode.
- `oracle_*.lua` — headless Lua oracles (no Hammerspoon): read a JSON scenario on stdin,
  run the real Lua module, emit JSON results. One per module: `oracle_solver`,
  `oracle_zones`, `oracle_memory`, `oracle_smartplacer`, `oracle_placement`.
- `zt-oracle` (Swift executable, `native/Sources/zt-oracle`) — same JSON contract; mode
  selected by argv: `solve` | `zones` | `memory` | `place` | `strategy`.
- `gen_fuzz_*.lua` — seeded random scenario generators.
- `cmp_*.lua` — result comparators implementing the comparison contract.
- `diff_*.sh` — drivers: build zt-oracle, run both sides over corpus + N fuzz seeds, diff.
  Failing scenarios are saved to `tools/fuzz_failures/`.

**Comparison contract (per the differential-testing design):**
- Solver: window→tile assignment **map** + total cost exact (NOT move order — cosmetic).
- Zone geometry / placement: rects within epsilon (1e-6).
- Window memory: positions/preferences arrays + ranked queries (counts exact, means epsilon).
- Tile indices compared by canonical string form; ties broken deterministically.

**Determinism is a prerequisite.** The Lua oracle must be deterministic or the diff has no
fixed target. Fixes made on `v2`:
- `zone_calculator.lua` — custom-screen + pattern matching iterate keys sorted (was
  hash-order `pairs()`); first match wins.
- `window_memory.lua` — `get_ranked_preferences` total-order sort; sorted-key tie-breaks
  in `get_preferred_tile`/`get_preferred_zone`.
- `placement_strategy.lua` — `find_largest_free_tile` sort is a total order (available
  desc, then original index asc).
- `auto_tiler.lua` — total-order tie-breaks on the working-set sort, solver
  available-tiles sort, and both fill-gaps sorts; `os.time` injectable via `auto_tiler._now`.
- `toml.lua` — Lua 5.5 compat (generic-for variables are now `const`; shadow with locals).

The solver core (`layout_solver.lua`) was already deterministic. All determinism cleanup
is complete.

### Recipe: porting a new ZTCore module

1. Make the Lua module deterministic if it has order-significant `pairs()` / unstable
   `table.sort` / wall-clock reads.
2. Write `tools/oracle_<module>.lua` (stub its system deps; inject any `hs.*` it touches).
3. Add a `zt-oracle` mode + a Swift type in `ZTCore` (value snapshots in/out).
4. Write `tools/gen_fuzz_<module>.lua`, `tools/cmp_<module>.lua`, `tools/diff_<module>.sh`.
5. Iterate until `diff_<module>.sh` is green over a few hundred fuzz seeds; freeze a corpus
   if useful. Add a Swift behavioral unit test in `ZTCoreTests`.

### Scope honesty

The differential engine covers `ZTCore` only. The adapter layer (AX, Carbon, CoreAudio,
overlays, settings GUI) has nothing to diff — the Lua side there is also `hs.*` glue.
Cover it with **visual validation** + a small capability-CLI (one verb per capability).

---

## Native window movement — AX quirks (carry over from Hammerspoon)

When implementing `WindowSystem.setFrame` / `AXFrameSetter` in `ZTSystem`, follow
`../modules/window_actions.lua` (`apply_frame`, ~L135–171; move-to-screen ~L416–484):

- **`AXEnhancedUserInterface` toggle.** Some apps (**Firefox** and other non-native-AX /
  GTK / Electron-ish apps) won't accept a frame change reliably unless the app element's
  `AXEnhancedUserInterface` is set `false` around the set and restored after. The Lua code
  gates this behind `config.tiler.advanced.enterprise_mode` (framed as a SentinelOne
  speedup), but it is the same mechanism quirky apps need.
  **Critical:** Hammerspoon's `hs.window:setFrame` does this dance *internally*; a raw
  `AXUIElementSetAttributeValue(kAXPosition/kAXSize)` native implementation LOSES it and
  must replicate it explicitly — likely always for known-quirky apps, not only in
  enterprise mode. Verify against Firefox specifically.
- **Set position, then size** (some apps clamp otherwise).
- **No animation** (Lua sets `animationDuration = 0`; native AX simply doesn't animate).
- **AppleScript / System-Events fallback** (`use_applescript_window_movement`) — a second
  `WindowSystem` impl for machines where AX is hooked/blocked (SentinelOne).

---

## Visual validation (standing rule)

Every feature that changes a **visual** aspect (window moves as seen on screen, overlays /
grid, menubar indicator, Pomodoro bar, the settings GUI, animations) is validated from the
user's point of view before it is "done":

1. Assume the role of a user — run the real scenario (drive the app via the computer-use
   MCP / `run` skill) and capture **video and screenshots**.
2. Reason about what a user would *expect* vs. what actually happened — catch visual errors
   a unit test can't (wrong monitor, off-by-margins, flicker, z-order, overlay misplacement).
3. **Automate it into a deterministic test** so the behavior is locked in.

This complements the headless differential harness (which cannot see what the user sees).
It applies to the system/adapter + ZTUI phases — not the headless ZTCore ports.

---

## Port status

| Module (Lua) | Swift (ZTCore) | Differential | Commit |
|---|---|---|---|
| layout_solver | LayoutSolver | diff_solver 507/507 | c5d1d62 |
| zone_calculator | ZoneCalculator + ZoneConfig + LuaPattern | diff_zones 410/410 | 6545f6e |
| window_memory | WindowMemory | diff_memory 400/400 | 7acdb7e |
| smart_placer | SmartPlacer | diff_place 500/500 | ce82b71 |
| placement_strategy | PlacementStrategy | diff_strategy 500/500 | 217b298 |
| auto_tiler | AutoTiler | diff_autotiler 600/600 | 34129c5 |

**The pure ZTCore algorithmic IP is complete** — zero Lua↔Swift divergence across all
differential harnesses.

### ZTCore logic modules (beyond the algorithmic IP) — done, headless

All ported as pure logic operating on snapshots, unit-tested (the system calls are the
boundary): **FocusManager** (zone-window collection/ordering + focus cycler),
**AppSwitcher** (toggle decision incl. ambiguous-pair/special-mapping), **Pomodoro**
(work/rest state machine), **AudioSwitcher** (device-cycle pick), **MonitorManager**
(uuid→logical-id registry), **ResizeManager** (grid offsets).

### Adapter layer (ZTSystem) — headless / read-only pieces done

| Adapter | Notes |
|---|---|
| `Storage` + `JSONFileStorage` | JSON per key under ~/.config/ZoneTilerWM; loads legacy shapes (numeric monitor_id, bare-count prefs); verified vs the real window_positions.json. |
| `ConfigLoader` (TOMLKit) | Decodes the real config.toml into ZTCore models; ~ expansion; golden-tested. |
| `ConfigValidator` | Semantic validation of a loaded config. |
| `TOMLEditor` | Surgical comment-preserving in-place edits of config.toml (settings-GUI dependency). |
| `NSScreenProvider` (ScreenProvider) | **Read-only** NSScreen/CGDisplay enumeration; stable UUIDs; top-left CG frames + visible insets. |
| `AXWindowSystem` (enumeration) | **Read-only** CGWindowList z-order/bounds (no permission); AX setFrame (move) validated separately. |
| `AudioDevices` | **Read-only** CoreAudio output-device enumeration + current default. |
| `zt-probe` CLI | Dumps screens/windows/audio — observes only, drives nothing. |

External dep: **TOMLKit** (toml++-backed) for config parsing — chosen over a hand-rolled
parser. `Package.resolved` is committed.

### Phase 0 AX spike — DONE (validated on real Zen/Firefox)

`ZTSystem/AXWindowSystem` + the `zt-axspike` CLI prove the riskiest live pieces:
- Window enumeration + z-order via `CGWindowListCopyWindowInfo` (no permission needed).
- AX `setFrame` (position-then-size) moves another app's window; validated moving Zen
  (Firefox-based) to left/right half — frames land exactly.
- The **AXEnhancedUserInterface toggle** path works; Zen reports it **enabled**, confirming
  it's the app class the toggle targets. (A single move also succeeded without the toggle,
  but the toggle is retained as the default for known-enhanced apps — reliability/speed,
  per the Hammerspoon precedent.)
- AppleScript/System-Events fallback implemented.
- Accessibility (TCC) trust check via `AXIsProcessTrustedWithOptions`.

**Window-move test methodology:** the deterministic assertion for a tiling move is the
post-move **AX frame readback** (`kAXPosition`/`kAXSize`) equal to the target within
tolerance — exactly what `zt-axspike` reports. Screenshots are the human-eye pass.

### Live agent (`zt-agent`) — feature complete except the ZTUI v2 editors

The keyboard-driven WM runs in the `zt-agent` menubar app. Each decision is differentially
verified vs Hammerspoon and/or live-validated (screenshots):

| Feature | Trigger | Verification |
|---|---|---|
| Zone tiling | mash+zone | diff_movezone 400/400; live (Zen) |
| Auto-tile screen | HYPER+return | diff_autotiler 600/600; live |
| Focus cycling | mash_shift+zone | diff_focus 400/400 |
| App switcher | appCuts/hyperAppCuts | unit; live (⇧⌃E→Finder) |
| Adaptive memory | learns on tile, persists | unit; diff_memory |
| Working-set focus tracking | 1s focus poll + startup seed | unit (cull honors real focus age) |
| Audio switch | HYPER+' | unit (cycle) |
| Pomodoro | mash+9/0; menubar text + color bar | unit + live (bar geometry, menubar item) |
| Zen mode | HYPER+\\ | unit |
| Activity Monitor | HYPER+= | live |
| Resize mode | resize_mode hotkey; arrows nudge zone lines | live (cyan overlay + line shift + persisted offsets); unit (GridLines, offset→placement) |
| Multi-monitor nav | placement_mode/zone_info/focus_next/prev_screen | unit + live (two-display validated) |
| Monitor identity | seed at startup + re-register on screen change | unit (lazy-mis-key regression) + live (id 1 = main, 2 = secondary) |
| Window hints | window_hints hotkey | live (icon + key + name badges, keyboard-half placement); unit (label assignment) |
| Hotkey conflicts | startup + reload log; Keys-tab banner | unit (`HotkeyConflicts.find`, real-config) |
| Config live-reload | edit config.toml; reload hotkey; menu item | live (valid/invalid/restore) |
| Overlays | flash on tile/focus; Pomodoro bar; grid; hints | live + unit (geometry/coordinate-flip) |
| Focus border | outline that follows the focused window (overlay + SkyLight renderers); motion-predicted | live (both backends) + unit (`FrameMotionPredictor`) |
| Settings GUI | menubar → Settings… | live (General / Keys / Apps / Layouts / Pomodoro / Advanced) |
| Analytics | menubar → Window Analytics… | live (zone/keyboard/by-app heatmaps + learned-placement table, read-only) |

System adapters: `CarbonHotkeyBinder` (+ modal register/unbind), `KeyMap`, `AppController`,
`AudioDevices`, `Overlay` (flash/bar/grid/hints), `FocusBorderController` (+ `OverlayBorderRenderer`
public NSWindow / `SkyLightBorderRenderer` private window-server, behind ZTCore's `BorderRenderer`;
focused frame sampled from CGWindowList = zero AX, lag compensated by `ZTCore.FrameMotionPredictor`),
`ConfigWatcher` (file-watch reload),
`ZTUI` (SwiftUI settings: General, keybind editor, visual layout editor, memory inspector).
Repo-root `build.sh` / `run.sh` build and launch the agent. `make verify` → **142 Swift tests,
all green** (the Lua + differential harness were retired post-parity — see the banner at the
top of "Differential oracle testing" below). Line coverage is ~92% for the pure-logic `ZTCore`
layer; the OS adapters / UI are validated by live screenshot QA + the post-move AX frame
readback rather than unit tests. See `REVIEW.md` for the full coverage breakdown and the
engineering/performance/UX review.

**Identity / assets** (`native/Assets/`): app icon in light + dark variants
(`AppIcon-1024-light.png` / `-dark.png`, a zone-grid-with-top-left-filled mark) and the
matching `menubar-glyph.svg`, generated with the `gemini-bridge` skill. The live menubar draws
the mark programmatically as a colored image (amber accent zone; grid lines flip for light/dark
menubars, re-rendered on appearance change). The Pomodoro time shows in a frosted-glass capsule
(behind-window `NSVisualEffectView` pinned in the status item with Auto Layout). The focus/tile
flash uses the system accent color (adapts to appearance + the user's accent); the grid (cyan)
and hint badges (amber on black) are deliberately high-contrast identity colors that read on any
desktop.

Three Lua-audit findings shaped scope (Lua is ground truth): the Lua does **not** auto-tile
on new windows (that subscription only warms `window_cache`), has **no** config auto-reload
(manual `hs.reload`), and its resize mode is internally inconsistent (modal arrows drive
`hs.grid.pushWindow*` while the overlay/`resize_manager` are about zone grid lines). Handled
respectively as: dropped (built the real gap — focus-time tracking), added as infra, and
rebuilt coherently (arrows nudge zone grid lines via `ResizeManager`).

### Remaining

- **Productization** (never in scope yet): a real `.app` bundle (`Info.plist`/`LSUIElement`),
  code signing / notarization, launch-at-login, and a first-run accessibility-permission
  onboarding. It currently runs as the SwiftPM `zt-agent` binary via `run.sh`.
- **Quality/polish debt** from `REVIEW.md`: settings-window sizing vs content, form-commit
  consistency (some fields commit only on Return), Keys-tab label alignment, the solver's
  flat cost-matrix / array-assignment micro-optimizations, and raising unit coverage on
  `AutoTiler` / `PlacementStrategy` / `TilerCoordinator` / `ConfigLoader`. None are
  correctness regressions against the Lua spec.

Live multi-monitor validation of the nav + monitor-identity features is now done (verified on
a two-display setup: main display seeds to logical id 1, secondary to 2; re-registers on
display-arrangement change). See `REMAINING_PORT_PLAN.md` for the per-slice detail and
`REVIEW.md` for the review.
