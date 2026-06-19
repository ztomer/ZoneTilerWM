// Intents.swift — App Intents front-end (Shortcuts / Spotlight / Siri / Raycast / Stream Deck).
//
// Like every other front-end, an intent just builds an ActionRequest and sends it to the running
// agent over the shared Unix-domain socket (AgentSocketClient). Forwarding over the socket — not
// calling the dispatcher directly — means the intents behave the same no matter which process the
// system runs them in, as long as zt-agent is running (it holds the AX grant + live state).
//
// These types are compiled into the .app by xcodegen; the App Intents metadata extraction (which
// makes them discoverable in Shortcuts) runs in the Xcode build. They also compile under plain
// `swift build` (the package targets macOS 13+), so the dev build stays green.

import AppIntents
import Foundation
import ZTCore
import ZTSystem

/// Forward an action to the running agent and return a human-readable summary for Shortcuts.
@available(macOS 13.0, *)
private func runAction(_ request: ActionRequest) -> String {
    switch AgentSocketClient(path: AgentSocket.defaultPath()).send(.action(request)) {
    case .action(let result): return CLIFormat.summary(result)
    case .error(let message): return "ZoneTilerWM unreachable: \(message)"
    case .query:              return "unexpected response"
    }
}

@available(macOS 13.0, *)
struct TileWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "Tile Focused Window"
    static var description = IntentDescription("Tile the focused window into a zone.")
    @Parameter(title: "Zone", description: "Zone key, e.g. h, j, k, l.") var zone: String
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: runAction(.tileFocusedToZone(zone: zone)))
    }
}

@available(macOS 13.0, *)
struct AutoTileScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Auto-Tile Screen"
    static var description = IntentDescription("Auto-tile every window on the focused screen.")
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: runAction(.autoTileScreen))
    }
}

@available(macOS 13.0, *)
struct SwitchAudioIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Audio Output"
    static var description = IntentDescription("Switch the system audio output device.")
    @Parameter(title: "Device", description: "Device name. Leave blank to cycle to the next one.")
    var device: String?
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let target: AudioTarget = (device?.isEmpty == false) ? .named(device!) : .next
        return .result(value: runAction(.switchAudio(device: target)))
    }
}

@available(macOS 13.0, *)
struct ToggleAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Application"
    static var description = IntentDescription("Launch, focus, or hide an application.")
    @Parameter(title: "App Name", description: "e.g. Finder, Arc.") var app: String
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: runAction(.appToggle(app: app)))
    }
}

@available(macOS 13.0, *)
struct ZenModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Zen Mode"
    static var description = IntentDescription("Minimize every other window on the focused screen.")
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: runAction(.toggleZen))
    }
}

/// Direction choices for the navigation intents, surfaced as a Shortcuts picker.
@available(macOS 13.0, *)
enum IntentDirection: String, AppEnum {
    case next, previous
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static var caseDisplayRepresentations: [IntentDirection: DisplayRepresentation] =
        [.next: "Next", .previous: "Previous"]
    var nav: NavDirection { self == .next ? .next : .previous }
}

@available(macOS 13.0, *)
struct FocusScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Focus Screen"
    static var description = IntentDescription("Focus the same app's window on the next/previous screen.")
    @Parameter(title: "Direction") var direction: IntentDirection
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: runAction(.focusScreen(direction: direction.nav)))
    }
}

/// A handful of zero-config phrases for Siri / Spotlight. Parameterized intents (tile, app,
/// audio device) are still fully usable in the Shortcuts editor.
@available(macOS 13.0, *)
struct ZoneTilerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AutoTileScreenIntent(),
                    phrases: ["Auto-tile with \(.applicationName)"],
                    shortTitle: "Auto-Tile", systemImageName: "rectangle.split.3x3")
        AppShortcut(intent: ZenModeIntent(),
                    phrases: ["Toggle zen mode with \(.applicationName)"],
                    shortTitle: "Zen Mode", systemImageName: "moon")
    }
}
