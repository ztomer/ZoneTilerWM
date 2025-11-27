# Contributing to ZoneTilerWM

Thank you for your interest in contributing! Whether you're fixing a bug, adding a feature, or improving documentation, this guide will help you get started. Following these guidelines helps maintain the quality and consistency of the codebase.

## Getting Started

1.  **Install Hammerspoon**: If you haven't already, download and install [Hammerspoon](https://www.hammerspoon.org/).
2.  **Clone the Repository**: Clone this project into your Hammerspoon configuration directory:
    ```sh
    git clone https://github.com/your-username/ZoneTilerWM.git ~/.hammerspoon
    ```
3.  **Reload Configuration**: Open the Hammerspoon console and reload the configuration to apply your changes. You can also bind a hotkey to `hs.reload()` for convenience.

## Coding Conventions

To ensure the code is clean and easy to read, please adhere to the following style guidelines.

### Naming

*   **Modules**: Use `snake_case` for module filenames (e.g., `window_state_manager.lua`).
*   **Variables & Functions**: Use `snake_case` for local and public variables and functions (e.g., `local focused_window`, `function tiler.move_window_to_zone(...)`).
*   **Module Tables**: The main table in a module should match the filename's intent (e.g., `local tiler = {}`).

### Formatting

*   **Indentation**: Use 4 spaces for indentation.
*   **Line Length**: Aim for a maximum line length of 120 characters where possible.
*   **Whitespace**: Use whitespace to improve readability around operators and after commas.

### Module Structure

Most modules follow a standard structure. Please use this as a template for new modules.

```lua
-- modules/my_new_module.lua

-- 1. Local dependencies (if any)
local hs_something = hs.something

-- 2. Module table
local my_new_module = {}

-- 3. Module state (private variables)
local config = nil
local other_module = nil
local debug_log = function(...) end -- Placeholder logger

-- 4. Private functions (if any)
local function do_something_private()
  -- ...
end

-- 5. Public functions
function my_new_module.do_something_public()
  -- ...
end

-- 6. Initialization function
function my_new_module.init(cfg, other_mod, log_func)
    config = cfg
    other_module = other_mod
    debug_log = log_func or debug_log
    debug_log("MyNewModule initialized")
end

-- 7. Return the module table
return my_new_module
```

### Commit Messages

Please follow a conventional commit format to make the project history easy to understand.

*   **Format**: `<type>(<scope>): <subject>`
*   **Example**: `feat(tiler): add support for window stacking in zones`
*   **Types**: `feat` (new feature), `fix` (bug fix), `docs` (documentation), `style` (formatting), `refactor`, `test`, `chore` (build/tooling changes).
*   **Scope**: The module or area of the codebase affected (e.g., `focus_manager`, `config`, `readme`).

---