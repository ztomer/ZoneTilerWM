# v2.0 — test & validation debt

Per the agreed cadence (build + write tests each stage; iterate/validate in a consolidated
phase), this tracks everything that has NOT been run or live-validated yet. Clear it in one
focused pass and delete items as they're verified. See `docs/AUTOMATION.md` for the features.

## Unit tests written but NOT YET RUN
- `RulesEngineTests` (ZTCoreTests) — compile-checked only.
- `RulesConfigTests` (ZTSystemTests) — compile-checked only.
- (Earlier suites — ActionRequest/Parser/Result, MCPServer, IPCEnvelope, QueryRequest,
  ZoneOccupancy, AgentSocket, CLIFormat, AutomationConfig — were run green at the CLI/GUI stage:
  219 tests. Re-run to confirm nothing regressed since.)

## Missing unit tests (write + run)
- `TilerCoordinator.moveWindow(id:toZone:)` — window-targeted tile (rules-engine path). No test
  yet; use the fake `WindowSystem`/`ScreenProvider` pattern in `TilerCoordinatorTests`. Cover:
  window resolved across screens, places into the right zone, learns on success, nil when the
  window/zone/tile can't be resolved.

## Live / integration validation pending
- **Rules engine (on-open)**: real new-window detection (CGWindowList id diff) fires the rule and
  the tile lands on the *newly opened* (not focused) window; baseline-seed does NOT retro-fire on
  pre-existing windows at startup or when a rule is added via live reload.
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

## Known polish (not bugs)
- `ActionResult`/`QueryResult` encode with Swift's synthesized enum keys (`{"_0":…}`) in the
  MCP/CLI-facing JSON — custom `Codable` would give cleaner payloads.
- `placement-stats` can surface empty app names from legacy store entries (shown as "(unknown)").
