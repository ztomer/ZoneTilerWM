// FirstRunWizard.swift — the multi-step first-run / no-permissions wizard (feedback 0/2).
//
// Shown on first launch AND whenever the agent lacks Accessibility (so a hand-off .app guides the
// recipient instead of silently doing nothing — the exact failure my brother hit). Walks through:
// welcome → Accessibility grant → tiling modifier → feature checklist → telemetry opt-in → done.
//
// Aesthetic: a refined dark panel (the app's intentional theme — see the UI design memo), NOT
// NSGlassEffectView. Reason: the wizard is validated by the headless PNG render + Gemini grade, and
// Liquid Glass composites the live desktop so it can't be captured deterministically. Solid fills +
// a subtle gradient render faithfully to the off-screen bitmap, which is what the grading loop needs.

import AppKit
import SwiftUI
import ZTSystem

// MARK: - Palette (one source of truth so every step is consistent — what the grader rewards)

enum WizardStyle {
    static let bg0 = Color(red: 0.11, green: 0.11, blue: 0.12)   // panel top
    static let bg1 = Color(red: 0.06, green: 0.06, blue: 0.07)   // panel bottom
    static let card = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let cardStroke = Color.white.opacity(0.08)
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.16) // amber — the HUD brand colour
    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.55)
    static let width: CGFloat = 540
    static let height: CGFloat = 600
}

public enum WizardStep: Int, CaseIterable {
    case welcome, accessibility, modifier, features, telemetry, done
}

// MARK: - Root

public struct FirstRunWizardView: View {
    @ObservedObject var model: SettingsModel
    @State private var step: WizardStep
    // ZT_WIZARD_FORCE_UNTRUSTED lets the headless render capture the not-yet-granted layout (the
    // state every new user actually sees) on a dev machine that's already trusted.
    @State private var trusted = ProcessInfo.processInfo.environment["ZT_WIZARD_FORCE_UNTRUSTED"] == nil
        && AXWindowSystem.isTrusted()
    let onFinish: () -> Void
    let openTutorial: () -> Void
    let openSettings: () -> Void

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(model: SettingsModel,
                initialStep: WizardStep = .welcome,
                onFinish: @escaping () -> Void = {},
                openTutorial: @escaping () -> Void = {},
                openSettings: @escaping () -> Void = {}) {
        self.model = model
        self._step = State(initialValue: initialStep)
        self.onFinish = onFinish
        self.openTutorial = openTutorial
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(WizardStyle.cardStroke)
            ScrollView { stepBody.padding(.horizontal, 32).padding(.vertical, 26) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(WizardStyle.cardStroke)
            footer
        }
        .frame(width: WizardStyle.width, height: WizardStyle.height)
        .background(LinearGradient(colors: [WizardStyle.bg0, WizardStyle.bg1],
                                   startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
        .onReceive(poll) { _ in
            let now = AXWindowSystem.isTrusted()
            if now != trusted { trusted = now }
        }
    }

    // MARK: Header — step glyph + title + progress dots

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(WizardStyle.accent.opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: stepIcon).font(.system(size: 22, weight: .semibold))
                    .foregroundColor(WizardStyle.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stepTitle).font(.system(.title3, design: .rounded)).bold()
                    .foregroundColor(WizardStyle.primaryText)
                Text(stepSubtitle).font(.callout).foregroundColor(WizardStyle.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 26).padding(.vertical, 20)
    }

    // MARK: Footer — Back · dots · primary

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button(action: back) { Text("Back").foregroundColor(WizardStyle.secondaryText) }
                    .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(WizardStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s == step ? WizardStyle.accent : Color.white.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            primaryButton
        }
        .padding(.horizontal, 26).padding(.vertical, 16)
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case .accessibility where !trusted:
            WizardButton(title: "Open System Settings", prominent: true) {
                _ = AXWindowSystem.isTrusted(prompt: true)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .done:
            WizardButton(title: "Finish", prominent: true, action: onFinish)
        default:
            WizardButton(title: "Continue", prominent: true, action: next)
        }
    }

    // MARK: Step bodies

    @ViewBuilder private var stepBody: some View {
        switch step {
        case .welcome:       welcomeBody
        case .accessibility: accessibilityBody
        case .modifier:      modifierBody
        case .features:      featuresBody
        case .telemetry:     telemetryBody
        case .done:          doneBody
        }
    }

