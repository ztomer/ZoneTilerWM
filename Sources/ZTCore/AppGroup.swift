// AppGroup.swift — a named set of apps summoned/dismissed together by its own hotkey. The
// generalisation of the single [scratchpad] set into multiple [[app_groups]], each with its own
// shortcut (the live review: scratchpad "is actually grouped apps … assign shortcuts for each
// group"). Pure value type; the summon/dismiss decision reuses ZTCore.Scratchpad, the activation
// is NSWorkspace in the agent.

public struct AppGroupProfile: Equatable {
    public let name: String
    public let apps: [String]
    public let hotkey: [String]      // [alias-or-modifier, key]; fewer than 2 elements = no hotkey
    public let autoDismiss: Bool

    public init(name: String, apps: [String], hotkey: [String], autoDismiss: Bool) {
        self.name = name
        self.apps = apps
        self.hotkey = hotkey
        self.autoDismiss = autoDismiss
    }
}
