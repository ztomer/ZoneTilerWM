# ZoneTilerWM — feature ideas + proposed plan (Gemini consult)

> **STATUS: PROPOSAL — NOT STARTED. Awaiting your approval before any work.**
> Source: Gemini 3 (Extended thinking) consult, 2026-06-19. The raw ideas are Gemini's; the
> *plan/phasing/prioritization* below is my engineering synthesis. Utility scores live in the
> companion file [GEMINI_FEATURE_UTILITY.md](GEMINI_FEATURE_UTILITY.md).

## Gemini's proposed features (Section A, verbatim intent)

Effort S/M/L; "AX risk" = added Accessibility-call cost (the project's perf budget).

| # | Feature | What it is | Effort | AX risk |
|---|---------|-----------|--------|---------|
| 1 | **Focus-follows-mouse** (Deterministic) | CGEventTap cursor tracking + cached CGWindowList; one AX focus only when the cursor crosses a window perimeter | M | Medium (1 AX per boundary cross) |
| 2 | **Visual Window Peek** (CoreAnimation matrix overlay) | Hardware-accel grid of the windows stacked/hidden in a zone; pick one by key. CGWindowList capture; AX only after selection | M | Low |
| 3 | **Scratchpad Drawer** | A hotkey slides a predefined utility set (Terminal/Notes) in as an overlay; auto-dismiss on focus loss | S | Low |
| 4 | **App-Cluster Profiles** | Bundle apps into named macro-contexts ("Dev", "Finance") and apply a whole multi-screen layout in one action | M | Low (batched moves) |
| 5 | **Sticky Tiles** (relative anchor-linking) | Resizing one tile edge proportionally resizes the coupled neighbour | M | Low |
| 6 | **State-diff event stream** (CLI) | Expose CGWindowList layout diffs on the existing UNIX socket as a subscribe-able stream (no polling) | M | None |
| 7 | **JSON spatial layout macros** | Author exact geometry as JSON → pixel coords; power-user control on asymmetric displays | S | Low |
| 8 | **Session sandbox** | Snapshot the current layout to memory, hide everything, give a clean virtual layer for a focused task; restore after | S | Low |
| 9 | **Environment/topology presets** | Auto-switch tiling presets when the hardware/network environment changes (display set, Wi-Fi SSID) | S | None |
| 10 | **Transactional drag-snap tap** | Re-implement drag-to-snap on a Quartz event tap so the whole drag is one transactional write on release (less EDR pressure, less lag) | M | Low (improves current drag-snap) |
| 11 | **Predictive shadow-buffer** | Verify layout math in a headless coordinate layer before mutating, to avoid intermediate resize stutter on big multi-window ops | L | None |
| 12 | **Headless virtual-display prefetch** | Pre-compute layouts for a display before it's physically connected, so windows land correctly on plug-in | L | None |

## My synthesis — proposed phased plan (for your approval)

Prioritized by Gemini's utility score × AX-safety × effort, and de-duplicated against what already
ships (e.g. #10 is really a refinement of the existing drag-to-snap; #1/#2 lean on the same passive-
monitor + CGWindowList patterns we already use for the zone HUD / drag-snap). Everything stays
**gated, default-off** per project convention, and routes through the existing ActionRequest spine.

- **Phase A — high-utility, low-AX, small/medium (do first if approved)**
  - Scratchpad Drawer (#3) — S, low AX, utility 7. Reuses the overlay-window pattern (ZoneHUDOverlay).
  - App-Cluster Profiles (#4) — M, utility 5 but high leverage; batches existing per-window moves; a
    natural extension of layout snapshots + rules.
  - Visual Window Peek (#2) — M, utility 6; CGWindowList capture (0 AX) + the deterministic-render
    harness just built; AX only on the final focus.
- **Phase B — power-user automation (gated, niche but cheap)**
  - State-diff event stream on the socket (#6) — M, 0 AX; complements the MCP/CLI surface.
  - JSON spatial layout macros (#7) — S; parser feeds the existing zone/tile geometry.
  - Session sandbox (#8) — S; snapshot/hide/restore over existing enumeration.
  - Environment/topology presets (#9) — S, 0 AX; extends the rules engine triggers.
- **Phase C — interaction polish (medium, evaluate AX carefully)**
  - Transactional drag-snap tap (#10) — refine the shipped drag-to-snap onto a single transactional
    write; measure AX/EDR before/after.
  - Sticky Tiles (#5) — M; coupled-resize; fits the resize-mode machinery.
  - Focus-follows-mouse (#1) — M, **Medium AX** — gate hard (default off, opt-in), it's the only
    proposed feature that adds per-interaction AX; validate the budget on a real SentinelOne trace.
- **Phase D — defer / maybe-skip**
  - Predictive shadow-buffer (#11) and headless virtual-display prefetch (#12) — L effort, utility 2,
    largely invisible internal optimizations. Skip unless a concrete stutter/multi-display bug
    justifies them.

## Caveats (read before approving)
- Gemini's utility lens is a **keyboard-tiling purist** — it scored the AI/automation surface low
  (MCP 2, on-device NL 1, suggestions 2, see the utility file). That's a real bias; those are
  arguably the app's *differentiators*. Don't let the consult talk you out of the agentic features.
- Several "new" ideas overlap existing features (#10 ≈ drag-snap; #1/#2 reuse shipped patterns), so
  the true *new* surface is smaller than 12 items.
- Nothing here is started. Tell me which phases/features to pursue and I'll plan them properly
  (TDD'd ZTCore logic, gated, AX-budget-checked, 5-persona review) like the rest of v2.
