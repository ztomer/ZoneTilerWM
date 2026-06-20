# Contributing to ZoneTilerWM

ZoneTilerWM is a native Swift macOS menubar agent — a SwiftPM package at the repo root. (It began as
a Hammerspoon/Lua config; the Lua was ported to Swift and removed once the port reached parity. It
remains in git history and on the `.hammerspoon` `origin` remote.) Read
[`ARCHITECTURE.md`](../ARCHITECTURE.md) for the full design; this is the contributor quick-start.

## Getting set up

- **macOS + a recent Xcode / Swift toolchain.** `swift --version` should work from the terminal.
- **Build & run:**
  ```sh
  ./build.sh         # build the package (pass-through flags, e.g. ./build.sh -c release)
  ./run.sh           # build + launch the agent in the foreground (Ctrl-C to quit)
  make verify        # the Swift unit + golden tests — the one green/red answer
  make app           # build ZoneTilerWM.app (Release) via xcodegen + xcodebuild
  ```
- **Accessibility permission.** Moving other apps' windows needs the running binary to have
  Accessibility (TCC) trust. macOS keys the grant to the code signature, so ad-hoc signing resets it
  on every rebuild — the build signs with a stable self-signed `ZoneTilerWM Dev` identity when present.
  See [`DEV_SIGNING.md`](DEV_SIGNING.md) for the one-time cert setup and the `tccutil reset` recovery.

## Branch & remote discipline (important)

- **All work stays on the `v2` branch**, published to the private repo `ZoneTilerWMv2` (remote
  `v2origin`). **Never push to the original `.hammerspoon` `origin`.**
- Commit only the files for the change at hand. **Never `git add -A`** — it sweeps in local-only files
  (e.g. `.claude/settings.local.json`). The user's live `~/.config/ZoneTilerWM/config.toml` is not in
  the repo; the repo `config.toml` is only the bundled default template.
- Conventional commits: `<type>(<scope>): <subject>` — e.g. `fix(#26): exposé modal safety-timeout`.

## Layering rules (the architecture is the contract)

| Layer | What it is | Rule |
|---|---|---|
| **`ZTCore`** | Pure logic: solver, zones, placement, memory, auto-tiler, action vocabulary | **MUST NOT import AppKit / ApplicationServices.** Operates on value snapshots. Headless-testable. |
| **`ZTSystem`** | OS adapters: AX, CGWindowList, NSScreen, Carbon hotkeys, CoreAudio, TOML/JSON, Spaces | Conforms to `ZTCore` protocols. Dependency inversion lives **only** here, at the OS boundary. |
| **`ZTUI`** | SwiftUI settings + analytics | Depends on `ZTCore` only. Reads *and* writes `config.toml`. |
| **`zt-agent`** | The `LSUIElement` menubar agent | Composition root (replaces the old `init.lua`). |

Plus the helper executables: `zt-mcp` (MCP server), `zonetiler-cli`, and dev CLIs (`zt-probe`,
`zt-tile`, `zt-autotile`, `zt-axspike`).

### Non-negotiables

- **Minimize AX calls — the primary perf gate.** SentinelOne hooks/logs/analyzes every Accessibility
  call, so cost is AX-round-trip *count*, not CPU. Reads / occupancy / z-order go through
  `CGWindowListCopyWindowInfo` (zero AX); AX is touched only to *mutate* + read the focused element.
  Don't add per-window AX reads for enumeration. See [`SENTINELONE_INVESTIGATION.md`](SENTINELONE_INVESTIGATION.md).
- **Coordinates are top-left CG space everywhere** (`ZTRect`), matching AX + CGWindowList. Convert only
  inside `NSScreenProvider` if reading `NSScreen.frame` (bottom-left). One flip bug breaks every tile.
- **Single-threaded on main.** Every event source hops to the main thread before touching
  `config`/`coordinator`/AppKit. No background queues.
- **One action vocabulary.** A new front-end (hotkey/MCP/CLI/URL/Intent) only builds an `ActionRequest`
  — it never re-implements an action. See [`AUTOMATION.md`](AUTOMATION.md).
- **Private APIs are gated.** CGS Spaces, `_AXUIElementGetWindow`, and the SkyLight border live behind
  the `ZT_PRIVATE_APIS` compile flag (set by the `build_*.sh` scripts, *not* in `Package.swift`) and a
  runtime toggle, each with a public fallback. Build flag-last; test with
  `swift test -Xswiftc -DZT_PRIVATE_APIS`.

## TDD & verification

- **Tests first.** `ZTCore` is headless, so the algorithmic IP is written test-first. The solver/zones
  tests assert against a frozen golden corpus in `Tests/Fixtures/` (a static regression set).
- **`make verify` before anything is "done."** Current baseline: **352 tests green**, ~92% ZTCore line
  coverage.
- **Visual features get user-POV validation.** Anything that changes pixels (window moves, overlays,
  the menubar widget, settings UI) is validated by running the app + screenshot **before** a
  deterministic test locks it in. For window moves the deterministic assertion is the post-move AX
  frame readback. There's a render harness for headless QA (`ZT_RENDER_UI=<tab>:/path.png`,
  `ZT_RENDER=…`, etc.).

## Tooling notes

- Prefer the editor's Read/Grep over `sed`/`awk`/`head` (a shell-rewrite hook can mangle them).
- **Build gotcha:** changing a public `ZTCore` initializer/signature can leave executables linking the
  old symbol (`Undefined symbols … __allocating_init`). SwiftPM incremental misses it —
  `rm -rf .build && swift build` to recover.