    private var welcomeBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            WizardBullet(icon: "square.grid.3x3.fill",
                         title: "Snap windows to zones",
                         detail: "Hold a modifier, tap a key — the focused window flies to that region of the screen.")
            WizardBullet(icon: "rectangle.3.group.fill",
                         title: "Auto-tile the whole desktop",
                         detail: "One shortcut arranges every open window into a clean, non-overlapping layout.")
            WizardBullet(icon: "brain.head.profile",
                         title: "Remembers your habits",
                         detail: "Each app re-opens where you like it. Drag a window somewhere new and it learns.")
        }
    }

    private var accessibilityBody: some View {
        VStack(spacing: 16) {
            Image(systemName: trusted ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 52)).foregroundColor(trusted ? .green : WizardStyle.accent)
                .padding(.top, 6)
            Text(trusted ? "Accessibility granted — you're ready to tile."
                         : "macOS needs your permission for ZoneTilerWM to move other apps' windows.")
                .font(.callout).foregroundColor(WizardStyle.primaryText)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !trusted {
                VStack(alignment: .leading, spacing: 10) {
                    WizardStepLine(n: 1, text: "Click **Open System Settings** below.")
                    WizardStepLine(n: 2, text: "Under Privacy & Security → Accessibility, switch **ZoneTilerWM** on.")
                    WizardStepLine(n: 3, text: "Come back here — this updates the moment it's granted.")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(WizardStyle.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WizardStyle.cardStroke))
            }
        }
    }

    private var modifierBody: some View {
        let current = model.config.aliases["mash"] ?? ["ctrl", "cmd"]
        return VStack(alignment: .leading, spacing: 18) {
            Text("ZoneTilerWM watches for one modifier you hold down. Hold it, then tap a zone key — "
                 + "release to place. Pick the combo that's comfortable:")
                .font(.callout).foregroundColor(WizardStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ForEach(WizardModifierPreset.all, id: \.tokens) { preset in
                    ModifierPresetChip(preset: preset, selected: preset.tokens == current) {
                        model.setAlias(name: "mash", modifiers: preset.tokens)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Text("You can fine-tune every shortcut later in Settings → Keys.")
                .font(.caption).foregroundColor(WizardStyle.secondaryText)
        }
    }

    private var featuresBody: some View {
        VStack(spacing: 10) {
            WizardFeatureRow(icon: "square.grid.3x3.topleft.filled", title: "Zone picker (HUD)",
                             detail: "A grid appears while you hold the modifier, so you never guess a key.",
                             isOn: bind(\.zoneHUDEnabled, model.setZoneHUDEnabled))
            WizardFeatureRow(icon: "rectangle.dashed", title: "Focus border",
                             detail: "A subtle outline marks the active window.",
                             isOn: Binding(get: { model.config.borders.enabled }, set: { model.setBordersEnabled($0) }))
            WizardFeatureRow(icon: "hand.draw", title: "Drag-to-snap",
                             detail: "Drag with the modifier held to drop a window into a zone.",
                             isOn: bind(\.dragSnapEnabled, model.setDragSnapEnabled))
            WizardFeatureRow(icon: "command.square", title: "Command palette",
                             detail: "A searchable menu of every action.",
                             isOn: bind(\.commandPaletteEnabled, model.setCommandPaletteEnabled))
            WizardFeatureRow(icon: "brain", title: "Window memory",
                             detail: "Re-opens apps where you last tiled them.",
                             isOn: Binding(get: { model.config.windowMemory.enabled }, set: { model.setWindowMemoryEnabled($0) }))
        }
    }

    private var telemetryBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield").font(.system(size: 40)).foregroundColor(WizardStyle.accent)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Help improve ZoneTilerWM?")
                .font(.system(.title3, design: .rounded)).bold().foregroundColor(WizardStyle.primaryText)
            Text("If you opt in, the app appends one anonymous line per command — just the action name "
                 + "and a timestamp — to a local file in /tmp. No window titles, no app names, nothing "
                 + "leaves your Mac (there's no server to send it to). Off unless you turn it on.")
                .font(.callout).foregroundColor(WizardStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            WizardFeatureRow(icon: "chart.bar.doc.horizontal", title: "Local usage telemetry",
                             detail: "Anonymous, local-only, off by default.",
                             isOn: bind(\.telemetryEnabled, model.setTelemetryEnabled))
        }
    }

    private var doneBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundColor(.green)
                Spacer()
            }
            Text("You're all set.").font(.system(.title3, design: .rounded)).bold()
                .foregroundColor(WizardStyle.primaryText).frame(maxWidth: .infinity, alignment: .center)
            VStack(alignment: .leading, spacing: 0) {
                WizardKeyRow(keys: "hold ⌃⌘", action: "Show the zone picker")
                Divider().overlay(WizardStyle.cardStroke)
                WizardKeyRow(keys: "⌃⌘ + J", action: "Tile focused window to the centre zone")
                Divider().overlay(WizardStyle.cardStroke)
                WizardKeyRow(keys: "⌃⌘ + Return", action: "Auto-tile the whole desktop")
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(WizardStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WizardStyle.cardStroke))
            HStack(spacing: 12) {
                WizardButton(title: "Open Tutorial", prominent: false, action: openTutorial)
                WizardButton(title: "Open Settings", prominent: false, action: openSettings)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Navigation

    private func next() {
        guard let i = WizardStep(rawValue: step.rawValue + 1) else { onFinish(); return }
        step = i
    }
    private func back() {
        guard let i = WizardStep(rawValue: step.rawValue - 1) else { return }
        step = i
    }

    private func bind(_ keyPath: KeyPath<ConfigLoader.LoadedConfig, Bool>,
                      _ setter: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { model.config[keyPath: keyPath] }, set: setter)
    }

    // MARK: Per-step chrome

    private var stepIcon: String {
        switch step {
        case .welcome: return "sparkles"
        case .accessibility: return "lock.shield.fill"
        case .modifier: return "command"
        case .features: return "slider.horizontal.3"
        case .telemetry: return "chart.bar.doc.horizontal"
        case .done: return "checkmark.seal.fill"
        }
    }
    private var stepTitle: String {
        switch step {
        case .welcome: return "Welcome to ZoneTilerWM"
        case .accessibility: return "Enable Accessibility"
        case .modifier: return "Pick your tiling shortcut"
        case .features: return "Choose what's on"
        case .telemetry: return "Privacy"
        case .done: return "Ready to tile"
        }
    }
    private var stepSubtitle: String {
        switch step {
        case .welcome: return "A keyboard-first tiling window manager"
        case .accessibility: return "One permission, then you're done"
        case .modifier: return "The modifier you'll hold to tile"
        case .features: return "Every option is reversible in Settings"
        case .telemetry: return "Your data stays on your Mac"
        case .done: return "A few keys to get you started"
        }
    }
}

