// TilerCoordinatorTests — move-to-zone decision against a fake WindowSystem/ScreenProvider
// (no live AX). The live AX path is exercised by the zt-tile CLI.

import XCTest
@testable import ZTCore

private final class FakeWindowSystem: WindowSystem {
    var focused: LiveWindow?
    var onScreen: [LiveWindow] = []
    var byScreen: [String: [LiveWindow]] = [:]   // per-uuid windows (for multi-monitor tests)
    private(set) var movedTo: ZTRect?
    func focusedWindow() -> LiveWindow? { focused }
    func windows(onScreen uuid: String) -> [LiveWindow] { byScreen[uuid] ?? onScreen }
    private(set) var moved: [(id: Int, rect: ZTRect)] = []
    private(set) var focusedIds: [Int] = []
    @discardableResult func moveFocusedWindow(to rect: ZTRect) -> Bool { movedTo = rect; return true }
    @discardableResult func move(windowId: Int, to rect: ZTRect) -> Bool { moved.append((windowId, rect)); return true }
    @discardableResult func focus(windowId: Int) -> Bool { focusedIds.append(windowId); return true }
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

    // MARK: - moveWindow(id:toZone:) — the rules-engine window-targeted path

    func testMoveWindowByIdTilesSpecificWindow() {
        let ws = FakeWindowSystem()
        let target = LiveWindow(id: 42, appName: "Arc", frame: ZTRect(x: 200, y: 200, w: 300, h: 200), screenUUID: "M1")
        ws.onScreen = [target]
        // Focus is on a different window — moveWindow must not depend on focus.
        ws.focused = LiveWindow(id: 1, appName: "Other", frame: ZTRect(x: 0, y: 0, w: 100, h: 100), screenUUID: "M1")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")

        let outcome = coord.moveWindow(windowId: 42, toZone: "y")   // "y" = a1 = top-left quadrant
        XCTAssertEqual(outcome?.windowId, 42)
        XCTAssertEqual(outcome?.zoneKey, "y")
        XCTAssertEqual(outcome?.target, ZTRect(x: 0, y: 0, w: 500, h: 500))
        XCTAssertEqual(outcome?.applied, true)
        XCTAssertEqual(ws.moved.last?.id, 42)
        XCTAssertEqual(ws.moved.last?.rect, ZTRect(x: 0, y: 0, w: 500, h: 500))
        XCTAssertNil(ws.movedTo)   // did NOT use the focused-window path
    }

    func testMoveWindowUnknownIdReturnsNil() {
        let ws = FakeWindowSystem()
        ws.onScreen = []
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertNil(coord.moveWindow(windowId: 999, toZone: "y"))
    }

