// LayoutSolver.swift — faithful port of modules/layout_solver.lua.
//
// Solves the window→tile assignment problem with recursive backtracking + branch-and-
// bound, minimizing total cost. The traversal order is replicated EXACTLY so tie-breaks
// match the Lua oracle bit-for-bit:
//   * windows processed in input order (input order == Z-order/recency at call sites)
//   * at each window, the "skip" branch is explored FIRST, then tiles in array order
//   * a complete assignment replaces the best only on STRICTLY lower cost (`<`), so the
//     first-reached minimum-cost leaf wins ties.
// All arithmetic is Double, matching Lua's numbers.

/// Tunable cost weights. Defaults mirror the `WEIGHTS` table in layout_solver.lua;
/// config.toml's [tiler.solver_weights] overrides them at the call site.
public struct CostWeights: Equatable {
    public var memoryExact: Double = -2000  // exact memory match (zone + tile)
    public var memoryZone: Double = -500    // correct zone, wrong tile
    public var aspectRatio: Double = 300    // AR mismatch penalty
    public var areaRatio: Double = 200      // size mismatch penalty
    public var movedDist: Double = 1        // (unused by solver core; kept for parity)
    public var skipWindow: Double = 5000    // cost to leave a window unassigned
    public var coverage: Double = -2000     // reward for covering screen real estate

    public init() {}
}

public enum LayoutSolver {
    static let maxChecks = 100_000

    /// One window→tile assignment in the optimal solution.
    public struct Move: Equatable {
        public let windowIndex: Int   // index into the input `windows`
        public let tileIndex: Int     // index into the input `tiles`
        public let cost: Double
    }

    /// Cost of placing `window` (1-based recency `windowRank`) into `tile`.
    /// Direct port of `calculate_assignment_cost` (the second, active definition).
    static func assignmentCost(window: WindowSnapshot,
                               tile: TileSpec,
                               screen: ZTRect,
                               windowRank: Int,
                               weights: CostWeights) -> Double {
        var cost = 0.0

        // 1. Geometric penalties.
        let tileAR = tile.rect.w / tile.rect.h
        let winAR = window.w / window.h
        cost += abs(winAR - tileAR) * weights.aspectRatio

        let tileAreaRatio = (tile.rect.w * tile.rect.h) / (screen.w * screen.h)
        let winAreaRatio = (window.w * window.h) / (screen.w * screen.h)
        cost += abs(winAreaRatio - tileAreaRatio) * weights.areaRatio

        // 2. Coverage reward, boosted for more-recent windows (lower rank).
        let recencyMult = 1.0 + (1.0 / Double(windowRank))
        cost += tileAreaRatio * weights.coverage * recencyMult

        // 3. Memory bonus — best matching preference only.
        if let memory = window.memory {
            for (i, pref) in memory.enumerated() where pref.zone_key == tile.zone {
                let rank = Double(i + 1)
                if pref.tile_index == tile.idx {
                    cost += weights.memoryExact / rank
                } else {
                    cost += weights.memoryZone / rank
                }
                break
            }
        }

        // 4. Small occupancy bias toward earlier tile indices (nil for split-tile ids).
        cost += (tile.idx.numericValue ?? 0) * 10

        return cost
    }

    public static func solve(windows: [WindowSnapshot],
                             tiles: [TileSpec],
                             screen: ZTRect,
                             weights: CostWeights = CostWeights()) -> [Move] {
        if windows.isEmpty || tiles.isEmpty { return [] }
        let n = windows.count
        let m = tiles.count

        // Pre-compute the N×M cost matrix (window rank = 1-based input index).
        var costMatrix = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
        for i in 0..<n {
            for j in 0..<m {
                costMatrix[i][j] = assignmentCost(
                    window: windows[i], tile: tiles[j], screen: screen,
                    windowRank: i + 1, weights: weights)
            }
        }

        final class State {
            var minCost = Double.infinity
            var assignments: [Int: Int] = [:]
            var checks = 0
        }
        let best = State()
        var current: [Int: Int] = [:]
        var occupied: [ZTRect] = []

        func recurse(_ winIdx: Int, _ currentCost: Double) {
            // Base case: all windows decided.
            if winIdx == n {
                if currentCost < best.minCost {
                    best.minCost = currentCost
                    best.assignments = current
                }
                return
            }
            // Branch & bound prune.
            if currentCost >= best.minCost { return }
            best.checks += 1
            if best.checks > maxChecks { return }

            // Option A: skip this window (explored first, matching Lua).
            recurse(winIdx + 1, currentCost + weights.skipWindow)

            // Option B: every non-overlapping tile, in array order.
            for t in 0..<m {
                var overlaps = false
                for r in occupied where rectsOverlap(tiles[t].rect, r) {
                    overlaps = true
                    break
                }
                if overlaps { continue }
                occupied.append(tiles[t].rect)
                current[winIdx] = t
                recurse(winIdx + 1, currentCost + costMatrix[winIdx][t])
                current[winIdx] = nil
                occupied.removeLast()
            }
        }

        recurse(0, 0)

        // The assignment map is order-independent; callers that need a stable order sort it.
        return best.assignments.map { (w, t) in
            Move(windowIndex: w, tileIndex: t, cost: costMatrix[w][t])
        }
    }
}
