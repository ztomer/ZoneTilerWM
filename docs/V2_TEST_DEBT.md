# v2.0 — test & validation debt

Per the agreed cadence (build + write tests each stage; iterate/validate in a consolidated
phase), this tracks everything that has NOT been run or live-validated yet. Clear it in one
focused pass and delete items as they're verified. See `docs/AUTOMATION.md` for the features.

## Unit tests — all RUN green
- Full suite green at **233 tests** (incl. RulesEngine, RulesConfig, moveWindow, on-display-change
  matching). The unrun-unit-test debt is cleared; keep running `make verify` each build (headless,
  works with no GUI).

## Live / integration validation pending (needs GUI / the built .app — deferred)
- **Rules engine (on-open)**: real new-window detection (CGWindowList id diff) fires the rule and
  the tile lands on the *newly opened* (not focused) window; baseline-seed does NOT retro-fire on
  pre-existing windows at startup or when a rule is added via live reload.
- **Rules engine (on-focus)**: fires once when focus changes to the app's window (not every poll);
  seed-skips the window focused at launch; tile re-applies on each focus change as documented.
- **Rules engine (on-display-change)**: dock/undock re-places every current window of a matching
  app (fires after monitors re-register).
- **`zonetiler://` URL scheme**: only effective from the installed `.app`. Build it, then
  `open "zonetiler://tile?zone=h"` and confirm dispatch. (So far: swift build green + the
  generated Info.plist carries `CFBundleURLTypes(zonetiler)` — handler not exercised live.)
- **`build_package.sh` helper bundling**: the full `xcodebuild` Release + copy
  `zt-mcp`/`zonetiler-cli` into `Contents/MacOS` + re-sign path has NOT been run. Verify: bundle
  launches, both helpers present and validly signed, Settings → Automation paths resolve to them.
- **Settings → Automation pane** (deferred, UI in use): screenshot pass; toggle persists
  `[automation] enabled`; the socket starts/stops on live reload; the capabilities list renders.
- **App Intents**: only `swift build`-compiled so far. Needs the Xcode-built `.app` so the
  AppIntents metadata extraction runs, then verify in **Shortcuts.app**: the intents appear
  (Tile/Auto-Tile/Switch Audio/Toggle App/Zen/Focus Screen), parameters work, and `perform()`
  forwards over the socket to the running agent (and reports a clean error when it's not running).
  Risk: App Intents discovery in a plain LSUIElement agent target (not a SwiftUI `App`) can be
  finicky — confirm the metadata processor runs and the App Shortcuts (Siri phrases) register.
- Already live-validated (OK): MCP handshake/tools/resources + a real AX tile via MCP;
  `zonetiler-cli` actions + resources + exit codes.

## Known polish
- ✅ DONE: `QueryResult` enum cases now carry labels, so the MCP/CLI JSON is self-describing
  (`{"zones":{"screens":[…]}}`) instead of `{"_0":…}`. (`ActionResult` cases were already labeled.)
- `placement-stats` can surface empty app names from legacy store entries (shown as "(unknown)").
- Possible future: retire legacy `zt-tile`/`zt-autotile` — but they're standalone (own coordinator,
  no agent needed), useful as a no-agent live AX test tool. Keep for now.
