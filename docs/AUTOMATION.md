# ZoneTilerWM — automation surface (action API, MCP, CLI)

v2.0 turns ZoneTilerWM from a keyboard tiler into a **programmable window layer**. Everything
the app can do is named once as an **action vocabulary**, and every entry point — global
hotkeys, the MCP server, and `zonetiler-cli` — is a thin front-end over that one vocabulary.

## The single source of truth

```
front-ends                       one vocabulary            one executor
──────────                       ──────────────            ───────────
hotkeys (Carbon)  ┐
zt-mcp (MCP)      ├─ build an ─▶ ActionRequest  ─────────▶ ActionDispatcher.perform()
zonetiler-cli     ┘             (+ QueryRequest)            (ZTSystem) ─▶ coordinator / AX
```

- **`ActionRequest`** (`ZTCore`) — the verb vocabulary (Codable, Equatable). `ActionResult` is
  the serializable outcome. `ActionParser` is the bidirectional name+params contract
  (`parse(canonical(x)) == x`), and `ActionParser.catalog` enumerates it (one source for the
  MCP tool list, the CLI `--help`, and the Settings capabilities list).
- **`ActionDispatcher`** (`ZTSystem`) — the ONE place actions execute. Adding a front-end never
  means re-implementing an action; it only means building an `ActionRequest`.
- **`QueryRequest`** (`ZTCore`) — read-only resources (`arrangement`, `zones`,
  `placement-stats`). Answered from `CGWindowList` + config + the learned store — **zero AX**,
  no window titles (so no Screen Recording dependency).

## Actions & resources

Run `zonetiler-cli --help` for the live list. Actions: `tile`, `autotile`, `focus-cycle`,
`stack-cycle`, `focus-screen`, `move-monitor`, `nudge`, `throw`, `swap`, `zen`, `float`, `audio`,
`app`, `pomodoro`, `resize-mode`, `window-hints`, `save-layout`, `apply-layout`, `sync-export`,
`sync-import`, `apply-suggestions`, `scratchpad`, `cluster`, `peek`, `sandbox`, `reload`. Resources:
`arrangement`, `zones`, `placement-stats`, `suggestions`.

**`sandbox`** (Session sandbox) toggles a clean-slate focus mode: hides every regular, visible,
non-focused app (remembering exactly which it hid) and restores that set on the next toggle. Unlike
zen (which minimizes others to the Dock), sandbox hides + un-hides, so one chord blanks the desktop
and one brings it all back. 0 AX (NSWorkspace hide/unhide). Bind a `sandbox` hotkey or use
palette/CLI/MCP.

**`peek`** (Window Peek) labels the windows stacked in the **focused window's zone** with hint keys;
type a label to focus that window (ESC cancels). It's `window-hints` scoped to the current zone —
a fast way to jump to a specific window piled in one zone. Same AX profile as window hints
(0-AX CGWindowList enumeration; focus only on selection). Bind a `peek` hotkey under
`[system_hotkeys]`, or trigger via palette/CLI/MCP.

**`cluster name=<name>`** arranges a named **app-cluster profile** (`[[clusters]]`, default none):
launches any of the cluster's apps that aren't running, then tiles each running matching window to
its configured zone. 0-AX enumeration (CGWindowList) + one move per window (the vetted rules-engine
path). Apps launched this pass land on a subsequent `cluster` apply (or pair with a `[[rules]]`
on-open). Surface via palette/CLI/MCP/URL.

**`scratchpad`** summons/dismisses a configured set of utility apps together (`[scratchpad] apps`,
default empty = off). If a scratchpad app is frontmost it hides the set; otherwise it activates them
(first one frontmost). With `auto_dismiss = true` (default) the set hides the moment focus leaves it.
0 AX (NSWorkspace activate/hide). Bind a `scratchpad` hotkey under `[system_hotkeys]`, or call the
action via palette/CLI/MCP.

**`suggestions`** (context-aware placement) cross-references the live arrangement against the
learned per-app preferences and lists every window sitting away from the zone its app usually
occupies on that monitor — each with `currentZone → suggestedZone` and a recency-decayed weight
(same decay the live auto-placement uses). Read-only, **0 AX**; returns `unavailable` when window
memory is off. It's the read surface the LLM-assisted-suggestions front-end builds on:
`zonetiler-cli get suggestions` (or the `zonetiler://suggestions` MCP resource).

### LLM-assisted placement

