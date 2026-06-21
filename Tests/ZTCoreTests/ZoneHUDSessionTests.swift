// ZoneHUDSessionTests — the interactive preview-then-commit state machine (v2.8), incl. cycling.

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

    private func shown(mode: ZoneHUDSession.Mode = .tileOnRelease,
                       tileCount: @escaping (String) -> Int = { _ in 1 }) -> ZoneHUDSession {
        var s = ZoneHUDSession(mode: mode, tileCount: tileCount)
        _ = s.modifier(matchesTarget: true, otherKeysDown: false)
        _ = s.armElapsed()
        return s
    }

    func testZoneKeyHighlightsButDoesNotCommit() {
        var s = shown()
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 0)])
        XCTAssertEqual(s.previewedKey, "j")
        XCTAssertEqual(s.previewedTile, 0)
    }

    func testPressingAnotherZoneResetsToItsFirstPlacement() {
        var s = shown(tileCount: { _ in 3 })
        _ = s.zoneKey("j"); _ = s.zoneKey("j")          // j now at tile 1
        XCTAssertEqual(s.zoneKey("l"), [.highlight(key: "l", tile: 0)])
        XCTAssertEqual(s.previewedKey, "l")
        XCTAssertEqual(s.previewedTile, 0)
    }

    func testReleaseCommitsTheHighlightedZoneAndHides() {
        var s = shown()
        _ = s.zoneKey("j")
        XCTAssertEqual(s.modifier(matchesTarget: false, otherKeysDown: false),
                       [.disarm, .commit(key: "j", tile: 0), .hide])
        XCTAssertFalse(s.isShown)
        XCTAssertNil(s.previewedKey)
    }

    func testReleaseWithNoHighlightJustHides() {
        var s = shown()
        XCTAssertEqual(s.modifier(matchesTarget: false, otherKeysDown: false), [.disarm, .hide])
    }

    func testPressingANonModifierKeyMidPreviewCancels() {
        // If another key joins the chord while shown, treat it as a release (commit current, no double).
        var s = shown()
        _ = s.zoneKey("j")
        XCTAssertEqual(s.modifier(matchesTarget: true, otherKeysDown: true),
                       [.disarm, .commit(key: "j", tile: 0), .hide])
    }

    // MARK: - cycling (re-press the same key)

    func testRepressCyclesThroughPlacements() {
        var s = shown(tileCount: { _ in 3 })
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 0)])
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 1)])
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 2)])
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 0)])   // wraps by tileCount
    }

    func testCycleWrapsByThatKeysOwnTileCount() {
        var s = shown(tileCount: { key in key == "j" ? 2 : 4 })
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 0)])
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 1)])
        XCTAssertEqual(s.zoneKey("j"), [.highlight(key: "j", tile: 0)])   // j has only 2 placements
    }

    func testSingleTileKeyStaysAtZero() {
        var s = shown(tileCount: { _ in 1 })
        _ = s.zoneKey("h")
        XCTAssertEqual(s.zoneKey("h"), [.highlight(key: "h", tile: 0)])   // nothing to cycle to
    }

    func testReleaseCommitsTheCurrentlyCycledTile() {
        var s = shown(tileCount: { _ in 4 })
        _ = s.zoneKey("j"); _ = s.zoneKey("j"); _ = s.zoneKey("j")        // cycled to tile 2
        XCTAssertEqual(s.modifier(matchesTarget: false, otherKeysDown: false),
                       [.disarm, .commit(key: "j", tile: 2), .hide])
    }

    // MARK: - tile immediately (the toggle) — preserves the coordinator's legacy auto-cycle

    func testImmediateModeCommitsWithoutAnExplicitIndex() {
        var s = shown(mode: .tileImmediately)
        XCTAssertEqual(s.zoneKey("j"), [.commit(key: "j", tile: nil)])   // tile: nil → coordinator auto-cycles
        XCTAssertTrue(s.isShown)            // overlay stays so you can place more
        XCTAssertNil(s.previewedKey)
    }

    func testImmediateModeReleaseJustHidesNoDoubleCommit() {
        var s = shown(mode: .tileImmediately)
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
