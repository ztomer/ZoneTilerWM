// TutorialWindow.swift — a scrollable getting-started guide opened from the menubar. Renders a
// small markdown subset (headings, bullets, fenced code, inline bold/code) so the text stays
// the single source. Mirrors docs/TUTORIAL.md. Uses the unified appbar chrome.

import AppKit
import SwiftUI

struct TutorialView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(Self.markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                    line(raw)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
        .frame(width: 580, height: 640)
    }

    /// Inline markdown (bold / `code` / links) for a single line.
    private func inline(_ s: Substring) -> AttributedString {
        (try? AttributedString(markdown: String(s),
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(String(s))
    }

    @ViewBuilder private func line(_ raw: String) -> some View {
        if raw.hasPrefix("### ") {
            Text(inline(raw.dropFirst(4))).font(.headline).padding(.top, 4)
        } else if raw.hasPrefix("## ") {
            Text(inline(raw.dropFirst(3))).font(.title3).bold().padding(.top, 10)
        } else if raw.hasPrefix("# ") {
            Text(inline(raw.dropFirst(2))).font(.system(.title, design: .rounded)).bold()
        } else if raw.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundColor(.secondary)
                Text(inline(raw.dropFirst(2)))
            }
        } else if raw.trimmingCharacters(in: .whitespaces).isEmpty {
            Spacer().frame(height: 2)
        } else if raw.hasPrefix("    ") || raw.hasPrefix("\t") {
            Text(raw.trimmingCharacters(in: .whitespaces))
                .font(.system(.callout, design: .monospaced)).foregroundColor(.secondary)
        } else {
            Text(inline(Substring(raw)))
        }
    }

    // The guide text (kept in sync with docs/TUTORIAL.md). Code fences (```) are skipped by the
    // renderer; the diagram below uses 4-space-indented monospace lines instead.
    static let markdown = """
# Welcome to ZoneTilerWM

ZoneTilerWM tiles your windows into **zones mapped to your keyboard**, so window management becomes muscle memory. Each zone lives on a key roughly where it sits on screen.

## First run

Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility) — macOS needs it to move other apps' windows. The agent lives in the menubar; there's no Dock icon.

## The zone keyboard

Zones map to three letter rows plus `0`:

    y  u  i  o      top row
    h  j  k  l      home row
    n  m  ,  .      bottom row
          0         center / full screen

`j` is center, `h` left, `k` right, and `y` `o` `n` `.` the corners.

## Tiling and focus

- **Tile the focused window:** hold `⌃⌘` (mash) and press a zone key. Press the same key again to cycle that zone's tile variations.
- **Focus windows in a zone:** `⇧⌃⌘` + zone key cycles focus through the windows in that zone.
- **Auto-tile the screen:** `HYPER+Return` (HYPER = `⇧⌃⌥⌘`) arranges every window at once, using your learned habits.

## Launching apps

- `⇧⌃` + key launches your everyday apps; `HYPER` + key a second set.
- Edit both maps visually in Settings → **Apps**.

## More features

- **Resize mode — `mash+r`:** arrows nudge the zone grid lines; `Esc` saves.
- **Window hints — `HYPER+-`:** labels every window; type a label to focus it.
- **Zen mode — `HYPER+\\`:** hides every window except the focused one.
- **Pomodoro — `mash+8` start, `mash+9` pause, `⇧⌃⌘+8` reset.**
- **Audio switch — `HYPER+'`:** cycles output devices.
- **Multi-monitor:** `mash+p` / `mash+;` move the window across displays; `⇧⌃⌘+p` / `⇧⌃⌘+;` move focus.

## Learning & analytics

ZoneTilerWM learns where you put each app and reuses it. The menubar **Window Analytics** window shows where windows land, per-app footprints, a daily trend, and the learned table.

## Settings & config

- The menubar **Settings…** window edits everything and writes changes live.
- The config file is `~/.config/ZoneTilerWM/config.toml` (hand edits live-reload too). Conflicting shortcuts are flagged on the Keys tab.
- **Launch at login:** Settings → General → Startup.
"""
}

public final class TutorialWindowController {
    private var window: NSWindow?
    public init() {}

    public func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let hosting = NSHostingController(rootView: TutorialView())
        hosting.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hosting)
        w.title = "ZoneTilerWM Tutorial"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
