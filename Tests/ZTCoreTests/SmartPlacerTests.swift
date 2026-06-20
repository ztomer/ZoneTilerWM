// SmartPlacerTests — behavioral spec for the SmartPlacer port. Lua↔Swift parity was originally
// validated by the (now-removed) tools/diff_place.sh differential oracle; that harness was deleted
// with the Lua. These tests are now the spec.

import XCTest
@testable import ZTCore

final class SmartPlacerTests: XCTestCase {

    private let screen = ZTRect(x: 0, y: 0, w: 1920, h: 1080)

    func testNoZonesReturnsNil() {
        XCTAssertNil(SmartPlacer.findBestTile(screen: screen, zones: [], occupied: []))
    }

    func testIndexPenaltyPrefersEarlierTileWhenEqual() {
        // Two identical tiles, nothing occupied: the index penalty favors tile 1.
        let t = ZTRect(x: 0, y: 0, w: 600, h: 600)
        let zone = SmartPlacer.Zone(zoneKey: "Z1", tiles: [t, t])
        let best = SmartPlacer.findBestTile(screen: screen, zones: [zone], occupied: [])
        XCTAssertEqual(best?.tileIndex, 1)
        XCTAssertEqual(best?.overlapRatio ?? -1, 0, accuracy: 1e-9)
    }

    func testEmptyTileBeatsFullyOccupiedTile() {
        // Tile 1 fully covered by an occupant; tile 2 empty -> tile 2 wins despite being later.
        let t1 = ZTRect(x: 0, y: 0, w: 600, h: 600)
        let t2 = ZTRect(x: 1000, y: 0, w: 600, h: 600)
        let zone = SmartPlacer.Zone(zoneKey: "Z1", tiles: [t1, t2])
        let best = SmartPlacer.findBestTile(screen: screen, zones: [zone], occupied: [t1])
        XCTAssertEqual(best?.tileIndex, 2)
        XCTAssertEqual(best?.overlapRatio ?? -1, 0, accuracy: 1e-9)
    }

    func testZonesIteratedInGivenOrder() {
        // Caller sorts zones; ties across zones resolve to the first encountered.
        let t = ZTRect(x: 0, y: 0, w: 500, h: 500)
        let za = SmartPlacer.Zone(zoneKey: "Za", tiles: [t])
        let zb = SmartPlacer.Zone(zoneKey: "Zb", tiles: [t])
        let best = SmartPlacer.findBestTile(screen: screen, zones: [za, zb], occupied: [])
        XCTAssertEqual(best?.zoneKey, "Za")
    }
}
