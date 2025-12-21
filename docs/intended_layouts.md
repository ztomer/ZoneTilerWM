# Intended Layouts (Golden Scenarios)

This document defines the "Ideal" layout behaviors for various common scenarios. These serve as the "Truth" for tuning the Auto-Tiler algorithm.

## Principles
1.  **Primary Focus**: The most recent/focused window gets the "Prime" slot (Center/Largest).
2.  **Maximization**: Use as much screen real estate as possible.
3.  **Hierarchy**: Secondary windows fill remaining gaps ordered by recency.
4.  **Shape Respect**: Don't force wide windows into thin columns if avoided.

---

## 1. Single Window Scenarios
*Reference Layout: 4x3 (Columns: A, B, C, D)*
*Reference Layout: 2x2 (Tyical Laptop)*

| Scenario | Window Type | Ideal Tile (4x3) | Ideal Tile (2x2) | Reason |
| :--- | :--- | :--- | :--- | :--- |
| **Solo Work** | Any | **Zone 'j' (Center)** | **Full Screen** | Maximum focus. "J" is the defined center. |
| **Solo Wide** | Video Player | **Zone 'j' (Center)** | **Top/Bottom** | Matches aspect ratio better than a side column. |

---

## 2. Duo Scenarios (2 Windows)

| Scenario | W1 (Focus) | W2 (Bg) | Ideal Assignment (4x3) | Reason |
| :--- | :--- | :--- | :--- | :--- |
| **Split** | Generic | Generic | **J (Center)** + **H (Left)** | Center is Prime. Left is secondary. Together they cover ~75% screen. |
| **Crammed** | Generic | Generic | **Left Half** + **Right Half** | *Alternative*: If user prefers 100% coverage over Center focus. |
| **Chat Mode** | Browser | Chat (Tall) | **J (Center)** + **I (Right Col)** | Browser gets main stage. Chat gets a sidebar. |

---

## 3. Trio Scenarios (3 Windows)

| Scenario | Ideal Assignment (4x3) | Coverage |
| :--- | :--- | :--- |
| **3 Equal** | **Left (H) + Center (J) + Right (K)** | ~Fully covers screen with overlaps? Or 3 distinct columns? |
| **3 Columns** | **A (Col 1) + B+C (Center) + D (Col 4)** | 100% Coverage, no overlap. |

---

## 4. Workflow-Specific Scenarios (The "Giant Pile")

### A. The "Coder" (3 Windows)
*   **Windows**:
    1.  IDE (Main Focus)
    2.  Browser (Documentation)
    3.  Terminal (Logs)
*   **Ideal Layout (4x3)**:
    *   IDE -> **Left (H)** or **Center (J)** (Large)
    *   Browser -> **Right Top (I)**
    *   Terminal -> **Right Bottom (K)** or **","**
    *   *Goal*: Main work area + Stacked sidebars.

### B. The "Comparison" (2 Windows)
*   **Windows**: 2x Identical Browsers / Docs.
*   **Ideal Layout**:
    *   **Left Half** + **Right Half** (Split Screen).
    *   *Constraint*: Must not pick "Center" + "Left". Symmetry is key.

### C. The "Trader" / "Monitoring" (4-6 Windows)
*   **Windows**: 4x Charts/Terminals.
*   **Ideal Layout**:
    *   **2x2 Grid** (Quadrants: Y, U, N, M or similar).
    *   *Constraint*: No overlaps. Maximize visibility of all.

### D. The "Writer" (3 Windows)
*   **Windows**:
    1.  Scrivener/Obsidian (Focus)
    2.  Browser (Research)
    3.  Spotify/Music (Background)
*   **Ideal Layout**:
    *   Writer -> **Center (J)**
    *   Browser -> **Left (H)**
    *   Music -> **Right Corner** (Smallest slot available)

### E. The "Presenter" (2 Windows)
*   **Windows**:
    1.  Keynote/Slides (Presentation)
    2.  Notes (Text)
*   **Ideal Layout**:
    *   Slides -> **Top/Center** (Large)
    *   Notes -> **Bottom/Side** (Small)

---

## 5. Shape-Driven Scenarios

### F. Ultrawide Logic (21:9)
*   **1 Window**: Center 50% (Not Full Screen).
*   **2 Windows**: Left Center 40% + Right Center 40%? Or 50/50 Split.
*   **3 Windows**: Left (33%) + Center (33%) + Right (33%).

### G. Vertical Monitor (9:16)
*   **1 Window**: Top Half (Ergonomics) or Full.
*   **2 Windows**: Top Half + Bottom Half (Stacked).
*   **3 Windows**: Top Third + Mid Third + Bot Third.

---

## 6. Edge Cases & Stress Tests

| ID | Description | Ideal Outcome |
| :--- | :--- | :--- |
| **Edge-1** | **Overload**: 10 Windows on 1 Screen. | Fill every tile (1-9). Skip least recent windows. |
| **Edge-2** | **Tiny**: 1 Tiny Window (100x100). | Assign to smallest available tile (don't waste huge slot). |
| **Edge-3** | **Huge**: 1 Huge Window (Larger than screen). | Assign to Full Screen (shrink to fit). |
| **Edge-4** | **Mixed Set**: 1 Vertical, 1 Horizontal, 1 Square. | Map to Tall, Wide, Square tiles respectively. |

---

## Test Cases to Implement
Run these against the solver to verify "Golden" behavior.

1.  **The "Researcher"**: 1 Main Browser, 1 PDF Reference, 1 Notes App.
    *   *Expect*: Browser -> Main, PDF -> Side, Notes -> Side.
2.  **The "Monitoring"**: 4 Terminal Windows.
    *   *Expect*: 2x2 Grid or 4x1 Columns.
3.  **The "Movie"**: 1 Video Player (Ultra Wide), 1 Chat.
    *   *Expect*: Video -> Top/Bottom (Wide) or Center. Chat -> Side.
