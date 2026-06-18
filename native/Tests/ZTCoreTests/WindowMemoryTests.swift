// WindowMemoryTests — behavioral spec for the WindowMemory port. Parity against the Lua
// implementation is covered by tools/diff_memory.sh; these assert the intended semantics
// directly (running means, ranking order, exclusion, debounce, save/load round-trip).

import XCTest
@testable import ZTCore

final class WindowMemoryTests: XCTestCase {

    private func learn(_ wm: WindowMemory, id: Int, app: String, monitor: String,
                       zone: String, tile: Int, w: Double, h: Double,
                       screenW: Double = 1920, screenH: Double = 1080) {
        wm.positionWindow(windowId: id, app: app, monitor: monitor, zone: zone, tile: .int(tile),
                          winW: w, winH: h, screenW: screenW, screenH: screenH)
        wm.flush(windowId: id)
    }

    func testRecencyDecayReordersRanking() {
        // j is used more (count 10) but long ago; k is used less (5) but recently.
        let wm = WindowMemory()
        wm.load(WindowMemory.SaveData(positions: [], preferences: [
            .init(app_name: "A", monitor_id: "1", zone_key: "j", tile_index: .int(1),
                  data: .init(count: 10, mean_ar: 0, mean_area: 0, last_seen: 1_000)),
            .init(app_name: "A", monitor_id: "1", zone_key: "k", tile_index: .int(1),
                  data: .init(count: 5, mean_ar: 0, mean_area: 0, last_seen: 100_000)),
        ]))
        // No `now`: pure count order → j first (matches the Lua / diff oracle behavior).
        XCTAssertEqual(wm.rankedPreferences(app: "A", monitor: "1").first?.zoneKey, "j")
        // With `now` + a short half-life: the stale j decays below the recent k.
        let recent = wm.rankedPreferences(app: "A", monitor: "1", now: 100_000, halfLifeSec: 3_600)
        XCTAssertEqual(recent.first?.zoneKey, "k")
        XCTAssertEqual(recent.first?.count, 5)   // raw count is preserved; only the weight decays
    }

    func testClockStampsLastSeen() {
        let wm = WindowMemory(clock: { 4_242 })
        learn(wm, id: 1, app: "Zen", monitor: "1", zone: "j", tile: 1, w: 800, h: 600)
        XCTAssertEqual(wm.save().preferences.first?.data.last_seen, 4_242)
    }

