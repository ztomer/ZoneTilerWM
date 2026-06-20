// LayoutSolverTests — differential parity against the Lua oracle's frozen goldens.
// Loads the shared fixtures in tools/fixtures/solver/*.json and their *.out.json goldens
// (produced by tools/oracle_solver.lua), runs the Swift LayoutSolver, and asserts the
// assignment map + costs match. `swift test` thus bakes the Lua↔Swift parity check in;
// tools/diff_solver.sh provides the live cross-check + fuzzing.

import XCTest
@testable import ZTCore

final class LayoutSolverTests: XCTestCase {

    private struct Scenario: Decodable {
        var screen: ZTRect?
        var windows: [WindowSnapshot]
        var tiles: [TileSpec]
    }

    private struct Golden: Decodable {
        struct Assignment: Decodable {
            let window_id: String
            let zone_key: String
            let tile_index: TileIndex
            let cost: Double
        }
        let assignments: [Assignment]
        let total_cost: Double
        let placed: Int
    }

    /// Tests/Fixtures/solver — Lua-dumped golden corpus, now a static regression set.
    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZTCoreTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Fixtures/solver", isDirectory: true)
    }

    func testCorpusParityWithLuaGoldens() throws {
        let dir = fixturesDir()
        let all = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        let fixtures = all
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".out.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(fixtures.isEmpty, "no fixtures found at \(dir.path)")

        for f in fixtures {
            let name = f.lastPathComponent
            let scenario = try JSONDecoder().decode(Scenario.self, from: Data(contentsOf: f))
            let goldenURL = f.deletingPathExtension().appendingPathExtension("out.json")
            let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: goldenURL))

            let screen = scenario.screen ?? ZTRect(x: 0, y: 0, w: 1000, h: 1000)
            let moves = LayoutSolver.solve(
                windows: scenario.windows, tiles: scenario.tiles, screen: screen)

            var got: [String: (zone: String, idx: TileIndex, cost: Double)] = [:]
            var total = 0.0
            for mv in moves {
                let w = scenario.windows[mv.windowIndex]
                let t = scenario.tiles[mv.tileIndex]
                got[w.id] = (t.zone, t.idx, mv.cost)
                total += mv.cost
            }

            XCTAssertEqual(got.count, golden.placed, "[\(name)] placed count")
            XCTAssertEqual(total, golden.total_cost, accuracy: 1e-6, "[\(name)] total_cost")
            for a in golden.assignments {
                guard let g = got[a.window_id] else {
                    XCTFail("[\(name)] missing assignment for \(a.window_id)")
                    continue
                }
                XCTAssertEqual(g.zone, a.zone_key, "[\(name)] \(a.window_id) zone")
                XCTAssertEqual(g.idx, a.tile_index, "[\(name)] \(a.window_id) tile_index")
                XCTAssertEqual(g.cost, a.cost, accuracy: 1e-6, "[\(name)] \(a.window_id) cost")
            }
        }
    }

    func testEmptyInputsReturnNoMoves() {
        let tile = TileSpec(zone: "j", idx: .int(1), rect: ZTRect(x: 0, y: 0, w: 100, h: 100))
        let win = WindowSnapshot(id: "A", w: 100, h: 100)
        let screen = ZTRect(x: 0, y: 0, w: 1000, h: 1000)
        XCTAssertTrue(LayoutSolver.solve(windows: [], tiles: [tile], screen: screen).isEmpty)
        XCTAssertTrue(LayoutSolver.solve(windows: [win], tiles: [], screen: screen).isEmpty)
    }

    func testMaxChecksTruncationReturnsValidResultWithoutHanging() {
        // Force truncation with a tiny node budget: the solver must return promptly with a STRUCTURALLY
        // VALID (possibly empty/partial) result — never a crash, hang, or out-of-range index. (It also
        // emits one diagnostic line to stderr, by design.)
        let windows = (0..<5).map { WindowSnapshot(id: "w\($0)", w: 400, h: 300) }
        let tiles = (0..<6).map {
            TileSpec(zone: "z\($0)", idx: .int($0 + 1), rect: ZTRect(x: Double($0) * 110, y: 0, w: 100, h: 100))
        }
        let moves = LayoutSolver.solve(windows: windows, tiles: tiles,
                                       screen: ZTRect(x: 0, y: 0, w: 1200, h: 800), maxChecks: 1)
        for m in moves {
            XCTAssertTrue((0..<windows.count).contains(m.windowIndex))
            XCTAssertTrue((0..<tiles.count).contains(m.tileIndex))
            XCTAssertTrue(m.cost.isFinite)
        }
        // A non-truncated solve on the same input is a superset-quality result (sanity: it doesn't crash).
        XCTAssertNoThrow(LayoutSolver.solve(windows: windows, tiles: tiles,
                                            screen: ZTRect(x: 0, y: 0, w: 1200, h: 800)))
    }
}
