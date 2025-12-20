# Algorithm Design Document: ZoneTilerWM Auto-Tiling

## 1. Algorithm Overview
The `auto_tiler.lua` module implements a **multi-pass, priority-based packing algorithm** designed to place windows into a pre-defined grid. It balances three competing goals:
1.  **User Intent**: Ensuring the currently focused window gets the "best" spot.
2.  **Memory/Persistence**: Respecting where windows were previously placed.
3.  **Density**: Filling gaps in the grid to avoid "holes".

## 2. Process Flow

### Phase 1: Preparation
- **Input**: List of all standard, visible windows (`hs.window.allWindows()`).
- **Obstacle Mapping**: Windows that are *excluded* from tiling (e.g., config exclusions, non-standard windows) are mapped immediately as "Obstacles". They occupy space but are not moved.

### Phase 2: Execution Passes

#### Pass 0: Focused Window (The Anchor)
- **Goal**: Place the user's primary focus immediately in the center or most relevant zone.
- **Logic**:
    - Identify the Focused Window.
    - Determine "Center Candidates": Either explicitly configured zones (`config.tiler.auto_tile_center_zones`) or geometrically deduced zones (closest to screen center).
    - **Optimization**: If the window is already being cycled (via hotkey), it sticks to its current zone.
    - **Outcome**: The focused window is placed, locked, and marked as `is_bumpable = false`. It cannot be displaced by subsequent passes.

#### Pass 1: Recursive Ranked Memory w/ Ripple
- **Goal**: Restore remaining windows to their last known positions, aggressively resolving conflicts.
- **Logic**:
    - Iterate through "Preference Ranks" (1st choice, 2nd choice... up to 5).
    - For each window `W`, retrieve its preferred Zone `Z` and Tile Index `I` for the current rank.
    - **Conflict Check**: Is `Z:I` occupied?
        - **No**: Place `W` in `Z:I`.
        - **Yes**:
            - **Ripple Logic**: Check if the *current occupant* `O` can be moved to `Z:I+1`.
            - Repeat recursively (`Z:I+1` -> `Z:I+2`) up to `depth=5`.
            - If a chain of moves results in a free slot, execute the chain: `O` moves to `I+1`, `W` takes `I`.
            - **Critical**: Windows marked `is_bumpable=false` (Pass 0) terminate the ripple (cannot be moved).
            - **Zone Overflow**: If the ripple reaches the end of the zone (Tile `N` blocked, `N+1` does not exist), it attempts to overflow into a predefined "Neighbor Zone" (e.g., `h (Left) -> y (Top-Left) -> j (Center)`). This ensures windows "spill" into available holes like the top-left rather than grouping in the center.
    - **Outcome**: Windows are stacked densely (`1, 2, 3`) based on their memory.

#### Pass 1.5: Compaction (Gravity)
- **Goal**: Ensure no gaps exist at the top of zones (e.g., `Tile 2` occupied but `Tile 1` empty).
- **Logic**:
    - Iterate through all zones on the monitor.
    - **Gap Check**: If `Tile 1` is empty AND `Tile 2` is occupied:
        - Move the window from `Tile 2` to `Tile 1`.
    - This provides a "gravity" effect, pulling floating windows up to the primary positions.

