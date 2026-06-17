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

case "place":
    struct ZoneIn: Decodable { var zone_key: String; var tiles: [ZTRect] }
    struct Scenario: Decodable { var screen: ZTRect; var zones: [ZoneIn]; var occupied: [ZTRect]? }
    struct Out: Encodable {
        let found: Bool
        let zone_key: String?
        let tile_index: Int?
        let tile: ZTRect?
        let overlap_ratio: Double?
    }

    guard let scenario = try? JSONDecoder().decode(Scenario.self, from: input) else {
        fail("bad place scenario JSON")
    }
    // Sort zones by key (mirrors the Lua sorted-key iteration), excluding "default".
    let zones = scenario.zones
        .filter { $0.zone_key != "default" }
        .sorted { $0.zone_key < $1.zone_key }
        .map { SmartPlacer.Zone(zoneKey: $0.zone_key, tiles: $0.tiles) }
    let best = SmartPlacer.findBestTile(screen: scenario.screen, zones: zones, occupied: scenario.occupied ?? [])
    let out: Out
    if let b = best {
        out = Out(found: true, zone_key: b.zoneKey, tile_index: b.tileIndex, tile: b.tile, overlap_ratio: b.overlapRatio)
    } else {
        out = Out(found: false, zone_key: nil, tile_index: nil, tile: nil, overlap_ratio: nil)
    }
    FileHandle.standardOutput.write(try encoder.encode(out))

case "strategy":
    struct OccIn: Decodable { var id: Int; var frame: ZTRect }
    struct StateIn: Decodable { var zone_key: String?; var tile_index: Int? }
    struct CurrentIn: Decodable { var frame: ZTRect; var state: StateIn? }
    struct Scenario: Decodable {
        var strategy: String
        var tiles: [ZTRect]
        var zone_key: String
        var current: CurrentIn
        var occupied: [OccIn]?
        var self_id: Int?
    }
    struct Out: Encodable { let found: Bool; let tile: ZTRect? }

    guard let scenario = try? JSONDecoder().decode(Scenario.self, from: input) else {
        fail("bad strategy scenario JSON")
    }
    let occupied = (scenario.occupied ?? []).map {
        PlacementStrategy.OccupiedWindow(id: $0.id, frame: $0.frame)
    }
    let tile = PlacementStrategy.findBestTile(
        strategy: PlacementStrategy.Strategy(config: scenario.strategy),
        tiles: scenario.tiles,
        zoneKey: scenario.zone_key,
        currentFrame: scenario.current.frame,
        stateZoneKey: scenario.current.state?.zone_key,
        stateTileIndex: scenario.current.state?.tile_index,
        occupied: occupied,
        selfId: scenario.self_id ?? 999)
    FileHandle.standardOutput.write(try encoder.encode(Out(found: tile != nil, tile: tile)))

