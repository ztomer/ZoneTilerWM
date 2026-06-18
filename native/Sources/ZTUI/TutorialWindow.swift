// TutorialWindow.swift — a scrollable getting-started guide opened from the menubar. Renders a
// small markdown subset (headings, bullets, indented code, inline bold/`code`). The single
// source is Sources/ZTUI/Resources/Tutorial.md (a SwiftPM resource, loaded via Bundle.module),
// which doubles as the repo-readable doc. Uses the unified appbar chrome.

import AppKit
import SwiftUI

struct TutorialView: View {
    // Single source: the bundled Tutorial.md (resource of this target → repo doc + in-app text).
    private static let markdown: String = {
        guard let url = Bundle.module.url(forResource: "Tutorial", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "# Tutorial\n\nTutorial content is unavailable in this build."
        }
        return text
    }()

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
