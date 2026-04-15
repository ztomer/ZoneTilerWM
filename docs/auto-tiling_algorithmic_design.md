# Auto-Tiler Algorithmic Design

> **Status**: Production
> **Implementation**: `modules/auto_tiler.lua`, `modules/layout_solver.lua`

## 1. Problem Formulation

The Auto-Tiler solves a **Resource Constraint Assignment Problem**.

Given:
*   $W$: A set of $N$ windows needing placement.
*   $T$: A set of $M$ potential layout tiles on the screen (defined by the user's grid).
*   $C(w, t)$: A cost function quantifying the "unhappiness" of placing window $w$ in tile $t$.

The objective is to find an injective mapping $f: W' \to T$ (where $W' \subseteq W$) that minimizes the **Total Global Cost**:

$$ \text{minimize} \sum_{w \in W'} C(w, f(w)) + \text{Penalty}_{skip} \cdot (|W| - |W'|) $$

**Constraints:**
1.  **Spatial Exclusivity**: If tile $t_a$ and tile $t_b$ geometrically intersect, they cannot both be part of the solution set.
    $$ \forall w_i, w_j \in W': \text{Intersection}(f(w_i), f(w_j)) = \emptyset $$
2.  **Uniqueness**: A tile can hold at most one window.
3.  **Completeness**: The solver must attempt to place every window, incurring a heavy penalty for any window left unassigned ($W \setminus W'$).

---

## 2. System Architecture

The tiling process executes in two deterministic passes to balance user intent with global optimality.

### Phase 1: The Anchor (Hard Constraint)
The **Focused Window** is the "Anchor" of the system. It is processed first to ensure the user's immediate context is preserved.
1.  The system identifies the optimal zone for the focused window (based on simple geometric centering or cycling logic).
2.  This selected tile is marked as **Occupied**.
3.  This occupancy becomes an immutable hard constraint for Phase 2.

### Phase 2: The Global Solver
All remaining windows are passed to the solver. The solver considers the entire monitor's layout definition and finds the configuration that fits the remaining windows best around the Anchor.

---

## 3. The Solver Algorithm: Recursive Backtracking

We employ a **Depth-First Search (DFS) with Branch & Bound** to explore the state space.

**Why Backtracking?**
Classic assignment algorithms like the *Hungarian Algorithm* cannot be used because our "resources" (tiles) are not independent. A generic grid often defines overlapping regions (e.g., a "Left Half" tile and a "Left Third" tile occupy the same space). Selecting one invalidates the other. Recursive backtracking naturally handles these complex dependencies.

### Complexity Analysis
*   **Worst Case**: $O(M^N)$, where $M$ is the number of tiles and $N$ is the number of windows.
*   **Practicality**: Since $N$ is typically small (2-8 windows), the state space is manageable ($< 10^5$ nodes).
*   **Pruning**: We maintain a global `min_total_cost`. Any branch whose partial cost exceeds this value is immediately pruned, significantly reducing the effective search space.

### Pseudocode Implementation

```lua
-- Global State
MinCost = Infinity
BestAssignment = {}

function Solve(windows, tiles)
    CostMatrix = PreCalculateCosts(windows, tiles)
    Occupied = { AnchorTile } -- Initial constraint from Phase 1
    Recurse(window_idx=1, current_cost=0, current_assignment={}, occupied)
    return BestAssignment
end

function Recurse(w_idx, current_cost, assignment, occupied)
    -- Branch & Bound Pruning
    if current_cost >= MinCost then return end

    -- Base Case: All windows processed
    if w_idx > Count(windows) then
        MinCost = current_cost
        BestAssignment = Clone(assignment)
        return
    end

    -- Branch A: The "Skip" Option (Soft Constraint)
    -- Attempt to solve the rest of the problem without placing this window.
    Recurse(w_idx + 1, current_cost + PENALTY_SKIP, assignment, occupied)

    -- Branch B: Attempt Assignments
    for t_idx, tile in tiles do
        if Not Intersects(tile, occupied) then
            -- 1. Modify State
            Add(assignment, windows[w_idx] -> tile)
            Add(occupied, tile)

            -- 2. Recurse
            Recurse(w_idx + 1, current_cost + CostMatrix[w_idx][t_idx], assignment, occupied)

            -- 3. Backtrack (Restore State)
            Remove(assignment, windows[w_idx])
            Remove(occupied, tile)
        end
    end
end
```

---

## 4. The Cost Function (Optimization Criteria)

The quality of the layout depends entirely on the detailed construction of the cost matrix $C(w, t)$.
Lower Cost = Higher Utility.

The total cost is a weighted sum of five key heuristics:

$$ C(w, t) = \alpha C_{mem} + \beta C_{geo} + \gamma C_{cov} + \delta C_{stab} $$

### 1. Persistence ($C_{mem}$)
*   **Weight**: Extremely High (-2000)
*   **Goal**: Ensure muscle memory.
*   **Logic**: If the window memory database records that the user previously placed Window $A$ in Tile $T$, the cost is massively reduced.
    *   *Exact Match*: Best score.
    *   *Zone Match*: Good score (e.g., window was in "Left Side", accepts "Left Half" or "Left Third").

### 2. Geometric Fit ($C_{geo}$)
*   **Weight**: High (500)
*   **Goal**: Content-Type awareness.
*   **Logic**: Compares the Aspect Ratio (AR) of the window contents to the tile.
    *   $$ \text{Cost} = | \frac{W_w}{W_h} - \frac{T_w}{T_h} | $$
    *   A "Wide" window (e.g., Video Player, Diff View) incurs high cost in a "Tall" tile (Sidebar).
    *   A "Tall" window (e.g., Chat, Mobile Sim) incurs high cost in a "Wide" tile.

### 3. Screen Coverage ($C_{cov}$)
*   **Weight**: High (-2000, scaled by area)
*   **Goal**: Maximize screen real estate usage.
*   **Logic**:
    *   $$ \text{Cost} = -1 \times (\frac{T_{area}}{Screen_{area}}) $$
    *   Larger tiles provide a larger "discount".
    *   This forces the solver to fill the "Main" (large) slots first before resorting to "Corner" (small) slots.
    *   *Recency Scaling*: The most recently focused windows get a multiplier on this discount, ensuring active tasks get the biggest monitor areas.

### 4. Stability ($C_{stab}$)
*   **Weight**: Low (1)
*   **Goal**: Eliminate jitter.
*   **Logic**: A negligible penalty proportional to the distance between the window's *current* position and the *proposed* tile. This serves as a tie-breaker: if two layouts are otherwise identical, the one requiring less movement is chosen.

### 5. Completeness (Penalty)
*   **Weight**: Massive (5000)
*   **Goal**: Minimize unassigned windows.
*   **Logic**: The "Skip Window" branch incurs this fixed penalty. This ensures the solver essentially operates in "Cram Mode"—it will accept very poor geometric fits if the alternative is not tiling the window at all.

---

## 5. Testing & Validation

The algorithm is validated through a dedicated test suite ensuring stability across edge cases.

*   **Unit Tests**: `tests/test_layout_solver.lua` validates the mathematics of the cost function (e.g., verifying that a Wide Window indeed gets a higher cost in a Tall Tile).
*   **Solver Corpus**: `tests/solver_corpus.lua` contains a set of "Golden Scenarios" (e.g., "The Coder Layout", "The Trader Layout"). The solver is run against these inputs to regression-test that it produces the expected optimal layout every time.
