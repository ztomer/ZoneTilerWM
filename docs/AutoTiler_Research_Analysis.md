# [IMPLEMENTED] Auto-Tiler Algorithmic Redesign: Research & Analysis

> **Status**: Completed (Dec 2025)
> **Outcome**: The "Cost-Solver" model proposed below was successfully implemented using recursive backtracking (Solver V2).
> **See Also**: [Algorithmic Design](auto-tiling_algorithmic_design.md)

## 1. Analysis of Previous Implementation (Legacy)

The previous `auto_tiler.lua` used a **Multi-Pass Greedy Heuristic** approach.

### The Algorithm
1.  **Pass 0 (Anchor)**: Locks the focused window to a priority zone (Center).
2.  **Pass 1 (Memory + Ripple)**: Iterates through windows by "Memory Rank". If a spot is taken, it triggers a **Blind Ripple**:
    *   *Problem*: It forces the current occupant to the *next* tile (`index + 1`). This is deterministic but content-agnostic. It moves a window without knowing if the new spot is a valid size or aspect ratio for that window.
    *   *Problem*: It works on a "First-Come-First-Serve" basis within the same rank.
3.  **Pass 1.5 (Compaction)**: Pulls windows to fill gaps (Gravity).
4.  **Pass 2 (Smart Cleanup)**: Places leftovers.
    *   *Problem*: Strongly biased (60%) towards **Position** (Top-Left 0,0).
    *   *Problem*: Biased (40%) towards **Area Match**, but ignores **Aspect Ratio**.
    *   *Result*: A wide "Timeline" window might be forced into a tall, skinny "Sidebar" tile just because it's in the top-left corner.

### The Inconsistency
The "inconsistent results" likely stem from the **Blind Ripple**. If Window A takes Window B's spot, Window B is shoved to the right. If Window C then takes Window B's new spot, B is shoved again. Small changes in window ID sorting or timing can result in vastly different layouts.

### The "Suboptimal Targeting"
The "apps target is not very optimize" observation is due to **Smart Placer** favoring *coordinates* over *shape*. It treats all empty tiles as "buckets" and all windows as "water", ignoring that some windows (IDEs, Spreadsheets) are "rocks" that need specific shapes.

---

## 2. Information Inventory

### We Currently Collect:
*   **Last Position**: Where the window *was* last seen (`positions[app][monitor]`).
*   **Frequency Map**: How often a window has been in a specific `zone:tile` (`preferences[app][monitor][zone][tile] -> count`).

### We Do NOT Collect:
*   **Preferred Aspect Ratio**: Does this app usually prefer Wide (>1.5), Tall (<0.8), or Square (~1.0) frames?
*   **Preferred Size**: Does this app typically occupy 50% of the screen or 10%?
*   **Co-occurrence**: "App A is usually tiled with App B".
*   **Rejection History**: "The user immediately moved App A *out* of Zone Z" (Negative reinforcement).

---

## 3. Research: Existing Approaches

### A. Bin Packing (2D)
*   *Concept*: Fit rectangles into a container.
*   *Verdict*: Not applicable. We have *fixed* slots (tiles), not a free canvas.

### B. Stable Marriage Problem (Gale-Shapley)
*   *Concept*: Windows propose to Tiles. Tiles accept the "best" suitor based on heuristic.
*   *Verdict*: Strong contender. It guarantees a "stable" matching where no two entities would rather be with each other than their current partners.

### C. The Assignment Problem (Global Cost Minimization)
*   *Concept*: Construct a Cost Matrix where `C(w, t)` is the "cost" of putting Window `w` in Tile `t`.
*   *Cost Factors*:
    *   Memory Miss (High cost)
    *   Aspect Ratio Mismatch (Medium cost)
    *   Distance from Last Known (Low cost)
    *   Displacement of Locked Window (Infinite cost)
*   *Algorithm*: Hungarian Algorithm (O(n^3)) or Min-Cost-Max-Flow.
*   *Verdict*: The "Gold Standard" for optimality. For N < 20 windows, O(n^3) is negligible (microseconds).

### D. Simulated Annealing / Genetic Algorithms
*   *Verdict*: Overkill. Non-deterministic (bad for muscle memory).

---

## 4. Implemented Solution: The "Cost-Solver" Model

We moved away from **Iterative Rippling** towards **Global Cost Minimization**.

### Data Strategy
We extended tracking to include **Geometric Hints**:
1.  **Mean Aspect Ratio**: Store `Σ(w/h) / count`.
2.  **Mean Area Ratio**: Store `Σ(win_area/screen_area) / count`.

### Algorithm Design (Solver V2)
1.  **Define Cost Function**:
    *   `Cost = (MemoryPenalty) + (ShapePenalty) + (MovementPenalty)`
2.  **Construct Matrix**: Calculate cost for every `Window x Tile` combination.
3.  **Solve**:
    *   Implemented **Recursive Backtracking** to handle spatial exclusivity (overlapping tiles).
    *   Find the configuration that produces the *lowest total unhappiness*.

### Why this is better:
*   **No Blind Ripples**: A window will never bump another window unless the *global* score improves.
*   **Shape Aware**: A wide window will "pay a high price" to sit in a tall tile, so the solver will naturally look for wide tiles.
*   **Deterministic**: Same input + Same weights = Same output.

---

## 5. Plan Execution History

1.  **Extend Memory**: Updated `window_memory.lua` to track Aspect Ratio and Area Ratio stats.
2.  **Implement Solver**: Created `modules/layout_solver.lua`.
    *   Implemented the Cost Function.
    *   Implemented Recursive Backtracking Solver.
3.  **Refactor Auto-Tiler**:
    *   Replaced Pass 1 & 2 with the Solver.
    *   Kept Pass 0 (Anchor) as a pre-solver constraint.

## 6. Testing Strategy

1.  **Unit Tests**: Created `tests/test_layout_solver.lua` and `tests/solver_corpus.lua`.
    *   Tested shape matching (Wide -> Wide).
    *   Tested Memory overrides.
    *   Tested Overlap resolution (Full vs Halves).
2.  **Regression**: Validated that the solver passes a 5-scenario corpus covering edge cases.

