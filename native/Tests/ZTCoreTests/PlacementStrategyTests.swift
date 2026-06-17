// PlacementStrategyTests — behavioral spec for the PlacementStrategy port. Lua↔Swift parity
// is covered by tools/diff_strategy.sh; these assert the intended behavior directly.

import XCTest
@testable import ZTCore

final class PlacementStrategyTests: XCTestCase {

    private let tiles = [
        ZTRect(x: 0, y: 0, w: 960, h: 1080),
        ZTRect(x: 960, y: 0, w: 960, h: 1080),
    ]

    func testStrategyConfigMapping() {
        XCTAssertEqual(PlacementStrategy.Strategy(config: "largest_free_space"), .largestFreeSpace)
        XCTAssertEqual(PlacementStrategy.Strategy(config: "rotate"), .rotate)
        XCTAssertEqual(PlacementStrategy.Strategy(config: "hybrid"), .rotate)
        XCTAssertEqual(PlacementStrategy.Strategy(config: "bogus"), .rotate)
    }

    func testRotateCyclesFromState() {
        // 2 tiles, current index 1 -> (1 % 2) + 1 = 2.
        let t = PlacementStrategy.rotate(tiles: tiles, currentTileIndex: 1)
        XCTAssertEqual(t, tiles[1])
        // No state -> index 0 -> tile 1.
        XCTAssertEqual(PlacementStrategy.rotate(tiles: tiles, currentTileIndex: nil), tiles[0])
    }

    func testLargestFreePicksEmptierTile() {
        // tile 1 fully occupied, tile 2 free; not already in zone, current frame matches nothing.
        let occ = [PlacementStrategy.OccupiedWindow(id: 1, frame: tiles[0])]
        let t = PlacementStrategy.findBestTile(
            strategy: .largestFreeSpace, tiles: tiles, zoneKey: "h",
            currentFrame: ZTRect(x: 500, y: 500, w: 10, h: 10),
            stateZoneKey: nil, stateTileIndex: nil, occupied: occ, selfId: 999)
        XCTAssertEqual(t, tiles[1])
    }

    func testLargestFreeAllBlockedCyclesFromCurrent() {
        // Both tiles fully occupied; current frame == tile 1 -> cycle to tile 2.
        let occ = [
            PlacementStrategy.OccupiedWindow(id: 1, frame: tiles[0]),
            PlacementStrategy.OccupiedWindow(id: 2, frame: tiles[1]),
        ]
        let t = PlacementStrategy.findBestTile(
            strategy: .largestFreeSpace, tiles: tiles, zoneKey: "h",
            currentFrame: tiles[0],
            stateZoneKey: "h", stateTileIndex: 1, occupied: occ, selfId: 999)
        XCTAssertEqual(t, tiles[1])
    }

    func testEmptyTilesReturnsNil() {
        XCTAssertNil(PlacementStrategy.findBestTile(
            strategy: .rotate, tiles: [], zoneKey: "h",
            currentFrame: ZTRect(x: 0, y: 0, w: 1, h: 1),
            stateZoneKey: nil, stateTileIndex: nil, occupied: [], selfId: 999))
    }
}
