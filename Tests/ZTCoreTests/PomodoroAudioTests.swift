// PomodoroAudioTests — Pomodoro state machine + audio device cycling.

import XCTest
@testable import ZTCore

final class PomodoroTests: XCTestCase {

    private func make() -> Pomodoro {
        Pomodoro(config: .init(workPeriodSec: 3, restPeriodSec: 2, enableColorBar: true))
    }

    func testEnableStartsActive() {
        let p = make()
        p.enable()
        XCTAssertTrue(p.isActive)
        XCTAssertEqual(p.disableCount, 0)
        XCTAssertEqual(p.phase, .work)
        XCTAssertEqual(p.timeLeft, 3)
    }

    func testTickCountsDownThenCompletesWorkIntoRest() {
        let p = make()
        p.enable()
        XCTAssertNil(p.tick())          // 3 -> 2
        XCTAssertEqual(p.timeLeft, 2)
        XCTAssertNil(p.tick())          // 2 -> 1
        XCTAssertEqual(p.tick(), .workCompleted)   // 1 -> 0 -> complete
        XCTAssertEqual(p.workCount, 1)
        XCTAssertEqual(p.phase, .rest)
        XCTAssertEqual(p.timeLeft, 2)   // rest period
        XCTAssertFalse(p.isActive)      // completion pauses
        XCTAssertEqual(p.disableCount, 1)
    }

    func testDisableThreePressSemantics() {
        let p = make()
        p.enable()
        _ = p.tick()                          // 3 -> 2, still active
        XCTAssertEqual(p.disable(), .paused(wasActive: true))
        XCTAssertFalse(p.isActive)
        XCTAssertEqual(p.disable(), .reset)   // resets to work/full
        XCTAssertEqual(p.phase, .work)
        XCTAssertEqual(p.timeLeft, 3)
        XCTAssertEqual(p.disable(), .shutdown)
        XCTAssertFalse(p.hasMenu)
    }

    func testDisplayString() {
        let p = Pomodoro(config: .init(workPeriodSec: 3120, restPeriodSec: 1020))
        XCTAssertEqual(p.displayString, "[work|52:00|#00]")
        p.enable()
        for _ in 0..<60 { _ = p.tick() }      // 60s elapsed
        XCTAssertEqual(p.displayString, "[work|51:00|#00]")
    }

    func testResetWork() {
        let p = make()
        p.enable()
        for _ in 0..<3 { _ = p.tick() }       // complete one work period
        XCTAssertEqual(p.workCount, 1)
        p.resetWork()
        XCTAssertEqual(p.workCount, 0)
    }

    func testRestPeriodCompletesBackIntoWork() {
        let p = make()                         // work 3, rest 2
        p.enable()
        for _ in 0..<3 { _ = p.tick() }        // finish work → rest, paused
        XCTAssertEqual(p.phase, .rest)
        p.enable()                             // resume into the rest countdown
        XCTAssertNil(p.tick())                 // 2 -> 1
        XCTAssertEqual(p.tick(), .restCompleted)   // 1 -> 0 -> rest done
        XCTAssertEqual(p.phase, .work)
        XCTAssertEqual(p.timeLeft, 3)          // re-baselined to the work period
    }

    func testFourthDisableIsNoopAfterShutdown() {
        let p = make()
        p.enable()
        XCTAssertEqual(p.disable(), .paused(wasActive: true))
        XCTAssertEqual(p.disable(), .reset)
        XCTAssertEqual(p.disable(), .shutdown) // tears down the menu
        XCTAssertEqual(p.disable(), .noop)     // no menu left → no-op, count pinned at 2
        XCTAssertEqual(p.disableCount, 2)
    }

    func testUpdateConfigRebaselinesWhenIdleButKeepsRemainingWhenActive() {
        let idle = make()
        idle.updateConfig(.init(workPeriodSec: 3000, restPeriodSec: 600))
        XCTAssertEqual(idle.timeLeft, 3000)    // idle → adopt the new work period
        XCTAssertEqual(idle.phase, .work)

        let active = make()
        active.enable()
        _ = active.tick()                      // 3 -> 2
        active.updateConfig(.init(workPeriodSec: 999, restPeriodSec: 999))
        XCTAssertEqual(active.timeLeft, 2)     // active → keep the running countdown
    }
}

final class AudioSwitcherTests: XCTestCase {

    private let devices = ["Audioengine 2+", "Bose QC35 II", "WH-1000XM6"]

    func testCyclesToNext() {
        XCTAssertEqual(AudioSwitcher.nextDevice(configured: devices, currentName: "Audioengine 2+"), "Bose QC35 II")
        XCTAssertEqual(AudioSwitcher.nextDevice(configured: devices, currentName: "Bose QC35 II"), "WH-1000XM6")
    }

    func testWrapsFromLastToFirst() {
        XCTAssertEqual(AudioSwitcher.nextDevice(configured: devices, currentName: "WH-1000XM6"), "Audioengine 2+")
    }

    func testUnknownCurrentGoesToFirst() {
        XCTAssertEqual(AudioSwitcher.nextDevice(configured: devices, currentName: "Some Other Device"), "Audioengine 2+")
        XCTAssertEqual(AudioSwitcher.nextDevice(configured: devices, currentName: nil), "Audioengine 2+")
    }

    func testFewerThanTwoIsNoOp() {
        XCTAssertNil(AudioSwitcher.nextDevice(configured: ["Only One"], currentName: "Only One"))
        XCTAssertNil(AudioSwitcher.nextDevice(configured: [], currentName: nil))
    }
}
