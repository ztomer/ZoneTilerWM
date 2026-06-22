# ZoneTilerWM — project guide

A macOS tiling window manager: a standalone native Swift menubar agent (a SwiftPM
package at the repo root), no Hammerspoon dependency. It reads the existing `config.toml` and
`~/.config/ZoneTilerWM/*.json`.

> History: this began as a Hammerspoon/Lua config and was ported to Swift against the Lua
> as an executable spec, validated with a Lua↔Swift differential-oracle harness. Once the
> port reached parity, the Lua and the harness were removed (commit "Remove the
> Lua/Hammerspoon implementation"). They remain recoverable in git history and on the
> original `.hammerspoon` `origin` remote. The Swift unit + golden tests are now the spec.

**Read `ARCHITECTURE.md`** for the full design and conventions. This file is the
quick operational guide.

## Hard rules

- **All work stays on the `v2` branch**, published to the dedicated private repo
  `ZoneTilerWMv2` (remote `v2origin`), and **never** to the original `.hammerspoon` `origin`.
  Commit only the files for the change at hand — leave unrelated working-tree changes alone;
  never `git add -A` (it sweeps in the user's `.claude/settings.local.json` etc.).
- **Verify with `make verify`** (= `swift test`) before considering anything done.
- Quality bar: TDD-first; data structures over clever code; dependency-inversion only at
  the OS boundary; AX-call-count-aware in the hot path (see below).
- **Ground rule: no source file over 500 LOC.** Split by concern (cohesive types → own file;
  a god-object class → `Type+Area.swift` extensions, making members internal as needed).

## Verify / test

- `make verify` — the Swift unit + golden tests. One green/red answer.
- `make build` / `make probe` for the rest.
- Current baseline: 352 Swift tests green; ~92% line coverage on the pure-logic `ZTCore`
  layer. The OS adapters / UI are validated by live screenshot QA + the post-move AX frame
  readback rather than unit tests (see `REVIEW.md`).
- The solver/zones Swift tests assert against a frozen golden corpus in
  `Tests/Fixtures/` (originally dumped from the Lua; now a static regression set).

## Conventions / gotchas

- **Layering:** `ZTCore` = pure logic, must NOT import AppKit/ApplicationServices; operates
  on value snapshots. `ZTSystem` = adapters (AX, NSScreen, CoreAudio, JSON, TOMLKit). `ZTUI`
  = SwiftUI settings + analytics.
- **Performance — minimize AX calls (the primary gate).** SentinelOne hooks/logs/analyzes
  every Accessibility call, so cost is AX-round-trip *count*, not CPU. Reads/occupancy/
  z-order go through `CGWindowListCopyWindowInfo` (zero AX); AX is touched only to mutate +
  read the focused element; the EnhancedUI flag is memoized per app. Don't add per-window AX
  reads for enumeration. See `docs/SENTINELONE_INVESTIGATION.md`, `REVIEW.md` §1.
- **Coordinates:** top-left CG space everywhere (`ZTRect`), matching AX/CGWindowList. Convert
  only inside `NSScreenProvider` if reading `NSScreen.frame`.
- **Two window value types (don't merge):** `WindowSnapshot` (solver input, opaque String
  label id) vs `AutoTiler.Window` / live enumeration (Int CGWindowID). See Models.swift.
- **Config location:** the live config is `~/.config/ZoneTilerWM/config.toml` (alongside the
  JSON state); the agent reads/writes only that file. The repo `config.toml` is just the
  default *template* (bundled into the .app) and the one-time migration seed — so editing/
  committing it is fine; it is no longer the user's live config. Read it (TOMLKit); edits via
  `TOMLEditor` (surgical, comment-preserving). Existing `~/.config/ZoneTilerWM/*.json` must
  stay loadable (legacy numeric monitor_id, bare-count prefs, etc.).
- **Native window moves** replicate the AX quirks: the `AXEnhancedUserInterface` toggle for
  Firefox/Zen/Electron-class apps (memoized per app), position-then-size, AppleScript
  fallback (see `AXWindowSystem`).
- **Multi-monitor:** logical monitor ids are seeded from the display arrangement at startup
  and re-registered on `didChangeScreenParametersNotification`, so memory/offsets resolve to
  the right display after a hot-plug.
- **Visual features** get user-POV validation (run the app, screenshot, then a deterministic
  test) before "done" — use the `user-pov-debug` skill. For window moves the deterministic
  assertion is the post-move AX frame readback.
- **Validate over BOTH a light and a dark background** (rule). Overlays/HUDs/glass float over the
  user's wallpaper, so legibility must be checked on a light AND a dark backdrop — a translucent or
  amber-on-glass element that reads fine on a dark desktop can wash out on a white one. Headless:
  `ZT_RENDER_BG=<white|dark>.png`; live glass: capture over both a light and a dark wallpaper.
- **It's fine to quit the running/installed app to validate** (rule, user-authorized). To live-QA a
  build, kill the running ZoneTilerWM instance (`pkill -f ZoneTilerWM`) and run the dev build — don't
  skip live validation just to avoid disrupting a running copy.
- **Tooling:** prefer the Read/Grep tools over `sed`/`awk`/`head` (a shell-rewrite hook can
  mangle them). Push only to the `v2origin` remote (`ZoneTilerWMv2`), never to `origin`.
- **Build gotcha:** changing a public `ZTCore` initializer/signature can leave the
  executables linking the old symbol ("Undefined symbols … TilerCoordinator.__allocating_init").
  SwiftPM incremental misses it — `rm -rf .build && swift build` to recover.

## Dev: accessibility

Moving other apps' windows needs Accessibility (TCC) permission for the running process;
it's granted on this machine. macOS keys the grant to the app's *code signature*, so ad-hoc
signing resets it on every rebuild. The build signs with a stable self-signed `ZoneTilerWM Dev`
identity when present (falls back to ad-hoc), keeping the grant across rebuilds — see
`docs/DEV_SIGNING.md` for the one-time cert setup and the `tccutil reset` recovery step.
