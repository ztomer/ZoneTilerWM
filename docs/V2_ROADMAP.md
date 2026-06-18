# ZoneTilerWM v2 — feature roadmap (brainstorm + plan)

Status: **planning only** (no execution committed). Captured 2026-06-18, against shipped
**1.3.4**. This is a menu of candidates and a recommended phasing, not a contract — revisit and
re-prioritise before building any phase.

## Where we are (so nothing below re-proposes it)

Shipped today: keyboard-grid **zone tiling** (CSP solver), **auto-tiler** (BSP cascade), **window
memory + placement analytics**, **resize mode**, **focus / screen navigation** (multi-monitor),
**app switcher + launcher**, **audio switcher** (+ runs a macOS Shortcut on change), **Pomodoro**
(+ color bar), **focus border** (overlay + experimental SkyLight), **window hints**, **margins/
gaps**, a SwiftUI **settings GUI + analytics**, config **live-reload** with a surgical TOML editor,
login-item, keyboard-layout detection.

## Governing constraints (every feature below is scored against these)

- **AX-call count is the budget, not CPU.** SentinelOne hooks/logs every Accessibility call.
  Reads stay on `CGWindowListCopyWindowInfo` (zero AX); AX is touched only to *mutate* (move/raise/
  hide) and only on user/event action — never per-window for enumeration. See
  `docs/SENTINELONE_INVESTIGATION.md`.