case "autotiler":
    struct ScreenIn: Decodable { var uuid: String; var name: String; var id: Int?; var frame: ZTRect }
    struct WindowIn: Decodable {
        var id: Int; var app: String; var monitor: String; var frame: ZTRect
        var last_focused_time: Int; var isStandard: Bool?; var isMinimized: Bool?
    }
    struct WorkingSetIn: Decodable { var time_limit_sec: Int?; var max_capacity: Int? }
    struct ConfigIn: Decodable {
        var auto_tile_center_zones: [String]?
        var working_set: WorkingSetIn?
        var auto_tiling_mode: String?
        var solver_weights: SolverWeightsIn?
        var grids: [String: GridConfig]
        var layouts: [String: [String: [String]]]
        var margins: Margins?
        var screen_detection: ScreenDetection?
        var custom_screens: [String: CustomScreen]?
    }
    struct SolverWeightsIn: Decodable {
        var memory_exact: Double?; var memory_zone: Double?; var aspect_ratio: Double?
        var area_ratio: Double?; var moved_dist: Double?; var skip_window: Double?; var coverage: Double?
    }
    struct Scenario: Decodable {
        var now: Int
        var config: ConfigIn
        var screens: [ScreenIn]
        var windows: [WindowIn]
        var z_order: [Int]?
        var focused_id: Int?
        var memory: [String: [MemoryPref]]?
    }
    struct MoveOut: Encodable {
        let window_id: Int; let monitor_id: String; let zone_key: String
        let tile_index: TileIndex; let rect: ZTRect
    }
    struct Out: Encodable { let moves: [MoveOut] }

    guard let scenario = try? JSONDecoder().decode(Scenario.self, from: input) else {
        fail("bad autotiler scenario JSON")
    }
    let c = scenario.config
    var weights = CostWeights()
    if let w = c.solver_weights {
        if let v = w.memory_exact { weights.memoryExact = v }
        if let v = w.memory_zone { weights.memoryZone = v }
        if let v = w.aspect_ratio { weights.aspectRatio = v }
        if let v = w.area_ratio { weights.areaRatio = v }
        if let v = w.moved_dist { weights.movedDist = v }
        if let v = w.skip_window { weights.skipWindow = v }
        if let v = w.coverage { weights.coverage = v }
    }
    let zoneConfig = ZoneConfig(grids: c.grids, layouts: c.layouts, margins: c.margins,
                                screen_detection: c.screen_detection, custom_screens: c.custom_screens)
    let config = AutoTiler.Config(
        centerZones: c.auto_tile_center_zones ?? ["j", "center", "0"],
        workingSetTimeLimit: c.working_set?.time_limit_sec ?? 1800,
        workingSetMaxCapacity: c.working_set?.max_capacity ?? 6,
        mode: c.auto_tiling_mode ?? "usage",
        weights: weights, zoneConfig: zoneConfig)
    let screens = scenario.screens.map { AutoTiler.Screen(uuid: $0.uuid, name: $0.name, frame: $0.frame) }
    let windows = scenario.windows.map {
        AutoTiler.Window(id: $0.id, app: $0.app, monitor: $0.monitor, frame: $0.frame,
                         lastFocusedTime: $0.last_focused_time,
                         isStandard: $0.isStandard ?? true, isMinimized: $0.isMinimized ?? false)
    }
    let planned = AutoTiler.plan(config: config, screens: screens, windows: windows,
                                 zOrder: scenario.z_order ?? [], focusedId: scenario.focused_id,
                                 memory: scenario.memory ?? [:], now: scenario.now)
    let out = planned.map {
        MoveOut(window_id: $0.windowId, monitor_id: $0.monitorId, zone_key: $0.zoneKey,
                tile_index: $0.tileIndex, rect: $0.rect)
    }
    FileHandle.standardOutput.write(try encoder.encode(Out(moves: out)))

case "movezone":
    final class FakeWS: WindowSystem {
        let focused: LiveWindow?
        let onScreen: [LiveWindow]
        init(focused: LiveWindow?, onScreen: [LiveWindow]) { self.focused = focused; self.onScreen = onScreen }
        func focusedWindow() -> LiveWindow? { focused }
        func windows(onScreen uuid: String) -> [LiveWindow] { onScreen }
        @discardableResult func moveFocusedWindow(to rect: ZTRect) -> Bool { true }
    }
    final class FakeSP: ScreenProvider {
        let screens: [ScreenSnapshot]
        init(_ s: [ScreenSnapshot]) { screens = s }
        func allScreens() -> [ScreenSnapshot] { screens }
        func mainScreen() -> ScreenSnapshot? { screens.first }
        func screen(uuid: String) -> ScreenSnapshot? { screens.first { $0.uuid == uuid } }
    }
    struct OccIn: Decodable { var id: Int; var frame: ZTRect }
    struct WinIn: Decodable { var frame: ZTRect }
    struct ScreenIn: Decodable { var name: String; var frame: ZTRect }
    struct Scenario: Decodable {
        var screen: ScreenIn
        var config: ZoneConfig
        var zone_key: String
        var strategy: String
        var window: WinIn
        var occupied: [OccIn]?
        var self_id: Int?
    }
    struct Out: Encodable { let found: Bool; let zone_key: String?; let tile_index: Int?; let rect: ZTRect? }

    guard let s = try? JSONDecoder().decode(Scenario.self, from: input) else { fail("bad movezone JSON") }
    let selfId = s.self_id ?? 999
    let screen = ScreenSnapshot(uuid: "M1", name: s.screen.name, frame: s.screen.frame, fullFrame: s.screen.frame)
    let focused = LiveWindow(id: selfId, appName: "Focused", frame: s.window.frame, screenUUID: "M1")
    let onScreen = [focused] + (s.occupied ?? []).map {
        LiveWindow(id: $0.id, appName: "Other", frame: $0.frame, screenUUID: "M1")
    }
    let coord = TilerCoordinator(windowSystem: FakeWS(focused: focused, onScreen: onScreen),
                                 screenProvider: FakeSP([screen]),
                                 zoneConfig: s.config, placementStrategy: s.strategy)
    let out: Out
    switch coord.moveFocusedToZone(s.zone_key) {
    case .success(let o): out = Out(found: true, zone_key: o.zoneKey, tile_index: o.tileIndex, rect: o.target)
    case .failure: out = Out(found: false, zone_key: nil, tile_index: nil, rect: nil)
    }
    FileHandle.standardOutput.write(try encoder.encode(out))

default:
    fail("unknown mode '\(mode)' (expected solve/zones/memory/place/strategy/autotiler/movezone)")
}
