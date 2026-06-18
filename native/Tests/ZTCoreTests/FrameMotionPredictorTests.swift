// FrameMotionPredictorTests — the focus-border frame mapper. Position passes through raw (1:1,
// no low-pass → no "float"); the One Euro filters supply only a smoothed velocity for the optional
// `lead`. Pure value logic, asserted deterministically. The simulated-drag case is the automated
// form of the offscreen finding: raw tracking is smooth (no jumps) and never overshoots.

import XCTest
@testable import ZTCore

final class FrameMotionPredictorTests: XCTestCase {

    private func rect(_ x: Double, _ y: Double = 0, _ w: Double = 100, _ h: Double = 100) -> ZTRect {
        ZTRect(x: x, y: y, w: w, h: h)
    }
    private let dt = 1.0 / 90.0

    func testDefaultIsExact1to1Mirror() {
        // Default lead 0 → the drawn frame equals the sampled frame exactly (no smoothing, no float).
        var p = FrameMotionPredictor()
        XCTAssertEqual(p.process(rect(10, 20, 300, 200), dt: dt), rect(10, 20, 300, 200))
        XCTAssertEqual(p.process(rect(55, 77, 301, 201), dt: dt), rect(55, 77, 301, 201))
    }

    func testAtRestHoldsExactly() {
        var p = FrameMotionPredictor()
        var out = rect(0)
        for _ in 0..<30 { out = p.process(rect(400), dt: dt) }
        XCTAssertEqual(out.x, 400, accuracy: 1e-9)   // a still window's border never drifts
    }

    func testZeroLeadMirrorsMotionWithNoOvershoot() {
        // Constant velocity, lead 0: output == input every tick (perfect 1:1, no lead/lag added).
        var p = FrameMotionPredictor(lead: 0)
        var input = 0.0, out = rect(0)
        for _ in 0..<60 { input += 5; out = p.process(rect(input), dt: dt) }
        XCTAssertEqual(out.x, input, accuracy: 1e-9)
    }

    func testLeadLeadsDuringSteadyMotion() {
        // With a lead, the output runs ahead of the raw sample (compensates poll lag) while moving.
        var led = FrameMotionPredictor(lead: 0.02)
        var input = 0.0, out = rect(0)
        for _ in 0..<40 { input += 5; out = p_process(&led, input) }
        XCTAssertGreaterThan(out.x, input)             // ahead of the sample
        XCTAssertLessThan(out.x - input, 5 * 0.02 * 90 + 2)   // but bounded (~ velocity*lead)
    }
    private func p_process(_ p: inout FrameMotionPredictor, _ x: Double) -> ZTRect { p.process(rect(x), dt: dt) }

    func testLeadDecaysToRestAfterStop() {
        // After motion stops, a lead must not leave the border parked ahead — velocity decays to 0.
        var led = FrameMotionPredictor(lead: 0.02)
        var input = 0.0
        for _ in 0..<30 { input += 8; _ = led.process(rect(input), dt: dt) }
        var out = rect(0)
        for _ in 0..<120 { out = led.process(rect(input), dt: dt) }   // hold still (~1.3s)
        XCTAssertEqual(out.x, input, accuracy: 0.5)   // settles back onto the window
    }

    func testReset() {
        var p = FrameMotionPredictor(lead: 0.02)
        var input = 0.0
        for _ in 0..<20 { input += 10; _ = p.process(rect(input), dt: dt) }
        p.reset()
        XCTAssertNil(p.lastFrame)
        XCTAssertEqual(p.process(rect(500), dt: dt), rect(500))   // fresh: no inherited velocity
    }

    /// Regression guard: a realistic polled + quantized drag, mirrored 1:1 (lead 0), must be smooth
    /// (no frame-to-frame jumps beyond pixel quantization) and never overshoot the true path — the
    /// opposite of the old velocity-extrapolator (~20px jumps) and the low-pass filter (drift/float).
    func testSimulatedDragIsSmoothAndNeverOvershoots() {
        func trueX(_ t: Double) -> Double {
            if t < 0.2 { return 400 }
            if t < 0.9 { let u = (t - 0.2) / 0.7; return 400 + 360 * (u * u * (3 - 2 * u)) }
            return 760
        }
        var p = FrameMotionPredictor()   // lead 0
        var outs: [Double] = [], acts: [Double] = []
        var t = 0.0
        while t < 1.2 {
            let act = trueX(t)
            outs.append(p.process(rect(act.rounded()), dt: dt).x)
            acts.append(act); t += dt
        }
        var maxJump = 0.0
        for i in 1..<outs.count { maxJump = max(maxJump, abs((outs[i] - outs[i-1]) - (acts[i] - acts[i-1]))) }
        XCTAssertLessThan(maxJump, 2.0)                       // only pixel quantization, no jumps
        let err = zip(outs, acts).map { $0 - $1 }
        XCTAssertLessThan(err.max()!, 1.0)                    // never overshoots past the window
        XCTAssertGreaterThan(err.min()!, -1.0)                // and never lags (1:1 with the sample)
    }
}
