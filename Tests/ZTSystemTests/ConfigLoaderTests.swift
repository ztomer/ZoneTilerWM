// ConfigLoaderTests — golden test that the real repo config.toml decodes into the expected
// ZTCore models (the plan's config-compatibility check).

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class ConfigLoaderTests: XCTestCase {

    private func repoConfigURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZTSystemTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("config.toml")
    }

    func testLoadsRealConfigToml() throws {
        let text = try String(contentsOf: repoConfigURL(), encoding: .utf8)
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")

        XCTAssertEqual(cfg.version, "1.0.0")

        // Grids + layouts.
        XCTAssertEqual(cfg.zoneConfig.grids["4x3"], GridConfig(cols: 4, rows: 3))
        XCTAssertEqual(cfg.zoneConfig.grids["2x2"], GridConfig(cols: 2, rows: 2))
        XCTAssertEqual(cfg.zoneConfig.layouts["4x3"]?["j"], ["b1:c3", "b1:b3", "b2", "b1:d3"])

        // Screen detection + custom screens decoded (ignoring unmodeled keys like `sizes`/`grid`).
        XCTAssertEqual(cfg.zoneConfig.screen_detection?.patterns?["DELL.*U32"], "4x3")
        XCTAssertEqual(cfg.zoneConfig.custom_screens?["DELL U3223QE"]?.layout, "4x3")
        XCTAssertEqual(cfg.zoneConfig.margins?.size, 5)
        XCTAssertEqual(cfg.zoneConfig.margins?.enabled, true)

        // Solver weights (TOML integers coerced to Double).
        XCTAssertEqual(cfg.solverWeights.memoryExact, -2000)
        XCTAssertEqual(cfg.solverWeights.coverage, -2000)
        XCTAssertEqual(cfg.solverWeights.aspectRatio, 300)
        XCTAssertEqual(cfg.solverWeights.skipWindow, 5000)
        XCTAssertEqual(cfg.solverWeights.movedDist, 1)

        // Auto-tile + working set.
        XCTAssertEqual(cfg.autoTileCenterZones, ["j", "center", "0"])
        XCTAssertEqual(cfg.autoTilingMode, "usage")
        XCTAssertEqual(cfg.workingSetTimeLimit, 1800)
        XCTAssertEqual(cfg.workingSetMaxCapacity, 6)
        XCTAssertEqual(cfg.placementStrategy, "largest_free_space")

        // Window memory + ~ expansion.
        XCTAssertTrue(cfg.windowMemory.enabled)
        XCTAssertEqual(cfg.windowMemory.settleDelaySec, 2.0)
        XCTAssertEqual(cfg.windowMemory.saveIntervalSec, 60)
        XCTAssertEqual(cfg.windowMemory.cacheDir, "/Users/test/.config/ZoneTilerWM")
        XCTAssertTrue(cfg.windowMemory.excludedApps.contains("System Settings"))
        XCTAssertEqual(cfg.windowMemory.defaultZone, "0")
        XCTAssertEqual(cfg.windowMemory.appZones["Firefox"], "k")

        // Aliases (raw; resolution deferred to hotkey work).
        XCTAssertEqual(cfg.aliases["mash"], ["ctrl", "cmd"])
        XCTAssertEqual(cfg.aliases["HYPER"], ["shift", "ctrl", "alt", "cmd"])

        // Pomodoro color-bar indicator (drives the menubar strip geometry/colors).
        XCTAssertTrue(cfg.pomodoroEnableColorBar)
        XCTAssertEqual(cfg.pomodoroIndicatorHeight, 0.2, accuracy: 0.0001)
        XCTAssertEqual(cfg.pomodoroIndicatorAlpha, 0.3, accuracy: 0.0001)
        XCTAssertEqual(cfg.pomodoroColorRemaining, "green")
        XCTAssertEqual(cfg.pomodoroColorUsed, "red")
    }

    func testAppSwitcherAndAppCutsDecode() throws {
        let cfg = try ConfigLoader.load(tomlString: String(contentsOf: repoConfigURL(), encoding: .utf8),
                                        homeDirectory: "/Users/test")
        // app_switcher
        XCTAssertTrue(cfg.appSwitcher.hideWorkaroundApps.contains("Firefox"))
        XCTAssertTrue(cfg.appSwitcher.ambiguousApps.contains { $0 == ["zen", "zen browser"] })
        // appCuts: modifier alias mash_app -> [shift, ctrl]; e -> Finder.
        XCTAssertEqual(cfg.appCuts.modifier, ["shift", "ctrl"])
        XCTAssertEqual(cfg.appCuts.apps["e"], "Finder")
        // hyperAppCuts: HYPER modifier; has entries.
        XCTAssertEqual(cfg.hyperAppCuts.modifier, ["shift", "ctrl", "alt", "cmd"])
        XCTAssertFalse(cfg.hyperAppCuts.apps.isEmpty)
        // tiler/focus modifiers resolved.
        XCTAssertEqual(cfg.tilerModifier, ["ctrl", "cmd"])
    }

    func testLoadedConfigBuildsAutoTilerConfig() throws {
        let text = try String(contentsOf: repoConfigURL(), encoding: .utf8)
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")
        let at = cfg.autoTilerConfig()
        XCTAssertEqual(at.centerZones, ["j", "center", "0"])
        XCTAssertEqual(at.workingSetMaxCapacity, 6)
        XCTAssertEqual(at.weights.memoryExact, -2000)
    }

    func testAppGroupsDecodeFromSubtables() throws {
        // Append app-group subtables to the valid repo template (mash alias exists there).
        let toml = try String(contentsOf: repoConfigURL(), encoding: .utf8) + """

        [app_groups.work]
        apps = ["Slack", "Mail"]
        hotkey = ["mash", "1"]
        auto_dismiss = false

        [app_groups.media]
        apps = ["Music"]
        """
        let cfg = try ConfigLoader.load(tomlString: toml, homeDirectory: "/Users/test")
        XCTAssertEqual(cfg.appGroups.count, 2)
        // sorted by name: media, work
        XCTAssertEqual(cfg.appGroups.map { $0.name }, ["media", "work"])
        let work = cfg.appGroups.first { $0.name == "work" }
        XCTAssertEqual(work?.apps, ["Slack", "Mail"])
        XCTAssertEqual(work?.hotkey, ["mash", "1"])
        XCTAssertEqual(work?.autoDismiss, false)
        let media = cfg.appGroups.first { $0.name == "media" }
        XCTAssertEqual(media?.hotkey, [])          // no hotkey → empty
        XCTAssertEqual(media?.autoDismiss, true)   // default
    }

    func testNoAppGroupsByDefault() throws {
        let cfg = try ConfigLoader.load(tomlString: String(contentsOf: repoConfigURL(), encoding: .utf8),
                                        homeDirectory: "/Users/test")
        XCTAssertTrue(cfg.appGroups.isEmpty)   // repo template ships none
    }

    func testAppLayersDecodeFromSubtables() throws {
        // N1: extra [app_layers.<name>] launch layers decode like app groups — modifier resolved via
        // the aliases, sorted by name, empty when absent.
        let base = try String(contentsOf: repoConfigURL(), encoding: .utf8)
        XCTAssertTrue(try ConfigLoader.load(tomlString: base, homeDirectory: "/Users/test").appLayers.isEmpty)
        let toml = base + """

        [app_layers.Dev]
        modifier = ["mash_shift"]
        g = "Ghostty"
        s = "Slack"

        [app_layers.Comms]
        modifier = ["HYPER"]
        m = "Mail"
        """
        let cfg = try ConfigLoader.load(tomlString: toml, homeDirectory: "/Users/test")
        XCTAssertEqual(cfg.appLayers.map { $0.name }, ["Comms", "Dev"])   // sorted by name
        let dev = cfg.appLayers.first { $0.name == "Dev" }
        XCTAssertEqual(dev?.group.modifier, ["shift", "ctrl", "cmd"])     // mash_shift resolved
        XCTAssertEqual(dev?.group.apps, ["g": "Ghostty", "s": "Slack"])
        XCTAssertEqual(cfg.appLayers.first { $0.name == "Comms" }?.group.apps, ["m": "Mail"])
    }

    func testHotkeyResolversAndDerivedAccessors() throws {
        let cfg = try ConfigLoader.load(tomlString: String(contentsOf: repoConfigURL(), encoding: .utf8),
                                        homeDirectory: "/Users/test")

        // resolvedHotkey: a real action resolves to (resolved modifier tokens, key); unknown → nil.
        if let resize = cfg.resolvedHotkey("resize_mode", in: cfg.tilerHotkeys) {
            XCTAssertFalse(resize.modifier.isEmpty)
            XCTAssertFalse(resize.key.isEmpty)
        } else {
            XCTFail("resize_mode should resolve")
        }
        XCTAssertNil(cfg.resolvedHotkey("does_not_exist", in: cfg.tilerHotkeys))

        // Pomodoro / system hotkey groups are populated.
        XCTAssertFalse(cfg.pomodoroHotkeys.isEmpty)
        XCTAssertNotNil(cfg.resolvedHotkey("reset", in: cfg.pomodoroHotkeys))

        // zoneKeys: union of layout keys minus the "default" marker, sorted & unique.
        let zk = cfg.zoneKeys
        XCTAssertFalse(zk.isEmpty)
        XCTAssertFalse(zk.contains("default"))
        XCTAssertEqual(zk, zk.sorted())
        XCTAssertEqual(Set(zk).count, zk.count)

        // allBindings spans zone tile + focus + launchers + actions; every binding has a label.
        let binds = cfg.allBindings()
        XCTAssertGreaterThan(binds.count, zk.count)   // at least tile+focus per zone key
        XCTAssertTrue(binds.allSatisfy { !$0.label.isEmpty })
        XCTAssertTrue(binds.contains { $0.label.hasPrefix("Tile zone ") })
        XCTAssertTrue(binds.contains { $0.label.hasPrefix("Focus zone ") })

        // Audio + keyboard-layout accessors.
        XCTAssertFalse(cfg.audioHotkeyModifier.isEmpty)
        XCTAssertEqual(cfg.keyboardLayout, "auto")   // default when [ui] keyboard_layout unset
    }
}
