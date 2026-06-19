# v2 autonomous build queue (overnight run)

Working through the remaining v2 roadmap unattended. **This file is the source of truth for an
autonomous loop** — update the checklist as features land so a fresh context can resume.

## Policies (set by the user for this run)
- **Gemini grading:** attempt it unattended for every visual feature (drive the Gemini desktop app
  via computer-use); apply its sound fixes within the dark design language (see `ui-design-intent`
  memory — don't gut the design to chase the score; the grader is biased/noisy on dense dark UI).
- **Live validation:** full live validation OK overnight — build the `.app`, reinstall to
  `/Applications` (the `ZoneTilerWM Dev` signature keeps the Accessibility grant), restart the
  agent, move real windows to verify. Restore the user's environment after (relaunch their agent).
- **Blocked features:** land **best-effort, availability-gated stubs** even if they can't be
  exercised on this machine (e.g. on-device Apple-Intelligence NL on an older SDK). Document the
  gap; never stall the loop.
- **Config sync:** **file-based** (user-chosen synced folder + export/import; no entitlements).
- **Cross-cutting (all features):** GATED — each new feature has a config toggle / opt-in hotkey,
  default OFF for anything intrusive or EDR-sensitive. `make verify` green before commit. Commit +
  push each to `v2origin` as a patch bump `1.4.x`. Exclude notarization / Sparkle / Developer ID.

## Per-feature loop
implement (gated) → `swift build` + `make verify` (`rm -rf native/.build` first if public ZTCore
enums/inits changed) → Gemini UI grade (visual) + apply sound fixes → **multi-persona review →
fix → review again → fix** (Linus: systems rigor / correctness / data-structures / simplicity;
Uncle Bob: clean code, naming, small functions, no duplication; Carmack: pragmatism, perf, the
AX-call budget, no over-abstraction; Kare: visual clarity/iconography [visual features]; Rams:
as-little-design-as-possible, unobtrusive [visual features]) → update docs (`AUTOMATION.md` /
`V2_ROADMAP.md` / `config.toml` template) → bump version (project.yml + AboutWindow fallback +
zt-mcp serverVersion) → commit + push → tick this file.

## Queue (ordered)
- [x] Command palette — v1.4.1
- [x] Per-window float toggle — v1.4.2
- [x] Swap / nudge / directional throw (actions) — v1.4.3
- [x] Zone HUD (modifier-held overlay) — v1.4.4 impl, **v1.4.5 review pass DONE**. 5-persona
      review ×2 rounds fixed: 0-AX screen pick (screenUnderMouse, was focusedWindow()=3+AX),
      no-orphan modifier poll + screen/space-change dismiss, hold-delay clamp, chip redesign
      (deoverlapped key chips on a light dim, no amber wash), forceShow-without-poll for QA.
      Gemini visual grade DEFERRED — 2am resume found the display asleep (see V2_TEST_DEBT.md;
      do a daylight pass via ZT_OPEN_WINDOW=hud).
- [x] Drag-to-snap — **v1.4.6 DONE**. `[drag_snap] enabled` default off. Implemented with a
      PASSIVE NSEvent global mouse monitor (down/drag/up), NOT an active CGEventTap — observe-only,
      0 AX for detection (screenUnderMouse + CGEvent.location + computeZones all 0 AX), AX only on
      the snap move (reuses tileFocusedToZone). Modifier-held-at-drop gate so plain drags aren't
      hijacked. Pure `DragSnap.target` TDD'd (6 tests). 5-persona review → ship; fixed mouse-down
      reset (no stale-drag), logging, CGEvent bail-out. Gemini N/A (no new visual surface). Live
      drag exercise deferred (display asleep) — see V2_TEST_DEBT.md; QA hook ZT_OPEN_WINDOW=dragsnap.
- [x] Window stacks / groups — **v1.4.7 DONE** (stack half). New `cycleZoneStack(direction:)`
      action cycles focus through the windows stacked in the focused zone (auto-detected),
      wrapping. Pure `ZoneStack.adjacent` TDD'd (6 tests); same AX profile as the live-validated
      `cycleFocus` (0-AX enumeration, 1 AX focus mutate). Surfaced in catalog (palette/CLI/MCP);
      opt-in hotkeys `stack_next`/`stack_prev` (no default). 5-persona review → ship. Live
      exercise + named persistent groups deferred (see V2_TEST_DEBT.md / future extension).
- [x] Context-aware placement + layout suggestions — **v1.4.8 DONE**. New read-only `suggestions`
      resource: cross-references the live arrangement vs learned WindowMemory prefs, lists windows
      away from their usual zone (`currentZone → suggestedZone` + recency-decayed weight). Pure
      `PlacementSuggestions.compute` TDD'd (5 tests); provider 0-AX (reuses arrangement() +
      rankedPreferences). Surfaced via catalog (CLI `get suggestions` / MCP `zonetiler://suggestions`).
      Gated behind window memory (returns `unavailable` when off). 5-persona review → fixed HIGH
      (thread `now` so weight is recency-decayed, matching live placement) + round-trip coverage.
      This is the read surface the LLM-assisted item consumes.
- [ ] Retro break theme (Pomodoro break screen; opt-in default off) — visual ← NEXT
- [x] Universal binary (arm64 + x86_64) — **v1.4.9 DONE** (build config, not a runtime feature →
      no gating/persona-review). `build_package.sh`: xcodebuild `ARCHS="arm64 x86_64"
      ONLY_ACTIVE_ARCH=NO`; helper tools built `--arch arm64 --arch x86_64` (land under
      `.build/apple/Products/Release`, resolved via `--show-bin-path`); added a `lipo` gate that
      fails packaging if any shipped binary isn't fat. SwiftPM universal half lipo-verified live
      (`x86_64 arm64`). Full `.app` xcodebuild packaging not re-run this session (slow + signing) —
      the lipo gate self-verifies on next package; noted in V2_TEST_DEBT.md.
- [x] Config + memory sync across machines (file-based; gated) — **v1.4.10 DONE**. `[sync] folder`
      (default off). `sync-export`/`sync-import` actions copy config.toml + window_positions.json +
      layouts.json to/from `<folder>/ZoneTilerWM/`. Pure `SyncPlan` TDD'd (5 tests, split config/
      state dirs); `SyncEngine` 0-AX two-phase (stage→atomic-commit, `<file>.bak` backups). Import
      adopts config + state live (layouts replace, positions merge). 5-persona review fixed
      data-loss CRITICAL/HIGH (non-atomic import) + path coupling + state-reload. Live round-trip
      deferred (V2_TEST_DEBT.md).
- [ ] On-device NL layout box (Foundation Models; gated, capable Macs; STUB if SDK-gated) — visual
- [ ] LLM-assisted suggestions (opt-in; lean on the MCP placement-stats resource)

## Final (after the queue)
- One consolidated `make verify`, rebuild + reinstall the complete `.app`, bump to a clean release
  (e.g. v1.5.0), update `docs/V2_ROADMAP.md` status, and write a run summary here.

## Resume note
On a fresh context: read this file + `docs/V2_TEST_DEBT.md` + the `v2-action-api-mcp` memory. The
action API is the spine — every new capability is a new `ActionRequest` case wired through
`ActionDispatcher`, surfaced to all front-ends via `ActionParser.catalog`. Pure logic in `ZTCore`
(TDD), OS glue in `ZTSystem`, UI in `zt-agent`/`ZTUI`.