Because both the read (`suggestions`) and the writes (`tile`, `apply-suggestions`) are MCP
tools/resources, an LLM (Claude over the MCP server) can reason about your layout end-to-end:
read `zonetiler://suggestions`, decide which moves make sense in context, and either issue
per-window `tile` calls or apply them all at once with **`apply-suggestions`** — which moves every
flagged window into its learned-preferred zone (the same per-window tile path the rules engine uses;
bounded AX, never automatic). `apply-suggestions` also stands alone as a one-shot "tidy up to my
usual layout" for the CLI / palette / Shortcuts, no LLM required.

## Transport: agent + Unix-domain socket

The running **agent** holds the Accessibility (TCC) grant and all live state. It listens on a
**Unix-domain socket** (a file, not a TCP port — less EDR attention):
`~/.config/ZoneTilerWM/agent.sock` (override with `ZT_AGENT_SOCKET`). The wire format is the
Codable `IPCEnvelope` (`.action`/`.query` → `.action`/`.query`/`.error`), one JSON line per
message. Front-ends that aren't the agent (the MCP shim, the CLI) do **zero AX** — they just
forward over the socket.

## MCP server (`zt-mcp`)

A tiny stdio shim the MCP client spawns; it speaks JSON-RPC (MCP) over stdin/stdout and forwards
to the agent over the socket. Register it with Claude Code (agent must be running):

```sh
claude mcp add zonetiler -- /ABS/PATH/ZoneTilerWM/native/.build/debug/zt-mcp
```

Tools are generated from `ActionParser.catalog`; resources from `QueryRequest`. The shim holds
no model, key, or network — your own MCP client supplies the model; the server only exposes
local actions/data you already control.

## `zonetiler-cli`

The shell front-end over the same vocabulary and socket:

```sh
zonetiler-cli tile --zone h          # run an action
zonetiler-cli audio --device next
zonetiler-cli get arrangement        # read a resource
zonetiler-cli get zones --json       # machine-readable
zonetiler-cli --help                 # the full catalog
```

Exit code is non-zero on a failed action or an unreachable agent.

## URL scheme (`zonetiler://`)

The bundled `.app` registers the `zonetiler://` scheme (CFBundleURLTypes). macOS delivers the
URL to the running agent as a GURL Apple Event; the agent parses it through the same
`ActionParser` and dispatches:

```
zonetiler://tile?zone=h
zonetiler://audio?device=next
zonetiler://move-monitor?direction=next
```

The host is the action name; the query is the params — identical to the CLI/MCP contract.
Scriptable from anything that can open a URL (`open`, Raycast, Stream Deck, browser, a `.command`
file). Only effective from the installed `.app` (the bare dev binary registers no scheme); it
acts on the focused window (no per-URL window targeting yet).

## App Intents (Shortcuts / Spotlight / Siri)

The bundled `.app` exposes typed **App Intents** — Tile Focused Window, Auto-Tile Screen, Switch
Audio Output, Toggle Application, Toggle Zen Mode, Focus Screen — usable in the Shortcuts editor
and (for a couple) by voice via App Shortcuts. Each intent forwards its `ActionRequest` to the
running agent over the same socket (so it works regardless of which process runs the intent, as
long as the agent is up). Defined in `native/Sources/zt-agent/Intents.swift`; discovered via the
App Intents metadata the Xcode build extracts.

## Layout snapshots (`save-layout` / `apply-layout`)

Capture the current window arrangement under a name and restore it later:

```sh
zonetiler-cli save-layout --name coding     # capture now
zonetiler-cli apply-layout --name coding    # restore later
```

A snapshot records, per (app, monitor), the zone its window occupies; restore matches each
saved assignment to a live window of that app (preferring the same monitor) and tiles it there.
Persisted to `~/.config/ZoneTilerWM/layouts.json`. Best-effort by design (app-name
re-identification) — single-main-window apps restore reliably; multi-window/Electron apps are
approximate (roadmap risk register). Available over MCP and the URL scheme too, same as any action.

## Command palette (in-app ⌘K)

An in-app, keyboard-driven fuzzy launcher over the same action vocabulary. Bind a hotkey, type a
command — `tile h`, `save-layout coding`, `audio`, `zen` — with live fuzzy matches (↑/↓ select,
⏎ run, Tab complete, ⎋ close). The first token resolves to an action (exact / unique-prefix /
subsequence); remaining tokens are the action's params positionally. Pure matching/resolve is
`ZTCore.CommandPalette`; the overlay is the agent.

