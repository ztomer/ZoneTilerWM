// zt-oracle — Swift side of the differential-testing harness.
// Reads a JSON scenario on stdin, runs a ZTCore algorithm, writes JSON results on stdout.
// Mode is selected by argv[1] ("solve" default, or "zones"); the JSON contract matches the
// corresponding Lua oracle (tools/oracle_solver.lua, tools/oracle_zones.lua).

import Foundation
import ZTCore

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "solve"
let input = FileHandle.standardInput.readDataToEndOfFile()

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("zt-oracle: \(msg)\n".utf8))
    exit(2)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

switch mode {

case "solve":
    struct Scenario: Decodable {
        var screen: ZTRect?
        var windows: [WindowSnapshot]
        var tiles: [TileSpec]
    }
    struct OutAssign: Encodable {
        let window_id: String; let zone_key: String; let tile_index: TileIndex; let cost: Double
    }
    struct OutResult: Encodable {
        let assignments: [OutAssign]; let total_cost: Double; let placed: Int
    }

    guard let scenario = try? JSONDecoder().decode(Scenario.self, from: input) else {
        fail("bad solve scenario JSON")
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
    assignments.sort { $0.window_id < $1.window_id }
    let result = OutResult(assignments: assignments, total_cost: total, placed: assignments.count)
    FileHandle.standardOutput.write(try encoder.encode(result))

case "zones":
    struct ScreenIn: Decodable { var name: String; var frame: ZTRect; var uuid: String? }
    struct Scenario: Decodable {
        var screen: ScreenIn
        var config: ZoneConfig
        var offsets: [String: [String: Double]]?
    }
    struct ZoneOut: Encodable { let layout_key: String; let zones: [String: [ZTRect]] }

    guard let scenario = try? JSONDecoder().decode(Scenario.self, from: input) else {
        fail("bad zones scenario JSON")
    }
    let offsets: ZoneCalculator.OffsetProvider = { axis, index in
        scenario.offsets?[axis]?[String(index)] ?? 0
    }
    let screen = ZoneCalculator.ScreenInfo(name: scenario.screen.name, frame: scenario.screen.frame)
    let (layoutKey, zones) = ZoneCalculator.computeZones(
        screen: screen, config: scenario.config, offsets: offsets)
    FileHandle.standardOutput.write(try encoder.encode(ZoneOut(layout_key: layoutKey, zones: zones)))

default:
    fail("unknown mode '\(mode)' (expected 'solve' or 'zones')")
}
