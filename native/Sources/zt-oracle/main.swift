// zt-oracle — Swift side of the differential-testing harness.
// Reads a JSON solver scenario on stdin, runs ZTCore's LayoutSolver, writes JSON results
// on stdout. The contract is identical to tools/oracle_solver.lua so the two can be diffed.

import Foundation
import ZTCore

struct Scenario: Decodable {
    var screen: ZTRect?
    var windows: [WindowSnapshot]
    var tiles: [TileSpec]
}

struct OutAssign: Encodable {
    let window_id: String
    let zone_key: String
    let tile_index: TileIndex
    let cost: Double
}

struct OutResult: Encodable {
    let assignments: [OutAssign]
    let total_cost: Double
    let placed: Int
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let scenario: Scenario
do {
    scenario = try JSONDecoder().decode(Scenario.self, from: input)
} catch {
    FileHandle.standardError.write(Data("zt-oracle: bad scenario JSON: \(error)\n".utf8))
    exit(2)
}

let screen = scenario.screen ?? ZTRect(x: 0, y: 0, w: 1000, h: 1000)
let moves = LayoutSolver.solve(windows: scenario.windows, tiles: scenario.tiles, screen: screen)

var assignments: [OutAssign] = []
var total = 0.0
for mv in moves {
    let w = scenario.windows[mv.windowIndex]
    let t = scenario.tiles[mv.tileIndex]
    assignments.append(OutAssign(window_id: w.id, zone_key: t.zone, tile_index: t.idx, cost: mv.cost))
    total += mv.cost
}
// Assignment set is order-independent; sort for deterministic diffs.
assignments.sort { $0.window_id < $1.window_id }

let result = OutResult(assignments: assignments, total_cost: total, placed: assignments.count)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let out = try encoder.encode(result)
FileHandle.standardOutput.write(out)
