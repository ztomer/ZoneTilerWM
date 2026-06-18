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
  `app == Arc → zone K on monitor 2, float`. Generalises today's per-app default zones into rules
  with triggers (on-open, on-display-change, on-focus). Pure logic → `ZTCore`, TDD-friendly; only
  acts on events, so AX cost is bounded.
  - **Match on app / bundle-ID by default — NOT window title.** `CGWindowListCopyWindowInfo`
    returns `kCGWindowName` (titles) as empty for *other* apps' windows on macOS Catalina+ unless we
    hold Screen Recording permission. So a `title ~ "..."` rule would either fail silently or force a
    Screen-Recording grant (a scary prompt that itself triggers EDR auditing) — or fall back to AX
    reads, busting the budget on every window event. Owner/app name *is* available zero-AX, so
    bundle-ID/app matching is the safe default. Title matching, if ever added, is an explicit opt-in
    that documents the Screen-Recording prerequisite. (Plan review, extended-thinking pass.)

### B. Discoverability — the on-brand "kinesthetic" pillar
- **Modifier-held zone HUD** (M · low · ~0 AX). Hold the tiling modifier → a translucent overlay
  shows the live zone keymap on screen; the keypress lands the window. Overlay + `flagsChanged`
  monitor, reuses `ZTCore` keymap + `GridLines`. **Must be toggleable — see design note below.**
- **Mouse drag-to-snap** (L · med · bounded AX: 1 read + 1 write per drag). Drag a window toward an
  edge/corner → live zone preview overlay → drop to tile (Rectangle/Magnet-style).
  - **Bounded-AX interaction (important):** you *cannot* continuously track a foreign window's frame
    mid-drag without AX/SkyLight — `CGWindowList` frames only commit at drag end, and live hit-testing
    via `AXUIElementCopyElementAtPosition` on every move is a continuous AX stream (severe EDR signal,
    busts the budget). So the design is: **one** AX read on `mouseDown` to grab the dragged window's
    ref, then track only the **cursor** via the `CGEventTap` (zero AX) to drive the live zone preview,
    then **one** AX `setFrame` write on `mouseUp`. 1 read + 1 write per drag, not a stream.
  - The global event tap is the fiddly/risky part; and an `LSUIElement` holding a `CGEventTap` is
    itself EDR-sensitive (see risk register). (Plan review, extended-thinking pass.)
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

### G. AI / agent integration — expose the app, don't embed a model
Framing: a tiling WM is a near-perfect *tool surface* for an agent. The bet is to make
ZoneTilerWM **agent-operable** without making it AI-dependent — we embed no model, key, or network
call; the user's own LLM drives our local action surface.

- **MCP server** *(headline · M · low · same AX as the equivalent manual action)*. Wrap the
  internal action API (the same one behind App Intents / URL / CLI in theme A) as MCP so the user's
  Claude (Desktop / Code) can operate the workspace:
  - **Tools** (verbs we already have): `tile_window(zone, monitor)`, `auto_tile_screen()`,
    `apply_layout(name)`, `save_layout(name)`, `switch_audio(device)`, `set_rule(match → action)`,
    `focus_window(...)`.
  - **Resources** (read-only; CGWindowList + the learned store): current arrangement, available
    zones/grids, placement-preference stats.
  - **Why it's cheap:** it's just another thin front-end over the theme-A action API — make that API
    the single source of truth (App Intents + URL + CLI + MCP all wrap it).
  - **Privacy-clean:** we ship no model/key/network; the user's existing client talks to the model,
    our server only exposes local actions/data the user already controls. Important under
    SentinelOne — shipping window titles/app names to a third party would be a real data-leak.
  - **Transport (the one real decision):** Claude Desktop spawns its own stdio MCP process, but our
    agent is already running. Cleanest: a **tiny stdio MCP shim** the client spawns, forwarding to
    the running agent over a local socket / URL scheme / XPC. (Alt: agent hosts a localhost HTTP MCP
    server — one fewer binary, but a listening port draws marginally more EDR attention.) Lean
    stdio-shim. The `mcp-builder` skill covers the build.
- **On-device natural language** *(optional · M · low)*. An in-app "describe your layout" box using
  Apple's **on-device Foundation Models** (Apple Intelligence) — no key, no network, free, private;
  maps "editor left two-thirds, terminal bottom-right" → a constrained zone/tile assignment. Gated
  to capable Macs, so lower priority — but the *only* in-app LLM path endorsed (no embedded cloud
  model; see non-goals).
