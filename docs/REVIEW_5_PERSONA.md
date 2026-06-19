# ZoneTilerWM — 5-persona review (v1.5.15)

A whole-codebase review through five lenses. **Findings only — no code was changed.** Each item has a
location, a severity, and a recommendation. Severity: **Blocker** (fix before shipping) · **Major**
(should fix) · **Minor** (nice to fix) · **Nit** (taste).

Scope: `Sources/{ZTCore,ZTSystem,ZTUI,zt-agent,zt-mcp,zonetiler-cli,…}` (~13.8 kLOC), the config
layer, the test suite (337 tests, ZTCore ≈95% line coverage), and the v6 in-flight features
(exposé replacement, Chrome tab toggle). The OS-adapter/UI layers are validated by live QA, not units.

> Method note: this is a static read, not a runtime audit. The live-only features (#26) are reviewed
> as code; their on-screen behavior is still pending the live test.

---

## 1. Linus Torvalds — taste, data structures, simplicity

**Good taste already present.** The pure/impure split is real (`ZTCore` can't import AppKit), the
solver/zones are value-in/value-out, and the "decision vs execution" seam (e.g. `AppSwitcher.decide`
→ `AppController.perform`) is exactly right — the decision is data, the side effect is thin. The two
distinct window value-types (`WindowSnapshot` opaque-label vs `LiveWindow` CGWindowID) are correctly
*not* merged. Keep this.

- **[Major] `zt-agent/main.swift` is 1,194 lines — the `AgentController` is a god object.** It owns
  ~15 sub-controllers, every hotkey binding, the render hooks, the lifecycle, the menubar, the socket
  wiring, and the QA env hooks. It works, but it's the one file that resists change. *Rec:* split the
  binding tables (`bind*Hotkeys`) and the QA/render hooks into extensions or a `HotkeyBindings` type;
  move the `ZT_RENDER*`/`ZT_NL` env-hook handling out of the executable's top level into a tiny
  `QAEntryPoints` helper.
- **[Major] Version string duplicated in 3 places** (`project.yml` ×2, `ZTUI/AboutWindow.swift`,
  `zt-mcp/main.swift`) and hand-bumped every release. This is precisely the "same fact in N places"
  smell — it *will* drift. *Rec:* single source of truth (a generated `Version.swift` or read
  `CFBundleShortVersionString` everywhere, with the SwiftPM binaries reading a generated constant).
- **[Minor] Helpers copy-pasted across UI files** — `caption(_:)`, `splitList(_:)`, `configSwatch`
  appear in multiple ZTUI files. *Rec:* one `SettingsKit.swift` with the shared bits.
- **[Nit] `ExposeController.refresh()` = `exit(); enter()` on a 0.3s timer** — a special-case dance
  around async window close. Tasteful version: have the overlay re-query + re-render in place rather
  than tearing the whole modal down and rebuilding it.

## 2. Robert "Uncle Bob" Martin — clean code, SOLID, tests

**Layering + DI are textbook** (protocols at the OS boundary, closures for live-reload, hand-written
fakes). Tests are a genuine spec (337, ~95% on the pure core), and the new features were TDD'd
(MissionControl pure layer before the controller). Naming is consistent and intention-revealing.

- **[Major] Single Responsibility violated by `AgentController`** (see Linus #1) — it's the
  composition root *and* the binding manager *and* the QA harness *and* the overlay coordinator.
  *Rec:* same as above; each `bind*` group and the render hooks are separable units.
- **[Minor] The OS-adapter + UI layers have ~0 unit coverage by design.** Defensible (live QA +
  render harness), but `AXWindowSystem` (frame-with-enhanced-toggle, menu-hide traversal,
  resolveWindow, the new `closeWindow`) is intricate, untested, and a frequent bug site. *Rec:* a thin
  seam test where possible (e.g. the menu-item search + close-button resolution against a fake AX
  tree) — even one or two would guard the trickiest paths.
- **[Minor] `ChromeTabsController` needle-matching is logic with no test.** The DFS + needle match is
  pure-ish and was the kind of thing that should be a ZTCore function with a fake AX node. *Rec:*
  extract the "pick the tab-strip button from a list of (role, description)" decision into ZTCore +
  unit-test it; leave only the AX walk in the controller.
- **[Nit] `main.swift` mixes top-level executable statements with the controller class** — fine for
  SwiftPM, but the QA env-hook block at file scope is easy to miss. Comment-fenced, but extract.

## 3. John Carmack — performance & the AX budget

**The core perf invariant is respected and well-documented:** enumeration is `CGWindowList` (0 AX),
AX is touched only to mutate or read the focused element, the `EnhancedUI` toggle is memoized, and
focus-follows-mouse hit-tests in 0 AX (only the focus mutates). This is the right model for the
SentinelOne "cost = AX-call count" constraint.

- **[Major] `ChromeTabsController.toggle()` DFS-walks Chrome's *entire* AX tree to depth 14.** Chrome's
  accessibility tree is huge; one press could be hundreds–thousands of AX calls — exactly the metric
  the project optimizes against. It's only on an explicit keypress (not the hot path), so it's
  *acceptable*, but document the cost and **prune aggressively**: stop at the toolbar subtree, cache
  the found element per Chrome window, and bail after the first match instead of collecting all
  buttons. *Rec:* targeted traversal (toolbar/tabstrip container) + a per-window element cache.
- **[Minor] `ExposeController` enumerates + lays out + rebinds N transient Carbon hotkeys on every
  open, and `refresh()` does it all again after a close.** Fine for N≈10–30 windows; just don't let
  the 0.3s `asyncAfter` + full rebuild become the norm if close is spammed. *Rec:* debounce refresh.
- **[Minor] `FocusBorderController` runs a 60 Hz fallback `Timer` in `.common` mode** while enabled.
  It coalesces with the skip-when-unchanged check (good), but a perpetual 60 Hz timer is a small
  always-on cost. *Rec:* it's already event-driven via AX observers; consider lowering the fallback
  poll to ~20 Hz, or pausing it when no AX move/resize has fired recently.
- **[Nit] The off-screen render harness spins `RunLoop.current.run(until:)`** — fine for QA, never on
  a user path. No action; noting it's QA-only.

## 4. Dieter Rams + Susan Kare — "less, but better" + visual craft

**The settings overhaul is a clear win:** header toggles instead of title-then-toggle-then-caption
duplication, the Automation declutter (collapsed capabilities, real hotkey shown), the live previews
(border 2×2, Pomodoro bar), the modifier-alias editor, and the custom geometric glyph set (Gemini-
graded to 8–9). The dark, keyboard-grid, data-dense language is intentional and coherent — don't let
a grader flatten it toward stock macOS.

- **[Minor] Icon set still has one fill-language outlier** — App Launcher's filled dots vs the
  otherwise-outlined set (Gemini's "fill bifurcation," partially fixed by outlining Tiling). *Rec:*
  one more Gemini round to decide dots-vs-outline for App Launcher (cosmetic; set is already strong).
- **[Minor] Custom glyphs don't carry SF Symbols' optical-weight matching at every size.** They're
  drawn on a 20-unit grid at one stroke; at very small sidebar sizes some (clock, key) get busy.
  *Rec:* a hairline-thinner stroke under ~16px, or verify at the real sidebar size live.
- **[Minor] Discoverability of the opt-in features still leans on the user finding Keys → Feature
  actions.** The help popovers help, but a first-run hint or an empty-state nudge per gated feature
  would close the loop the original review opened. *Rec:* optional onboarding callout.
- **[Nit] Two "preview" sections (Appearance, Pomodoro) use slightly different framing.** Unify the
  preview chrome (label, padding) so they read as one component.

## 5. Security & Robustness Engineer — attack surface + failure modes

**The remote surface is conservative and well-bounded.** `AgentSocketServer` is a Unix-domain socket
(not TCP — less EDR attention), `chmod 0700`, one request/connection, a 2s recv timeout, a 1 MB read
cap, malformed-JSON → `.error`, all on `.main`. The MCP shim does zero AX. Input from CLI/URL/MCP all
funnels through the validated `ActionParser`. This is a good trust model for a local automation tool.

- **[Major, future] The deferred literal-⌘S Chrome feature needs a keyboard `CGEventTap`.** Correctly
  **not** built yet. Flagging it as the highest-risk planned item: a tap on `keyDown` sees *every*
  keystroke and a bug can wedge or swallow all input. *Rec (when built):* tap on a dedicated runloop
  with `.tapDisabledByTimeout` re-enable, the narrowest possible filter (consume only ⌘S when
  `frontmost.bundleId == com.google.Chrome`), pass-through by default, and a kill-switch.
- **[Minor] Socket trust = "any process running as this user."** `0700` means same-user only, which is
  the intended model, but every powerful action (move/close windows, switch audio, toggle apps) is
  available to any local process of the user with no token. Acceptable for a personal tool; *Rec:*
  document the trust boundary in `AUTOMATION.md`, and if it ever ships broadly, add a per-launch
  token in the socket path or handshake.
- **[Minor] `AXWindowSystem.closeWindow` presses the AX close button blindly.** If the window has
  unsaved changes, the app may show a "save?" sheet — the exposé × then leaves a modal sheet up with
  the overlay possibly still mid-teardown. *Rec:* after close, verify the window went away before
  refreshing; don't assume success.
- **[Minor] `expose`/`peek`/window-hints register transient global hotkeys for single letters
  (a, s, d…).** While the modal is up these shadow those keys globally; if `exit()` is ever missed
  (an exception, a dropped event), the letters stay swallowed. *Rec:* a safety timeout that force-
  exits the modal after N seconds (the Zone HUD already has a poll safety-net — mirror it).
- **[Nit] `open -a <name>` launch fallback in `AppController` passes a user/config string to a
  process.** It's `Process` with argv (not a shell), so no injection — fine; noting it was checked.

---

## Synthesis — prioritized

| # | Item | Lens(es) | Severity |
|---|------|----------|----------|
| 1 | `main.swift` god object — split bindings/QA hooks out of `AgentController` | Linus, Bob | Major |
| 2 | Version string in 3 hand-bumped places → single source of truth | Linus | Major |
| 3 | `ChromeTabsController` AX DFS — prune to the toolbar subtree + cache + bail-on-first | Carmack | Major |
| 4 | When building literal-⌘S: keyboard `CGEventTap` hardening (re-enable, narrow filter, kill-switch) | Security | Major (future) |
| 5 | Extract testable decisions from `AXWindowSystem`/`ChromeTabsController`; seam-test the AX-tricky paths | Bob | Minor |
| 6 | Modal hotkey safety-timeout (expose/peek can't get stuck swallowing keys) | Security | Minor |
| 7 | `closeWindow` should verify the window closed before refreshing | Security | Minor |
| 8 | Dedupe UI helpers (`caption`/`splitList`/`configSwatch`) into one file | Linus, Bob | Minor |
| 9 | Icon polish — App-Launcher fill cohesion + small-size stroke | Rams/Kare | Minor |
| 10 | `FocusBorderController` 60 Hz fallback timer — lower/pause when idle | Carmack | Minor |

**Overall:** the architecture, layering, test discipline, perf model, and recent UX work are strong —
there are no Blockers. The two structural Majors (god-object `main.swift`, duplicated version) are the
highest-value cleanups; the two feature Majors (Chrome AX cost, future ⌘S event-tap) are about doing
the in-flight #26 work carefully rather than fixing existing damage. Nothing here blocks the live test
of #26.
