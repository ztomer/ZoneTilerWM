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
            .deletingLastPathComponent()   // native
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
        XCTAssertEqual(cfg.windowMemory.appZones["Arc"], "k")

        // Aliases (raw; resolution deferred to hotkey work).
        XCTAssertEqual(cfg.aliases["mash"], ["ctrl", "cmd"])
        XCTAssertEqual(cfg.aliases["HYPER"], ["shift", "ctrl", "alt", "cmd"])
    }

    func testLoadedConfigBuildsAutoTilerConfig() throws {
        let text = try String(contentsOf: repoConfigURL(), encoding: .utf8)
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")
        let at = cfg.autoTilerConfig()
        XCTAssertEqual(at.centerZones, ["j", "center", "0"])
        XCTAssertEqual(at.workingSetMaxCapacity, 6)
        XCTAssertEqual(at.weights.memoryExact, -2000)
    }
}
