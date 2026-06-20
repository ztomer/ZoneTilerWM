import XCTest
@testable import ZTSystem

/// The launch-seed + elimination join that maps opaque marker ids to plist ManagedSpaceIDs so the
/// public Spaces path can report an exact live current Space.
final class MarkerSpaceResolverTests: XCTestCase {
    private let D = "DISPLAY-A"
    private let E = "DISPLAY-B"

    /// At launch (fresh plist) the on-screen marker binds to the plist's current Space.
    func testLaunchSeedFromFreshPlist() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20]], currentMarkerByDisplay: [D: 1], markerDisplay: [1: D],
            plistCurrent: [D: 10], plistFresh: true, prior: [:])
        XCTAssertEqual(r.map, [1: 10])
        XCTAssertEqual(r.currentByDisplay, [D: 10])
    }

    /// A 2-Space display resolves EXACTLY on the first visit to the other Space — by elimination, even
    /// though the plist's current is stale (still pointing at the old Space).
    func testTwoSpaceResolvesByElimination() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20]], currentMarkerByDisplay: [D: 2], markerDisplay: [1: D, 2: D],
            plistCurrent: [D: 10], plistFresh: false, prior: [1: 10])
        XCTAssertEqual(r.map, [1: 10, 2: 20])
        XCTAssertEqual(r.currentByDisplay[D], 20)        // exact, not the stale plist value 10
    }

    /// A ≥3-Space display can't resolve a fresh marker from a plain switch (two Spaces still unbound) —
    /// it falls back to the plist's best-effort current rather than guessing.
    func testThreeSpaceStallsToBestEffort() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20, 30]], currentMarkerByDisplay: [D: 2], markerDisplay: [1: D, 2: D, 3: D],
            plistCurrent: [D: 10], plistFresh: false, prior: [1: 10])
        XCTAssertEqual(r.map, [1: 10])                   // unchanged — no guess
        XCTAssertEqual(r.currentByDisplay[D], 10)        // best-effort fallback
    }

    /// …but if the plist read is fresh (e.g. the user just added/removed a Space), the resolver re-seeds
    /// the unknown current marker from the trustworthy plist value.
    func testThreeSpaceReseedsWhenPlistFresh() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20, 30]], currentMarkerByDisplay: [D: 2], markerDisplay: [1: D, 2: D, 3: D],
            plistCurrent: [D: 20], plistFresh: true, prior: [1: 10])
        XCTAssertEqual(r.map[2], 20)
        XCTAssertEqual(r.currentByDisplay[D], 20)
    }

    /// Never binds two markers to the same Space: a fresh plist value that's already claimed is ignored.
    func testDoesNotDoubleClaim() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20]], currentMarkerByDisplay: [D: 2], markerDisplay: [1: D, 2: D],
            plistCurrent: [D: 10], plistFresh: true, prior: [1: 10])   // 10 already taken by marker 1
        XCTAssertEqual(r.map[2], 20)                     // forced to the only free Space
    }

    /// No marker on-screen yet for a display → report the plist's current verbatim, learn nothing.
    func testNoMarkerYetUsesPlist() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20]], currentMarkerByDisplay: [:], markerDisplay: [:],
            plistCurrent: [D: 20], plistFresh: false, prior: [:])
        XCTAssertTrue(r.map.isEmpty)
        XCTAssertEqual(r.currentByDisplay, [D: 20])
    }

    /// Displays are independent: a resolved D doesn't leak its claims into E's candidate set.
    func testMultiDisplayIndependence() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20], E: [10, 99]],          // same id 10 on both displays (ids aren't global)
            currentMarkerByDisplay: [D: 2, E: 4], markerDisplay: [1: D, 2: D, 3: E, 4: E],
            plistCurrent: [D: 10, E: 10], plistFresh: false, prior: [1: 10, 3: 10])
        XCTAssertEqual(r.map[2], 20)                     // D eliminates to 20
        XCTAssertEqual(r.map[4], 99)                     // E eliminates to 99 (its own claimed set)
        XCTAssertEqual(r.currentByDisplay, [D: 20, E: 99])
    }

    /// An already-known current marker just reports its binding — idempotent, no churn.
    func testKnownMarkerIsStable() {
        let r = MarkerSpaceResolver.resolve(
            layout: [D: [10, 20]], currentMarkerByDisplay: [D: 1], markerDisplay: [1: D, 2: D],
            plistCurrent: [D: 99], plistFresh: true, prior: [1: 10, 2: 20])
        XCTAssertEqual(r.map, [1: 10, 2: 20])
        XCTAssertEqual(r.currentByDisplay[D], 10)        // marker 1 → Space 10, ignores bogus plist 99
    }
}
