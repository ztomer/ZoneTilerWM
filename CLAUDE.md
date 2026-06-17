# ZoneTilerWM — project guide

A macOS window manager. Two implementations coexist in this repo:

- **Lua (Hammerspoon)** — the original, in `modules/` + `init.lua` + `config.toml`. This is
  the **executable spec**: the v2 port is checked for behavioral parity against it.
- **Swift native port (v2)** — in `native/` (SwiftPM). A standalone menubar agent, no
  Hammerspoon. `tools/` holds the Lua↔Swift differential oracles.

**Read `native/ARCHITECTURE.md`** for the full design, port status, and methodology. This
file is the quick operational guide.

## Hard rules

- **All v2 work stays on the local `v2` branch. NEVER push to origin, no PRs.** Commit
  locally only (and only the files for the slice at hand — leave unrelated working-tree
  changes alone).
- **Verify with `make verify`** before considering anything done (see below).
- Quality bar: TDD-first; data structures over clever code; dependency-inversion only at
  the OS boundary; perf-aware in the hot solver path. The Lua is the source of truth for
  behavior.

## Verify / test

- `make verify` — Swift tests + all six differential harnesses + the Lua spec runner. One
  green/red answer. Use this.
- `make test-swift` / `make test-lua` / `make diff` / `make probe` for pieces.
- Current baseline: `swift test` green (70+), all `diff_*.sh` green, Lua runner 4/4.

## Porting a ZTCore module (the differential recipe)

1. If the Lua module has nondeterminism (order-significant `pairs()`, unstable `table.sort`,
   wall-clock reads), fix it first — total-order sorts, inject the clock. The Lua must be
   deterministic or the diff has no fixed target.
2. `tools/oracle_<m>.lua` — headless (no Hammerspoon; stub system deps), JSON in/out.
3. `zt-oracle` gets a mode; the Swift type goes in `ZTCore` (operate on value snapshots).
4. `tools/gen_fuzz_<m>.lua` + `tools/cmp_<m>.lua` + `tools/diff_<m>.sh`; iterate to green
   over a few hundred fuzz seeds. Add a Swift behavioral test in `ZTCoreTests`.

Pure logic with low float risk (focus/app/pomodoro/audio/etc.) can be TDD'd with Swift unit
tests mirroring the Lua instead of a full oracle.

**The Lua/Hammerspoon version is ground truth — always.** This includes orchestration /
coordinator *decisions*, not just leaf algorithms: e.g. the live move-to-zone decision is
diffed against the real `zone_calculator` + `placement_strategy` (`diff_movezone.sh`), not
only fake-unit-tested. When you build a new decision path, add a differential oracle that
runs the equivalent Lua and compares — fakes verify wiring, the diff verifies behavior.

## Conventions / gotchas

- **Layering:** `ZTCore` = pure logic, must NOT import AppKit/ApplicationServices; operates
  on value snapshots. `ZTSystem` = adapters (AX, NSScreen, CoreAudio, JSON, TOMLKit). `ZTUI`
  = SwiftUI settings (later).
- **Coordinates:** top-left CG space everywhere (`ZTRect`), matching AX/CGWindowList. Convert
  only inside `NSScreenProvider` if reading `NSScreen.frame`.
- **Two window value types (don't merge):** `WindowSnapshot` (solver input, opaque String
  label id) vs `AutoTiler.Window` / live enumeration (Int CGWindowID). See Models.swift.
- **Config:** read the existing `config.toml` (TOMLKit); edits via `TOMLEditor` (surgical,
  comment-preserving — toml++ can't round-trip comments). Existing
  `~/.config/ZoneTilerWM/*.json` must stay loadable (legacy numeric monitor_id, etc.).
- **Lua headless logging goes to stderr** (logger + config banner), so oracle stdout stays
  clean JSON. Keep it that way.
- **Native window moves** must replicate the Hammerspoon AX quirks: `AXEnhancedUserInterface`
  toggle for Firefox/Zen-class apps, position-then-size, AppleScript fallback (see
  `AXWindowSystem` + `native/ARCHITECTURE.md`).
- **Visual features** get user-POV validation (run the app, screenshot/video, then a
  deterministic test) before "done" — use the `user-pov-debug` skill. For window moves the
  deterministic assertion is the post-move AX frame readback.
- **Tooling:** prefer the Read/Grep tools over `sed`/`awk`/`head` (a shell-rewrite hook can
  mangle them). Don't `git push`.
- **Build gotcha:** changing a public `ZTCore` initializer/signature can leave the
  executables linking the old symbol ("Undefined symbols … TilerCoordinator.__allocating_init").
  SwiftPM incremental misses it — `rm -rf native/.build && swift build` to recover.

## Dev: accessibility (UI phase)

Moving other apps' windows needs Accessibility (TCC) permission for the running process;
it's granted on this machine. Re-signing/rebuilding can reset the grant — re-add the binary
in System Settings → Privacy & Security → Accessibility. Use a stable signing identity to
minimize churn.
