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
- [x] App-Cluster Profiles — **v1.4.15 DONE**. `cluster name=<n>` action + `[[clusters]]` config
      (name + [[clusters.windows]] app/zone). Launches missing apps (0 AX) + tiles matching windows
      via moveWindow (0-AX enumerate + bounded moves). Pure `ClusterPlan.match` TDD'd (4 tests).
      monitor hint deferred (places on current screen). Self-reviewed (5 lenses).
- [x] Visual Window Peek — **v1.4.16 DONE**. `peek` action + opt-in hotkey. Implemented as
      window-hints scoped to the focused window's zone (reuses the validated badges-overlay +
      key-modal-to-focus infra via a refactored `present()` + new `enterZone()`). Same AX profile as
      window hints (0-AX enumerate; focus on select). Thumbnail grid intentionally NOT used — that
      needs Screen Recording, which the app deliberately avoids. Self-reviewed (5 lenses).
### Phase B — power-user automation (cheap, gated)
- [ ] State-diff event stream on the agent socket (subscribe to CGWindowList diffs)
- [ ] JSON spatial layout macros (author exact geometry → apply)
- [x] Session sandbox — **v1.4.17 DONE**. `sandbox` toggle action: hide every regular/visible/
      non-focused app (remember the set) → restore on toggle. Distinct from zen (minimize). Pure
      `Sandbox.appsToHide` TDD'd (3 tests); 0 AX (NSWorkspace hide/unhide); SandboxController owns
      state. Self-reviewed (5 lenses).
- [x] Environment/topology presets — **v1.4.18 DONE** (display topology; Wi-Fi SSID deferred —
      needs a location entitlement). `[[display_presets]]` (displays must-all-be-present + action
      parsed via ActionParser); on display-set change the first match fires. Pure
      `DisplayPresetEngine.match` TDD'd (5 tests); 0 AX; reuses the existing didChangeScreenParameters
      observer. No new action (it's a trigger). Self-reviewed (5 lenses).
### Phase C — interaction polish (check AX)
- [ ] Transactional drag-snap tap (refine drag-to-snap onto one transactional write)
- [ ] Sticky Tiles (coupled-resize of adjacent tiles)
- [x] Focus-follows-mouse — **v1.4.19 DONE** (gated HARD, default off). Passive `.mouseMoved`
      monitor (0 AX) → dwell timer → on settle, CGWindowList hit-test (`FocusFollowsMouse.topWindow`,
      TDD'd 3 tests) → focus the window under cursor if changed. **5-persona review (AX-sensitive) →
      fixed:** honest AX-cost comments (focus is ~3+N AX, not 1; dwell bounds frequency not cost),
      single coordinate space via `screen(containing:)` (was a bottom-left/top-left mismatch),
      exclude own-app windows, oscillation guard documented. **AX-trace validation required before
      enabling widely — see V2_TEST_DEBT.md.**
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
