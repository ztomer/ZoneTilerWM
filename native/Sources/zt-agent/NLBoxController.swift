// NLBoxController.swift — the on-device natural-language layout box. A centered panel with one
// field: type "put terminal left and browser right", press ⏎; the on-device model
// (ZTSystem.NLInterpreter, FoundationModels) turns it into ActionRequests (mapped via the catalog
// prompt — ZTCore.NLCommand) which are dispatched on the main thread. The model call is async + can
// take a few seconds, so the box shows a "thinking…" state and stays up until it returns. Gated
// ([nl] enabled). Needs Apple Intelligence enabled + the model downloaded; if not, the box shows the
// availability reason. The AppKit shell here mirrors the validated command palette.

import AppKit
import ZTCore
import ZTSystem

private final class NLKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class NLBoxController: NSObject, NSTextFieldDelegate {
    private let perform: (ActionRequest) -> ActionResult
    private var panel: NLKeyPanel?
    private var field: NSTextField!
    private var status: NSTextField!
    private var busy = false

    init(perform: @escaping (ActionRequest) -> ActionResult) { self.perform = perform }

    func toggle() { if let p = panel, p.isVisible { hide() } else { show() } }

    func show() {
        let p = panel ?? build()
        panel = p
        field.stringValue = ""
        status.stringValue = statusLine()
        busy = false
        if let scr = NSScreen.main {
            p.setFrame(NSRect(x: scr.frame.midX - 320, y: scr.frame.midY - 60, width: 640, height: 120), display: true)
        } else { p.center() }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        p.makeFirstResponder(field)
    }

    func hide() { panel?.orderOut(nil) }

    private func statusLine() -> String {
        switch NLInterpreter.status {
        case .available: return "⏎ to run · ⎋ to close"
        case .unavailable(let why): return "on-device model unavailable — \(why)"
        }
    }

    private func build() -> NLKeyPanel {
        let p = NLKeyPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 120),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.level = .floating
        p.isFloatingPanel = true; p.hidesOnDeactivate = false; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = NSVisualEffectView()
        root.material = .hudWindow; root.blendingMode = .behindWindow; root.state = .active
        root.wantsLayer = true; root.layer?.cornerRadius = 12; root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1; root.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false

        field = NSTextField()
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = "Describe a layout —  e.g. tile this left, focus the next screen"
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.textColor = .labelColor; field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(field); root.addSubview(divider); root.addSubview(status)
        p.contentView = root
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: p.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: p.contentView!.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: p.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: p.contentView!.trailingAnchor),
            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            divider.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 14),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
        ])
        return p
    }

    private func run() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !busy else { return }
        busy = true
        status.stringValue = "thinking…"
        let prompt = NLCommand.systemPrompt(catalog: ActionParser.catalog)
        Task { [weak self] in
            let outcome = await NLInterpreter.interpret(text, systemPrompt: prompt)
            await MainActor.run { self?.finish(outcome) }
        }
    }

    private func finish(_ outcome: NLInterpreter.Outcome) {
        busy = false
        switch outcome {
        case .requests(let reqs) where !reqs.isEmpty:
            for r in reqs { _ = perform(r) }
            log("zt-agent: nl ran \(reqs.count) action(s)")
            hide()
        case .requests:
            status.stringValue = "no matching actions for that request"
        case .error(let why):
            status.stringValue = why
            log("zt-agent: nl error — \(why)")
        }
    }

    // MARK: NSTextFieldDelegate
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):   run(); return true
        case #selector(NSResponder.cancelOperation(_:)):  hide(); return true
        default: return false
        }
    }
}
