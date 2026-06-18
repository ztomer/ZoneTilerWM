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
`focus-screen`, `move-monitor`, `zen`, `audio`, `app`, `pomodoro`, `resize-mode`,
`window-hints`, `reload`. Resources: `arrangement`, `zones`, `placement-stats`.

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

Triggers:
- **on-open** *(wired)* — a new window of the app appears. Detected by diffing the CGWindowList
  window-id set each focus tick (**0 AX**), baseline-seeded so pre-existing windows never fire.
  `tile` actions target that specific window via `coordinator.moveWindow(id:toZone:)`.
- **on-focus**, **on-display-change** — parsed and stored; agent wiring lands in a follow-up.

Malformed rules (unknown trigger, missing required action params) are dropped at load. Rules
re-load live with the rest of the config.

## Layering / constraints

- Vocabulary + parsing + MCP message logic + CLI formatting are **pure `ZTCore`** (no AppKit,
  unit-tested). Executor + sockets + CoreAudio/NSWorkspace glue are `ZTSystem`. The shims are
  thin executables.
- **AX budget:** front-ends add no new AX calls — actions reuse the same mutate-on-action paths
  the hotkeys use; resources are `CGWindowList` (0 AX).
