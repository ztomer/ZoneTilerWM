# ZoneTilerWM — roadmap & backlog

The single forward-looking view: what's shipped, what's left, and the decisions that frame it.
This file is **self-contained** — it replaces the old per-version planning docs (V2–V7 roadmaps,
queues, backlogs), which were consolidated here and removed (recoverable in git history).

**The product is mature.** ~80 features shipped across v1.3 → v1.5.16 plus the v2.0 automation
spine and the real-Spaces / Exposé workstream. What's left is small: the App-Store-safe Spaces
fallback, build/distribution plumbing, a little verification owed, and opportunistic tech debt.

Legend: [P1] high · [P2] medium · [P3] low · [deferred] (needs a decision / risky)

---

## 0. Recently shipped (2026-06-20, v2.6 → v2.7)

- **Auto-tile correctness.** `LayoutSolver` made provably globally-optimal (admissible branch-and-bound
  bound; was suboptimal on ~14% of inputs) + best-match window memory. Solver candidate set deduped +
  capped (the real 4×3 made ~34 tiles and the solver was silently truncating to a partial, gap-leaving
  placement). New `stretchToFill` pass grows placed windows into empty space so the desktop is actually
  full (was 49–90% coverage → ~99%). Repeated auto-tile now cycles the centre "j" zone.
- **The empty-desktop root cause:** auto-tile was tiling the agent's own 1×1 Spaces-marker windows;
  `onScreenWindows()` now excludes our own pid (markers, overlays, settings window).
- **Spaces (no private API):** `HybridSpacesProvider` (plist layout + 1×1-marker live current) — the menu
  bar AND Exposé strip now show every Space with the experimental toggle off; per-Space wallpapers wired
  through (plain plist read). Rename-a-Space works in Exposé (double-click a thumbnail).
- **Exposé fixes:** window previews were upside-down (CGImage into a flipped view → now uses `drawUpright`).
- **NOT viable — off-Space window previews/outlines.** Proven empirically: the window-image API returns
  nil for every off-Space window, AND `CGSCopySpacesForWindows` returns an empty space list for windows
  not on the current Space — so off-Space windows can be neither captured nor even *attributed* to a
  Space via point-in-time queries. The only path is a heavy always-on window→Space tracking + thumbnail
  cache subsystem (AltTab/yabai-style); out of scope. Non-current Spaces show their (correct) wallpaper.
- **Style:** Susan Kare TUI glyphs (`ZTCore.Kare`: → · ✓ ✗ ⚠, mirrored from `~/projects/scripts/_stylerc`)
  for the CLI + agent log; **emoji are a failure state**, enforced by `EmojiPolicyTest` over all Swift
  sources (kare glyphs are the only allowlist).

---

## 1. Shipped (the foundation)

Condensed by theme — everything here is **done and in the build**.

- **Tiling engine:** zone keyboard tiling (CSP cost-based backtracking solver), auto-tiler (BSP +
  fill-gaps), resize mode, swap/nudge/throw, per-window float, window stacks (`stack-cycle`),
  adaptive window memory (recency/time decay), layout snapshots, context-aware placement +
  suggestions, margins/gaps.
- **Multi-monitor:** focus/screen nav, move-to-monitor, per-monitor zone grids, display-topology
  presets (auto-action on dock/undock), hot-plug re-registration (logical ids re-seed on
  `didChangeScreenParametersNotification`).
- **Discoverability / UI:** SwiftUI settings (sidebar taxonomy) + live-reload, command palette (⌘K),
  find-a-window-by-typing (fuzzy app-name search in the command palette, and via `/` in window hints
  and Exposé — matches are bordered, the rest dim), window hints, zone HUD (hold-to-reveal), window
  peek, focus border (1:1 frame-tracking outline,
  overlay + experimental SkyLight renderer), custom vector glyphs, appbar-mode settings window.
- **Automation spine (v2.0):** one action vocabulary (`ActionRequest`/`ActionResult`/`ActionParser`
  → `ActionDispatcher`) wrapped by hotkeys, the **MCP server** (`zt-mcp`), **App Intents**, the
  `zonetiler://` **URL scheme**, the **`zonetiler-cli`** CLI, a **rules engine** (`[[rules]]`,
  on-open/on-focus/on-display-change), an event stream, file-based settings sync, and the Automation
  settings pane. See [AUTOMATION.md](AUTOMATION.md).
