// LayoutSolver.swift — faithful port of modules/layout_solver.lua.
//
// Solves the window→tile assignment problem with recursive backtracking + branch-and-bound,
// finding the GLOBAL minimum-cost assignment. Traversal order fixes the tie-break deterministically:
//   * windows processed in input order (input order == Z-order/recency at call sites)
//   * at each window, the "skip" branch is explored FIRST, then tiles in array order
//   * a complete assignment replaces the best only on STRICTLY lower cost (`<`), so among equal-cost
//     optima the first-reached leaf wins.
// NOTE: this INTENTIONALLY diverges from the Lua oracle. The Lua (and this port until 2026-06-20) used
// a non-admissible bound (prune on `currentCost >= best.minCost`) which, because the cost function has
// negative rewards, could prune the true optimum — empirically suboptimal on ~14% of fuzzed inputs.
// The admissible bound below (see `minRemaining`) restores optimality. The curated solver golden
// corpus was UNAFFECTED (those 7 scenarios were already in the optimal majority) — divergence from the
// Lua only occurs on inputs outside the corpus, so Lua bit-for-bit parity is given up only there, in
// favor of correctness (see REVIEW §9). All arithmetic is Double.

import Foundation   // FileHandle.standardError — a single diagnostic line when the search is truncated

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
    /// Backtracking node budget. A safety valve against pathological N×M blow-ups; on a real autotile
    /// (n ≤ workingSetMaxCapacity, default 6) it is effectively never hit. Overridable per-call so a test
    /// can force truncation. NOTE: hitting it returns the best COMPLETE assignment found so far — whose
    /// floor is the all-skip leaf (an empty move list), since skip is explored first.
    public static let defaultMaxChecks = 100_000

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

        // Guard the divisors against exactly-zero dimensions (degenerate windows/screens) so a
        // bad input can't produce Inf/NaN — a NaN cost would silently defeat the branch-and-
        // bound pruning below. Real AX frames are always positive, so this substitutes only on
        // zero and leaves every valid computation byte-identical.
        let tileH = tile.rect.h != 0 ? tile.rect.h : 1
        let winH = window.h != 0 ? window.h : 1
        let screenArea = (screen.w * screen.h) != 0 ? (screen.w * screen.h) : 1

        // 1. Geometric penalties.
        let tileAR = tile.rect.w / tileH
        let winAR = window.w / winH
        cost += abs(winAR - tileAR) * weights.aspectRatio

        let tileAreaRatio = (tile.rect.w * tile.rect.h) / screenArea
        let winAreaRatio = (window.w * window.h) / screenArea
        cost += abs(winAreaRatio - tileAreaRatio) * weights.areaRatio

        // 2. Coverage reward, boosted for more-recent windows (lower rank).
        let recencyMult = 1.0 + (1.0 / Double(windowRank))
        cost += tileAreaRatio * weights.coverage * recencyMult

        // 3. Memory bonus — the STRONGEST applicable preference for this zone (most-negative reward).
        // Scans all same-zone prefs rather than breaking on the first, so a lower-ranked EXACT (zone+tile)
        // match isn't shadowed by a higher-ranked zone-only one (memoryExact is far larger than
        // memoryZone, so the exact bonus usually wins even at a worse rank).
        if let memory = window.memory {
            var bonus = 0.0, found = false
            for (i, pref) in memory.enumerated() where pref.zone_key == tile.zone {
                let rank = Double(i + 1)
                let b = (pref.tile_index == tile.idx) ? weights.memoryExact / rank : weights.memoryZone / rank
                if !found || b < bonus { bonus = b; found = true }
            }
            if found { cost += bonus }
        }

        // 4. Small occupancy bias toward earlier tile indices (nil for split-tile ids).
        cost += (tile.idx.numericValue ?? 0) * 10

        return cost
    }

    public static func solve(windows: [WindowSnapshot],
                             tiles: [TileSpec],
                             screen: ZTRect,
                             weights: CostWeights = CostWeights(),
                             maxChecks: Int = defaultMaxChecks) -> [Move] {
        if windows.isEmpty || tiles.isEmpty { return [] }
        let n = windows.count
        let m = tiles.count

        // Pre-compute the N×M cost matrix (window rank = 1-based input index) as one flat,
        // cache-contiguous buffer indexed [i*m + j] — read in the backtracking inner loop.
        var costMatrix = [Double](repeating: 0, count: n * m)
        for i in 0..<n {
            for j in 0..<m {
                costMatrix[i * m + j] = assignmentCost(
                    window: windows[i], tile: tiles[j], screen: screen,
                    windowRank: i + 1, weights: weights)
            }
        }

        // Admissible lower bound on the cost still to come from windows i..n-1: each remaining window
        // contributes at least the cheaper of skipping or its best tile (the overlap constraint is
        // relaxed — assuming any tile is free can only LOWER the bound, so it stays admissible). Without
        // this, the old prune (currentCost >= best.minCost) was UNsound, because the cost function has
        // negative rewards (coverage/memory): a deeper window could reduce the total, so a strictly-
        // better leaf could be pruned. Suffix-summing the per-window minimum restores a true lower bound,
        // so the prune below never discards the optimum.
        var minRemaining = [Double](repeating: 0, count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var cheapest = weights.skipWindow
            for j in 0..<m { cheapest = min(cheapest, costMatrix[i * m + j]) }
            minRemaining[i] = cheapest + minRemaining[i + 1]
        }

        // Assignment is a dense [Int] indexed by window (-1 == skipped) rather than a
        // dictionary: the leaf copy is a flat array copy and the inner-loop set/clear avoids
        // hashing. Semantics are identical (skipped windows are simply left -1).
        final class State {
            var minCost = Double.infinity
            var assignments: [Int]
            var checks = 0
            var truncated = false
            init(n: Int) { assignments = [Int](repeating: -1, count: n) }
        }
        let best = State(n: n)
        var current = [Int](repeating: -1, count: n)
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
            // Branch & bound prune, with the admissible bound (currentCost + best-possible remainder).
            if currentCost + minRemaining[winIdx] >= best.minCost { return }
            best.checks += 1
            if best.checks > maxChecks { best.truncated = true; return }

            // Option A: skip this window (explored first, matching Lua; current stays -1).
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
                recurse(winIdx + 1, currentCost + costMatrix[winIdx * m + t])
                current[winIdx] = -1
                occupied.removeLast()
            }
        }

        recurse(0, 0)

        // Truncation is normally unreachable; surface it (instead of silently dropping windows) so a
        // pathological case is diagnosable in the agent log. One line, no AX cost.
        if best.truncated {
            FileHandle.standardError.write(Data(
                "LayoutSolver: maxChecks (\(maxChecks)) exhausted at n=\(n) m=\(m) — assignment may be sub-optimal/partial\n".utf8))
        }

        // Emit a Move per assigned window (skipped windows excluded); callers sort if needed.
        var moves: [Move] = []
        for w in 0..<n where best.assignments[w] >= 0 {
            let t = best.assignments[w]
            moves.append(Move(windowIndex: w, tileIndex: t, cost: costMatrix[w * m + t]))
        }
        return moves
    }
}
