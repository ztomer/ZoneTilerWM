// CommandPaletteController.swift — the ⌘K-style command palette overlay. A centered, dark,
// key-accepting panel: type a command ("tile h", "save-layout coding", "zen"), see live fuzzy
// matches from the action catalog, ↑/↓ to select, ⏎ to run, ⎋ to dismiss. Pure matching/resolve
// lives in ZTCore.CommandPalette; this is the AppKit shell + key handling. Gated by config
// ([command_palette] enabled, opt-in) — the agent only builds + binds it when enabled.

import AppKit
import ZTCore

/// A borderless panel that can become key (so the search field receives typing).
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Flipped so the results stack lays out top-to-bottom and the scroll view shows the first row.
private final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class CommandPaletteController: NSObject, NSTextFieldDelegate {
    private let perform: (ActionRequest) -> ActionResult
    private var panel: KeyPanel?
    private var field: NSTextField!
    private var listStack: NSStackView!
    private var hintLabel: NSTextField!
    private var results: [ActionSpec] = []
    private var selection = 0

    init(perform: @escaping (ActionRequest) -> ActionResult) {
        self.perform = perform
    }

    func toggle() {
        if let p = panel, p.isVisible { hide() } else { show() }
    }

    // MARK: build + show

    func show() {
        let p = panel ?? build()
        panel = p
        field.stringValue = ""
        refresh("")
        if let scr = NSScreen.main {
            let f = NSRect(x: scr.frame.midX - 290, y: scr.frame.midY - 100, width: 580, height: 420)
            p.setFrame(f, display: true)
        } else {
            p.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        p.makeFirstResponder(field)
        log("zt-agent: palette show — visible=\(p.isVisible) frame=\(p.frame) screen=\(NSScreen.main?.frame ?? .zero)")
    }

    func hide() { panel?.orderOut(nil) }

    private func build() -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false

        field = NSTextField()
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = "Run a command —  tile h · save-layout coding · audio · zen"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay   // float the scroller over rows instead of insetting them
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(listStack)
        scroll.documentView = doc

        hintLabel = NSTextField(labelWithString: "↑↓ select · ⏎ run · ⎋ close")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(field); root.addSubview(divider); root.addSubview(scroll); root.addSubview(hintLabel)
        p.contentView = root

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: p.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: p.contentView!.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: p.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: p.contentView!.trailingAnchor),

            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),

            divider.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -6),

            listStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 2),
            listStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -2),   // drive doc height
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor),

            hintLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            hintLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        return p
    }

    // MARK: results

    private func refresh(_ query: String) {
        results = CommandPalette.match(query)
        selection = 0
        rebuildList()
    }

    private func rebuildList() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, spec) in results.enumerated() {
            let row = rowView(spec, selected: i == selection)
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true   // now share an ancestor
        }
        if results.isEmpty {
            hintLabel.stringValue = "no matching command"
        } else {
            let spec = results[min(selection, results.count - 1)]
            let params = spec.params.map { $0.required ? "<\($0.name)>" : "[\($0.name)]" }.joined(separator: " ")
            hintLabel.stringValue = params.isEmpty ? "⏎ run \(spec.name)" : "\(spec.name)  \(params)   ·   ⏎ run · Tab complete"
        }
    }

    private func rowView(_ spec: ActionSpec, selected: Bool) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 6
        row.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor : NSColor.clear.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: spec.name)
        name.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        name.textColor = .labelColor
        name.translatesAutoresizingMaskIntoConstraints = false
        let desc = NSTextField(labelWithString: spec.description)
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = NSColor.labelColor.withAlphaComponent(0.72)   // brighter than .secondary on the dark material
        desc.lineBreakMode = .byTruncatingTail
        desc.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(name); row.addSubview(desc)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 30),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            name.widthAnchor.constraint(equalToConstant: 130),
            desc.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 10),
            desc.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            desc.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = max(0, min(results.count - 1, selection + delta))
        rebuildList()
    }

    /// Replace the action token with the highlighted result; keep any typed args.
    private func autocomplete() {
        guard !results.isEmpty else { return }
        let spec = results[min(selection, results.count - 1)]
        let rest = field.stringValue.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let args = rest.count > 1 ? " " + rest[1] : (spec.params.isEmpty ? "" : " ")
        field.stringValue = spec.name + args
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
        refresh(field.stringValue)
    }

    private func run() {
        var input = field.stringValue.trimmingCharacters(in: .whitespaces)
        if input.isEmpty { return }
        // Snap the action token to the highlighted result when the user typed a fuzzy prefix.
        if !results.isEmpty {
            let spec = results[min(selection, results.count - 1)]
            let toks = input.split(separator: " ", maxSplits: 1).map(String.init)
            if toks.first?.lowercased() != spec.name {
                input = spec.name + (toks.count > 1 ? " " + toks[1] : "")
            }
        }
        switch CommandPalette.resolve(input) {
        case .success(let request):
            hide()
            _ = perform(request)
        case .failure:
            // Missing a required arg — keep the action in the field with a trailing space + hint.
            if !input.hasSuffix(" ") { input += " " }
            field.stringValue = input
            field.currentEditor()?.selectedRange = NSRange(location: input.count, length: 0)
            refresh(input)
        }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { refresh(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):     run(); return true
        case #selector(NSResponder.cancelOperation(_:)):   hide(); return true
        case #selector(NSResponder.moveUp(_:)):            move(-1); return true
        case #selector(NSResponder.moveDown(_:)):          move(1); return true
        case #selector(NSResponder.insertTab(_:)):         autocomplete(); return true
        default: return false
        }
    }
}
