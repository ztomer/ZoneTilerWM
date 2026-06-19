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
implement (gated) → `swift build` + `make verify` → Gemini UI grade (visual) + apply sound fixes
→ update docs (`AUTOMATION.md` / `V2_ROADMAP.md` / `config.toml` template) → bump version
(project.yml + AboutWindow fallback + zt-mcp serverVersion) → commit + push → tick this file.

## Queue (ordered)
- [x] Command palette — v1.4.1
- [x] Per-window float toggle — v1.4.2
- [x] Swap / nudge / directional throw (actions) — v1.4.3
- [ ] Zone HUD (modifier-held overlay; `[zone_hud] enabled` + hold-delay) — visual
- [ ] Drag-to-snap (CGEventTap; `[drag_snap] enabled` default off; EDR-sensitive) — visual
- [ ] Window stacks / groups (gated)
- [ ] Context-aware placement + layout suggestions (gated config)
- [ ] Retro break theme (Pomodoro break screen; opt-in default off) — visual
- [ ] Universal binary (arm64 + x86_64) — build flag
- [ ] Config + memory sync across machines (file-based; gated)
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
