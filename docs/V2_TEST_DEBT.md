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

## Residual (low risk — optional, GUI/Shortcuts round-trips)
- **`zonetiler://` dispatch round-trip**: registration + parse are confirmed and the dispatcher
  path is validated (rules/MCP/CLI all use it); the GURL handler is trivial glue. A full
  LaunchServices round-trip (`open "zonetiler://…"`) wasn't run — it needs the `.app` installed as
  the sole handler (and would reset the ad-hoc grant). Worth one check after a real install.
- **App Intents firing in Shortcuts.app**: metadata present (discoverable) and each intent just
  forwards over the socket (same path as the validated CLI). Visual Shortcuts check is the last mile.
- **Rules on-focus / on-display-change**: share the validated `apply()`/`moveWindow` path and the
  tested matching logic; the trigger *detection* (focus-change / display-change) is unexercised
  live (on-display-change needs a real dock/undock).
- **Note on install**: the installed `.app` is ad-hoc signed; the new build uses `ZoneTilerWM Dev`,
  so installing it resets the Accessibility grant (one-time re-grant) — see `INSTALL.txt`.

## Known polish
- ✅ DONE: `QueryResult` enum cases now carry labels, so the MCP/CLI JSON is self-describing
  (`{"zones":{"screens":[…]}}`) instead of `{"_0":…}`. (`ActionResult` cases were already labeled.)
- `placement-stats` can surface empty app names from legacy store entries (shown as "(unknown)").
- Possible future: retire legacy `zt-tile`/`zt-autotile` — but they're standalone (own coordinator,
  no agent needed), useful as a no-agent live AX test tool. Keep for now.
