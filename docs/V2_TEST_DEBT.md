# v2.0 — test & validation debt

Per the agreed cadence (build + write tests each stage; iterate/validate in a consolidated
phase), this tracks everything that has NOT been run or live-validated yet. Clear it in one
focused pass and delete items as they're verified. See `docs/AUTOMATION.md` for the features.

## Unit tests — all RUN green
- Full suite green at **236 tests** (incl. RulesEngine, RulesConfig, moveWindow, on-display-change
  matching, hint deoverlap). The unrun-unit-test debt is cleared; keep running `make verify` each
  build (headless).

## Validation pass — DONE (GUI session, this push)
- ✅ **Packaging path** (`build_package.sh`): full xcodegen + xcodebuild Release built the `.app`;
  the helper-bundling + re-sign step works — `Contents/MacOS/{zt-mcp,zonetiler-cli}` present and
  validly signed, deep bundle signature OK.
- ✅ **URL scheme registration**: built Info.plist carries `CFBundleURLTypes(zonetiler)`.
- ✅ **App Intents discoverability**: the `.app` contains `Contents/Resources/Metadata.appintents`
  (metadata extraction ran) → intents will surface in Shortcuts.
- ✅ **Rules engine — on-open**: live-validated. A new Finder window fired
  `rule Finder/on-open → tile h applied=true` and the arrangement confirmed it landed in zone h
  while the pre-existing Finder window was left untouched (baseline-seed correct).
- ✅ **Settings → Automation pane**: screenshot confirmed — Automation tab, enable toggle,
  Status = Listening, MCP/CLI connect snippets + Copy, capabilities list.
- ✅ **Menu bar icon + hint overlap** (commit c87c45c): GUI-validated.
- ✅ Already validated earlier: MCP handshake/tools/resources + a real AX tile via MCP;
  `zonetiler-cli` actions + resources + exit codes.

## Validation pass 2 — DONE (full GUI session, the complete build installed)
The complete build (incl. layout snapshots) was installed to `/Applications` and validated live.
The `ZoneTilerWM Dev` signature already had an Accessibility grant, so installing kept tiling
working (no re-grant). Confirmed:
- ✅ **`zonetiler://` round-trip**: `open "zonetiler://autotile"` auto-tiled the screen,
  `reload` reloaded config, `tile` parsed, and `save-layout?name=…` persisted to `layouts.json`.
  (The GURL handler routes → parses → dispatches → executes.)
- ✅ **App Intents in Shortcuts.app**: ZoneTilerWM appears in the action library with all six
  actions — Tile Focused Window, Auto-Tile Screen, Focus Screen, Switch Audio Output, Toggle
  Application, Toggle Zen Mode. (Surfaced after a post-install reindex / Shortcuts relaunch.)
- ✅ **Rules on-focus**: activating Finder (focus change) fired the rule and tiled the Finder
  window (the `apply()` trigger log was fixed to print the real trigger, not always "on-open").

## Residual (one item, hardware-gated)
- **Rules on-display-change** *detection*: shares the validated `apply()`/`moveWindow` path and the
  tested matching logic; the trigger is the standard `didChangeScreenParametersNotification`
  observer. Not exercised live because it needs a real dock/undock or display reconfiguration.

## Known polish
- ✅ DONE: `QueryResult` enum cases now carry labels, so the MCP/CLI JSON is self-describing
  (`{"zones":{"screens":[…]}}`) instead of `{"_0":…}`. (`ActionResult` cases were already labeled.)
- `placement-stats` can surface empty app names from legacy store entries (shown as "(unknown)").
- Possible future: retire legacy `zt-tile`/`zt-autotile` — but they're standalone (own coordinator,
  no agent needed), useful as a no-agent live AX test tool. Keep for now.

## Pending visual grade (display asleep during overnight run)
- **Zone HUD Gemini grade** — the redesign (deoverlapped key chips on a light dim, no amber wash)
  could not be Gemini-graded: the 2am resume found the display asleep (screencapture = black). Code
  was reviewed twice (5-persona pass) and fixed: 0-AX screen pick (screenUnderMouse), modifier
  poll + screen/space-change dismissal (no orphan), hold-delay clamp, chip de-overlap, fade. Do a
  Gemini visual pass in daylight via ZT_OPEN_WINDOW=hud.

## Live validation deferred — drag-to-snap (v1.4.6)
- **Drag-to-snap live exercise** — the pure target selection (`DragSnap.target`) is fully unit-
  tested (6 cases) and the AX budget / lifecycle / gating were 5-persona-reviewed (verdict: ship).
  Not yet exercised with a REAL modifier-held drag (needs an awake display + a manual drag). The
  controller's mouse-down→drag→up state machine has no unit test (it's NSEvent-monitor-coupled);
  validate live in daylight: set `[drag_snap] enabled = true`, hold the tiling modifier, drag a
  window, confirm it snaps to the zone under the cursor. QA shortcut: `ZT_OPEN_WINDOW=dragsnap`
  snaps the focused window to the cursor's zone without a drag (bypasses the modifier/drag gate).
- **No Gemini grade** — drag-to-snap adds no new visual surface (it reuses the existing tile move),
  so there is nothing to grade; N/A by design.

## Live validation deferred — settings sync (v1.4.10)
- **sync-export / sync-import live round-trip** — pure `SyncPlan` is unit-tested (5 cases) and the
  `SyncEngine` two-phase stage→atomic-commit was 5-persona reviewed (data-loss CRITICAL/HIGH fixed:
  no window where a live file is deleted-but-not-replaced; prior versions kept as `<file>.bak`). Not
  yet exercised against a real synced folder: set `[sync] folder`, run `zonetiler-cli sync-export`,
  confirm `<folder>/ZoneTilerWM/{config.toml,window_positions.json,layouts.json}` appear; on import
  confirm `<file>.bak` is written and the agent adopts the imported config + state live. No visual
  surface → no Gemini grade.

## Packaging check deferred — universal binary (v1.4.9)
- **Full universal `.app` packaging** — `build_package.sh` now requests `ARCHS="arm64 x86_64"`
  and builds the helper tools multi-arch; the SwiftPM half was lipo-verified live (`x86_64 arm64`).
  The full `xcodebuild` Release packaging wasn't re-run this session (slow + Dev signing). Run
  `./build_package.sh` in daylight; the built-in `lipo` gate fails the build if any shipped binary
  (ZoneTilerWM, zt-mcp, zonetiler-cli) isn't fat, so a non-universal regression can't ship silently.

## Live validation deferred — window stacks (v1.4.7)
- **stack-cycle live exercise** — pure `ZoneStack.adjacent` is unit-tested (6 cases) and
  `cycleZoneStack` has the same AX profile as the live-validated `cycleFocus` (5-persona review:
  ship). Not yet exercised with real stacked windows: pile ≥2 windows into one zone, bind
  `stack_next`/`stack_prev` (or call `zonetiler-cli stack-cycle --direction next`), confirm focus
  cycles through the zone's windows and wraps. No new visual surface → no Gemini grade.
