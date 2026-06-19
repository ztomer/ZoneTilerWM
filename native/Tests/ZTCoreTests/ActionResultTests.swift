// ActionResultTests — the outcome type is Codable so a CLI / MCP can report what happened,
// and ActionError mirrors TilerCoordinator.MoveError totally.

import XCTest
@testable import ZTCore

final class ActionResultTests: XCTestCase {

    private static let rect = ZTRect(x: 0, y: 0, w: 100, h: 200)

    static let allCases: [ActionResult] = [
        .tiled(windowId: 7, zone: "h", tileIndex: 1, target: rect, applied: true),
        .autoTiled(moves: [
            TiledMove(windowId: 1, zone: "h", tileIndex: .int(1), rect: rect),
            TiledMove(windowId: 2, zone: "4", tileIndex: .string("4a"), rect: rect),
        ]),
        .focusCycled(focusedWindowId: 9),
        .focusCycled(focusedWindowId: nil),
        .screenFocused(focusedWindowId: 3),
        .monitorMoved(windowId: 5, zone: "k", tileIndex: 2, target: rect, applied: false),
        .zenToggled,
        .windowMoved(windowId: 3, target: rect, applied: true),
        .swapped(windowA: 1, windowB: 2, applied: true),
        .floatToggled(windowId: 7, floating: true),
        .audioSwitched(deviceName: "BlackHole"),
        .audioSwitched(deviceName: nil),
        .appToggled(app: "Finder"),
        .pomodoroUpdated(active: true, phase: "work", timeLeftSec: 1500),
        .modeToggled(mode: .resize),
        .modeToggled(mode: .windowHints),
        .configReloaded(ok: true),
        .layoutSaved(name: "coding", windowCount: 3),
        .layoutApplied(name: "coding", moved: 2),
        .synced(direction: "export", files: ["config.toml", "layouts.json"]),
        .failed(reason: .noFocusedWindow),
        .failed(reason: .noZone("z")),
        .failed(reason: .invalidParameter("zone")),
    ]

    func testCodableRoundTripEveryCase() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for res in Self.allCases {
            let data = try enc.encode(res)
            let back = try dec.decode(ActionResult.self, from: data)
            XCTAssertEqual(res, back, "round-trip mismatch for \(res)")
        }
    }

    func testTiledMoveProjectsFields() {
        let m = TiledMove(windowId: 42, zone: "h", tileIndex: .int(3), rect: Self.rect)
        XCTAssertEqual(m.windowId, 42)
        XCTAssertEqual(m.zone, "h")
        XCTAssertEqual(m.tileIndex, .int(3))
        XCTAssertEqual(m.rect, Self.rect)
    }

    /// Every MoveError must map to a distinct ActionError — the mapping is total.
    func testMoveErrorMappingIsTotal() {
        let cases: [TilerCoordinator.MoveError] = [
            .noFocusedWindow, .noScreenForWindow, .noZone("h"), .noTile,
        ]
        let mapped = cases.map { ActionError($0) }
        XCTAssertEqual(mapped, [
            .noFocusedWindow, .noScreenForWindow, .noZone("h"), .noTile,
        ])
    }
}
