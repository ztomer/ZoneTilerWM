// SyncPlanTests — pure file-list/path logic for settings sync.

import XCTest
@testable import ZTCore

final class SyncPlanTests: XCTestCase {

    func testExportMapsConfigAndStateDirsToSyncSubfolder() {
        let plan = SyncPlan.plan(direction: .export, configDir: "/cfg", stateDir: "/state", syncDir: "/sync") { _ in true }
        XCTAssertEqual(Set(plan.map { $0.name }), Set(SyncPlan.syncedFiles))
        let configToml = plan.first { $0.name == "config.toml" }!
        XCTAssertEqual(configToml.from, "/cfg/config.toml")            // config.toml from the config dir
        XCTAssertEqual(configToml.to, "/sync/ZoneTilerWM/config.toml")
        let layouts = plan.first { $0.name == "layouts.json" }!
        XCTAssertEqual(layouts.from, "/state/layouts.json")           // state file from the state dir
        XCTAssertEqual(layouts.to, "/sync/ZoneTilerWM/layouts.json")
    }

    func testImportReversesDirection() {
        let plan = SyncPlan.plan(direction: .import, configDir: "/cfg", stateDir: "/state", syncDir: "/sync") { _ in true }
        let configToml = plan.first { $0.name == "config.toml" }!
        XCTAssertEqual(configToml.from, "/sync/ZoneTilerWM/config.toml")
        XCTAssertEqual(configToml.to, "/cfg/config.toml")
    }

    func testMissingSourceFilesAreSkipped() {
        let plan = SyncPlan.plan(direction: .export, configDir: "/cfg", stateDir: "/state", syncDir: "/sync") {
            $0 == "/cfg/config.toml"   // only config.toml exists
        }
        XCTAssertEqual(plan.map { $0.name }, ["config.toml"])
    }

    func testTrailingSlashesDoNotDoubleUp() {
        let plan = SyncPlan.plan(direction: .export, configDir: "/cfg/", stateDir: "/state/", syncDir: "/sync/") { _ in true }
        let c = plan.first { $0.name == "config.toml" }!
        XCTAssertEqual(c.from, "/cfg/config.toml")
        XCTAssertEqual(c.to, "/sync/ZoneTilerWM/config.toml")
    }

    func testEmptyWhenNothingExists() {
        XCTAssertTrue(SyncPlan.plan(direction: .export, configDir: "/cfg", stateDir: "/state", syncDir: "/sync") { _ in false }.isEmpty)
    }
}