- **Proprietary** — no GPL/code we can't license (the focus border was clean-roomed for this reason).
- **Layering** — pure logic in `ZTCore` (no AppKit; TDD'd), OS adapters in `ZTSystem`, UI in `ZTUI`.
  New algorithmic features (rules engine, context-aware placement) belong in `ZTCore` and should be
  driven by tests first.
- **Private SkyLight / Spaces APIs are a last resort** — fragile across OS updates and noisy under
  SentinelOne.

## North star

**From a keyboard tiler → a programmable, discoverable window layer.** Two pillars that together
serve both new users and power users:

1. **Discoverable for the hands** — a zone HUD and mouse drag-to-snap, so the app is learnable
   without first memorising the keymap.
2. **Programmable** — App Intents / URL / CLI feeding a declarative rules engine, so the app is an
   automation surface, not just an interactive tool.

Layout snapshots are the connective tissue both pillars want.

## Feature catalog (effort S/M/L · risk · AX cost)

### A. Programmability — highest leverage, lowest AX cost
- **macOS App Intents / Shortcuts actions** (M · low · ~0 AX). Expose "tile focused to zone X",
  "auto-tile screen", "switch audio device", "save/restore layout" as App Intents → scriptable from
  Shortcuts, Spotlight, Siri, Raycast, Stream Deck. We already *run* Shortcuts on audio change; this
  is the reverse direction.
- **URL scheme + small CLI** (S–M · low · ~0 AX). `zonetiler://tile?zone=j&monitor=1`, `ztwm tile j`
  — the same action set for shell/automation tools.
- **Window rules engine** (L · low–med · event-gated AX). Declarative match → action, e.g.
  `app == Arc && title ~ "Meet" → zone K on monitor 2, float`. Generalises today's per-app default
  zones into rules with triggers (on-open, on-display-change, on-focus). Pure logic → `ZTCore`,
  TDD-friendly; only acts on events, so AX cost is bounded.

### B. Discoverability — the on-brand "kinesthetic" pillar
- **Modifier-held zone HUD** (M · low · ~0 AX). Hold the tiling modifier → a translucent overlay
  shows the live zone keymap on screen; the keypress lands the window. Overlay + `flagsChanged`
  monitor, reuses `ZTCore` keymap + `GridLines`. **Must be toggleable — see design note below.**
- **Mouse drag-to-snap** (L · med · AX only on drop). Drag a window toward an edge/corner → live
  zone preview overlay → drop to tile (Rectangle/Magnet-style). `CGEventTap` for the drag + overlay
  preview + a single AX `setFrame` on drop. Opens the app to mouse-first users without abandoning
  keyboard-first. The global event tap is the fiddly/risky part.
- **Command palette** (M · low). Fuzzy search over all actions.

### C. Tiling depth
- **Layout snapshots / workspaces** (M · med AX on restore). Save named arrangements ("coding",
  "writing"); restore on demand or automatically on app-set / display detection. Natural extension
  of window memory.
- **Window groups / stacks** (L · med). Several windows share one zone as a tab-stack, cycled with a
  key (yabai/Amethyst-style).
- **Swap / nudge / directional throw** (S–M · low–med). Swap focused window with a neighbour zone;
  throw in a direction.
- **Per-window float toggle** (S · low). Plus remembered floats (extends today's excluded-apps).

### D. Intelligence — build on the analytics already collected
- **Context-aware placement** (M · low · pure `ZTCore`). Add time-of-day / connected-display /
  running-app-set as features in the learner ("morning + external monitor → this layout").
- **Layout suggestions** (M · low). Surface "you usually put Arc here — apply?" from the existing
  preference map.

### E. Distribution & platform maturity
- **Developer ID + notarization + Sparkle auto-update** (M · low · process). Removes the Gatekeeper/
  quarantine + stale-TCC remove/re-add dance (see `INSTALL.txt`, `docs/DEV_SIGNING.md`); gives a real
  update channel.
- **Universal binary** (S). Currently arm64-only (flagged in `build_dist.sh`).
- **Config + memory sync across machines** (M). iCloud or file-based.

### F. Fun / personality — a retro "break" theme (scoped)
- **Retro themed personality moments** (M · low · ~0 AX). A CRT / Gameboy / TV visual treatment —
  applied to *our own* SwiftUI surfaces only (we control those pixels; a Metal/SwiftUI effect is
  trivial there). **Not** a global skin: see the design note below for where it may and may not go.
  The achievable, on-brand version is a **"retro break" theme** — e.g. a Gameboy/CRT Pomodoro
  *break* screen + an optional themed About — opt-in and off by default.

  Reviewed against Rams + Kare and accepted as scoped:

  | Surface | Verdict |
  |---|---|
  | Settings / Analytics / Advanced / zone HUD | **No shader** — read/operate surfaces; a filter is noise that degrades the function (Rams: as little design as possible, unobtrusive, understandable) |
  | About, Pomodoro **break**, onboarding splash, empty states / celebrations | **Yes, sparingly** — personality moments with no data to read; delight that serves, never obscures (Kare) |

  Guardrails: opt-in / off by default (decoration the user didn't ask for is noise — same rule as
  the HUD); never over live data or controls; must read as a deliberate *mode*, not a random reskin
  that fractures the app's one coherent dark visual language.

## Design note — the zone HUD is training wheels, and must come off

The modifier-held HUD is a *learning aid*. Once muscle memory is established, an overlay that fires
every time the modifier is held becomes **noise**, not help. So it is a first-class requirement that
the HUD be **toggleable and unobtrusive by default for experienced users**:

- A plain **on/off setting** (config + Settings UI), and ideally a hotkey to toggle it live.
- A **delay before it appears** (e.g. the overlay only shows if the modifier is held > ~400 ms — a
  quick, confident chord never triggers it; a hesitant hold does). This makes it self-silencing:
  experts who press-and-go never see it, learners who pause get the cheat sheet.
- Consider a **"training wheels" auto-retire**: track HUD-assisted vs blind placements per zone and
  fade/stop showing zones the user clearly knows (data we can derive from the existing analytics).
  Optional / later — the manual toggle + hold-delay already solve the core complaint.
- Rams lens: it should disappear when not needed and never compete with the focused window. Default
  posture leans toward *quiet* (hold-delay on, or off entirely for upgrade installs that already have
  established habits).

## Suggested phasing

- **v2.0 — Programmable core.** App Intents + URL scheme + CLI, then the rules engine on top. Low AX,
  high leverage, mostly testable `ZTCore`, and it makes everything else automatable. Land Developer
  ID + notarization + auto-update here so v2 ships on a real update channel.
- **v2.1 — Kinesthetic discoverability.** Modifier-held zone HUD (with the toggle/hold-delay design
  above), then mouse drag-to-snap. Built on the existing overlay infrastructure.
- **v2.2 — Depth & intelligence.** Layout snapshots/workspaces, window stacks, context-aware
  placement + suggestions.

## Non-goals (and why)

- **macOS Spaces integration** — needs private SkyLight space APIs; fragile across OS updates and
  noisy under SentinelOne, and deliberately out of scope since the Lua original. See
  `docs/SPACES_RESEARCH.md`. Parked unless a public/robust path appears.
- **Live per-window content shaders on *other* apps** (CRT/Gameboy/TV over arbitrary windows) — you
  can't access another process's window surface on macOS, so it would mean continuously
  ScreenCaptureKit-capturing each window → Metal → re-rendering in an overlay that hides the real
  one. That needs the Screen Recording permission, adds capture→shader→draw latency that breaks
  interaction (a shaded text editor is unusable), is GPU-heavy per window, and — worst — a process
  continuously screen-capturing *other* apps reads to an EDR exactly like an infostealer (a hard no
  in a SentinelOne environment). The shippable version is F above (our own surfaces only). A one-shot
  "stylize a window screenshot" novelty is the only capture variant worth maybe revisiting (static,
  opt-in, still needs the recording permission).
- **Animated tiling transitions** — cosmetic, and AX `setFrame` animation was deliberately avoided
  (jank + cost).
- **Any feature needing per-window AX reads for enumeration** — violates the AX budget. Window
  state must come from CGWindowList or be strictly event-gated.