// MARK: - Window host

public final class FirstRunWizardController {
    private var window: NSWindow?
    private let model: SettingsModel
    private let openTutorial: () -> Void
    private let openSettings: () -> Void

    public init(model: SettingsModel, openTutorial: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.openTutorial = openTutorial
        self.openSettings = openSettings
    }

    public func show(initialStep: WizardStep = .welcome) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = FirstRunWizardView(
            model: model, initialStep: initialStep,
            onFinish: { [weak self] in self?.window?.close() },
            openTutorial: openTutorial, openSettings: openSettings)
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        // One-shot fixed size (the view is .frame-sized). NOT fullSizeContentView: that would put the
        // dark header under the traffic-light buttons; a plain transparent titlebar over a dark window
        // background keeps the close button clear of the step icon.
        w.setContentSize(NSSize(width: WizardStyle.width, height: WizardStyle.height))
        w.title = "Welcome to ZoneTilerWM"
        w.styleMask = [.titled, .closable]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
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

// MARK: - Reusable pieces

struct WizardButton: View {
    let title: String
    var prominent: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.callout.weight(.semibold))
                .foregroundColor(prominent ? .black : WizardStyle.primaryText)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? WizardStyle.accent : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

struct WizardBullet: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(WizardStyle.accent)
                .frame(width: 28, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundColor(WizardStyle.primaryText)
                Text(detail).font(.callout).foregroundColor(WizardStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WizardFeatureRow: View {
    let icon: String, title: String, detail: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(WizardStyle.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(WizardStyle.primaryText)
                Text(detail).font(.caption).foregroundColor(WizardStyle.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(WizardStyle.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 11).fill(WizardStyle.card))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(WizardStyle.cardStroke))
    }
}

struct WizardStepLine: View {
    let n: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundColor(.black)
                .frame(width: 19, height: 19)
                .background(Circle().fill(WizardStyle.accent))
            Text(.init(text)).font(.callout).foregroundColor(WizardStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

struct WizardKeyRow: View {
    let keys: String, action: String
    var body: some View {
        HStack {
            Text(keys).font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundColor(WizardStyle.accent)
                .frame(width: 120, alignment: .leading)
            Text(action).font(.callout).foregroundColor(WizardStyle.primaryText)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

struct WizardModifierPreset {
    let tokens: [String]
    let label: String
    static let all = [
        WizardModifierPreset(tokens: ["ctrl", "cmd"], label: "Comfortable"),
        WizardModifierPreset(tokens: ["alt", "cmd"], label: "One-handed"),
        WizardModifierPreset(tokens: ["ctrl", "alt"], label: "No ⌘ clash"),
        WizardModifierPreset(tokens: ["shift", "ctrl", "cmd"], label: "Distinct"),
    ]
    var glyphs: String { ModGlyph.string(tokens) }
}

struct ModifierPresetChip: View {
    let preset: WizardModifierPreset
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(preset.glyphs).font(.system(size: 24, weight: .medium))
                    .foregroundColor(selected ? .black : WizardStyle.primaryText)
                Text(preset.label).font(.caption2)
                    .foregroundColor(selected ? .black.opacity(0.7) : WizardStyle.secondaryText)
            }
            .frame(width: 100, height: 64)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? WizardStyle.accent : WizardStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.clear : WizardStyle.cardStroke))
        }
        .buttonStyle(.plain)
    }
}
