// ZoneStackTests — pure stack-cycling index arithmetic.

import XCTest
@testable import ZTCore

final class ZoneStackTests: XCTestCase {

    func testNextStepsForward() {
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 10, ordered: [10, 20, 30], direction: .next), 20)
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 20, ordered: [10, 20, 30], direction: .next), 30)
    }

    func testNextWrapsAtEnd() {
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 30, ordered: [10, 20, 30], direction: .next), 10)
    }

    func testPreviousStepsBackAndWraps() {
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 20, ordered: [10, 20, 30], direction: .previous), 10)
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 10, ordered: [10, 20, 30], direction: .previous), 30)
    }

    func testTwoWindowStackTogglesBothWays() {
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 1, ordered: [1, 2], direction: .next), 2)
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 2, ordered: [1, 2], direction: .next), 1)
        XCTAssertEqual(ZoneStack.adjacent(focusedId: 1, ordered: [1, 2], direction: .previous), 2)
    }

    func testSingleOrEmptyStackReturnsNil() {
        XCTAssertNil(ZoneStack.adjacent(focusedId: 1, ordered: [1], direction: .next))
        XCTAssertNil(ZoneStack.adjacent(focusedId: 1, ordered: [], direction: .next))
    }

    func testFocusedNotInStackReturnsNil() {
        XCTAssertNil(ZoneStack.adjacent(focusedId: 99, ordered: [1, 2, 3], direction: .next))
    }
}