    func testMoveWindowUnknownZoneReturnsNil() {
        let ws = FakeWindowSystem()
        ws.onScreen = [LiveWindow(id: 42, appName: "Arc", frame: ZTRect(x: 0, y: 0, w: 100, h: 100), screenUUID: "M1")]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertNil(coord.moveWindow(windowId: 42, toZone: "nope"))
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

    func testAutoTileSkipsFloatedWindow() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 0, y: 0, w: 800, h: 600), screenUUID: "M1")
        ws.onScreen = [ws.focused!,
                       LiveWindow(id: 2, appName: "B", frame: ZTRect(x: 100, y: 100, w: 400, h: 400), screenUUID: "M1")]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate",
                                     isFloated: { $0 == 2 })   // window 2 is floated
        let atConfig = AutoTiler.Config(centerZones: ["j"], workingSetTimeLimit: 1800,
                                        workingSetMaxCapacity: 6, mode: "usage",
                                        weights: CostWeights(), zoneConfig: zoneConfig())
        let moves = coord.autoTileScreen(autoTilerConfig: atConfig, memory: [:], now: 10_000)
        XCTAssertFalse(moves.contains { $0.windowId == 2 }, "floated window must be excluded from the plan")
        XCTAssertFalse(ws.moved.contains { $0.id == 2 }, "floated window must not be moved")
        XCTAssertTrue(moves.contains { $0.windowId == 1 }, "non-floated window still tiled")
    }

    func testAutoTileFeedsRealFocusAgeIntoPlan() {
        // The Lua working-set cull (auto_tiler.lua) routes windows last-focused beyond
        // working_set.time_limit_sec to the limbo-stack pass instead of the solver — they're
        // still moved, but to a different target. The live regression we're fixing was that
        // every window was fed lastFocusedTime=now, so the cull never engaged. Prove the
        // coordinator now feeds true per-window focus age: a stale window yields a DIFFERENT
        // plan than the same windows treated as fresh.
        let w1 = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 0, y: 0, w: 800, h: 600), screenUUID: "M1")
        let w2 = LiveWindow(id: 2, appName: "B", frame: ZTRect(x: 100, y: 100, w: 400, h: 400), screenUUID: "M1")
        let atConfig = AutoTiler.Config(centerZones: ["j"], workingSetTimeLimit: 1800,
                                        workingSetMaxCapacity: 6, mode: "usage",
                                        weights: CostWeights(), zoneConfig: zoneConfig())
        func plan(staleWindow2: Bool) -> [Int: ZTRect] {
            let ws = FakeWindowSystem(); ws.onScreen = [w1, w2]
            let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                         zoneConfig: zoneConfig(), placementStrategy: "rotate")
            if staleWindow2 { ws.focused = w2; coord.noteFocusedWindow(now: 0) }   // last focus far in past
            ws.focused = w1; coord.noteFocusedWindow(now: 10_000)
            let moves = coord.autoTileScreen(autoTilerConfig: atConfig, memory: [:], now: 10_000)
            return Dictionary(uniqueKeysWithValues: moves.map { ($0.windowId, $0.rect) })
        }
        let stale = plan(staleWindow2: true)
        let fresh = plan(staleWindow2: false)
        XCTAssertNotEqual(stale[2], fresh[2],
                          "stale window 2 should be placed differently (limbo) than when fresh — focus age must reach the plan")
        XCTAssertEqual(stale[1], fresh[1], "the current window's placement is unaffected by window 2's age")
    }

    func testResizeOffsetShiftsZoneBoundary() {
        // Resize mode adjusts grid-line offsets; those must flow into placement. A +10% offset
        // on vertical line index 1 widens the top-left "y" zone (a1) from 500 to 600 on a
        // 1000-wide screen. No MonitorManager → offsets are keyed by the screen uuid.
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 100, y: 100, w: 400, h: 300), screenUUID: "M1")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate",
                                     offsetProvider: { _, axis, index in (axis == "x" && index == 1) ? 0.1 : 0 })
        guard case .success(let outcome) = coord.moveFocusedToZone("y") else { return XCTFail("expected success") }
        XCTAssertEqual(outcome.target, ZTRect(x: 0, y: 0, w: 600, h: 500),
                       "the +10% x-offset should widen the top-left zone from 500 to 600")
    }

    // MARK: - Multi-monitor (unit-test only; no live multi-display here)

    private func twoScreens() -> [ScreenSnapshot] {
        [ScreenSnapshot(uuid: "M1", name: "Left", frame: ZTRect(x: 0, y: 0, w: 1000, h: 1000),
                        fullFrame: ZTRect(x: 0, y: 0, w: 1000, h: 1000)),
         ScreenSnapshot(uuid: "M2", name: "Right", frame: ZTRect(x: 1000, y: 0, w: 1000, h: 1000),
                        fullFrame: ZTRect(x: 1000, y: 0, w: 1000, h: 1000))]
    }

    // Regression: logical monitor ids must follow screen-enumeration order, not the order
    // the first window-op happens to touch. The MonitorManager registry is in-memory and
    // re-derived each launch (like Lua's monitor_manager.init), so on-disk monitor_id "1"
    // means the main display. If we tile on the SECONDARY display first and assign lazily,
    // the secondary steals id 1 and reads the main display's learned preferences — i.e. zone
    // memory "doesn't refresh properly" after a (re)connect. Seeding the registry from
    // allScreens() up front fixes it.
    func testLazyRegistrationMiskeysSecondaryMonitor() {
        let ws = FakeWindowSystem()
        // Focused window lives on M2 (the secondary), and we act on it before ever touching M1.
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 1000, y: 0, w: 400, h: 300), screenUUID: "M2")
        let mm = MonitorManager()
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider(twoScreens()),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate",
                                     monitorManager: mm)
        _ = coord.moveFocusedToZone("y")
        // Bug: M2 grabbed logical id 1 (what the on-disk data calls the main display).
        XCTAssertEqual(mm.id(forUUID: "M2"), 1)
        XCTAssertEqual(mm.id(forUUID: "M1"), 2)
    }

    func testSeedingRegistryFromScreenOrderKeysCorrectly() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 1000, y: 0, w: 400, h: 300), screenUUID: "M2")
        let provider = FakeScreenProvider(twoScreens())
        let mm = MonitorManager()
        mm.reregister(uuids: provider.allScreens().map { $0.uuid })   // the startup-seed step
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: provider,
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate",
                                     monitorManager: mm)
        _ = coord.moveFocusedToZone("y")
        // Seeded in enumeration order: main M1 == 1, secondary M2 == 2, regardless of op order.
        XCTAssertEqual(mm.id(forUUID: "M1"), 1)
        XCTAssertEqual(mm.id(forUUID: "M2"), 2)
    }

    func testFocusScreenFocusesSameAppOnTarget() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1")
        ws.byScreen["M2"] = [
            LiveWindow(id: 8, appName: "Mail", frame: ZTRect(x: 1000, y: 0, w: 400, h: 300), screenUUID: "M2"),
            LiveWindow(id: 9, appName: "Zen", frame: ZTRect(x: 1400, y: 0, w: 400, h: 300), screenUUID: "M2"),
        ]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider(twoScreens()),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertEqual(coord.focusScreen(.next), 9, "should focus the same-app window on the next screen")
        XCTAssertEqual(ws.focusedIds, [9])
    }

    func testMoveFocusedToMonitorPlacesAtDefaultZone() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 100, y: 100, w: 400, h: 300), screenUUID: "M1")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider(twoScreens()),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        let outcome = coord.moveFocusedToMonitor(.next)
        // No "0" zone; default falls to "j" (= a1:b2, full screen) tile 1 on M2 (x:1000,w:1000).
        XCTAssertEqual(outcome?.zoneKey, "j")
        XCTAssertEqual(outcome?.target, ZTRect(x: 1000, y: 0, w: 1000, h: 1000))
        XCTAssertEqual(ws.moved.last?.id, 1)
    }

    func testMoveToMonitorNoOpOnSingleScreen() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1")
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertNil(coord.moveFocusedToMonitor(.next))   // only one screen → nothing happens
        XCTAssertNil(coord.focusScreen(.next))
    }

    func testAppZonesDefaultPlacementWhenNoMemory() {
        // No learned memory; an app with a configured default zone (window_memory.app_zones)
        // should auto-tile into that zone. "Zen" -> "k" (= b1:b2 right column in this 2x2).
        let ws = FakeWindowSystem()
        let w = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1")
        ws.focused = w; ws.onScreen = [w]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate",
                                     monitorManager: MonitorManager(), appZones: ["Zen": "k"])
        let atConfig = AutoTiler.Config(centerZones: ["zzz"], workingSetTimeLimit: 1800,
                                        workingSetMaxCapacity: 6, mode: "usage",
                                        weights: CostWeights(), zoneConfig: zoneConfig())
        let moves = coord.autoTileScreen(autoTilerConfig: atConfig, now: 10_000)
        // "k" in the test zoneConfig = ["b1:b2"] → right half (x:500,w:500).
        XCTAssertEqual(moves.first { $0.windowId == 1 }?.zoneKey, "k")
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

    func testCycleFocusMovesToNextWindowInZone() {
        // Two windows both fully inside zone "j" (full screen). Focus starts on 1 → cycle to 2.
        let ws = FakeWindowSystem()
        let w1 = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 10, y: 10, w: 200, h: 200), screenUUID: "M1")
        let w2 = LiveWindow(id: 2, appName: "B", frame: ZTRect(x: 20, y: 20, w: 200, h: 200), screenUUID: "M1")
        ws.focused = w1; ws.onScreen = [w1, w2]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertEqual(coord.cycleFocus("j"), 2)
        XCTAssertEqual(ws.focusedIds, [2])
    }

    func testCycleFocusReturnsNilOnEmptyZone() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 0, y: 0, w: 100, h: 100), screenUUID: "M1")
        ws.onScreen = [ws.focused!]
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen()]),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate")
        XCTAssertNil(coord.cycleFocus("zzz"))   // no such zone
    }

    func testMoveToMonitorUsesRememberedPosition() {
        // A learned preference for "Zen" on the target monitor (logical id 2 = M2) should win
        // over the default-zone fallback, placing the window into the remembered zone "k".
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 100, y: 100, w: 300, h: 300), screenUUID: "M1")
        let mem = WindowMemory()
        let mm = MonitorManager()
        mm.reregister(uuids: ["M1", "M2"])   // M1=1, M2=2
        // Learn a placement for Zen in zone "k" tile 1 on monitor "2".
        mem.positionWindow(windowId: 1, app: "Zen", monitor: "2", zone: "k", tile: .int(1),
                           winW: 500, winH: 1000, screenW: 1000, screenH: 1000)
        mem.flush(windowId: 1)
        let coord = TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider(twoScreens()),
                                     zoneConfig: zoneConfig(), placementStrategy: "rotate",
                                     memory: mem, monitorManager: mm)
        let outcome = coord.moveFocusedToMonitor(.next)
        XCTAssertEqual(outcome?.zoneKey, "k")
        // "k" = b1:b2 (right column) on M2 (x:1000,w:1000) → right half x:1500,w:500.
        XCTAssertEqual(outcome?.target, ZTRect(x: 1500, y: 0, w: 500, h: 1000))
    }

    // MARK: - Directional ops (nudge / throw / swap) against the fake window system

    private func makeCoord(_ ws: FakeWindowSystem, _ screens: [ScreenSnapshot]? = nil) -> TilerCoordinator {
        TilerCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider(screens ?? [screen()]),
                         zoneConfig: zoneConfig(), placementStrategy: "rotate")
    }

    func testNudgeFocusedShiftsAStep() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 100, y: 100, w: 400, h: 300), screenUUID: "M1")
        let outcome = makeCoord(ws).nudgeFocused(.right)   // +5% of 1000 = +50
        XCTAssertEqual(outcome?.target, ZTRect(x: 150, y: 100, w: 400, h: 300))
        XCTAssertTrue(outcome?.applied ?? false)
        XCTAssertEqual(ws.moved.last?.id, 1)
    }

    func testThrowFocusedSnapsToEdge() {
        let ws = FakeWindowSystem()
        ws.focused = LiveWindow(id: 1, appName: "Zen", frame: ZTRect(x: 100, y: 100, w: 400, h: 300), screenUUID: "M1")
        let outcome = makeCoord(ws).throwFocused(.left)    // x → screen left edge (0)
        XCTAssertEqual(outcome?.target, ZTRect(x: 0, y: 100, w: 400, h: 300))
        XCTAssertEqual(ws.moved.last?.rect.x, 0)
    }

    func testNudgeAndThrowReturnNilWithNoFocus() {
        let ws = FakeWindowSystem()   // focused = nil
        XCTAssertNil(makeCoord(ws).nudgeFocused(.up))
        XCTAssertNil(makeCoord(ws).throwFocused(.down))
        XCTAssertNil(makeCoord(ws).swapFocused(.left))
    }

    func testSwapFocusedSwapsFramesWithNeighbour() {
        let ws = FakeWindowSystem()
        let w1 = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 100, y: 100, w: 200, h: 200), screenUUID: "M1")
        let w2 = LiveWindow(id: 2, appName: "B", frame: ZTRect(x: 700, y: 100, w: 200, h: 200), screenUUID: "M1")
        ws.focused = w1; ws.byScreen["M1"] = [w1, w2]
        let result = makeCoord(ws).swapFocused(.right)
        XCTAssertEqual(result?.a, 1); XCTAssertEqual(result?.b, 2)
        XCTAssertTrue(result?.applied ?? false)
        // Each window moved into the other's frame.
        XCTAssertEqual(ws.moved.first { $0.id == 1 }?.rect, w2.frame)
        XCTAssertEqual(ws.moved.first { $0.id == 2 }?.rect, w1.frame)
    }

    func testSwapFocusedNoNeighbourReturnsNil() {
        let ws = FakeWindowSystem()
        let w1 = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 100, y: 100, w: 200, h: 200), screenUUID: "M1")
        ws.focused = w1; ws.byScreen["M1"] = [w1]
        XCTAssertNil(makeCoord(ws).swapFocused(.left))   // alone on screen → no neighbour
    }

    // MARK: - Zone-stack focus cycling + focus-time bookkeeping

    func testCycleZoneStackFocusesNextInZone() {
        let ws = FakeWindowSystem()
        // Two windows stacked in the top-left "y" zone (a1 = 0,0,500,500).
        let w1 = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 0, y: 0, w: 480, h: 480), screenUUID: "M1")
        let w2 = LiveWindow(id: 2, appName: "B", frame: ZTRect(x: 5, y: 5, w: 480, h: 480), screenUUID: "M1")
        ws.focused = w1; ws.byScreen["M1"] = [w1, w2]
        let next = makeCoord(ws).cycleZoneStack(.next)
        XCTAssertEqual(next, 2)
        XCTAssertEqual(ws.focusedIds, [2])
    }

    func testCycleZoneStackReturnsNilWithNoFocus() {
        let ws = FakeWindowSystem()
        XCTAssertNil(makeCoord(ws).cycleZoneStack(.next))
    }

    func testSeedAndPruneFocusTimesAreSafe() {
        let ws = FakeWindowSystem()
        let w = LiveWindow(id: 1, appName: "A", frame: ZTRect(x: 0, y: 0, w: 400, h: 300), screenUUID: "M1")
        ws.focused = w; ws.onScreen = [w]
        let c = makeCoord(ws)
        c.seedFocusTimes(now: 100)        // baseline every visible window
        c.noteFocusedWindow(now: 200)
        c.pruneFocusTimes(liveIds: [1])   // keep live ids only
        XCTAssertNotNil(c.nudgeFocused(.right))   // still operable afterward
    }
}
