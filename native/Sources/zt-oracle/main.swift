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

case "memory":
    struct WH: Decodable { var w: Double; var h: Double }
    struct EventIn: Decodable {
        var op: String
        var windowId: Int?
        var app: String?; var monitor: String?; var zone: String?; var tile: TileIndex?
        var win: WH?; var screen: WH?
    }
    struct ConfigIn: Decodable { var excluded_apps: [String]?; var settle_delay_sec: Double? }
    struct QueryIn: Decodable { var app: String; var monitor: String; var zone: String? }
    struct Scenario: Decodable { var config: ConfigIn?; var events: [EventIn]; var queries: [QueryIn]? }

    struct RememberedOut: Encodable { let zone_key: String; let tile_index: TileIndex }
    struct RankedOut: Encodable {
        let zone_key: String; let tile_index: TileIndex
        let count: Int; let mean_ar: Double; let mean_area: Double
    }
    struct QueryOut: Encodable {
        let app: String; let monitor: String; let zone: String?
        let remembered: RememberedOut?
        let preferred_zone: String?
        let preferred_tile: TileIndex?
        let ranked: [RankedOut]
    }
    struct Out: Encodable { let save: WindowMemory.SaveData; let queries: [QueryOut] }

    guard let scenario = try? JSONDecoder().decode(Scenario.self, from: input) else {
        fail("bad memory scenario JSON")
    }
    let settle = (scenario.config?.settle_delay_sec ?? 2.0) > 0
    let wm = WindowMemory(excludedApps: scenario.config?.excluded_apps ?? [], settleEnabled: settle)

    for e in scenario.events {
        switch e.op {
        case "position":
            wm.positionWindow(windowId: e.windowId ?? 0, app: e.app ?? "", monitor: e.monitor ?? "",
                              zone: e.zone ?? "", tile: e.tile ?? .int(0),
                              winW: e.win?.w ?? 0, winH: e.win?.h ?? 0,
                              screenW: e.screen?.w ?? 0, screenH: e.screen?.h ?? 0)
        case "flush":
            wm.flushAll()
        default:
            break
        }
    }

    var queries: [QueryOut] = []
    for q in scenario.queries ?? [] {
        let remembered = wm.rememberedPosition(app: q.app, monitor: q.monitor)
            .map { RememberedOut(zone_key: $0.zone, tile_index: $0.tile) }
        let preferredZone = wm.preferredZone(app: q.app, monitor: q.monitor)
        let preferredTile = q.zone.flatMap { wm.preferredTile(app: q.app, monitor: q.monitor, zone: $0) }
        let ranked = wm.rankedPreferences(app: q.app, monitor: q.monitor).map {
            RankedOut(zone_key: $0.zoneKey, tile_index: $0.tile,
                      count: $0.count, mean_ar: $0.meanAR, mean_area: $0.meanArea)
        }
        queries.append(QueryOut(app: q.app, monitor: q.monitor, zone: q.zone,
                                remembered: remembered, preferred_zone: preferredZone,
                                preferred_tile: preferredTile, ranked: ranked))
    }
    FileHandle.standardOutput.write(try encoder.encode(Out(save: wm.save(), queries: queries)))

default:
    fail("unknown mode '\(mode)' (expected 'solve', 'zones', or 'memory')")
}
