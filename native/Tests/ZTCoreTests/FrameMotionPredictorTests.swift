// FrameMotionPredictorTests — the focus-border motion filter (One Euro). The filter denoises a
// polled, integer-quantized window frame (kills jitter at rest, low lag during motion) with an
// optional small velocity lead. Pure value logic, so behavior is asserted deterministically; the
// final case is the automated form of the offscreen visual-debug finding (no jumps / overshoot).

import XCTest
@testable import ZTCore

final class FrameMotionPredictorTests: XCTestCase {

    private func rect(_ x: Double, _ y: Double = 0, _ w: Double = 100, _ h: Double = 100) -> ZTRect {
        ZTRect(x: x, y: y, w: w, h: h)
    }
    private let dt = 1.0 / 90.0

    func testFirstSampleReturnsItself() {
        var p = FrameMotionPredictor()
        XCTAssertEqual(p.process(rect(10, 20), dt: dt), rect(10, 20))
    }

    func testConstantInputConvergesAndHolds() {
        var p = FrameMotionPredictor()
        var out = rect(0)
        for _ in 0..<30 { out = p.process(rect(400), dt: dt) }
        XCTAssertEqual(out.x, 400, accuracy: 1e-6)   // still window → exact, no drift
    }

    func testRestJitterIsSmoothedAway() {
        // 1px flicker (quantization) while "at rest" must not pass through to the border.
        var p = FrameMotionPredictor()
        var maxDev = 0.0
        for i in 0..<60 {
            let out = p.process(rect(400 + Double(i % 2)), dt: dt)   // 400,401,400,401…
            if i > 10 { maxDev = max(maxDev, abs(out.x - 400.5)) }
        }
        XCTAssertLessThan(maxDev, 1.0)   // output sits ~mid, well under the 1px flicker
    }

    func testTracksConstantVelocityWithBoundedLag() {
        // 5px/tick (450 px/s). After warmup the output should follow closely (small lag/lead).
        var p = FrameMotionPredictor()   // default lead 0.012
        var out = rect(0); var input = 0.0
        for _ in 0..<60 { input += 5; out = p.process(rect(input), dt: dt) }
        XCTAssertEqual(out.x, input, accuracy: 8)        // within a few px of the true position
    }

    func testLeadPushesAheadDuringMotion() {
        // With a lead, the output leads the no-lead output while moving (compensates lag).
        var led = FrameMotionPredictor(lead: 0.02)
        var noLead = FrameMotionPredictor(lead: 0)
        var a = rect(0), b = rect(0); var input = 0.0
        for _ in 0..<40 { input += 5; a = led.process(rect(input), dt: dt); b = noLead.process(rect(input), dt: dt) }
        XCTAssertGreaterThan(a.x, b.x)                   // led output is further along
    }

    func testReset() {
        var p = FrameMotionPredictor()
        var input = 0.0
        for _ in 0..<20 { input += 10; _ = p.process(rect(input), dt: dt) }
        p.reset()
        XCTAssertNil(p.lastFrame)
        XCTAssertEqual(p.process(rect(500), dt: dt), rect(500))   // fresh start, no inherited motion
    }

    func testAllComponentsFiltered() {
        var p = FrameMotionPredictor(lead: 0)
        var out = rect(0)
        for i in 0..<40 { let v = Double(i) * 3; out = p.process(ZTRect(x: v, y: v, w: 100 + v, h: 200 + v), dt: dt) }
        XCTAssertEqual(out.y, out.x, accuracy: 1e-6)      // x and y move identically → filtered identically
        XCTAssertEqual(out.w - 100, out.x, accuracy: 1e-6)
    }

    /// Regression guard for the bug the offscreen debug surfaced: feed a realistic polled +
    /// quantized drag (smoothstep accel → constant → stop) and assert the OUTPUT neither jumps
    /// frame-to-frame nor overshoots the true path (the old extrapolator did both, badly).
    func testSimulatedDragIsSmoothAndBounded() {
        func trueX(_ t: Double) -> Double {
            if t < 0.2 { return 400 }
            if t < 0.9 { let u = (t - 0.2) / 0.7; return 400 + 360 * (u * u * (3 - 2 * u)) }   // 400→760
            return 760
        }
        var p = FrameMotionPredictor()
        var outs: [Double] = [], acts: [Double] = []
        var t = 0.0
        while t < 1.2 {
            let act = trueX(t)
            let sample = (act).rounded()                 // integer-px quantization (CGWindowList)
            outs.append(p.process(rect(sample), dt: dt).x)
            acts.append(act)
            t += dt
        }
        // No jumps: frame-to-frame output change never exceeds the true change by much.
        var maxJump = 0.0
        for i in 1..<outs.count {
            maxJump = max(maxJump, abs((outs[i] - outs[i-1]) - (acts[i] - acts[i-1])))
        }
        XCTAssertLessThan(maxJump, 8.0, "border jumps frame-to-frame (was ~20px with the old extrapolator)")
        // Bounded overshoot: output never runs far past / behind the true path.
        let overshoot = zip(outs, acts).map { $0 - $1 }
        XCTAssertLessThan(overshoot.max()!, 25.0)
        XCTAssertGreaterThan(overshoot.min()!, -25.0)
    }
}