- **LLM-assisted suggestions** *(opt-in · M · low)*. Name discovered layouts ("your 'research'
  setup"), suggest rules ("you always put Slack here — make a rule?"). Best served *through* the MCP
  stats resource so the user's LLM does the reasoning and we run nothing.

**Hard guardrail:** the LLM *proposes*; the **deterministic solver executes**. Never put a model in
the hot tiling loop — tiling stays instant, deterministic, and oracle-test-covered. AI is for intent
translation + suggestion, not per-keystroke control.

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

- **v2.0 — Programmable core.** App Intents + URL scheme + CLI + the **MCP server** (theme G) — all
  thin front-ends over one internal action API — then the rules engine on top. Low AX, high leverage,
  mostly testable `ZTCore`, and it makes everything else automatable (incl. agent-operable).
- **v2.1 — Kinesthetic discoverability.** Modifier-held zone HUD (with the toggle/hold-delay design
  above), then mouse drag-to-snap. Built on the existing overlay infrastructure.
- **v2.2 — Depth & intelligence.** Layout snapshots/workspaces, window stacks, context-aware
  placement + suggestions.
- **v2.3 — Distribution maturity.** Developer ID + notarization + Sparkle auto-update (theme E), so
  v2 ships on a real update channel. Pushed to last because it's the one phase gated by an external
  dependency (Apple enrollment + notarization round-trips), not by build effort, and the feature work
  shouldn't wait on it. Until v2.3 lands, builds stay ad-hoc-signed and shared via the current
  `build_dist.sh` flow (the bundled `INSTALL.txt` + stale-TCC remove/re-add steps). Universal-binary
  (Intel) also rides here.
  - **Decision (deliberate): notarization is deferred until feature-complete** so the
    distribution/signing approach can be chosen with the full feature set known — accepting the
    caveat below rather than front-loading it.
  - **Caveat to honour at v2.3:** ad-hoc signing *masks* production TCC/EDR behaviour — a
    hardened-runtime, notarized bundle in `/Applications` behaves differently from an ad-hoc build.
    So the EDR-sensitive features (the MCP shim doing IPC, the drag-snap `CGEventTap`) must be
    **re-validated under a notarized build before being considered done**; their ad-hoc behaviour is
    not authoritative. (Plan review flagged production-first; we keep it last by choice + this gate.)

## Risk register (from the extended-thinking plan review)

Validated macOS/EDR traps to design around — not blockers, but each kills a naïve implementation:

- **`kCGWindowName` needs Screen Recording.** Other apps' window titles read empty from
  `CGWindowListCopyWindowInfo` unless `CGPreflightScreenCaptureAccess()` is granted. → rules engine
  matches app/bundle-ID by default (see theme A).
- **Foreign-window live drag tracking is architecturally impossible** without AX/SkyLight polling
  (WindowServer commits frames only at drag end). → drag-snap uses the bounded 1-read/1-write design
  + cursor tracking (see theme B).
- **EDR profile of the agent.** An un-notarized `LSUIElement` that (a) holds a global `CGEventTap`
  and (b) accepts IPC/XPC from an IDE-spawned MCP shim matches Process-Injection / C2 / priv-esc
  heuristics; SentinelOne flags on process ancestry + IPC context. → notarized + hardened runtime is
  the mitigation, and these features get re-validated under a notarized build (see v2.3 caveat).
- **Ad-hoc signing masks production behaviour.** TCC/EDR outcomes differ between an ad-hoc
  `build_dist.sh` binary and a notarized bundle in `/Applications` — don't trust ad-hoc results for
  the security-sensitive features.
- **Layout-snapshot restore is unreliable for multi-window / Electron apps** (Slack, Discord, Adobe,
  CAD): restoring requires re-identifying and mutating non-owned sub-windows whose identity isn't
  stable across launches. → scope snapshots to single-main-window apps first; treat multi-window
  restore as best-effort.

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
- **An embedded cloud LLM** (our own API key, calling out to a hosted model) — cost, latency, key
  management, and a privacy/EDR problem (window titles + app names + habits leaving the device).
  In-app AI, if any, is **on-device only** (Apple Foundation Models); otherwise the user's own MCP
  client supplies the model (theme G). And the LLM never drives the hot tiling loop — it proposes,
  the deterministic solver executes.
