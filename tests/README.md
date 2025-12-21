# ZoneTilerWM Test Suite

This directory contains the automated test suite for ZoneTilerWM.

## Running Tests

To run the full test suite, execute the runner script from the project root:

```bash
lua tests/test_runner.lua
```

## Test Files

*   **`test_runner.lua`**: The main harness that loads `mock_hs.lua` and executes all registered test files.
*   **`mock_hs.lua`**: Mocks the Hammerspoon `hs` API (window, screen, geometry, drawing, configdir, etc.) to allow tests to run in a standalone Lua environment.
*   **`test_config_load.lua`**: Verifies that `config.toml` is correctly loaded, parsed, and post-processed (e.g., color conversion).
*   **`test_storage.lua`**: Tests the JSON storage and persistence module (`modules/storage.lua`).
*   **`test_window_memory.lua`**: Tests the window position memory system (`modules/window_memory.lua`).
*   **`test_config_validator.lua`**: Tests the configuration schema validation logic (`modules/config_validator.lua`).