    func testRunningMeanAndCount() {
        let wm = WindowMemory()
        // Two learns of the same slot on a 1920x1080 screen.
        // AR: 2.0 then 1.0 -> mean 1.5.
        // area: (1920*960)/(1920*1080)=8/9, then (960*960)/(1920*1080)=4/9 -> mean (8/9+4/9)/2 = 2/3.
        learn(wm, id: 1, app: "A", monitor: "M", zone: "h", tile: 1, w: 1920, h: 960)   // AR 2.0
        learn(wm, id: 1, app: "A", monitor: "M", zone: "h", tile: 1, w: 960, h: 960)    // AR 1.0
        let ranked = wm.rankedPreferences(app: "A", monitor: "M")
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].count, 2)
        XCTAssertEqual(ranked[0].meanAR, 1.5, accuracy: 1e-9)
        XCTAssertEqual(ranked[0].meanArea, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testRankingOrderAndTieBreak() {
        let wm = WindowMemory()
        // h:1 used 3x, k:1 used once, j:2 used once. Ties (k vs j, both count 1) break by zone asc.
        for _ in 0..<3 { learn(wm, id: 1, app: "A", monitor: "M", zone: "h", tile: 1, w: 800, h: 600) }
        learn(wm, id: 2, app: "A", monitor: "M", zone: "k", tile: 1, w: 800, h: 600)
        learn(wm, id: 3, app: "A", monitor: "M", zone: "j", tile: 2, w: 800, h: 600)
        let ranked = wm.rankedPreferences(app: "A", monitor: "M")
        XCTAssertEqual(ranked.map { $0.zoneKey }, ["h", "j", "k"])  // count desc, then zone asc
        XCTAssertEqual(wm.preferredZone(app: "A", monitor: "M"), "h")
        XCTAssertEqual(wm.preferredTile(app: "A", monitor: "M", zone: "h"), .int(1))
    }

    func testExcludedAppNotLearned() {
        let wm = WindowMemory(excludedApps: ["Secret"])
        learn(wm, id: 1, app: "Secret", monitor: "M", zone: "h", tile: 1, w: 800, h: 600)
        XCTAssertTrue(wm.rankedPreferences(app: "Secret", monitor: "M").isEmpty)
        XCTAssertNil(wm.rememberedPosition(app: "Secret", monitor: "M"))
    }

    func testDebounceCancelsIntermediatePositions() {
        let wm = WindowMemory()
        // Same window repositioned twice before settling: only the last should be learned.
        wm.positionWindow(windowId: 1, app: "A", monitor: "M", zone: "h", tile: .int(1),
                          winW: 800, winH: 600, screenW: 1920, screenH: 1080)
        wm.positionWindow(windowId: 1, app: "A", monitor: "M", zone: "k", tile: .int(2),
                          winW: 800, winH: 600, screenW: 1920, screenH: 1080)
        wm.flushAll()
        let ranked = wm.rankedPreferences(app: "A", monitor: "M")
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].zoneKey, "k")
        XCTAssertEqual(ranked[0].tile, .int(2))
        // The immediate "last position" still reflects the final placement.
        XCTAssertEqual(wm.rememberedPosition(app: "A", monitor: "M")?.zone, "k")
    }

    func testSaveLoadRoundTrip() {
        let wm = WindowMemory()
        learn(wm, id: 1, app: "A", monitor: "M", zone: "h", tile: 1, w: 1000, h: 500)
        learn(wm, id: 2, app: "B", monitor: "M", zone: "j", tile: 2, w: 800, h: 800)
        let data = wm.save()

        let restored = WindowMemory()
        restored.load(data)
        XCTAssertEqual(restored.save(), data)
        XCTAssertEqual(restored.rememberedPosition(app: "A", monitor: "M")?.zone, "h")
        XCTAssertEqual(restored.rankedPreferences(app: "B", monitor: "M").first?.tile, .int(2))
    }

    func testDailyHistogramCountsAndRoundTrips() {
        // Two placements on day 20000 (epoch 20000*86400), one on day 20001.
        var now = 20_000 * 86_400
        let wm = WindowMemory(clock: { now })
        learn(wm, id: 1, app: "A", monitor: "M", zone: "h", tile: 1, w: 800, h: 600)
        learn(wm, id: 2, app: "B", monitor: "M", zone: "j", tile: 1, w: 800, h: 600)
        now = 20_001 * 86_400
        learn(wm, id: 3, app: "A", monitor: "M", zone: "k", tile: 1, w: 800, h: 600)

        XCTAssertEqual(wm.dailyCounts().map { $0.count }, [2, 1])         // ascending by day
        XCTAssertEqual(wm.dailyCounts().map { $0.day }, [20_000, 20_001])

        let restored = WindowMemory()
        restored.load(wm.save())
        XCTAssertEqual(restored.dailyCounts().map { $0.count }, [2, 1])   // survives save/load
    }

    func testLegacyDataHasEmptyDailyHistogram() {
        // A SaveData written before the `daily` field (decoded from JSON without it) loads fine.
        let json = #"{"positions":[],"preferences":[]}"#.data(using: .utf8)!
        let data = try! JSONDecoder().decode(WindowMemory.SaveData.self, from: json)
        XCTAssertTrue(data.daily.isEmpty)
        let wm = WindowMemory(); wm.load(data)
        XCTAssertTrue(wm.dailyCounts().isEmpty)
    }
}
