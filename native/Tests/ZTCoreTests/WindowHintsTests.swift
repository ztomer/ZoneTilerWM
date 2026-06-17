// WindowHintsTests — label assignment for the window-hints overlay.

import XCTest
@testable import ZTCore

final class WindowHintsTests: XCTestCase {

    func testLabelsAreUniqueHomeRowFirst() {
        let l = WindowHints.labels(count: 4)
        XCTAssertEqual(l, ["a", "s", "d", "f"])   // home-row order
        XCTAssertEqual(Set(l).count, l.count)     // unique
    }

    func testSpatialLabelsMatchPositions() {
        // 3x3 key grid; windows at the four corners should get corner keys on the right side.
        let keys = [["q","w","e"], ["a","s","d"], ["z","x","c"]]
        let centers = [(x: 0.0, y: 0.0),   // top-left   → q
                       (x: 1.0, y: 0.0),   // top-right  → e
                       (x: 0.0, y: 1.0),   // bottom-left→ z
                       (x: 1.0, y: 1.0)]   // bottom-right→ c
        let l = WindowHints.spatialLabels(centers: centers, keys: keys)
        XCTAssertEqual(l[0], "q")
        XCTAssertEqual(l[1], "e")
        XCTAssertEqual(l[2], "z")
        XCTAssertEqual(l[3], "c")
        XCTAssertEqual(Set(l).count, 4)   // unique
    }

    func testSpatialLabelsCapAndEmpty() {
        XCTAssertEqual(WindowHints.spatialLabels(centers: [], keys: [["a"]]), [])
        // More windows than keys: extras get "".
        let l = WindowHints.spatialLabels(centers: [(0,0), (1,1), (0.5, 0.5)], keys: [["a", "b"]])
        XCTAssertEqual(l.filter { !$0.isEmpty }.count, 2)
    }

    func testEmptyAndCap() {
        XCTAssertEqual(WindowHints.labels(count: 0), [])
        // More windows than the alphabet: labels cap at the alphabet size (rest unlabeled).
        let many = WindowHints.labels(count: 100)
        XCTAssertEqual(many.count, WindowHints.alphabet.count)
        XCTAssertEqual(Set(many).count, many.count)
    }
}
