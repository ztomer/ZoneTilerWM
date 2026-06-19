# v3 feature build queue (Gemini-proposed plan — APPROVED)

User approved implementing **everything** from the Gemini consult
([GEMINI_FEATURE_IDEAS.md](GEMINI_FEATURE_IDEAS.md)), each **gated behind a default-off toggle**,
via the autonomous loop. **This file is the source of truth** — tick items as they land so a fresh
context resumes cleanly. Starting version: 1.4.13 → patch-bump per feature → **v1.5.0** at the end.

## Policies (carried from the v2 run)
- Every feature GATED, default OFF (config toggle and/or opt-in hotkey). Routes through the
  ActionRequest spine where it's an action; surfaced via `ActionParser.catalog`.
- AX budget is the gate: enumeration via CGWindowList (0 AX); AX only to mutate. Flag/justify any
  per-interaction AX (only focus-follows-mouse adds any — gate hard).
- Pure logic in `ZTCore` (TDD); OS glue in `ZTSystem`; UI/controllers in `zt-agent`/`ZTUI`.
- `make verify` green before commit. Commit + push each to `v2origin` (branch `v2`). Never `git add -A`.
- **Review:** self-review (5 lenses) for simple/low-risk features; spawn a subagent 5-persona review
  for AX-sensitive or complex ones (focus-follows-mouse, transactional drag-snap, on-device NL).
- Visual features (Scratchpad/Peek/NL box): render via the `ZT_RENDER`/overlay harness + optional
  Gemini grade (Extended) when a display is available; else defer the grade to V2_TEST_DEBT.

## Per-feature loop
implement (gated) → `swift build` + `make verify` (`rm -rf native/.build` first if public ZTCore
enums/inits changed) → self/subagent review → fix → docs (`AUTOMATION.md` / config.toml template) →
bump version → commit + push → tick this file.

## Queue (ordered: Phase A → D, then the parked NL box)
### Phase A — high-utility, low-AX
- [x] Scratchpad Drawer — **v1.4.14 DONE**. `scratchpad` action + `[scratchpad] apps`/`auto_dismiss`
      (default off). Summon/dismiss a configured app set together; auto-dismiss on focus loss. Pure
      `Scratchpad.decide` TDD'd (3 tests); 0 AX (NSWorkspace activate/hide); `ScratchpadController`
      owns state + the didActivateApplication observer. Self-reviewed (5 lenses).
- [ ] App-Cluster Profiles — apply a whole multi-screen layout for a named context ([[clusters]])
- [ ] Visual Window Peek — CoreAnimation/overlay grid of windows stacked in a zone; pick by key
### Phase B — power-user automation (cheap, gated)
- [ ] State-diff event stream on the agent socket (subscribe to CGWindowList diffs)
- [ ] JSON spatial layout macros (author exact geometry → apply)
- [ ] Session sandbox (snapshot+hide → clean layer → restore)
- [ ] Environment/topology presets (auto-switch layout on display-set / Wi-Fi SSID change)
### Phase C — interaction polish (check AX)
- [ ] Transactional drag-snap tap (refine drag-to-snap onto one transactional write)
- [ ] Sticky Tiles (coupled-resize of adjacent tiles)
- [ ] Focus-follows-mouse (gated HARD, default off — only feature adding per-interaction AX)
### Phase D — internal (deferred by Gemini utility, but user said everything)
- [ ] Predictive shadow-buffer (verify layout math headless before mutating)
- [ ] Headless virtual-display layout prefetch
### Parked v2 item
- [ ] On-device NL layout box (FoundationModels — available on this Mac; build real, gated [nl])

## Final
Consolidated `rm -rf native/.build && make verify`, rebuild + reinstall the `.app`, bump to v1.5.0,
update `docs/V2_ROADMAP.md` status, write a run summary here.

## Resume note
Fresh context: read this file + [GEMINI_FEATURE_IDEAS.md](GEMINI_FEATURE_IDEAS.md) + the
`v2-overnight-run` memory. The action API is the spine; mirror the shipped features
(drag-snap/stacks/suggestions) for structure.
