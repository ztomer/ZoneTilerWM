# Gemini Project Context: ZoneTilerWM

This file provides context for the Gemini AI assistant to understand the ZoneTilerWM project.

## Project Overview

ZoneTilerWM is a tiling window manager for macOS built on the [Hammerspoon](https://www.hammerspoon.org/) automation framework. It uses Lua for its configuration and modules. The goal is to provide a highly configurable and efficient keyboard-driven window management experience.

## Project Structure

The project is organized into several key files and directories:

- **`init.lua`**: The main entry point for the Hammerspoon configuration. It is responsible for loading all the necessary modules and setting up the initial state.
- **`config.lua`**: Contains user-configurable variables and settings for the window manager, such as layouts, keybindings, and appearance.
- **`modules/`**: This directory contains the core logic of the window manager, with each file representing a distinct module with a specific responsibility.
- **`Spoons/`**: This directory contains third-party Hammerspoon plugins, known as "Spoons," that extend the functionality of the core window manager.

### Core Modules (`modules/`)

- **`tiler.lua`**: The heart of the window manager. This module contains the core tiling logic that arranges windows into predefined layouts.
- **`zone_calculator.lua`**: Works in conjunction with the `tiler` to calculate the screen regions (zones) where windows can be placed based on the current layout and monitor configuration.
- **`focus_manager.lua`**: Manages window focus, including cycling through windows, focusing adjacent windows, and potentially focus-follows-mouse functionality.
- **`window_actions.lua`**: Defines a set of actions that can be performed on windows, such as moving, resizing, maximizing, and sending them to different monitors.
- **`window_state_manager.lua`**: Manages the state of windows (e.g., floating, tiled, minimized) and ensures they are handled correctly by the tiler.
- **`window_memory.lua`**: Remembers the position, size, and layout of windows so they can be restored across application restarts or system reboots.
- **`monitor_manager.lua`**: Handles multi-monitor setups, allowing for different layouts and behaviors on each monitor.
- **`smart_placer.lua`**: Provides logic for intelligently placing new windows in sensible locations.
- **`placement_strategy.lua`**: Determines the best tile for a window based on a chosen strategy (e.g., rotation, largest free space).
- **`app_switcher.lua`**: Implements a custom application switcher.
- **`lru_cache.lua`**: A utility module providing a Least Recently Used (LRU) cache, likely used by other modules like the `app_switcher`.
- **`pomodoor.lua`**: A Pomodoro timer integrated into the window manager.

### Spoons (`Spoons/`)

- **`RoundedCorners.spoon/`**: A Spoon used to create rounded corners for window frames, enhancing the visual aesthetics of the desktop.

## Development Workflow

When working on this project, keep the following in mind:

- **Modularity**: Changes should respect the modular design. New functionality should be added in new modules or by extending existing ones in a logical way.
- **Configuration**: Core logic in the `modules/` directory should be kept separate from user-specific settings in `config.lua`.
- **Hammerspoon API**: All code interacts with the macOS windowing system through the Hammerspoon API. Refer to the official [Hammerspoon documentation](https://www.hammerspoon.org/docs/) for API details.
