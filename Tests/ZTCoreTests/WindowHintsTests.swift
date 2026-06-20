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
        // The flat label pool extends past the 26 lowercase keys into digits + uppercase (62 total),
        // so >26 windows stay typed-jumpable; only beyond 62 are windows left unlabeled.
        let many = WindowHints.labels(count: 100)
        XCTAssertEqual(many.count, WindowHints.labelPool.count)   // 62
        XCTAssertEqual(many.count, 62)
        XCTAssertEqual(Set(many).count, many.count, "all labels distinct (case-significant)")
        // First 26 stay the home-row lowercase keys (unchanged for the common case).
        XCTAssertEqual(WindowHints.labels(count: 26), (0..<26).map { String(WindowHints.alphabet[$0]) })
    }

    // MARK: - deoverlap (badge dodging so hints don't hide each other)

    private func anyOverlap(_ rects: [ZTRect], gap: Double = 6) -> Bool {
        for i in rects.indices {
            for j in rects.indices where j > i {
                let a = rects[i], b = rects[j]
                if a.x - gap < b.x + b.w && a.x + a.w + gap > b.x &&
                   a.y - gap < b.y + b.h && a.y + a.h + gap > b.y { return true }
            }
        }
        return false
    }

    func testDeoverlapLeavesNonOverlappingRectsUnchanged() {
        let rects = [ZTRect(x: 0, y: 0, w: 100, h: 40), ZTRect(x: 400, y: 400, w: 100, h: 40)]
        XCTAssertEqual(WindowHints.deoverlap(rects), rects)
    }

    func testDeoverlapDodgesIdenticalAnchors() {
        // Three windows stacked at the same center → three identical badge rects.
        let r = ZTRect(x: 500, y: 500, w: 120, h: 38)
        let out = WindowHints.deoverlap([r, r, r], gap: 6)
        XCTAssertEqual(out[0], r)                       // first keeps its spot
        XCTAssertFalse(anyOverlap(out))                 // none overlap after dodging
        XCTAssertTrue(out[1].y > out[0].y)              // pushed downward
        XCTAssertTrue(out[2].y > out[1].y)
        // x preserved, sizes preserved.
        XCTAssertEqual(out.map { $0.x }, [500, 500, 500])
        XCTAssertEqual(out.map { $0.w }, [120, 120, 120])
    }

    func testDeoverlapResolvesPartialOverlap() {
        let a = ZTRect(x: 0, y: 0, w: 100, h: 40)
        let b = ZTRect(x: 10, y: 10, w: 100, h: 40)   // overlaps a
        let out = WindowHints.deoverlap([a, b])
        XCTAssertEqual(out[0], a)
        XCTAssertFalse(anyOverlap(out))
    }
}
