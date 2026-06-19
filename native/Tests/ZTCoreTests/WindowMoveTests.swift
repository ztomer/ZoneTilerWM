// WindowMoveTests — pure geometry for nudge / throw / swap.

import XCTest
@testable import ZTCore

final class WindowMoveTests: XCTestCase {

    private let screen = ZTRect(x: 0, y: 0, w: 1000, h: 1000)

    func testNudgeShiftsByFractionAndClamps() {
        let f = ZTRect(x: 500, y: 500, w: 200, h: 200)
        XCTAssertEqual(WindowMove.nudge(f, screen: screen, .right, fraction: 0.05).x, 550)
        XCTAssertEqual(WindowMove.nudge(f, screen: screen, .up, fraction: 0.05).y, 450)
        // Clamp: nudging right from the right edge stops at the screen edge.
        let edge = ZTRect(x: 850, y: 0, w: 200, h: 200)
        XCTAssertEqual(WindowMove.nudge(edge, screen: screen, .right).x, 800)   // 1000 - 200
    }

    func testThrowSnapsToEdges() {
        let f = ZTRect(x: 300, y: 300, w: 200, h: 150)
        XCTAssertEqual(WindowMove.throwTo(f, screen: screen, .left).x, 0)
        XCTAssertEqual(WindowMove.throwTo(f, screen: screen, .right).x, 800)
        XCTAssertEqual(WindowMove.throwTo(f, screen: screen, .up).y, 0)
        XCTAssertEqual(WindowMove.throwTo(f, screen: screen, .down).y, 850)
    }

    func testSwapTargetNearestInDirection() {
        let focused = ZTRect(x: 400, y: 400, w: 100, h: 100)   // center ~450,450
        let others: [(id: Int, frame: ZTRect)] = [
            (1, ZTRect(x: 700, y: 400, w: 100, h: 100)),   // right, near
            (2, ZTRect(x: 900, y: 400, w: 100, h: 100)),   // right, far
            (3, ZTRect(x: 0, y: 400, w: 100, h: 100)),     // left
            (4, ZTRect(x: 400, y: 0, w: 100, h: 100)),     // up
        ]
        XCTAssertEqual(WindowMove.swapTarget(focused: focused, others: others, .right), 1)
        XCTAssertEqual(WindowMove.swapTarget(focused: focused, others: others, .left), 3)
        XCTAssertEqual(WindowMove.swapTarget(focused: focused, others: others, .up), 4)
        XCTAssertNil(WindowMove.swapTarget(focused: focused, others: others, .down))
    }

    func testParseAndCanonicalRoundTrip() {
        XCTAssertEqual(ActionParser.parse(name: "nudge", params: ["direction": "up"]), .success(.nudge(direction: .up)))
        XCTAssertEqual(ActionParser.parse(name: "swap", params: ["direction": "right"]), .success(.swap(direction: .right)))
        XCTAssertEqual(ActionParser.parse(name: "throw", params: [:]), .failure(.invalidParameter("direction")))
        XCTAssertEqual(ActionParser.parse(name: "nudge", params: ["direction": "sideways"]), .failure(.invalidParameter("direction")))
    }
}
