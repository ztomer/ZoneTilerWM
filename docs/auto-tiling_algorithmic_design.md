# Auto-Tiler Algorithmic Design: The Global Cost-Solver

> **Status**: Production (V2)
> **Implementation**: `modules/auto_tiler.lua`, `modules/layout_solver.lua`

## 1. Executive Summary

The **Auto-Tiler V2** abandons the traditional "Iterative Greedy" approach (placing one window at a time based on immediate heuristics) in favor of a **Global Cost-Minimization Solver**.

It formulates window management as a **Weighted Assignment Problem** with **Spatial Constraints**:
> *"Given N windows and M overlapping tiles, find the assignment configuration that produces the minimum total 'unhappiness' (Cost)."*

This approach ensures stable, deterministic, and content-aware layouts, solving complex edge cases like "Wide vs Tall" windows and overlapping grid definitions that previous heuristics failed to handle.

---

## 2. The Algorithm: Multi-Pass Architecture

The tiling process is divided into two distinct passes to balance user intent (Focus) with global optimality (Solver).

### Pass 0: The Anchor (User Intent)
**Objective**: Guarantee that the user's primary focus is respected immediately.

1.  **Selection**: Identify the **Focused Window**.
2.  **Targeting**:
    *   If the window has never been auto-tiled before: Assign to the **Primary Center Zone** (usually `j` or `center`).
    *   If previously auto-tiled: Cycle through the available tiles in that zone (Cycle 1 -> Cycle 2 -> ...).
3.  **Constraint Generation**: The selected tile is marked as **Occupied**. This becomes an immutable hard constraint for the subsequent solver.

### Pass 1: The Global Solver (Optimality)
**Objective**: Arrange all remaining windows around the Anchor to minimize global cost.

1.  **Filter**: Gather all non-minimized, standard windows on the screen (excluding the Anchor).
2.  **Map**: Identify all available tiles from the screen's layout (e.g., "Left Half", "Left Third", "Top-Left Quarter").
3.  **Solve**: Execute the **Recursive Backtracking Solver** to find the optimal assignment.

---

## 3. The Solver Core (Recursive Backtracking)

We use recursive backtracking instead of the Hungarian Algorithm because our "slots" (tiles) are not independent. They have **Spatial Exclusivity**:
*   *Example*: Assigning a window to "Left Half" implicitly destroys "Left Third" and "Top-Left Quarter" because they physically overlap.

### Pseudocode Representation

```lua
function solve(windows, tiles)
    State = { min_total_cost = Infinity, best_assignment = {} }
    recurse(window_index=1, current_cost=0, occupied_rects={Anchor})
    return State.best_assignment
end

function recurse(w_idx, cost, occupied)
    -- 1. Pruning (Branch & Bound)
    if cost >= State.min_total_cost then return end

    -- 2. Base Case (Solution Found)
    if w_idx > #windows then
        State.min_total_cost = cost
        State.best_assignment = current_path
        return
    end

    -- 3. Branch A: The "Skip" Option (Pigeonhole Principal)
    -- If no tiles fit, we accept a heavy penalty to leave the window floating.
    recurse(w_idx+1, cost + PENALTY_SKIP, occupied)

    -- 4. Branch B: Attempt Assignments
    for Tile T in tiles do
        if not intersects(T, occupied) then
            local move_cost = calculate_cost(Window[w_idx], T)
            recurse(w_idx+1, cost + move_cost, occupied + T)
        end
    end
end
```

---

## 4. The Cost Function (The "Brain")

The "Intelligence" of the tiler lies entirely in how it calculates the cost of putting Window $W$ into Tile $T$.
Lower Cost = Better Fit.

$$ Cost = (W_{Mem} \cdot -2000) + (W_{AR} \cdot 500) + (W_{Area} \cdot 200) + (W_{Cov} \cdot -2000) + (W_{Idx} \cdot 10) $$

### Cost Factors Breakdown

| Factor | Weight | Purpose | Logic |
| :--- | :--- | :--- | :--- |
| **Memory Match** | **-2000** | **Persistence** | If the user previously put this app in this specific tile, heavily reward putting it back there. Dominates all other factors. |
| **Zone Match** | **-500** | **Flexibility** | If exact tile isn't available, prefer the same *general zone* (e.g., Left side) over a random spot. |
| **Coverage** | **-2000** | **Efficiency** | Reward occupying screen space. Larger tiles get larger rewards, encouraging the solver to use "Main" slots before "tiny" corners. Scaled by **Recency**: Recent windows want bigger slots. |
| **Aspect Ratio ($\Delta AR$)** | **500** | **Content-Aware** | Penalty for shape mismatch. $|W_{ar} - T_{ar}|$. Prevents wide windows (Terminal) from going into tall slots (Sidebar). |
| **Area Difference ($\Delta Area$)** | **200** | **Fit** | Penalty for size mismatch. Prevents tiny windows (Calculator) from taking full-screen slots. |
| **Skip Window** | **5000** | **Completeness** | Massive penalty for failing to place a window. Forces the solver to "cram" windows in even if the fit is poor, rather than leaving them untiled. |
| **Movement** | **1** | **Stability** | Tiny penalty for moving a window far from its current position. Acts as a tie-breaker to prevent pointless shuffling. |

---

## 5. Key Advantages over Heuristics

### 1. Spatial Correctness (The "Overlap" Problem)
*   **Old Way**: Pass 1 might put App A in "Left Half". Pass 2 might put App B in "Left Third". Result: Messy overlap.
*   **New Way**: The solver knows that "Left Half" and "Left Third" intersect. If Branch A picks "Left Half", Branch B *cannot* pick "Left Third". It finds a combination of non-overlapping tiles (e.g., "Left Half" + "Right Half") that minimizes cost.

### 2. Intelligent "Cramming"
*   **Scenario**: 5 Windows, 4 Slots.
*   The solver will mathematically determine which window is the "least important" (lowest Memory/Size score) and choose to **Skip** that one, while successfully tiling the other 4. Heuristics would often fail completely or stack them randomly.

### 3. Aspect Ratio Sensitivity
*   **Scenario**: A vertical implementation plan (Tall) and a wide code diff (Wide).
*   The solver compares specific `w/h` ratios. It "costs more" to put the diff in a vertical slot than the plan. The global minimum naturally swaps them to their ideal orientations.

---

## 6. Future Extensibility

The Cost Matrix design is easily extensible. We can verify new behaviors simply by adding terms to the cost function:

*   **Co-occurrence**: Add a cost reduction if App A and App B are placed in adjacent zones.
*   **Color Matching**: Add a tiny cost for placing dark-mode apps next to light-mode apps (aesthetic).
*   **Frequency Heatmap**: Reward placing frequently used apps in "easy to reach" zones (center coverage).

---

## 7. Testing & Validation

The algorithm is validated through a dedicated test suite ensuring stability across edge cases.

*   **Unit Tests**: `tests/test_layout_solver.lua` validates the mathematics of the cost function (e.g., verifying that a Wide Window indeed gets a higher cost in a Tall Tile).
*   **Solver Corpus**: `tests/solver_corpus.lua` contains a set of "Golden Scenarios" (e.g., "The Coder Layout", "The Trader Layout"). The solver is run against these inputs to regression-test that it produces the expected optimal layout every time.
