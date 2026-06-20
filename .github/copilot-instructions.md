# Copilot Instructions for ZoneTilerWM

A quick reference for an AI agent working on this codebase. For the full picture read
[ARCHITECTURE.md](../ARCHITECTURE.md), [docs/CONTRIBUTING.md](../docs/CONTRIBUTING.md), and
[docs/ROADMAP.md](../docs/ROADMAP.md).

## 1. Big picture

ZoneTilerWM is a **native Swift macOS menubar agent** — a SwiftPM package at the repo root, no
Hammerspoon. It maps window placement to your keyboard layout (zone tiling), learns preferences, and
adds an automation spine, Exposé, and real macOS Spaces. (It began as a Hammerspoon/Lua config that
was ported to Swift against the Lua as an executable spec; the Lua was removed at parity and lives in
git history.)

## 2. Layering (the contract)

- **`ZTCore`** — pure logic (solver, zones, placement, memory, auto-tiler, action vocabulary). **MUST
  NOT import AppKit / ApplicationServices.** Operates on flat value snapshots; headless-testable.
- **`ZTSystem`** — OS adapters (AX, CGWindowList, NSScreen, Carbon hotkeys, CoreAudio, TOML/JSON,
  Spaces). Conforms to `ZTCore` protocols; dependency inversion lives **only** here, at the OS boundary.
- **`ZTUI`** — SwiftUI settings + analytics. Depends on `ZTCore` only; reads and writes `config.toml`.
- **`zt-agent`** — the `LSUIElement` menubar agent (composition root). Plus helper executables
  `zt-mcp`, `zonetiler-cli`, and dev CLIs.

## 3. Non-negotiables

- **Minimize AX calls — the primary perf gate.** SentinelOne hooks every Accessibility call, so cost
  is AX-round-trip *count*, not CPU. Reads / occupancy / z-order go through `CGWindowListCopyWindowInfo`
  (0 AX); AX is touched only to *mutate* + read the focused element. Never add per-window AX reads for
  enumeration.
- **Top-left CG coordinates everywhere** (`ZTRect`). Convert only inside `NSScreenProvider`.
- **Single-threaded on main**; every event source hops to main before touching `config`/`coordinator`.
- **One action vocabulary** — every front-end builds an `ActionRequest`; none re-implements an action.
- **Private APIs gated** behind the `ZT_PRIVATE_APIS` compile flag (set by `build_*.sh`, not
  `Package.swift`) + a runtime toggle, each with a public fallback. Test gated paths with
  `swift test -Xswiftc -DZT_PRIVATE_APIS`.

## 4. Workflow

- Build/run: `./build.sh`, `./run.sh`. Verify: `make verify` (the Swift unit + golden tests — current
  baseline **352 green**). `.app`: `make app`.
- **`v2` branch only**, push only to `v2origin`. Never `git add -A`; never commit the user's config.
- TDD-first for `ZTCore`; visual features get user-POV (run + screenshot) validation before a
  deterministic test locks them in.

## 5. Documentation

- **[ARCHITECTURE.md](../ARCHITECTURE.md)** — design, layering, conventions, feature status
- **[docs/ROADMAP.md](../docs/ROADMAP.md)** — what's shipped / what's left / standing decisions
- **[docs/CONTRIBUTING.md](../docs/CONTRIBUTING.md)** — build, branch discipline, layering rules
- **[docs/AUTOMATION.md](../docs/AUTOMATION.md)** — the MCP / CLI / URL / Intents / rules surface
- **[REVIEW.md](../REVIEW.md)** — engineering / perf / UI / algorithm review + coverage