**Gated (opt-in):** off unless `[command_palette] enabled = true` AND a `command_palette` hotkey is
set under `[system_hotkeys]`. Then it's just another front-end over the dispatcher.

## Zone HUD (modifier-held cheat-sheet)

Hold the tiling modifier past a short delay and a translucent overlay shows each zone key at its
on-screen region — a learnable map so you don't have to memorize the keymap first. Pure layout is
`ZTCore.ZoneHUD.layout(zones:)`; the agent shows it via a `flagsChanged` monitor + hold-delay
timer. It's *display only* — the actual tiling stays the existing modifier+zone hotkey.

**Gated (opt-in):** off unless `[zone_hud] enabled = true`. `hold_delay_ms` (default 400) means a
quick, confident chord never triggers it; only a hesitant hold gets the map — self-silencing for
experienced users.

## Window stacks (`stack-cycle`)

When several windows pile into one zone they form a *stack*; `stack-cycle direction=next|previous`
moves focus through that stack (the focused window's current zone, auto-detected — no zone key
needed), wrapping around. Pure stepping is `ZTCore.ZoneStack.adjacent(focusedId:ordered:direction:)`
over the same z-order-stable ordering `focus-cycle` uses; the coordinator's `cycleZoneStack` has the
**identical AX profile** to `cycleFocus` (enumeration via CGWindowList = 0 AX; the only mutate is the
final focus). No-ops when the focused window isn't in a zone or its zone has < 2 windows.

**Gated (opt-in):** reachable via the `stack-cycle` action in the palette / CLI / MCP; bind a hotkey
by setting `stack_next` / `stack_prev` under `[tiler_hotkeys]` (no default binding).

## Drag-to-snap (modifier + drag)

Drag a window with the tiling modifier held; on drop it snaps into the zone under the cursor.
Target selection is pure (`ZTCore.DragSnap.target(atX:y:zones:)` — smallest zone region that
contains the drop point, else nearest zone centre); the agent observes drags with a **passive**
`NSEvent` global mouse monitor (deliberately *not* an active `CGEventTap`: observe-only, **0 AX**
for detection, and far less EDR attention). The snap reuses the same `tileFocusedToZone` action the
keyboard hotkey dispatches — the cursor position only chooses the zone.

**Gated (opt-in):** off unless `[drag_snap] enabled = true`. Requiring the modifier at drop means
an ordinary window drag is never hijacked. Default off (it installs a global mouse monitor — kept
opt-in for the EDR-conscious). QA hook: `ZT_OPEN_WINDOW=dragsnap` snaps the focused window to the
zone under the cursor without a real drag.

## Retro break screen (Pomodoro)

When a Pomodoro work period ends, a full-screen retro overlay (amber CRT terminal: glowing
monospace "BREAK TIME", scanlines, the rest length + session count) prompts you to step away. It
auto-dismisses after `duration_sec` (default 6) or on a click. Trigger + copy are pure
(`ZTCore.BreakScreen`); the overlay (`ZTSystem.BreakScreenOverlay`) is purely visual and **0 AX**
(screen picked via `screenUnderMouse`). Driven off the existing Pomodoro tick — fires only on
work→break.

**Gated (opt-in):** off unless `[break_screen] enabled = true`. QA hook: `ZT_OPEN_WINDOW=break`.

## Settings sync (`sync-export` / `sync-import`)

Carry your config + learned state across machines through a folder you already sync (iCloud Drive,
Dropbox, …) — no network, no entitlements, no account. Set `[sync] folder` to that folder, then:
`zonetiler-cli sync-export` copies `config.toml`, `window_positions.json`, and `layouts.json` into
`<folder>/ZoneTilerWM/`; on the other machine `sync-import` copies them back. Path logic is pure
(`ZTCore.SyncPlan`); the I/O (`ZTSystem.SyncEngine`) is **0 AX** and **two-phase**: it stages every
file to a temp first (the failure-prone copy touches no live file), then commits with an atomic
swap, keeping the prior version as `<file>.bak`. So a mid-import failure never leaves a file
deleted-but-not-replaced. After a successful import the agent re-reads the config and adopts the
imported state live (layouts replace; learned positions merge, imported winning per app/monitor).

**Gated (opt-in):** does nothing unless `[sync] folder` is set; surfaced via the catalog
(palette/CLI/MCP). Default off.

## Arrangement event stream (`[events]`)

