// TilerCoordinatorTests — move-to-zone decision against a fake WindowSystem/ScreenProvider
// (no live AX). The live AX path is exercised by the zt-tile CLI.

import XCTest
@testable import ZTCore

private final class FakeWindowSystem: WindowSystem {
    var focused: LiveWindow?
    var onScreen: [LiveWindow] = []
    private(set) var movedTo: ZTRect?
    func focusedWindow() -> LiveWindow? { focused }
    func windows(onScreen uuid: String) -> [LiveWindow] { onScreen }
    @discardableResult func moveFocusedWindow(to rect: ZTRect) -> Bool { movedTo = rect; return true }
}

private final class FakeScreenProvider: ScreenProvider {
    let screens: [ScreenSnapshot]
    init(_ screens: [ScreenSnapshot]) { self.screens = screens }
    func allScreens() -> [ScreenSnapshot] { screens }
    func mainScreen() -> ScreenSnapshot? { screens.first }
    func screen(uuid: String) -> ScreenSnapshot? { screens.first { $0.uuid == uuid } }
}

final class TilerCoordinatorTests: XCTestCase {

    private func zoneConfig() -> ZoneConfig {
        ZoneConfig(
            grids: ["2x2": GridConfig(cols: 2, rows: 2)],
            layouts: ["2x2": ["y": ["a1"], "j": ["a1:b2"], "k": ["b1:b2"]]],
            margins: Margins(enabled: false, size: 0, screen_edge: false))
    }

    private func screen() -> ScreenSnapshot {
        ScreenSnapshot(uuid: "M1", name: "Internal",
                       frame: ZTRect(x: 0, y: 0, w: 1000, h: 1000),
                       fullFrame: ZTRect(x: 0, y: 0, w: 1000, h: 1000))
    }

    func testMovesFocusedWindowToZoneTile() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 100, y: 100, w: 400, h: 300), screenUUID: "M1")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")

        let result = coord.moveFocusedToZone("y")   // "y" = a1 = top-left quadrant
        guard case .success(let outcome) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(outcome.target, ZTRect(x: 0, y: 0, w: 500, h: 500))
        XCTAssertEqual(outcome.zoneKey, "y")
        XCTAssertEqual(outcome.tileIndex, 1)
        XCTAssertTrue(outcome.applied)
        XCTAssertEqual(ws.movedTo, ZTRect(x: 0, y: 0, w: 500, h: 500))
    }

    func testNoFocusedWindow() {
        let ws = FakeWindowSystem()  // focused = nil
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertEqual(coord.moveFocusedToZone("y"), .failure(.noFocusedWindow))
    }

    func testUnknownZone() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertEqual(coord.moveFocusedToZone("zzz"), .failure(.noZone("zzz")))
    }

    func testNoScreenForWindow() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "OTHER")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertEqual(coord.moveFocusedToZone("y"), .failure(.noScreenForWindow))
    }
}
