# Porting ZoneTilerWM to Native Swift

This document outlines the architectural shift required to move ZoneTilerWM from a Hammerspoon (Lua) script to a standalone native macOS application written in Swift.

## 1. Core Technology Stack

Moving to native Swift means leaving the Hammerspoon sandbox. You will interface directly with macOS system APIs.

| Component | Hammerspoon (Current) | Native Swift (Target) |
| :--- | :--- | :--- |
| **Language** | Lua 5.4 | Swift 6 |
| **Window Control** | `hs.window` (wrapper) | **Accessibility API (AXUIElement)** |
| **Hotkeys** | `hs.hotkey` | **Carbon (RegisterEventHotKey)** or **CGEventTap** |
| **Drawing** | `hs.canvas` | **NSWindow (Overlay) + Core Graphics/SwiftUI** |
| **Configuration** | `config.lua` (executable code) | **JSON/TOML/YAML** + Swift `Codable` |
| **State** | Lua Tables | Swift Actors / Classes |

## 2. Architecture Mapping

The modular structure of ZoneTilerWM translates well to Swift patterns.

### A. The Engine (`WindowManager`)
*   **Current**: `tiler.lua`
*   **Native**: A central `WindowManager` class (likely an Actor to handle concurrency safely).
*   **Responsibility**:
    *   Observe `NSWorkspace` notifications (app launch, termination).
    *   Observe `AXUIElement` notifications (window created, focused, moved).
    *   Maintain the "Source of Truth" for window state.

### B. The Hands (`AXClient`)
*   **Current**: `window_actions.lua`
*   **Native**: A wrapper around the C-based Accessibility API.
*   **Challenge**: The AX API is verbose, untyped, and can be slow.
*   **Implementation**:
    ```swift
    class AXClient {
        func setFrame(_ window: AXUIElement, _ frame: CGRect)
        func getWindowList() -> [AXUIElement]
        func observeEvents(pid: pid_t)
    }
    ```

### C. The Brain (`ZoneCalculator`)
*   **Current**: `zone_calculator.lua`
*   **Native**: Pure Swift logic.
*   **Improvement**: Swift's strong typing (`CGRect`, `CGSize`) will make the math much safer and easier to unit test than Lua tables.

### D. The Interface (`OverlayWindow`)
*   **Current**: `grid_overlay.lua`
*   **Native**: A transparent, click-through `NSWindow` that sits at `CGWindowLevel.floating`.
*   **Drawing**: Use SwiftUI `Path` or Core Graphics for the "Tron" grid lines. This will be significantly more performant and smoother (60/120fps) than Hammerspoon's canvas.

## 3. Key Challenges & Risks

### 1. Permissions (TCC)
*   **Issue**: Native window managers require "Accessibility" permissions in System Settings > Privacy & Security.
*   **UX**: You must implement a checking mechanism on startup to prompt the user if permissions are missing.

### 2. Configuration Complexity
*   **Issue**: `config.lua` is code, allowing logic (e.g., `if screen:name():match("Dell")`).
*   **Native**: Static config files (JSON) can't do logic.
*   **Solution**: You'll need a robust "Rules Engine" in Swift that can parse conditions from the config file (e.g., `{"rule": "name_contains", "value": "Dell", "layout": "4x3"}`).

### 3. "Kinesthetic" Latency
*   **Issue**: Hammerspoon is highly optimized C underneath. A naive Swift implementation using high-level wrappers might introduce lag.
*   **Mitigation**: Use caching for AXUIElements and avoid blocking the main thread with AX calls.

## 4. Implementation Roadmap

### Phase 1: The Skeleton (Proof of Concept)
1.  Create a standard macOS App (Menu Bar only, `LSUIElement = true`).
2.  Implement the **Permissions Check**.
3.  Build a basic **AXClient** that can print the title of the focused window.

### Phase 2: Input & Control
1.  Implement a **Hotkey Manager** (using `Carbon` APIs is standard for global shortcuts).
2.  Connect Hotkeys to AXClient to move the focused window to a hardcoded frame (e.g., Left Half).

### Phase 3: The Logic Port
1.  Port `ZoneCalculator` and `ResizeManager` to Swift.
2.  Implement the `Config` struct and JSON parser.
3.  Connect the logic: Hotkey -> Calculate Frame -> AXClient.setFrame.

### Phase 4: Delight
1.  Implement the **Grid Overlay** using a transparent SwiftUI window.
2.  Add the "Resize Mode" state machine.

## 5. Why do this? (Pros/Cons)

| Pros | Cons |
| :--- | :--- |
| **Performance**: Native code, direct API access. | **Development Time**: High. Swift/AX is verbose. |
| **Distribution**: Can be signed/notarized (outside App Store). | **Config Flexibility**: Losing Lua scripting reduces power for power users. |
| **UI**: Access to full SwiftUI for settings/overlays. | **Maintenance**: You own the whole stack, not just a script. |
| **Stability**: Strong typing prevents runtime nil errors. | |

## Conclusion
Porting is feasible and would result in a higher-quality, more robust product. The biggest hurdle is replacing the dynamic nature of `config.lua` with a static configuration system that is still flexible enough for your needs.
