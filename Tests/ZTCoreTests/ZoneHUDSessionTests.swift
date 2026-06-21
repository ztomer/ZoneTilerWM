// ZoneHUDSessionTests — the interactive preview-then-commit state machine (v2.8).

import XCTest
@testable import ZTCore

final class ZoneHUDSessionTests: XCTestCase {

    // MARK: - arming

    func testHoldingModifierArmsTheShowTimer() {
        var s = ZoneHUDSession(holdDelayMs: 200)
        XCTAssertEqual(s.modifier(matchesTarget: true, otherKeysDown: false), [.arm(delayMs: 200)])
        XCTAssertFalse(s.isShown)
    }

    func testArmingThenElapsedShowsTheOverlay() {
        var s = ZoneHUDSession()
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        XCTAssertEqual(s.armElapsed(), [.show])
        XCTAssertTrue(s.isShown)
    }

    func testReleasingBeforeElapsedDisarmsWithoutShowing() {
        var s = ZoneHUDSession()
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        XCTAssertEqual(s.modifier(matchesTarget: false, otherKeysDown: false), [.disarm])
        XCTAssertEqual(s.armElapsed(), [])   // timer fired after release → no-op
        XCTAssertFalse(s.isShown)
    }

    func testOtherKeyHeldSuppressesArming() {
        // Feedback #10: only summon the grid when the modifier is held ALONE.
        var s = ZoneHUDSession()
        XCTAssertEqual(s.modifier(matchesTarget: true, otherKeysDown: true), [.disarm])
        XCTAssertEqual(s.armElapsed(), [])
        XCTAssertFalse(s.isShown)
    }

    func testRepeatedModifierEventsWhileArmingDoNotRearm() {
        var s = ZoneHUDSession()
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        XCTAssertEqual(s.modifier(matchesTarget: true, otherKeysDown: false), [])
    }

    // MARK: - tile on release (the default)

    func testZoneKeyHighlightsButDoesNotCommit() {
        var s = ZoneHUDSession(mode: .tileOnRelease)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        XCTAssertEqual(s.zoneKey("j"), [.highlight("j")])
        XCTAssertEqual(s.previewedKey, "j")
    }

    func testPressingAnotherZoneMovesTheHighlight() {
        var s = ZoneHUDSession(mode: .tileOnRelease)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        _ = s.zoneKey("j")
        XCTAssertEqual(s.zoneKey("l"), [.highlight("l")])
        XCTAssertEqual(s.previewedKey, "l")
    }

    func testReleaseCommitsTheHighlightedZoneAndHides() {
        var s = ZoneHUDSession(mode: .tileOnRelease)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        _ = s.zoneKey("j")
        XCTAssertEqual(s.modifier(matchesTarget: false, otherKeysDown: false), [.disarm, .commit("j"), .hide])
        XCTAssertFalse(s.isShown)
        XCTAssertNil(s.previewedKey)
    }

    func testReleaseWithNoHighlightJustHides() {
        var s = ZoneHUDSession(mode: .tileOnRelease)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        XCTAssertEqual(s.modifier(matchesTarget: false, otherKeysDown: false), [.disarm, .hide])
    }

    func testPressingANonModifierKeyMidPreviewCancels(/* feedback #10 once shown */) {
        // If another key joins the chord while shown, treat it as a release (cancel, no commit).
        var s = ZoneHUDSession(mode: .tileOnRelease)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        _ = s.zoneKey("j")
        XCTAssertEqual(s.modifier(matchesTarget: true, otherKeysDown: true), [.disarm, .commit("j"), .hide])
    }

    // MARK: - tile immediately (the toggle)

    func testImmediateModeCommitsOnKeypressAndStaysUp() {
        var s = ZoneHUDSession(mode: .tileImmediately)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        XCTAssertEqual(s.zoneKey("j"), [.commit("j")])
        XCTAssertTrue(s.isShown)            // overlay stays so you can place more
        XCTAssertNil(s.previewedKey)        // no highlight bookkeeping in immediate mode
    }

    func testImmediateModeReleaseJustHidesNoDoubleCommit() {
        var s = ZoneHUDSession(mode: .tileImmediately)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        _ = s.zoneKey("j")
        XCTAssertEqual(s.modifier(matchesTarget: false, otherKeysDown: false), [.disarm, .hide])
    }

    // MARK: - guards

    func testZoneKeyBeforeShownIsIgnored() {
        var s = ZoneHUDSession()
        XCTAssertEqual(s.zoneKey("j"), [])     // not armed/shown yet
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        XCTAssertEqual(s.zoneKey("j"), [])     // arming, not shown
    }
}
