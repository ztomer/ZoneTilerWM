// WindowHintsTests — label assignment for the window-hints overlay.

import XCTest
@testable import ZTCore

final class WindowHintsTests: XCTestCase {

    func testLabelsAreUniqueHomeRowFirst() {
        let l = WindowHints.labels(count: 4)
        XCTAssertEqual(l, ["a", "s", "d", "f"])   // home-row order
        XCTAssertEqual(Set(l).count, l.count)     // unique
    }

    func testEmptyAndCap() {
        XCTAssertEqual(WindowHints.labels(count: 0), [])
        // More windows than the alphabet: labels cap at the alphabet size (rest unlabeled).
        let many = WindowHints.labels(count: 100)
        XCTAssertEqual(many.count, WindowHints.alphabet.count)
        XCTAssertEqual(Set(many).count, many.count)
    }
}
