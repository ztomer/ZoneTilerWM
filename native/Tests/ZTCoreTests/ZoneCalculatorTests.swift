// ZoneCalculatorTests — parity against the Lua zone oracle's frozen goldens
// (tools/fixtures/zones/*.json + *.out.json from tools/oracle_zones.lua). Plus focused
// unit tests for grid parsing and the Lua-pattern translator.

import XCTest
@testable import ZTCore

final class ZoneCalculatorTests: XCTestCase {

    private struct Scenario: Decodable {
        struct ScreenIn: Decodable { var name: String; var frame: ZTRect; var uuid: String? }
        var screen: ScreenIn
        var config: ZoneConfig
        var offsets: [String: [String: Double]]?
    }

    private struct Golden: Decodable {
        let layout_key: String
        let zones: [String: [ZTRect]]
    }

    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZTCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // native
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("tools/fixtures/zones", isDirectory: true)
    }

    func testZoneCorpusParityWithLuaGoldens() throws {
        let dir = fixturesDir()
        let fixtures = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".out.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(fixtures.isEmpty, "no zone fixtures found at \(dir.path)")

        for f in fixtures {
            let name = f.lastPathComponent
            let scenario = try JSONDecoder().decode(Scenario.self, from: Data(contentsOf: f))
            let golden = try JSONDecoder().decode(
                Golden.self,
                from: Data(contentsOf: f.deletingPathExtension().appendingPathExtension("out.json")))

            let offsets: ZoneCalculator.OffsetProvider = { axis, index in
                scenario.offsets?[axis]?[String(index)] ?? 0
            }
            let screen = ZoneCalculator.ScreenInfo(name: scenario.screen.name, frame: scenario.screen.frame)
            let (layoutKey, zones) = ZoneCalculator.computeZones(
                screen: screen, config: scenario.config, offsets: offsets)

            XCTAssertEqual(layoutKey, golden.layout_key, "[\(name)] layout_key")
            XCTAssertEqual(Set(zones.keys), Set(golden.zones.keys), "[\(name)] zone keys")
            for (zoneKey, goldenTiles) in golden.zones {
                guard let gotTiles = zones[zoneKey] else {
                    XCTFail("[\(name)] missing zone \(zoneKey)"); continue
                }
                XCTAssertEqual(gotTiles.count, goldenTiles.count, "[\(name)] zone \(zoneKey) tile count")
                for (i, gt) in goldenTiles.enumerated() where i < gotTiles.count {
                    let r = gotTiles[i]
                    XCTAssertEqual(r.x, gt.x, accuracy: 1e-6, "[\(name)] \(zoneKey)[\(i)].x")
                    XCTAssertEqual(r.y, gt.y, accuracy: 1e-6, "[\(name)] \(zoneKey)[\(i)].y")
                    XCTAssertEqual(r.w, gt.w, accuracy: 1e-6, "[\(name)] \(zoneKey)[\(i)].w")
                    XCTAssertEqual(r.h, gt.h, accuracy: 1e-6, "[\(name)] \(zoneKey)[\(i)].h")
                }
            }
        }
    }

    func testGridCoordParsing() {
        let a1 = ZoneCalculator.parseGridCoords("a1")
        XCTAssertEqual(a1?.colStart, 1); XCTAssertEqual(a1?.rowStart, 1)
        XCTAssertEqual(a1?.colEnd, 1); XCTAssertEqual(a1?.rowEnd, 1)

        let span = ZoneCalculator.parseGridCoords("b1:d3")
        XCTAssertEqual(span?.colStart, 2); XCTAssertEqual(span?.rowStart, 1)
        XCTAssertEqual(span?.colEnd, 4); XCTAssertEqual(span?.rowEnd, 3)

        XCTAssertNil(ZoneCalculator.parseGridCoords("nonsense"))
    }

    func testLuaPatternMatching() {
        XCTAssertTrue(LuaPattern.find("DELL U3219Q", "DELL.*U32"))
        XCTAssertTrue(LuaPattern.find("Built-in Retina Display", "Built[-]?in"))
        XCTAssertTrue(LuaPattern.find("Builtin Display", "Built[-]?in"))
        XCTAssertTrue(LuaPattern.find("Color LCD", "Color LCD"))
        XCTAssertFalse(LuaPattern.find("Generic FHD", "DELL.*U32"))
    }
}
