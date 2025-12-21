# Algorithm Design Document: ZoneTilerWM Auto-Tiler V2 (Cost-Based Solver)

## 1. Overview
The **Auto-Tiler V2** abandons the previous "Multi-Pass Heuristic" (Pass 0-2) in favor of a **Global Cost-Minimization Solver**. It formulates the tiling problem as an **Assignment Problem** with constraints, solved via **Recursive Backtracking**.

The goal is to assign $N$ windows to $M$ available tiles such that the **Total Global Cost** is minimized, subject to **Spatial Exclusivity Constraints**.

---

## 2. Process Flow

### Phase 1: Preparation (Anchors & Candidates)
1.  **Anchor the Focused Window**:
    *   The focused window is processed first (Pass 0). It is assigned to its preferred or cycled center zone.
    *   This tile becomes a hard constraint (Occupied) for the subsequent solver pass.
2.  **Filter Candidates**:
    *   Remaining windows are collected.
    *   All defined tiles on the monitor are collected as "Available Slots".

### Phase 2: Global Solver (Recursive Backtracking)
The solver recursively attempts to assign the next unassigned window to an available tile.

**Algorithm:**
```lua
function solve(windows, tiles)
    BestSolution = { cost = Infinity }
    recurse(window_index=1, current_cost=0, occupied_rects={Anchor})
end

function recurse(w_idx, cost, occupied)
    if cost >= BestSolution.cost then return end -- Pruning
    if w_idx > #windows then
        BestSolution = current_assignment -- Found better solution
        return
    end

    -- Option A: Skip Window (Penalty: 5000)
    recurse(w_idx+1, cost + 5000, occupied)

    -- Option B: Assign to Tile T
    for Tile T in AvailableTiles:
        if NOT intersects(T, occupied):
            recurse(w_idx+1, cost + Cost(W, T), occupied + T)
```

**Why Backtracking?**
*   Unlike the **Hungarian Algorithm** (which assumes independent slots), our tiles can overlap (e.g., "Left Half" overlaps "Left Third").
*   Backtracking naturally handles this **Spatial Exclusivity**: Choosing "Left Half" simply disables branches where "Left Third" is chosen.
*   Since $N$ (windows) is small (typically <10), this approach finds the **Exhaustive Global Optimum** in milliseconds.

---

## 3. Cost Function

The cost of assigning Window $W$ to Tile $T$ is a weighted sum:

$$ Cost = (W_{AR} \cdot \Delta AR) + (W_{Area} \cdot \Delta Area) + (W_{Mem} \cdot Match) + (W_{Idx} \cdot Index) $$

| Factor | Weight | Description |
| :--- | :--- | :--- |
| **Memory Match** | **-2000** | Huge bonus if $W$ was previously in this exact Zone/Tile. Dominates all other factors. |
| **Zone Match** | **-500** | Bonus if $W$ was in this Zone (but different tile index). |
| **Aspect Ratio ($\Delta AR$)** | **500** | Penalty for squashing a wide window into a tall tile (e.g. $|\frac{W_w}{W_h} - \frac{T_w}{T_h}|$). |
| **Area Difference ($\Delta Area$)** | **200** | Penalty for putting a large window in a tiny tile (normalized to screen size). |
| **Tile Index** | **10** | Tiny penalty for higher indices (prefer Tile 1 over Tile 2). |
| **Movement** | **1** | Negligible penalty for distance from current position (prevents random shuffling of identical windows). |
| **Skip Window** | **5000** | Massive penalty for failing to place a window. Ensures the solver "crams" as many windows as possible before giving up. |

---

## 4. Key Behaviors

### 1. Spatial Exclusivity (The "Overlap" Fix)
Typical grid layouts have overlapping definitions (e.g., specific workflows vs generic halves).
*   **Old Behavior**: Greedy heuristic would put App A in "Left Half" and App B in "Left Third", causing visual overlap.
*   **New Behavior**: Solver sees that choosing "Left Half" makes "Left Third" invalid (intersecting). It forces the next window to "Right Half" or another non-overlapping zone.

### 2. Cramming (The "Pigeonhole" Logic)
If there are 5 windows and only 4 slots:
*   The solver minimizes total cost, meaning it will drop the window that incurs the *least* penalty to drop (or preserves the highest value placements for the other 4).
*   It effectively prioritizes "Important" windows (those with strong Memory scores) and sacrifices generic windows.

### 3. Shape Matching
*   If a user opens a Video Player (Wide) and a Chat App (Tall):
*   The solver automatically assigns Video -> Top/Bottom (Wide) and Chat -> Left/Right (Tall) to minimize AR penalties.
