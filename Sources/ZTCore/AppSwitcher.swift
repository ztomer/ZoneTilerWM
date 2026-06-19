// AppSwitcher.swift — port of the pure app-toggle decision in modules/app_switcher.lua.
// Given the frontmost app and a toggle target, decides whether to hide the front app
// (directly or via its Hide menu item) or launch/focus the target — handling special
// launch-vs-display name mappings and ambiguous app-name pairs (e.g. Notion vs Notion
// Calendar). The actual launch/hide/menu calls are the system boundary.

import Foundation

public enum AppSwitcher {

    public struct Config: Equatable {
        /// launch-name (lowercased) -> display-name (lowercased)
        public let specialMappings: [String: String]
        /// pairs of names that must NOT be treated as substring-matching each other
        public let ambiguousApps: [[String]]
        /// apps that must be hidden via their "Hide <name>" menu item rather than hide()
        public let hideWorkaroundApps: [String]

        public init(specialMappings: [String: String] = [:],
                    ambiguousApps: [[String]] = [],
                    hideWorkaroundApps: [String] = []) {
            // Match the Lua preprocessing: special mappings are compared lowercased.
            var lowered: [String: String] = [:]
            for (k, v) in specialMappings { lowered[k.lowercased()] = v.lowercased() }
            self.specialMappings = lowered
            self.ambiguousApps = ambiguousApps
            self.hideWorkaroundApps = hideWorkaroundApps
        }
    }

    public enum Action: Equatable {
        case hideViaMenu(menuItem: String)   // selectMenuItem("Hide <front>")
        case hide
        case launchOrFocus(app: String)
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    /// Whether front/target are a known ambiguous pair (so a substring match must be ignored).
    static func isAmbiguous(_ frontLower: String, _ targetLower: String, _ pairs: [[String]]) -> Bool {
        let a1 = trim(frontLower), a2 = trim(targetLower)
        for pair in pairs where pair.count >= 2 {
            let p1 = trim(pair[0].lowercased()), p2 = trim(pair[1].lowercased())
            if (a1 == p1 && a2 == p2) || (a1 == p2 && a2 == p1) { return true }
        }
        return false
    }

    public static func decide(frontApp: String, target: String, config: Config) -> Action {
        let frontLower = frontApp.lowercased()
        let targetLower = target.lowercased()

        var switchingToSame = (config.specialMappings[targetLower] == frontLower) || (targetLower == frontLower)

        if !isAmbiguous(frontLower, targetLower, config.ambiguousApps) {
            if frontLower.contains(targetLower) || targetLower.contains(frontLower) {
                switchingToSame = true
            }
        }

        if switchingToSame {
            if config.hideWorkaroundApps.contains(frontApp) {
                return .hideViaMenu(menuItem: "Hide \(frontApp)")
            }
            return .hide
        }
        return .launchOrFocus(app: target)
    }
}
