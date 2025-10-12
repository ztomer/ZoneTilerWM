# Copilot Instructions for ZoneTilerWM

This document provides essential guidance for an AI agent working on the ZoneTilerWM codebase. Understanding these concepts is crucial for making effective contributions.

## 1. Big Picture: A Modular Hammerspoon Window Manager

This project is a tiling window manager for macOS built entirely in **Lua** on the **Hammerspoon** framework. It is not a standalone application but a Hammerspoon configuration that lives in `~/.hammerspoon/`.

The core design is modular, with a central configuration file (`config.lua`) driving the behavior of various components located in the `modules/` directory.

### Core Architectural Flow:

1.  **Entry Point (`init.lua`):** This is the main script that Hammerspoon loads. It requires `config.lua` and initializes the primary modules like `tiler.lua`, `app_switcher.lua`, and `window_memory.lua`.
2.  **Central Configuration (`config.lua`):** This is the most important file for an agent to understand. **Nearly all user-facing behavior is defined here.** This includes:
    *   Keybindings (`config.keys`).
    *   Grid layouts for different screen sizes (`config.tiler.grids`, `config.tiler.layouts`).
    *   Application-specific hotkeys and behaviors (`config.appCuts`, `config.app_switcher`).
    *   Feature toggles and parameters for all modules (e.g., `config.tiler.debug`, `config.window_memory.enabled`).
3.  **Orchestrator (`modules/tiler.lua`):** This module is the heart of the window manager. It initializes all other tiling-related sub-modules, binds hotkeys for window manipulation, and sets up watchers for window and screen events (`handle_window_created`, `handle_screen_change`).
4.  **Module Responsibilities:**
    *   `monitor_manager.lua`: Provides stable identifiers for monitors, which is critical for multi-monitor support.
    *   `zone_calculator.lua`: Translates abstract grid definitions from `config.lua` (e.g., `"a1:b2"`) into concrete pixel coordinates (`hs.geometry`) for the current screen.
    *   `window_state_manager.lua`: Tracks which window is in which "tile" (a specific rectangle within a zone).
    *   `window_actions.lua`: Contains the fundamental functions to move and resize windows to calculated tiles.
    *   `placement_strategy.lua`: Decides which tile to use when a zone has multiple options (e.g., cycling through `{"a1:a2", "a1", "a1:b2"}`).
    *   `window_memory.lua`: Persists and recalls window positions for specific applications, overriding default placement logic.

## 2. Developer Workflow

*   **Editing:** The project is a live Hammerspoon configuration. Changes to `.lua` files are applied by reloading the Hammerspoon config.
*   **Reloading:** A hotkey is configured for rapid iteration: `Shift+Ctrl+Cmd+R`. This is the primary way to apply changes.
*   **Debugging:**
    *   Enable debug logging by setting `config.tiler.debug = true` in `config.lua`.
    *   Logs are printed to the **Hammerspoon Console**. This is the main place to look for errors and debug output.
    *   The `tiler.debug_zone(zone_key)` function is a useful utility for inspecting the state of a specific zone.
*   **Linting & Formatting:**
    *   This project uses `luacheck` for linting and `stylua` for code formatting.
    *   To check for issues, run `luacheck .` from the root directory.
    *   To format all Lua files, run `stylua .`.

## 3. Key Conventions & Patterns

*   **Configuration-Driven Development:** Before implementing new logic in a module, check if it can be expressed as a new option in `config.lua`. The goal is to keep the modules generic and push specifics into the configuration.
*   **Hierarchy: Monitor -> Zone -> Tile:**
    *   A **Monitor** is a physical screen.
    *   A **Zone** is a logical area a window can be moved to, triggered by a hotkey (e.g., the "h" zone for the left side).
    *   A **Tile** is a specific rectangular geometry within a zone. A zone can contain multiple tiles to cycle through (e.g., left half, left third, left two-thirds).
*   **Event-Driven and Asynchronous:** Window and screen events are handled asynchronously with small delays (`hs.timer.doAfter`) to allow the OS to settle. This is important for stability, especially for `handle_window_created` and `handle_screen_change` in `modules/tiler.lua`.
*   **Stable Monitor IDs:** Do not rely on `hs.screen:id()` directly. Use `monitor_manager.get_id(screen)` to get a stable, persistent identifier for a monitor, which is crucial for `window_memory.lua` and multi-monitor logic.
*   **Type Annotations:** To improve code clarity and assist AI-driven development, all new functions should be documented with EmmyLua-style annotations. This makes the code easier to reason about and safer to modify.
    ```lua
    --- My function description.
    ---@param name string The name of the user.
    ---@return boolean success
    function my_module.my_function(name)
      -- ...
    end
    ```

## 4. How to Approach Common Tasks

*   **Adding a new keybinding:**
    1.  Define the key combination in `config.keys` if it's new.
    2.  Add the binding in `init.lua` (for general features) or `modules/tiler.lua` (for tiling actions).
    3.  Implement the function that the hotkey calls.
*   **Changing a layout:**
    1.  Modify the appropriate layout table in `config.tiler.layouts`. For example, to change the behavior of the 'h' key on a 4x3 grid, edit `config.tiler.layouts["4x3"]["h"]`.
    2.  The values are grid coordinates (e.g., `"a1:c2"` means column 'a' row 1 to column 'c' row 2).
*   **Supporting a new application:**
    1.  For an app hotkey, add it to `config.appCuts`.
    2.  If the app has unusual window behavior, add it to `config.tiler.problem_apps`.
    3.  If it needs a default position, add it to `config.window_memory.app_zones`.