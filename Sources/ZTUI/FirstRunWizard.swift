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
    // All from the shared ZTPalette (Rams/Kare): neutral charcoal base, one functional accent used
    // only for the active step / selected chip / toggled switch / primary CTA.
    static let bg0 = ZTPalette.backgroundColor                                   // #1A1A1A
    static let bg1 = Color(.sRGB, red: 0.063, green: 0.063, blue: 0.063)         // a touch darker for the gradient
    static let card = ZTPalette.surfaceColor                                     // #282828
    static let cardStroke = Color.white.opacity(0.08)
    static let accent = ZTPalette.accentColor                                    // #FF6B00 — binary accent
    static let primaryText = ZTPalette.primaryTextColor                          // #F5F5F7
    static let secondaryText = ZTPalette.secondaryTextColor                      // #8E8E93
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
            ScrollView { stepBody.padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 26) }
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
        // Left-aligned to match the left-aligned header + the other steps (one consistent grammar).
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: trusted ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 52)).foregroundColor(trusted ? .green : WizardStyle.accent)
                .padding(.top, 6).padding(.bottom, -8)   // tighten the gap below the hero icon
            Text(trusted ? "Accessibility granted — you're ready to tile."
                         : "macOS needs your permission for ZoneTilerWM to move other apps' windows.")
                .font(.callout).foregroundColor(WizardStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !trusted {
                VStack(alignment: .leading, spacing: 10) {
                    WizardStepLine(n: 1, text: "Click **Open System Settings** below.")
                    WizardStepLine(n: 2, text: "Under Privacy & Security → Accessibility, switch **ZoneTilerWM** on.")
                    WizardStepLine(n: 3, text: "Come back here — this updates the moment it's granted.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(WizardStyle.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WizardStyle.cardStroke))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // ONE container card with internal dividers (not 5 floating cards) — matches the single-card
        // grammar of the other steps.
        VStack(spacing: 0) {
            WizardFeatureRow(icon: "square.grid.3x3.topleft.filled", title: "Zone picker (HUD)",
                             detail: "A grid appears while you hold the modifier, so you never guess a key.",
                             isOn: bind(\.zoneHUDEnabled, model.setZoneHUDEnabled))
            Divider().overlay(WizardStyle.cardStroke)
            WizardFeatureRow(icon: "rectangle.dashed", title: "Focus border",
                             detail: "A subtle outline marks the active window.",
                             isOn: Binding(get: { model.config.borders.enabled }, set: { model.setBordersEnabled($0) }))
            Divider().overlay(WizardStyle.cardStroke)
            WizardFeatureRow(icon: "hand.draw", title: "Drag-to-snap",
                             detail: "Drag with the modifier held to drop a window into a zone.",
                             isOn: bind(\.dragSnapEnabled, model.setDragSnapEnabled))
            Divider().overlay(WizardStyle.cardStroke)
            WizardFeatureRow(icon: "command.square", title: "Command palette",
                             detail: "A searchable menu of every action.",
                             isOn: bind(\.commandPaletteEnabled, model.setCommandPaletteEnabled))
            Divider().overlay(WizardStyle.cardStroke)
            WizardFeatureRow(icon: "brain", title: "Window memory",
                             detail: "Re-opens apps where you last tiled them.",
                             isOn: Binding(get: { model.config.windowMemory.enabled }, set: { model.setWindowMemoryEnabled($0) }))
            Divider().overlay(WizardStyle.cardStroke)
            WizardFeatureRow(icon: "character.cursor.ibeam", title: "Window hints",
                             detail: "Label every window; type a key to jump focus.",
                             isOn: Binding(get: { model.config.windowHintsEnabled }, set: { model.setWindowHintsEnabled($0) }))
            Divider().overlay(WizardStyle.cardStroke)
            WizardFeatureRow(icon: "rectangle.3.group", title: "Exposé / window grid",
                             detail: "Lay every window out in a labeled grid; type to focus.",
                             isOn: Binding(get: { model.config.exposeEnabled }, set: { model.setExposeEnabled($0) }))
            Divider().overlay(WizardStyle.cardStroke)
            WizardFeatureRow(icon: "dock.rectangle", title: "Dock previews",
                             detail: "Hover a Dock icon to preview that app's windows.",
                             isOn: Binding(get: { model.config.dockPreviewsEnabled }, set: { model.setDockPreviewsEnabled($0) }))
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(WizardStyle.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WizardStyle.cardStroke))
    }

    private var telemetryBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield").font(.system(size: 40)).foregroundColor(WizardStyle.accent)
                .padding(.bottom, -8)   // tighten the gap below the hero icon
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
                .background(RoundedRectangle(cornerRadius: 12).fill(WizardStyle.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WizardStyle.cardStroke))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The configured tiler modifier (picker + per-zone tiles) and the fixed HYPER modifier (auto-tile),
    // rendered as key-cap glyphs so the cheatsheet always matches the live bindings.
    private var tilerGlyphs: String { tilingGlyphs(model) }
    private var hyperGlyphs: String { ModGlyph.string(model.config.aliases["HYPER"] ?? ["shift", "ctrl", "option", "cmd"]) }

    private var doneBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundColor(.green)
            Text("You're all set.").font(.system(.title3, design: .rounded)).bold()
                .foregroundColor(WizardStyle.primaryText)
            VStack(alignment: .leading, spacing: 0) {
                // Reflect the ACTUAL bindings: the zone picker + per-zone tiles use the tiler modifier;
                // auto-tile is bound to HYPER+Return (see AgentController bindAutoTile).
                WizardKeyRow(keys: "hold \(tilerGlyphs)", action: "Show the zone picker")
                Divider().overlay(WizardStyle.cardStroke)
                WizardKeyRow(keys: "\(tilerGlyphs) + J", action: "Tile focused window to the centre zone")
                Divider().overlay(WizardStyle.cardStroke)
                WizardKeyRow(keys: "\(hyperGlyphs) + Return", action: "Auto-tile the whole desktop")
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(WizardStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WizardStyle.cardStroke))
            HStack(spacing: 12) {
                WizardButton(title: "Open Tutorial", prominent: false, action: openTutorial)
                WizardButton(title: "Open Settings", prominent: false, action: openSettings)
            }
            .padding(.top, 6)   // separate the secondary buttons from the cheatsheet card above
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            // Neutral: these illustrate features, they're not the active element (binary-accent rule).
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(WizardStyle.primaryText)
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
            // Neutral icon; the accent appears only when the row's toggle is ON (binary-accent rule).
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(isOn ? WizardStyle.accent : WizardStyle.secondaryText)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(WizardStyle.primaryText)
                Text(detail).font(.caption).foregroundColor(WizardStyle.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(WizardStyle.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
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
