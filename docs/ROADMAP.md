# ZoneTilerWM — roadmap & backlog

The single forward-looking view: what's shipped, what's left, and the decisions that frame it.
This file is **self-contained** — it replaces the old per-version planning docs (V2–V7 roadmaps,
queues, backlogs), which were consolidated here and removed (recoverable in git history).

**The product is mature.** ~80 features shipped across v1.3 → v1.5.16 plus the v2.0 automation
spine and the real-Spaces / Exposé workstream. What's left is small: the App-Store-safe Spaces
fallback, build/distribution plumbing, a little verification owed, and opportunistic tech debt.

Legend: 🔴 high · 🟡 medium · ⚪ low · ⏸ deferred (needs a decision / risky)

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
  window hints, zone HUD (hold-to-reveal), window peek, focus border (1:1 frame-tracking outline,
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

### A. Spaces — finish the App-Store story  🟡
1. 🟡 **Public-API `SpacesProvider`.** Define a `SpacesProvider` protocol; `SpacesReader` (private CGS)
   is one impl. Add the App-Store-safe public impl (WhichSpace/AirSpace technique: an invisible 1×1
   `.dynamic` `NSWindow` per Space cross-referenced via `kCGWindowWorkspace` +
   `activeSpaceDidChangeNotification`, plus a one-time "cycle your Spaces" onboarding step). Selector
   picks the impl by `ZT_PRIVATE_APIS` + the runtime toggle. Limits to document: no create/destroy, no
   native-fullscreen tracking. → so a MAS build is more than "current space only".
2. ⏸ **Move a window between real Spaces.** Needs private `CGSAddWindowsToSpaces` (SIP-touchy) or AX
   emulation (grab-titlebar + switch). Cross-*monitor* move already works (autotile on drop). Decide
   whether to attempt at all.
3. ⚪ **Fullscreen-space + monitor-label polish.** `SpacesReader` flags `isFullscreen` (type 4) — verify
   it renders sanely and doesn't break ordering; prefer the real display product name over "Monitor N"
   where available (the DELL already shows "DELL U3223QE").

### B. Distribution & App Store  🟡 / ⏸
4. 🟡 **`.app` build variants.** Thread `ZT_PRIVATE_APIS` into `project.yml` (XcodeGen) so `make app`
   can emit MAS / public / dev `.app` bundles matching the three `build_*.sh` scripts (the flag is
   currently wired only for `swift build`).
5. ⏸ **Notarization + Sparkle auto-update** — deferred to ~v2.3 (needs EDR re-validation under a
   notarized build).
6. ⏸ **Full MAS submission** — App Sandbox + entitlements (Accessibility, Apple Events) + distribution
   signing + notarization. Only if actually shipping to the App Store.

### C. Verification owed (live, user-POV)  🔴 / 🟡
7. 🔴 **#6 Notion / Notion Calendar unhide.** The port-parity fix (`AppController.launchOrFocus` →
   `NSWorkspace.openApplication`) is in but not yet live-confirmed from a Cmd-H state via the app
   shortcut. Verify both apps.
8. 🟡 **Keyboard actions in Exposé.** Live key-capture confirm for ↵/⌘W/⌘M/⌘Q and arrow / vim-hjkl /
   wasd nav (Carbon binds while the modal is up). Pure nav logic is unit-tested; the capture path isn't.
9. ⚪ **Liquid Glass final look.** Eyeball `NSGlassEffectView` + dark tint once more on the real display
   against Mission Control (⌃↑) and tune the tint if needed.

### D. Tech debt / infra (opportunistic)  🟡 / ⚪
10. 🟡 **`AgentController` / `main.swift` god-object** (~1.2k lines) — split the binding tables + modal
    sub-controllers + QA hooks into extensions/types.
11. 🟡 **MAS AX-fallback tie-breaker.** The MAS-safe `windowID(of:pid:)` matches by pid+frame and is
    fragile when an app has multiple identical-size windows — add a z-order/title tie-breaker or accept
    the limit explicitly.
12. ⚪ **Dead-code / cleanup.** `ExposeController.getSpaceWallpapers()` and
    `AXWindowSystem.allWindowsAcrossSpaces()` (no callers since the on-screen-only switch); the
    `scratch_*.swift` probes in the repo root.
13. ⚪ **Targeted unit tests.** Golden coverage for the per-display Exposé layout math
    (`ExposeController.layoutFrame(for:union:pos:)`) and `SpacesReader` plist parsing (against a fixture)
    if worth it; the long-standing ZTCore coverage gaps (AutoTiler / PlacementStrategy /
    TilerCoordinator / ConfigLoader) tracked in [REVIEW.md](../REVIEW.md).

### E. Explicitly deferred / skip
- **Literal ⌘S Chrome interception** (CGEventTap) — deferred pending AX-button confirmation; the
  hotkey-driven tab toggle already ships.
- **Predictive shadow-buffer / headless display prefetch** ("Gemini Phase D") — recommended SKIP
  (speculative, no gateable surface).

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
