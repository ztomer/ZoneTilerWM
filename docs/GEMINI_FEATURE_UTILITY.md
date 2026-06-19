# ZoneTilerWM — feature utility grading (Gemini consult)

> **Consulting only — NOT actionable. No work is implied by this file.**
> Source: Gemini 3 (Extended thinking), 2026-06-19. Utility = Gemini's estimate of how broadly/often
> the feature is used (10 = most users, daily; 0 = niche/rare). Feature ideas are in the companion
> file [GEMINI_FEATURE_IDEAS.md](GEMINI_FEATURE_IDEAS.md).

## Ranked utility (Gemini's scores, verbatim)

| Feature | Current/Proposed | Utility | Gemini's one-line why |
|---------|------------------|:------:|------------------------|
| Zone-based tiling to keyboard zones | Current | 10 | Core workflow power-users hit hundreds of times daily |
| Auto-tile whole screen | Current | 9 | Essential default fallback for fast workspace clearing |
| Drag-to-snap (modifier+drag) | Current | 9 | Bridges keyboard ops with casual mouse positioning |
| Focus-follows-mouse (deterministic) | Proposed | 8 | High-impact speed on large hi-res desktops |
| Window memory (per-app placement) | Current | 8 | High-value background; minimizes manual placement |
| Command palette (⌘K) | Current | 8 | Definitive access hub w/o complex keymaps |
| Scratchpad Drawer | Proposed | 7 | Efficient transient reference / terminal / snippets |
| Focus-cycle within a zone | Current | 7 | Core nav for overlapping elements |
| Move-to-next/prev monitor | Current | 7 | Essential for multi-display |
| Window-stack cycle | Current | 7 | Untangles overlapping app instances in a zone |
| Focus border | Current | 7 | Vital visual confirmation on big/complex displays |
| Transactional drag-snap tap | Proposed | 6 | Optimizes responsiveness; less EDR logging on placement |
| Visual Window Peek (CoreAnimation overlay) | Proposed | 6 | Clarity/triage for densely layered tiles |
| Declarative rules engine | Current | 6 | Powerful set-and-forget, but setup overhead |
| Swap / nudge / directional throw | Current | 6 | Fine-tuning; secondary to clean structural ops |
| App-Cluster Profiles | Proposed | 5 | Swift context shifts, mostly at transition points |
| Sticky Tiles (relative anchor-linking) | Proposed | 5 | Granular editing control; bypassed by standard layouts |
| App Intents / Shortcuts | Current | 5 | Deep OS automation, but power-user-only |
| Per-window float toggle | Current | 4 | Necessary escape hatch; breaks tiling philosophy |
| JSON spatial layout macros | Proposed | 4 | Exceptional depth, advanced-users-only |
| File-based settings sync | Current | 4 | Solves multi-machine, but only at provisioning |
| Window hints (type-to-focus) | Current | 4 | Niche; redundant if a fuzzy palette exists |
| zonetiler-cli / URL scheme | Current | 4 | Unlocks automation; scripting-purists |
| State-diff shell pipe | Proposed | 3 | Specialized data pipe for custom config projects |
| Session sandbox | Proposed | 3 | Valuable for distraction removal; rarely standard |
| Environment/topology presets | Proposed | 3 | Situational; multi-office travelers |
| Zen mode (minimize others) | Current | 3 | Specialized; redundant if a scratchpad exists |
| Audio-output switch | Current | 3 | Feature bloat; deviates from spatial window mgmt |
| Predictive shadow-buffer | Proposed | 2 | Internal perf; invisible to daily users |
| Headless virtual-display prefetch | Proposed | 2 | Minor edge case |
| Pomodoro timer + break overlay | Current | 2 | Feature creep; better in dedicated tools |
| Context-aware "suggestions" resource | Current | 2 | Cognitive/operational overhead for static computing |
| MCP server (Claude/LLM control) | Current | 2 | Experimental; minimal applicability for keyboard-driven |
| On-device natural-language layout | Current | 1 | Impractical gimmick; full sentences destroy shortcut ergonomics |

## How to read this (important)

Gemini graded through a **keyboard-tiling-purist** lens: it rewards the fast spatial core (tiling,
auto-tile, drag-snap, palette) and penalizes anything it sees as "feature creep" or mouse/AI-driven.
That lens systematically **under-rates the agentic/automation surface** (MCP 2, on-device NL 1,
suggestions 2, audio/pomodoro 2–3) — which is precisely what differentiates ZoneTilerWM from
Magnet/Rectangle/yabai. Treat the low AI scores as "a tiling purist wouldn't use these," not as
"these have no value." The scores are a useful *prioritization signal for the core power-user
audience*, not a mandate to remove the differentiators. Decisions are yours — this file is just the
consult.