#### Pass 2: Greedy Smart Cleanup
- **Goal**: Place any windows that have no memory, were displaced, or are currently in "holes".
- **Logic**:
    - Iterate through all unplaced windows.
    - For each window, execute `smart_placer.find_best_tile(window, occupied_rects)`.
    - **Scoring Function (Fit & Flow)**:
        - **Area Score (40%)**: `CandidateTileArea`. Prioritizes finding a tile that fits the window reasonably well.
        - **Positional Score (60%)**: `ScreenArea * (1.0 - (DistToOrigin / ScreenDiagonal))`. Extremely aggressive bias toward the top-left (0,0) to ensure "y" and "h" zones are filled first.
        - **Base Score**: `(AreaScore * 0.4) + (PositionScore * 0.6)`.
    - **Continuous Penalties**:
        - **Tile Index Penalty**: Decays score by ~10% for each subsequent tile in a zone (prefer `tile 1` over `tile 2`).
        - **Coverage Penalty (Size De-biasing)**: `Score = Score * (1.1 - CoverageRatio)`. This ensures that for a small window, a small tile in the corner scores higher than a massive tile in the center, keeping the grid "open".
        - **Overlap Penalty (Anti-Stacking)**: `Multiplier = 1.0 / (1.0 + (OverlapRatio * 500))`.
            - This is a steep, non-clipping penalty.
            - Even a 1% overlap reduces score significantly (~0.16x).
            - A 100% overlap reduces score to near zero (~0.002x).
            - **Result**: This forces windows to "spread out" into empty gaps even if those gaps are in less "ideal" positions, preventing the "stacking in the corner" bug.
    - **Shadow/Bleed Tolerance**: Overlaps < 1% of tile area are ignored to prevent window shadows or alignment artifacts from triggering fallback behavior.

### Phase 3: Queue Optimization
- **Logic**: Iterate the move queue *backwards*.
- Keep only the **last** move instruction for each unique window ID.
- **Why**: The Ripple logic might move Window A to `Tile 2`, then a later ripple moves it to `Tile 3`. We only want to execute the final jump `start -> 3`, avoiding visual jitter.
- **Global Integration**: `auto_tiler.tile_all_windows` is registered as a reposition callback in `tiler.lua`, ensuring this logic is applied automatically during screen changes or startup restoration.

---

## 3. Critical Evaluation

### Complexity Analysis
- **Time Complexity**:
    - Let `W` be windows, `Z` be zones, `T` be tiles per zone.
    - **Pass 0**: O(Z*T) (Finding best center fit). negligible.
    - **Pass 1 (Ripple)**: O(Rank * W * RecursionDepth).
        - Max Rank = 5.
        - Max Recursion = 5 (Chain).
        - Effectively **O(W)**.
    - **Pass 1.5 (Compaction)**: O(Z). Scans zones once.
    - **Pass 2**: O(W_remaining * Z * T).
        - Checking intersection against all occupied frames.
        - Worst case **O(W^2)** if many windows remain (since occupied list grows).
    - **Overall**: Effectively **O(W^2)** in worst case, but practically very fast for <50 windows.

### Strengths
1.  **Stability**: The "Anchor" concept (Pass 0) ensures the user's focus is never stolen or shifted unexpectedly.
2.  **Density**: The Ripple + Overflow implementation turns a fragile "validity check" algorithm into a robust "insertion sort" style placement.
3.  **Gravity**: The Compaction pass ensures the layout naturally "cleans itself" up by pulling windows into primary slots.
4.  **Visual Smoothness**: Queue optimization eliminates the intermediate states often seen in tiling algorithms.

### Weaknesses / Risks
1.  **Blind Ripple**: The ripple moves valid windows just to make space. If Window B *really* wanted Tile 1 (Rank 1 memory), and Window A bumps it to Tile 2, Window B is now in a "worse" spot. The algorithm assumes density > individual preference preference for equivalent windows.
2.  **Race Conditions**: `hs.window.allWindows()` is a snapshot. If a window closes *during* the calculation (rare in Lua due to single-threaded, but possible via OS delays), the final move command might target a dead window (handled gracefully by `window_actions`, but worth noting).

### Recommendations
1.  **Bi-directional Ripple**: Allow rippling to `I-1` if `I` is wanted and `I-1` is free? (Mitigated partially by Pass 1.5 Compaction).
2.  **Configurable Overflow**: Move the `ZONE_OVERFLOW_MAP` from hardcoded logic to `config.lua` to allow users to define their own flow (e.g. `Right -> Left` or `Center -> Secondary Monitor`).