Append one JSON line to an events file whenever the window arrangement meaningfully changes (a window
moves zone/monitor, appears, or disappears). External tools `tail -f` it to react to layout changes
**without polling**. The agent polls the arrangement on a timer (CGWindowList = 0 AX) and emits only
when `ZTCore.ArrangementSignature` changes (raw pixel jitter within a zone doesn't emit). Each line:
`{"ts":<epoch>,"windows":[{windowId,app,frame,monitor,zone}…]}`. Gated `[events] enabled` (default
off) + `path` (default `cache_dir/events.jsonl`) + `interval_ms` (default 1000, clamped 250–10000).
0 AX.

## Focus-follows-mouse (`[focus_follows_mouse]`)

Focus the window the cursor **settles** on. A passive `NSEvent` mouse monitor (0 AX) re-arms a
`delay_ms` dwell timer on every move; only when the cursor rests does it hit-test the window under it
(`ZTCore.FocusFollowsMouse.topWindow`, CGWindowList = 0 AX) and focus it **if it changed**. Passing
the cursor over windows costs nothing — only a deliberate rest on a *new* window focuses.

**AX note (important):** detection is 0 AX, but the focus itself is *not* free — resolving the AX
element reads the target app's window list (~3 + N AX). The dwell bounds the *frequency* (one focus
per rest-on-a-new-window), not the per-focus cost. So this is the only feature that adds
per-interaction AX — **gated HARD, default off**, and you should validate the AX budget on a real
SentinelOne trace before relying on it (see `docs/V2_TEST_DEBT.md`). `[focus_follows_mouse] enabled`
+ `delay_ms` (default 250, clamped 50–2000).

## Display-topology presets (`[[display_presets]]`)

Auto-run an action when the connected display set changes (dock/undock, plug a monitor). Each preset
lists the display names that must all be present; on `didChangeScreenParameters` the first matching
preset (config order) fires its action — e.g. re-apply your docked layout when the external monitor
appears. An empty/omitted `displays` matches always (a fallback). Matching is pure
(`ZTCore.DisplayPresetEngine`); the action is parsed via the shared `ActionParser` (same vocabulary
as rules/CLI). 0 AX (display names from NSScreen). Gated: no-op unless presets are configured.
Wi-Fi-SSID presets are deferred (would need a location entitlement).

## Settings → Automation pane

The agent's Settings window has an **Automation** tab that surfaces this whole feature:
- a **master enable toggle** (writes `[automation] enabled`),
- live **socket status** (path + listening indicator),
- copy-paste **connect snippets** (the `claude mcp add …` command and the `zonetiler-cli` path),
- the full **capabilities list** — every action and resource, rendered straight from
  `ActionParser.catalog` + `QueryRequest`, so the pane can't drift from what the agent supports.

## Config: `[automation]`

```toml
[automation]
enabled = true   # default. Set false to turn off the MCP/CLI control socket entirely.
```

Omitted entirely → **enabled** (the local socket is low-risk and the feature should work out of
the box). The agent starts/stops the socket to match this on launch and on every live reload.

## Window rules (`[[rules]]`)

Declarative **match → action** rules in `config.toml`. A rule matches by **app name**
(case-insensitive; never window title — that needs Screen Recording), fires on a **trigger**, and
runs an **action** expressed in the same `action` + params contract as the CLI/MCP:

```toml
[[rules]]
app = "Arc"
trigger = "on-open"     # on-open | on-focus | on-display-change
action = "tile"         # any action name; params are the action's params
zone = "k"

[[rules]]
app = "Slack"
trigger = "on-open"
action = "tile"
zone = "l"
```

Triggers (all wired):
- **on-open** — a new window of the app appears. Detected by diffing the CGWindowList window-id
  set each focus tick (**0 AX**), baseline-seeded so pre-existing windows never fire.
- **on-focus** — the focused window changes to one of the app's. Fires once per focus change
  (seed-skips the window focused at launch).
- **on-display-change** — the display arrangement changes (dock/undock); re-places every current
  window of a matching app.

`tile` actions target the matched window directly (`coordinator.moveWindow(id:toZone:)`); other
actions fall back to focused-window semantics.

Malformed rules (unknown trigger, missing required action params) are dropped at load. Rules
re-load live with the rest of the config.

## Layering / constraints

- Vocabulary + parsing + MCP message logic + CLI formatting are **pure `ZTCore`** (no AppKit,
  unit-tested). Executor + sockets + CoreAudio/NSWorkspace glue are `ZTSystem`. The shims are
  thin executables.
- **AX budget:** front-ends add no new AX calls — actions reuse the same mutate-on-action paths
  the hotkeys use; resources are `CGWindowList` (0 AX).
