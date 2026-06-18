// FrameMotionPredictorTests — the focus-border motion predictor. Pure value logic, so the
// behavior (extrapolate during motion, clamp the horizon, collapse to the exact frame at rest)
// is asserted deterministically with hand-fed timestamped samples.

import XCTest
@testable import ZTCore

final class FrameMotionPredictorTests: XCTestCase {

    private func rect(_ x: Double, _ y: Double, _ w: Double = 100, _ h: Double = 100) -> ZTRect {
        ZTRect(x: x, y: y, w: w, h: h)
    }

    func testNoHistoryReturnsNil() {
        let p = FrameMotionPredictor()
        XCTAssertNil(p.predicted(at: 1.0))
    }

    func testSingleSampleReturnsThatFrame() {
        var p = FrameMotionPredictor()
        p.record(rect(10, 20), at: 0)
        XCTAssertEqual(p.predicted(at: 0.5), rect(10, 20))
    }

    func testConstantVelocityExtrapolatesWithinHorizon() {
        // smoothing 0 → velocity is the exact last-diff. Move 10px in x over 0.1s → 100 px/s.
        var p = FrameMotionPredictor(maxLead: 0.05, smoothing: 0, restEpsilon: 2)
        p.record(rect(0, 0), at: 0.0)
        p.record(rect(10, 0), at: 0.1)
        // Query 0.05s after the last sample (== maxLead): x = 10 + 100*0.05 = 15.
        let out = p.predicted(at: 0.15)
        XCTAssertEqual(out?.x ?? -1, 15, accuracy: 1e-9)
        XCTAssertEqual(out?.y ?? -1, 0, accuracy: 1e-9)
    }

    func testExtrapolationClampedToMaxLead() {
        var p = FrameMotionPredictor(maxLead: 0.05, smoothing: 0, restEpsilon: 2)
        p.record(rect(0, 0), at: 0.0)
        p.record(rect(10, 0), at: 0.1)        // 100 px/s
        // Query far in the future — lead must clamp at 0.05s, so x = 10 + 100*0.05 = 15 (not more).
        let out = p.predicted(at: 5.0)
        XCTAssertEqual(out?.x ?? -1, 15, accuracy: 1e-9)
    }

    func testAtRestReturnsExactFrameNoJitter() {
        var p = FrameMotionPredictor(maxLead: 0.05, smoothing: 0, restEpsilon: 2)
        p.record(rect(40, 40), at: 0.0)
        p.record(rect(40, 40), at: 0.1)       // no movement → velocity 0
        XCTAssertEqual(p.predicted(at: 0.2), rect(40, 40))
    }

    func testSubEpsilonDriftIsTreatedAsRest() {
        // Drift of 0.1px over 0.1s = 1 px/s, below restEpsilon (2) → no extrapolation.
        var p = FrameMotionPredictor(maxLead: 0.05, smoothing: 0, restEpsilon: 2)
        p.record(rect(0, 0), at: 0.0)
        p.record(rect(0.1, 0), at: 0.1)
        XCTAssertEqual(p.predicted(at: 0.2), rect(0.1, 0))
    }

    func testSizeIsExtrapolatedToo() {
        // A tile animation grows the window: w 100→120 over 0.1s = 200 px/s.
        var p = FrameMotionPredictor(maxLead: 0.05, smoothing: 0, restEpsilon: 2)
        p.record(rect(0, 0, 100, 100), at: 0.0)
        p.record(rect(0, 0, 120, 100), at: 0.1)
        let out = p.predicted(at: 0.15)       // lead 0.05 → w = 120 + 200*0.05 = 130
        XCTAssertEqual(out?.w ?? -1, 130, accuracy: 1e-9)
    }

    func testResetClearsVelocity() {
        var p = FrameMotionPredictor(maxLead: 0.05, smoothing: 0, restEpsilon: 2)
        p.record(rect(0, 0), at: 0.0)
        p.record(rect(10, 0), at: 0.1)
        p.reset()
        XCTAssertNil(p.predicted(at: 0.2))    // no history after reset
        p.record(rect(50, 50), at: 0.2)
        XCTAssertEqual(p.predicted(at: 0.3), rect(50, 50))   // fresh start, no inherited velocity
    }

    func testSmoothingDampensVelocity() {
        // With smoothing 0.5 the first motion estimate is halved: vel = 0.5*0 + 0.5*100 = 50.
        var p = FrameMotionPredictor(maxLead: 0.05, smoothing: 0.5, restEpsilon: 2)
        p.record(rect(0, 0), at: 0.0)
        p.record(rect(10, 0), at: 0.1)        // raw 100 px/s, smoothed → 50 px/s
        let out = p.predicted(at: 0.15)       // x = 10 + 50*0.05 = 12.5
        XCTAssertEqual(out?.x ?? -1, 12.5, accuracy: 1e-9)
    }
}