- **App / feature:** app switcher (incl. ambiguous-pair disambiguation), audio switcher (+Shortcut
  trigger), Pomodoro + retro CRT break screen, scratchpad / app-groups, app-cluster profiles, session
  sandbox, focus-follows-mouse (gated hard — the one per-interaction AX feature), Chrome tab-strip
  toggle, zen mode.
- **On-device AI:** natural-language layout box (FoundationModels, gated), LLM-assisted suggestions.
- **Exposé (#26):** hotkey window-grid Mission-Control replacement — type-to-jump labels,
  click-×-to-close, keyboard actions (↵ open / ⌘W close / ⌘M minimize / ⌘Q quit), arrow / vim-hjkl /
  wasd navigation, modal safety-timeout, real per-window mini-previews, Liquid-Glass space strip.
- **Spaces (real macOS Spaces):** `SpacesReader` (private CGS, read-only) with correct per-space
  wallpapers + current-space highlight; **gesture Space switcher** (`SpaceSwitcher`: synthetic
  dock-swipe `CGEvent` for the active display, "Switch to Desktop N" keyboard fallback cross-display);
  **rename Spaces** (`SpaceNameStore`, persisted by real-Space UUID); **Spaceman-style menubar widget**
  (`SpacesMenubar` pure layout → `SpacesMenubarRenderer` → `SpacesMenubarController` NSStatusItem:
  real spaces grouped per monitor inside a bracket, current filled / others hollow, click-to-switch,
  Kare-flash feedback, selectable bracket style). Designed via a Rams + Kare consult (one honest
  style, no relative view / nav-arrows / switch-mode menu — see §4).
- **Private-API gating + build variants:** the `ZT_PRIVATE_APIS` compile flag gates all three private
  surfaces (CGS Spaces, `_AXUIElementGetWindow`, SkyLight border), each with a public fallback;
  `build_mas.sh` (strict, no private) / `build_public.sh` (private under an experimental toggle, off by
  default) / `build_dev.sh`; runtime toggle `experimental_real_spaces`.
- **Infra / quality:** universal binary, config live-reload, login item, `.app` bundle + CI/CD
  (XcodeGen + self-hosted runner), **352 unit tests** / ~92% ZTCore line coverage, render harness +
  `ZT_*` QA hooks, hardening tests for degenerate inputs, multi-persona reviews.

## 2. What's left

### A. Spaces — finish the App-Store story
1. [done] **Public-API `SpacesProvider`** (built 2026-06-20; live-validated). Three impls selected in order
   by `Spaces.provider(experimentalEnabled:)`:
   - `PrivateSpacesProvider` — wraps the CGS `SpacesReader` (`ZT_PRIVATE_APIS` + runtime toggle on).
     Exact live current + wallpapers + native full-screen.
   - `HybridSpacesProvider` — **NEW (2026-06-20):** the best public path, **no private API**. Joins two
     halves: the **layout** (count / order / per-display / UUIDs / full-screen) from
     `~/Library/Preferences/com.apple.spaces.plist` (`PlistSpacesReader`; parser drops
     stale/disconnected-display entries and remaps the primary's `"Main"` → its CGDisplay UUID), and the
     **live current Space** from a 1×1 marker window pinned per Space (the WhichSpace trick). The join —
     opaque marker id ⇄ plist `ManagedSpaceID` — is `MarkerSpaceResolver`: **launch-seed** from the
     plist when it's fresh + **elimination** as Spaces are visited. This fixed "turning off real Spaces
     makes them disappear" AND keeps the current highlight live. Live-validated: launch `[1,1384]` →
     Ctrl+→ `[3,1384]` → Ctrl+← `[1,1384]`, no marker leak. **Honest limit:** a monitor with ≥3 Spaces
     resolves the launch Space + any visited-by-elimination, else best-effort plist value (the plist's
     `Current Space` only refreshes on create/delete; `kCGWindowWorkspace` is dead). Exact-always = the
     private path. Tests: `PlistSpacesReaderTests` ×6, `MarkerSpaceResolverTests` ×8.
   - `PublicSpacesProvider` — bare marker-window technique. Now the *deepest* fallback, for when even the
     plist is unreadable (a sandboxed App-Store build). Limits: visited-Spaces only, visit-order, no
     wallpapers, synthetic ids.
   `switching` is provider-independent and best-effort (step count assumes desktop order).
2. [deferred] **Move a window between real Spaces.** Needs private `CGSAddWindowsToSpaces` (SIP-touchy) or AX
   emulation (grab-titlebar + switch). Cross-*monitor* move already works (autotile on drop). Decide
   whether to attempt at all.
3. [P3] **Fullscreen-space + monitor-label polish.** `SpacesReader` flags `isFullscreen` (type 4) — verify
   it renders sanely and doesn't break ordering; prefer the real display product name over "Monitor N"
   where available (the DELL already shows "DELL U3223QE").

### B. Distribution & App Store  [deferred] (DEFERRED — no Apple Developer account)
> All signed/notarized/MAS distribution is **blocked on an Apple Developer account**, which we don't
> have. Deferred until one exists. The `build_*.sh` variants + ad-hoc/dev-signed `.app` still work for
> local/dev use; only public/notarized/MAS distribution is gated.
4. [done] **`.app` build variants** (done 2026-06-20). Three package builders emit a full `.app`:
   `./package_dev.sh` (Debug/arm64, private APIs on, dev-signed), `./package_public.sh` (Release
   universal, private on, zipped), `./package_mas.sh` (Release universal, private OFF — verified
   MAS-clean by an `nm` leak guard, zipped). `ZT_PRIVATE_APIS` now threads into the `.app` via
   `Package.swift` reading the env var (xcodebuild's SwiftPM manifest eval picks it up) + the app
   target's `OTHER_SWIFT_FLAGS`. Verified: dev `.app` links the SkyLight SPIs, mas `.app` links none.
   (Real distribution *signing*/notarization of these bundles is still account-blocked, below.)
5. [deferred] **Notarization + Sparkle auto-update** — needs an Apple Developer account (Developer ID + notary).
6. [deferred] **Full MAS submission** — App Sandbox + entitlements (Accessibility, Apple Events) + distribution
   signing + notarization. Needs an Apple Developer account.

### C. Verification owed (live, user-POV)  [P1] / [P2]
7. [P1] **#6 Notion / Notion Calendar unhide.** The port-parity fix (`AppController.launchOrFocus` →
   `NSWorkspace.openApplication`) is in but not yet live-confirmed from a Cmd-H state via the app
   shortcut. Verify both apps.
8. [P2] **Keyboard actions in Exposé.** Live key-capture confirm for ↵/⌘W/⌘M/⌘Q and arrow / vim-hjkl /
   wasd nav (Carbon binds while the modal is up). Pure nav logic is unit-tested; the capture path isn't.
9. [P3] **Liquid Glass final look.** Eyeball `NSGlassEffectView` + dark tint once more on the real display
   against Mission Control (⌃↑) and tune the tint if needed.

### D. Tech debt / infra (opportunistic)  [done] DONE 2026-06-20
> **Ground rule established: no source file over 500 LOC.** Enforced — every file was split to comply.
10. [done] **`AgentController` / `main.swift` god-object** — split into `main.swift` (props + init + bootstrap)
    + `AgentController+Setup.swift` + `AgentController+Runtime.swift` (members made internal for the
    cross-file extensions). Also split: `SettingsGroups`→`SettingsPreviews`, `FeatureSettings`→
    `SettingsRows`, `EditorViews`→`LayoutEditorView`, `MissionControlOverlay`→`MissionControlView`(+`Mouse`),
    `ConfigLoader`→`+Accessors`. All 6 over-limit files now <500.
11. [done] **MAS AX-fallback tie-breaker.** `windowID(of:pid:)` now filters pid+frame matches and breaks ties
    by **z-order** (frontmost = focused), logging the ambiguous case. Title rejected (kCGWindowName is
    usually empty without screen-recording permission).
12. [done] **Dead-code / cleanup.** Removed `AXWindowSystem.allWindowsAcrossSpaces()` (no callers) and the
    `scratch_*.swift` probes. (`getSpaceWallpapers` was already gone.)
13. [P3] **Targeted unit tests.** Golden coverage for the per-display Exposé layout math
    (`ExposeController.layoutFrame(for:union:pos:)`) and `SpacesReader` plist parsing (against a fixture)
    if worth it; the long-standing ZTCore coverage gaps (AutoTiler / PlacementStrategy /
    TilerCoordinator / ConfigLoader) tracked in [REVIEW.md](../REVIEW.md).

### E. Explicitly deferred / skip
- **Literal ⌘S Chrome interception** (CGEventTap) — deferred pending AX-button confirmation; the
  hotkey-driven tab toggle already ships.
- **Predictive shadow-buffer / headless display prefetch** ("Gemini Phase D") — recommended SKIP
  (speculative, no gateable surface).

### F. v2.8 — field-feedback UX pass (NEW 2026-06-20)

Synthesized from a hands-on first-time-user testing pass (a real user, not a developer). The
through-line: the features exist but are **invisible and unexplained** — this is a discoverability
pass, not a capability pass. Decisions locked with the user: overlay defaults to **tile-on-release**;
telemetry is **opt-in / anonymous / off by default**; the "three versions" are **distribution
channels** (App-Store / development / public-DMG), which map onto the existing
`package_mas.sh` / `package_dev.sh` / `package_public.sh` builders.

**Wave 1 — the discoverability spine (highest leverage):**
- [P1] **First-run flow.** Extend the Accessibility-only onboarding into a multi-step: Accessibility →
  **feature checklist** (borders / zone HUD / app launcher / auto-tile, each with a one-line "what it
  does") → **movement-modifier chooser, default Ctrl+Opt** (was Ctrl+Cmd) → **telemetry opt-in**. Single
  screen satisfies feedback 0, 2, the modifier-default fix, and telemetry consent. `AccessibilityOnboarding.swift`.
- [done] **Interactive zone picker — tile-on-release, clarity redesign, cycle-preview, #10 guard**
  (2026-06-21; commits 115c7eb · 6b382d0 · 2d89813). The passive cheat-sheet is now a real preview-then-
  commit picker, on by default. What shipped:
  - **Tile-on-release flow** — pure `ZoneHUDSession` state machine drives it; the Carbon zone-hotkey calls
    `previewIfShowing(_:)` to highlight instead of tiling while the picker is up; **release commits**.
    `[zone_hud] commit_mode` = `on_release` (default) | `immediately`; hold delay default **200ms**.
  - **Cycle-the-preview** — `ZoneHUDSession` tracks `(key, cycleIndex)`; re-pressing the held key advances
    through that zone's placements and the **fill visibly resizes**; release commits exactly the previewed
    tile via `TilerCoordinator.moveFocusedToZone(_:tileIndex:)` (WYSIWYG, bypasses the `findBestTile` auto-
    pick). Immediate mode keeps `tile: nil` so the legacy auto-cycle is preserved.
  - **Clarity redesign (Rams + Kare + Magnet/Moom/Loop consult)** — resolved "caps land between zones": caps
    sit at each key's **smallest tile** (`ZoneHUD.caps`, its atomic cell, not the overlapping primary
    centroid); the **true `cols×rows` base grid** is drawn via `GridLines` (the settings-editor grammar);
    keys that collapse to one cell (`i`/`o`→`d1`, `,`/`.`→`d3`) are **split side-by-side**; the auto-tile
    keys (`default`, `0`) are dropped. The `ZT_HUD_STYLE`/`ZT_HUD_CAPS`/`legend`/`boxes`/`Pick` prototype
    scaffolding was collapsed into one clean implementation.
  - **Feedback-#10 guard** — a keyDown/keyUp monitor feeds the session `otherKeysDown`, so the picker only
    arms when the modifier is held ALONE; a key during the show-delay cancels the arm (quick chord → tile at
    once). With the guard in, **`[zone_hud] enabled` now defaults to true.**
  - Tests: session cycling/wrap, coordinator explicit-index, `ZoneHUD.caps` (smallest/split/drop-0), overlay
    render (highlight + cycle resize) — 412 green. Live-validated via the render harness (`ZT_HUD_HIGHLIGHT`
    + `ZT_HUD_TILE`): j tile0 wide-centre vs tile1 narrow-column, corner `o` clean, `i/o` + `,/.` split.
  - **Live-QA owed:** the #10 guard's real key-monitor behaviour (hold a key + modifier → picker stays
    hidden) isn't automatable headlessly — verify on the live agent; the session logic itself is unit-tested.
- [done] **App-launcher hint grid** (feedback 8, 2026-06-21). Hold `mash_app` (appCuts) or `HYPER`
  (hyperAppCuts) → a Liquid-Glass keyboard palette of that group's shortcuts; release dismisses.
  `AppLauncherHUD` (pure layout) + `AppLauncherHUDController` (hold-to-reveal, both modifiers) +
  `AppLauncherOverlay` (Liquid Glass). Gemini-cleared (SHIP IT 10/10/9.5/10/9.5).

**Wave 1.6 — "Liquid Glass everywhere" overlay sweep + infra (NEW 2026-06-21).** Directive: every
overlay goes native macOS 26 Liquid Glass via ONE shared template (`LiquidGlass.container`/`chip`,
`.clear` style, NSVisualEffectView fallback). Live-screenshot QA (glass can't headless-render) +
**consult Gemini for the aesthetics**, iterate to SHIP IT. Order: **infra first, then the sweep.**
- _Template + done:_ `LiquidGlass` helper ✓; **app-launcher** ✓ (Gemini SHIP IT); **zone HUD** ✓; Exposé
  already used `NSGlassEffectView`.
- **Infra (do first):**
  - [ ] **`borders on|off` socket action** — `ActionRequest.setBorders(enabled:)` + parser + dispatcher
    hook + `FocusBorderController` runtime enable/disable + `zonetiler-cli borders on|off`. So a Gemini
    run flips the focus border over the socket instead of editing the live `config.toml` (done 3× by
    hand tonight). The border occludes the target window's edge and blocks computer-use clicks; the WM
    can't be allowlisted (LSUIElement, unresolvable by name or bundle id).
  - [done] **gemini-bridge skill → AX/osascript** — added the `borders` socket-toggle disable/restore
    step + a steer to the headless osascript/cliclick flow over computer-use screenshots for grading.
- **Sweep — triaged (apply the template where it fits; preserve intentional designs):**
  - [done] **Command palette** (⌘K) — `NSGlassEffectView` backdrop (Exposé sibling pattern), live-verified.
  - [SKIP — intentional design] **Break screen** (Pomodoro) — a deliberate retro CRT aesthetic; glass
    would gut it. **Window-hint badges** — black-on-pastel **zone-color coding is functional** (colour =
    zone); glass dilutes the tint and hurts legibility. Both kept as-is (the design-intent rule).
  - [deferred — SwiftUI, needs a decision] **Onboarding / tutorial / Settings** windows are SwiftUI
    (`NSHostingController`). True `NSGlassEffectView` there needs either the SwiftUI 26 glass modifier or
    a contentView restructure; the onboarding is a **critical first-run path that previously crashed**, so
    not worth a blind autonomous restructure for a subtle backdrop. Do with the user / the wizard build.
  - [separate build, not a glass-conversion] **First-run wizard** — the feedback 0/2 multi-step wizard
    (feature checklist + Ctrl+Opt modifier default + telemetry opt-in) is its own feature; glass it when built.
- **Net:** the interactive AppKit overlays that matter are Liquid Glass (app-launcher — Gemini SHIP IT;
  zone HUD; command palette) + Exposé (pre-existing). The rest are intentional-design skips or a
  user-decision (SwiftUI panels / the wizard build).

**Wave 2 — correctness & intelligence:**
- [P1] **Border filtering** (feedback 1 — the only real *bug*). Arc shows a border "in the middle"
  (latching the wrong layer-0 surface); autocomplete / typing-hint boxes get borders they shouldn't.
  Current filter (`FocusBorderController` frontmost topmost `layer == 0`) is too thin. Plan: live-probe
  Arc + an autocomplete (`probe-first` / `user-pov-debug`) → build a window-trait deny-list (role /
  size / lifetime / floating level) → lock with a deterministic test.
- [P2] **Zone intelligence** (feedback 7). (a) [done 2026-06-21, a932138] Focus-zone falls back to the
  **nearest** window when none overlaps (`FocusManager.collectZoneWindows` opt-in `nearestFallback`;
  pure, 3 tests). (b) [core done 2026-06-21] Manual moves re-learn the zone. Pure core landed +
  tested: `FocusManager.placement(of:zones:)` (frame → best-fit zone/tile by IoU, so a quadrant drag
  re-learns the quadrant not a looser half-zone) + `TilerCoordinator.relearnPlacement(window:screenUUID:)`
  (reuses the existing `learn`/`flush`; **AX-budget-free** — operates on the window the caller already
  read from the CGWindowList poll). **Remaining:** the runtime trigger — a settle-detector on the
  existing CGWindowList poll that fires `relearnPlacement` when a window's frame changes then holds
  stable (skipping our own tile ops), **not** new AX observers. That step writes to the user's *live*
  learned memory, so it needs live drag-QA (drag a window → confirm `window_positions.json` re-learns)
  before "done" per the user-POV-validation rule — pending a live session.

**Wave 3 — infra & heavier UI:**
- [done] **Three-channel CI + DMG** (feedback 12; 2026-06-20). `package_app.sh` gained `ZT_DMG=1`
  (hdiutil drag-to-Applications `.dmg` + INSTALL.txt with the one-time Gatekeeper-unblock step);
  `package_share.sh` = ad-hoc public DMG for hand-off (the dev-cert build was unopenable on other
  Macs). `release.yml` now builds all three channel DMGs on a tag / manual dispatch — `-mas`
  (App-Store-clean), `-dev` (debug), `-public` (direct download) — uploads them as artifacts and
  attaches to the Release; Developer-ID-sign + notarize each when secrets exist, else ad-hoc.
  Notarization itself still **account-blocked** (§B); the DMG build matrix is the unblocked part.
- [P2] **Telemetry** (feedback 11). Wave 1 ships only the local event capture + the consent gate; the
  network sink waits for a privacy policy + endpoint. Opt-in, anonymous, no titles/app-names without
  explicit extra consent — non-negotiable for an app with full Accessibility access.
- [P3] **Zone/tile editor clarity** (feedback 6). The zone-vs-tile mental model isn't conveyed
  anywhere; needs a visual editor that *shows* "a zone is a named region; tiles are its slots." Own
  design pass — not a bolt-on.

**Wave 4 — window previews (NEW 2026-06-21, user request):**
- [P2] **HUD legibility on light desktops** (field bug). The overlay keycaps — dark frosted-glass
  background + **amber/yellow lettering** — wash out over a white/light desktop (the glass is
  translucent, so a bright wallpaper bleeds through and the yellow-on-pale-glass loses contrast). Fix:
  give caps a contrast-guaranteeing treatment independent of the desktop behind them (a darker/denser
  cap fill or a vibrancy-aware label colour + subtle text shadow), so they read on any background.
  Validate via the render harness over BOTH a dark and a white backdrop (`ZT_RENDER_BG`) + Gemini.
- [P2, in progress] **App previews on hover — DockDoor-style** (Windows-11-inspired). Hovering a Dock
  icon (or a HUD/Exposé target) pops a live thumbnail of that app's window(s), click-to-raise. New
  **"Previews" settings sidebar entry**. Requirements locked with the user:
  - **All four Dock positions** — left, right, bottom, AND auto-hidden (resolve the Dock edge + hidden
    state and anchor the panel correctly for each). "Hidden" = auto-hide on any edge, not a 4th edge.
  - **Customizable preview size.**
  - **License: inspiration only.** Reference is [DockDoor](https://github.com/ejbills/DockDoor) but it
    is **GPL** — this app is proprietary, so clean-room from behaviour only, **never** copy its code
    (same discipline as the JankyBorders focus-border reimplementation).
  - **Architecture (probe-validated 2026-06-21).** The Dock's AX tree (`com.apple.dock` process →
    single `AXList` → `AXApplicationDockItem` children) yields every tile's **title + frame** in one
    bounded query — cache it, re-query on Dock change. So hover detection is **0-AX**: a passive
    NSEvent mouse monitor hit-tests the cursor against cached frames; only the one-shot tile-frame read
    and click-to-raise touch AX. Dock edge + auto-hide come from `defaults read com.apple.dock
    orientation/autohide` (no AX). Capture reuses the Exposé `CGWindowListCreateImage` path
    (`MissionControlView`) — on-Space windows only (off-Space capture is impossible, §0).
  - **Status:** [done] pure core `DockPreview` (ZTCore) — `DockEdge`, `DockItem`, cursor hit-test
    (`item(at:)` w/ slop), per-edge panel anchoring (`panelOrigin`) + screen clamping, orientation
    parsing; 8 tests. **Remaining:** `DockObserver` (ZTSystem AX adapter: tile frames + orientation/
    autohide) → `DockPreviewController` (zt-agent: passive mouse monitor + hover dwell + thumbnail
    capture + preview NSPanel + click-raise, gated `[dock_previews] enabled` default off, AX-budget
    gated like focus-follows-mouse) → Previews settings tab (enable + size) → Gemini-grade the panel UI.
- [P3] **HUD previews where relevant.** Where a HUD targets a specific window (zone picker showing the
  focused window, app-launcher showing a running app), show a small live thumbnail so the user sees
  *what* they're about to act on — same capture path as the hover previews above.

## 3. Standing decisions (context for the backlog)

- **Spaces = REAL, not virtual** (2026-06-19). The cosmetic virtual-spaces model was removed; the
  overlay + menubar reflect real macOS Spaces. Unblocks rename, correct wallpapers, and true switching.
- **Private APIs are gated + experimental, with public fallbacks** (2026-06-19). Per-feature runtime
  toggle (default off) + the `ZT_PRIVATE_APIS` compile flag (MAS vs. not). Real Spaces / SkyLight
  border / AX-SPI are the three private surfaces; each degrades to a public path.
- **AX-call budget is the perf gate** (SentinelOne hooks every Accessibility call). Enumeration stays
  0-AX (CGWindowList); AX is touched only on user-triggered mutation. Focus-follows-mouse — the one
  per-interaction AX feature — is gated hard. See [SENTINELONE_INVESTIGATION.md](SENTINELONE_INVESTIGATION.md).

## 4. The Spaces menubar widget — design rationale (Rams + Kare)

The user found Spaceman's relative-space display confusing and its monitor grouping not discernible.
A Rams + Kare consult settled the imported subset:

- **Rams (less, but better):** show **all** spaces, **absolute**, grouped by their **real** monitor —
  one honest representation. CUT the neighbor/relative view, the continuous-vs-restart numbering toggle,
  the nav arrows, the icon-style proliferation, and the switch-mode radio. One well-resolved style, not
  a settings museum. Quiet and monochrome so it lives calmly in the corner of the eye.
- **Kare (every pixel communicates at 22px):** make **monitor grouping the headline** — a thin bracket
  per monitor so the eye parses `[▢ ▢ ▢] [▢ ▢]` as two monitors (the same device proved in the Exposé
  strip — shared visual grammar). Active space **filled**, others **hollow** (unmistakable in peripheral
  vision); a number / 1–2-char name per cell in the app's existing glyph language; fullscreen cells a
  distinct shape; a Kare press-flash on switch for feedback. Per-space **color** is an opt-in recognition
  aid — the hook exists, default off.

**Not imported:** relative/neighbor display, prev/next arrows, numbering toggles, the
filled/rounded/pill/width/font/two-row/list-vs-grid options, switch-mode radio, switch HUD (we have
Exposé), hide-fullscreen, main-display-only (we group all displays instead).

---

### One-paragraph summary

The engine, multi-monitor, automation (MCP/CLI/URL/Intents/rules), settings UI, Exposé, and real
macOS Spaces (switch + rename + menubar widget) are **done and tested** (352 tests). What remains is the
**App-Store-safe public Spaces provider**, **build/distribution plumbing** (xcodegen variants, then
notarization/Sparkle, optionally MAS), a little **verification owed** (Notion unhide, Exposé key
capture), and **opportunistic tech debt**. There is no large unbuilt feature area left — this is
finish-and-ship territory.
