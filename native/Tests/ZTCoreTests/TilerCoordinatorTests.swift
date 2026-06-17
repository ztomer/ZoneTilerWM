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
    private(set) var moved: [(id: Int, rect: ZTRect)] = []
    @discardableResult func moveFocusedWindow(to rect: ZTRect) -> Bool { movedTo = rect; return true }
    @discardableResult func move(windowId: Int, to rect: ZTRect) -> Bool { moved.append((windowId, rect)); return true }
    @discardableResult func focus(windowId: Int) -> Bool { true }
    private(set) var minimized: [Int: Bool] = [:]
    @discardableResult func setMinimized(_ m: Bool, windowId: Int) -> Bool { minimized[windowId] = m; return true }
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

    func testManualMoveLearnsAndPersists() {
        final class MemStore: Storage {
            var blobs: [String: Data] = [:]
            func load<T: Decodable>(_ k: String, as t: T.Type) -> T? { blobs[k].flatMap { try? JSONDecoder().decode(t, from: $0) } }
            @discardableResult func save<T: Encodable>(_ k: String, _ v: T) -> Bool {
                blobs[k] = try? JSONEncoder().encode(v); return blobs[k] != nil
            }
        }
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 7, appName: "Safari", frame: ZTRect(x: 0, y: 0, w: 800, h: 600), screenUUID: "M1")
        let mem = WindowMemory()
        let mm = MonitorManager()
        let store = MemStore()
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate",
                                     memory: mem, monitorManager: mm, storage: store)
        _ = coord.moveFocusedToZone("y")
        let key = String(mm.id(forUUID: "M1"))   // logical id "1"
        let ranked = mem.rankedPreferences(app: "Safari", monitor: key)
        XCTAssertEqual(ranked.first?.zoneKey, "y")
        XCTAssertEqual(ranked.first?.count, 1)
        XCTAssertNotNil(store.blobs["window_positions"], "should persist on learn")
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

    func testAutoTileScreenPlansAndApplies() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 0, y: 0, w: 800, h: 600), screenUUID: "M1")
        ws.onScreen = [
            ws.focused!,
            LiveWindow(id: 2, appName: "B", frame: ZTRect(x: 100, y: 100, w: 400, h: 400), screenUUID: "M1"),
        ]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        let atConfig = AutoTiler.Config(centerZones: ["j"], workingSetTimeLimit: 1800,
                                        workingSetMaxCapacity: 6, mode: "usage",
                                        weights: CostWeights(), zoneConfig: zoneConfig())
        let moves = coord.autoTileScreen(autoTilerConfig: atConfig, memory: [:], now: 10_000)
        XCTAssertFalse(moves.isEmpty)
        // Every planned move was applied via the WindowSystem.
        XCTAssertEqual(Set(moves.map { $0.windowId }), Set(ws.moved.map { $0.id }))
        // The focused window anchors to "j".
        XCTAssertEqual(moves.first { $0.windowId == 1 }?.zoneKey, "j")
    }

    func testZenMinimizesOthersAndRestores() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1")
        ws.onScreen = [
            ws.focused!,
            LiveWindow(id: 2, appName: "B", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1"),
            LiveWindow(id: 3, appName: "C", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1"),
        ]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        coord.toggleZen()
        XCTAssertEqual(ws.minimized[2], true)
        XCTAssertEqual(ws.minimized[3], true)
        XCTAssertNil(ws.minimized[1])     // focused window not minimized
        coord.toggleZen()
        XCTAssertEqual(ws.minimized[2], false)
        XCTAssertEqual(ws.minimized[3], false)
    }

    func testNoScreenForWindow() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "OTHER")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertEqual(coord.moveFocusedToZone("y"), .failure(.noScreenForWindow))
    }
}
