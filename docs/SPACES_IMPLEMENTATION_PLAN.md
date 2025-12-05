# macOS Spaces Support - Implementation Plan

## Executive Summary

Adding macOS Spaces support to ZoneTilerWM will enable workspace-based window management, allowing users to organize different monitor/layout configurations for different tasks. This implementation will use the native `hs.spaces` API to directly integrate with macOS Mission Control Spaces.

## Requirements Analysis

### User Requirements
1. **Space-to-Monitor Mapping**: Each Space can contain one or more monitors in specific arrangements
2. **macOS Spaces Integration**: Direct integration with macOS Mission Control Spaces using `hs.spaces` API
3. **Menubar Indicator**: Visual indicator showing current space (e.g., `[1][2][3][4]`)
4. **Persistent Layouts**: Save and restore tile/zone layouts per Space per monitor
5. **Space Switching**: Quick switching between Spaces with automatic layout restoration

### Technical Approach

#### Using hs.spaces API
This implementation will use Hammerspoon's built-in `hs.spaces` API for direct macOS Spaces integration:
- **hs.spaces.allSpaces()**: Get all available Spaces
- **hs.spaces.focusedSpace()**: Get currently active Space
- **hs.spaces.gotoSpace(spaceId)**: Switch to a specific Space
- **hs.spaces.moveWindowToSpace(window, spaceId)**: Move windows between Spaces
- **hs.spaces.watcher**: Detect Space changes in real-time

**Note**: The `hs.spaces` API uses private macOS APIs and behavior may vary across macOS versions. This implementation targets macOS 15+ (Sequoia/later) where the API is stable.

**API References:**
- [Hammerspoon hs.spaces docs](https://www.hammerspoon.org/docs/hs.spaces.html)
- [hs.spaces API reference](https://commandpost.fcp.cafe/api-references/hammerspoon/hs.spaces/)
- [GitHub - hs.spaces source](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua)

---

## Proposed Architecture

### macOS Spaces Integration

Direct integration with macOS Mission Control Spaces using the `hs.spaces` API.

#### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Space Manager                           │
│  - Integrates with hs.spaces API                           │
│  - Tracks macOS Space IDs                                   │
│  - Watches for Space changes (hs.spaces.watcher)           │
│  - Handles Space switching and window movement              │
└──────────────────┬──────────────────────────────────────────┘
                   │
         ┌─────────┴──────────┬──────────────────────┐
         │                    │                       │
┌────────▼─────────┐  ┌──────▼────────┐  ┌─────────▼──────────┐
│  Space Storage   │  │ Space Layout  │  │  Menubar Widget    │
│  - JSON files    │  │  - Per-space  │  │  - [1][2][3][4]    │
│  - Keyed by      │  │    monitor    │  │  - Click to switch │
│    macOS Space   │  │    configs    │  │  - Hotkeys         │
│    ID            │  │  - Zone/tile  │  │  - Uses hs.menubar │
│  - Window pos    │  │    mappings   │  │                    │
└──────────────────┘  └───────────────┘  └────────────────────┘
         │
         │
┌────────▼─────────────────────────────────────────────────────┐
│              hs.spaces.watcher                               │
│  - Detects Space changes                                     │
│  - Triggers layout save/restore                              │
│  - Notifies space_manager of active Space                    │
└──────────────────────────────────────────────────────────────┘
```

#### Key Components

1. **`modules/space_manager.lua`** (NEW)
   - Core orchestrator for Spaces functionality
   - Uses `hs.spaces` API for all Space operations
   - Maintains mapping: macOS Space ID → ZoneTiler configuration
   - Space switching via `hs.spaces.gotoSpace()`
   - Window movement via `hs.spaces.moveWindowToSpace()`
   - Integration with existing modules

2. **`modules/space_storage.lua`** (NEW)
   - Persistence layer for Space configurations
   - JSON format: `~/.config/ZoneTilerWM/spaces.json`
   - Keyed by macOS Space ID (from `hs.spaces`)
   - Schema:
     ```json
     {
       "active_space_id": 123456,
       "spaces": {
         "123456": {
           "name": "Work",
           "macos_space_id": 123456,
           "monitors": [1, 2],
           "layouts": {
             "1": { "layout_key": "4x3", "zone_positions": {...} },
             "2": { "layout_key": "2x2", "zone_positions": {...} }
           },
           "window_positions": [...]
         }
       }
     }
     ```

3. **`modules/space_menubar.lua`** (NEW)
   - Menubar indicator using `hs.menubar`
   - Displays: `[1] 2  3  4` (current Space highlighted)
   - Click handler for Space switching
   - Hotkey bindings

4. **Enhanced `layout_manager.lua`** (MODIFY)
   - Add Space awareness
   - Save/restore layouts per Space
   - Current: saves single "default" layout
   - New: saves per-Space layouts

5. **Enhanced `window_memory.lua`** (MODIFY)
   - Add Space dimension to memory: `app -> space_id -> monitor_id -> {zone, tile}`
   - Current: `app -> monitor_id -> {zone, tile}`
   - Backward compatible with existing cache

#### Data Flow

**Space Switch Sequence:**
```
1. User triggers Space switch (hotkey/menubar)
2. space_manager captures current Space state
3. space_storage saves current window positions
4. space_manager calls hs.spaces.gotoSpace(target_space_id)
5. hs.spaces.watcher fires, detecting Space change
6. space_manager loads target Space layout from storage
7. window_actions repositions all windows
8. space_menubar updates indicator
```

**Space Detection on Startup:**
```
1. space_manager.init() called
2. Get all Spaces via hs.spaces.allSpaces()
3. Get current active Space via hs.spaces.focusedSpace()
4. Load configurations for all known Spaces from storage
5. Register hs.spaces.watcher for Space change events
6. Update menubar with current Space
```

---

## Detailed Implementation Plan

### Phase 1: Core Space Management (Week 1-2)

#### 1.1 Create `modules/space_manager.lua`

**State Structure:**
```lua
local spaces = {
    current_space_id = nil, -- macOS Space ID from hs.spaces.focusedSpace()
    definitions = {
        -- macos_space_id -> space_definition
        [123456] = {
            name = "Work",
            macos_space_id = 123456,
            created_at = timestamp,
            monitor_ids = {1, 2}, -- Logical monitor IDs from monitor_manager
        }
    },
    watcher = nil, -- hs.spaces.watcher instance
}
```

**Key Functions:**
- `space_manager.init(config, tiler, monitor_manager, window_memory)`
- `space_manager.get_current_space()` → Returns current macOS space_id
- `space_manager.switch_to_space(space_id)` → Calls `hs.spaces.gotoSpace()`
- `space_manager.get_all_spaces()` → Wraps `hs.spaces.allSpaces()`
- `space_manager.on_space_change(space_id)` → Watcher callback
- `space_manager.set_space_name(space_id, name)` → Custom naming
- `space_manager.sync_spaces()` → Syncs with macOS Mission Control Spaces

#### 1.2 Create `modules/space_storage.lua`

Extends existing `storage.lua` pattern:
```lua
space_storage.save_space_state(space_id, state)
space_storage.load_space_state(space_id) → state
space_storage.save_all_spaces(spaces_table)
space_storage.load_all_spaces() → spaces_table
```

**File Location:** `~/.config/ZoneTilerWM/spaces.json`

#### 1.3 Configuration Updates

Add to `config.lua`:
```lua
config.spaces = {
    enabled = true,
    debug = true,

    -- Hotkeys for switching Spaces (Ctrl+Shift+Number)
    hotkeys = {
        space_1 = {{"ctrl", "shift"}, "1"},
        space_2 = {{"ctrl", "shift"}, "2"},
        space_3 = {{"ctrl", "shift"}, "3"},
        space_4 = {{"ctrl", "shift"}, "4"},
        space_5 = {{"ctrl", "shift"}, "5"},
        space_6 = {{"ctrl", "shift"}, "6"},
        space_7 = {{"ctrl", "shift"}, "7"},
        space_8 = {{"ctrl", "shift"}, "8"},
        space_9 = {{"ctrl", "shift"}, "9"},
    },

    -- Auto-save interval
    auto_save_interval_sec = 60,

    -- Restore Space on startup
    restore_on_startup = true,

    -- Capture layout on Space switch
    capture_on_switch = true,

    -- Visual preview settings
    preview = {
        enabled = true,

        -- Preview activation mode: "hover" or "click"
        activation_mode = "hover",  -- "hover" = show on hover, "click" = show on menubar click

        hover_delay = 0.3,  -- seconds before showing preview (only for "hover" mode)
        window_width = 600,
        window_height = 400,
        thumbnail_size = {width = 100, height = 80},
        show_window_titles = true,
        show_monitor_indicators = true,
    },
}
```

---

### Phase 2: Menubar Indicator with Visual Previews (Week 2-3)

#### 2.1 Create `modules/space_menubar.lua`

**Visual Design:**
```
Inactive: [1] 2  3  4
Active:   1 [2] 3  4
```

**Basic Implementation:**
```lua
local menubar = hs.menubar.new()
local preview_window = nil  -- Canvas for window previews

function space_menubar.update(current_space_id, total_spaces)
    local display = ""
    for i = 1, total_spaces do
        if i == current_space_id then
            display = display .. "[" .. i .. "]"
        else
            display = display .. " " .. i .. " "
        end
    end
    menubar:setTitle(display)
end

function space_menubar.init(space_manager)
    menubar:setClickCallback(function()
        -- Show dropdown menu with Space list
        local menu_items = build_space_menu()
        menubar:setMenu(menu_items)
    end)
end
```

**Basic Features:**
- Click to show dropdown menu with Space names
- Hotkey display in menu
- "Create New Space" option
- "Delete Current Space" option

---

#### 2.2 Create `modules/space_preview.lua` (NEW - Enhanced Feature)

**Visual Window Preview on Hover**

When user hovers over the menubar Space indicator, show a visual preview panel below it displaying:
- Miniaturized representation of all windows in each Space
- Window outlines with app icons
- Drag-and-drop support to move windows between Spaces

**Architecture:**

```
┌─────────────────────────────────────────┐
│  Menubar: [1] 2  3  4                   │
└─────────────────────────────────────────┘
           ↓ (hover)
┌─────────────────────────────────────────┐
│  Space Preview Panel (hs.canvas)        │
├─────────────────────────────────────────┤
│  Space 1  │  Space 2  │  Space 3        │
│  ┌─────┐  │  ┌─────┐  │  ┌─────┐        │
│  │ 🌐  │  │  │ 💻  │  │  │ 📧  │        │
│  │Arc  │  │  │Code │  │  │Mail │        │
│  └─────┘  │  └─────┘  │  └─────┘        │
│  ┌─────┐  │  ┌─────┐  │                 │
│  │ 📝  │  │  │ 🎵  │  │                 │
│  │Note │  │  │Music│  │                 │
│  └─────┘  │  └─────┘  │                 │
└─────────────────────────────────────────┘
     ↑ Drag window between columns
```

**Implementation:**

```lua
-- modules/space_preview.lua
local space_preview = {}
local canvas = nil
local mouse_tracker = nil
local drag_state = {
    active = false,
    window_id = nil,
    source_space = nil,
    target_space = nil
}

-- Configuration
local PREVIEW_CONFIG = {
    window_width = 600,
    window_height = 400,
    thumbnail_width = 100,
    thumbnail_height = 80,
    padding = 10,
    columns_per_space = 3,
    show_delay = 0.3, -- seconds before showing preview
}

--- Creates a miniature representation of a window
local function create_window_thumbnail(window, x, y)
    local app = window:application()
    local icon = app:icon()

    return {
        type = "rectangle",
        frame = {x = x, y = y, w = PREVIEW_CONFIG.thumbnail_width, h = PREVIEW_CONFIG.thumbnail_height},
        strokeColor = {white = 0.7, alpha = 1},
        fillColor = {white = 0.2, alpha = 0.8},
        strokeWidth = 2,
        roundedRectRadii = {xRadius = 5, yRadius = 5}
    },
    {
        type = "image",
        image = icon,
        frame = {x = x + 5, y = y + 5, w = 20, h = 20}
    },
    {
        type = "text",
        text = app:name(),
        frame = {x = x + 30, y = y + 5, w = 65, h = 20},
        textColor = {white = 1, alpha = 1},
        textSize = 10
    }
end

--- Builds the preview canvas with all Spaces and windows
function space_preview.show(spaces_data, menubar_frame)
    if canvas then
        canvas:delete()
    end

    -- Position below menubar
    local screen = hs.screen.mainScreen()
    local screen_frame = screen:frame()
    local x = menubar_frame.x
    local y = menubar_frame.y + menubar_frame.h + 5

    canvas = hs.canvas.new({
        x = x,
        y = y,
        w = PREVIEW_CONFIG.window_width,
        h = PREVIEW_CONFIG.window_height
    })

    -- Background
    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {white = 0.1, alpha = 0.95},
        roundedRectRadii = {xRadius = 10, yRadius = 10}
    }

    -- Draw each Space column
    local num_spaces = #spaces_data
    local column_width = PREVIEW_CONFIG.window_width / num_spaces
    local element_index = 2

    for i, space_data in ipairs(spaces_data) do
        local col_x = (i - 1) * column_width

        -- Space header
        canvas[element_index] = {
            type = "text",
            text = "Space " .. i .. "\n" .. (space_data.name or ""),
            frame = {x = col_x + 10, y = 10, w = column_width - 20, h = 40},
            textColor = {white = 1, alpha = 1},
            textSize = 14,
            textAlignment = "center"
        }
        element_index = element_index + 1

        -- Draw windows in this Space
        local win_y = 60
        local win_x = col_x + (column_width - PREVIEW_CONFIG.thumbnail_width) / 2

        for _, window in ipairs(space_data.windows) do
            local thumbnail_elements = create_window_thumbnail(window, win_x, win_y)
            for _, elem in ipairs(thumbnail_elements) do
                canvas[element_index] = elem
                element_index = element_index + 1
            end
            win_y = win_y + PREVIEW_CONFIG.thumbnail_height + 10
        end

        -- Draw drop zone indicator
        canvas[element_index] = {
            type = "rectangle",
            frame = {x = col_x + 5, y = 55, w = column_width - 10, h = PREVIEW_CONFIG.window_height - 65},
            strokeColor = {white = 0.5, alpha = 0.3},
            strokeWidth = 2,
            action = "stroke",
            roundedRectRadii = {xRadius = 8, yRadius = 8}
        }
        element_index = element_index + 1
    end

    canvas:show()
    space_preview.setup_drag_handlers(canvas, spaces_data)
end

--- Sets up mouse event handlers for drag-and-drop
function space_preview.setup_drag_handlers(canvas_obj, spaces_data)
    canvas_obj:mouseCallback(function(canvas, event, id, x, y)
        if event == "mouseDown" then
            -- Start drag
            local window_id = space_preview.get_window_at_position(x, y, spaces_data)
            if window_id then
                drag_state.active = true
                drag_state.window_id = window_id
                drag_state.source_space = space_preview.get_space_at_position(x, y, spaces_data)
            end
        elseif event == "mouseUp" then
            -- End drag
            if drag_state.active then
                drag_state.target_space = space_preview.get_space_at_position(x, y, spaces_data)
                if drag_state.target_space and drag_state.target_space ~= drag_state.source_space then
                    -- Move window to new Space
                    space_preview.move_window_to_space(drag_state.window_id, drag_state.target_space)
                end
                drag_state.active = false
            end
        elseif event == "mouseMove" then
            -- Update drag visual feedback
            if drag_state.active then
                space_preview.update_drag_indicator(x, y)
            end
        end
    end)
end

--- Moves a window to a different Space using hs.spaces API
function space_preview.move_window_to_space(window_id, target_space_id)
    local window = hs.window.get(window_id)
    if not window then return end

    local success = pcall(function()
        hs.spaces.moveWindowToSpace(window, target_space_id)
    end)

    if success then
        hs.alert.show("Moved " .. window:application():name() .. " to Space " .. target_space_id)
        space_preview.refresh()
    else
        hs.alert.show("Failed to move window")
    end
end

--- Hides the preview panel
function space_preview.hide()
    if canvas then
        canvas:delete()
        canvas = nil
    end
end

--- Gets the window ID at a given mouse position
function space_preview.get_window_at_position(x, y, spaces_data)
    -- Implementation: calculate which thumbnail was clicked
    -- Returns window_id or nil
end

--- Gets the Space ID at a given mouse position
function space_preview.get_space_at_position(x, y, spaces_data)
    local num_spaces = #spaces_data
    local column_width = PREVIEW_CONFIG.window_width / num_spaces
    local space_index = math.floor(x / column_width) + 1
    return spaces_data[space_index] and spaces_data[space_index].space_id
end

--- Refreshes the preview (after window move)
function space_preview.refresh()
    if canvas then
        -- Rebuild preview with updated window positions
        local spaces_data = space_manager.get_all_spaces_with_windows()
        local menubar_frame = menubar:frame()
        space_preview.show(spaces_data, menubar_frame)
    end
end

return space_preview
```

**Integration with space_menubar.lua:**

```lua
local space_preview = require "modules.space_preview"
local hover_timer = nil
local preview_visible = false

function space_menubar.init(space_manager, config)
    local activation_mode = config.spaces.preview.activation_mode or "hover"

    if activation_mode == "hover" then
        -- Set up hover detection
        menubar:setHoverCallback(function(is_hovering)
            if is_hovering then
                -- Delay before showing preview
                hover_timer = hs.timer.doAfter(config.spaces.preview.hover_delay or 0.3, function()
                    local spaces_data = space_manager.get_all_spaces_with_windows()
                    local menubar_frame = menubar:frame()
                    space_preview.show(spaces_data, menubar_frame)
                    preview_visible = true
                end)
            else
                -- Hide preview when mouse leaves
                if hover_timer then
                    hover_timer:stop()
                    hover_timer = nil
                end
                space_preview.hide()
                preview_visible = false
            end
        end)
    elseif activation_mode == "click" then
        -- Set up click to toggle preview
        menubar:setClickCallback(function()
            if preview_visible then
                -- Hide preview if already shown
                space_preview.hide()
                preview_visible = false
            else
                -- Show preview
                local spaces_data = space_manager.get_all_spaces_with_windows()
                local menubar_frame = menubar:frame()
                space_preview.show(spaces_data, menubar_frame)
                preview_visible = true

                -- Set up click-away to close
                space_preview.set_click_away_handler(function()
                    space_preview.hide()
                    preview_visible = false
                end)
            end
        end)
    end
end
```

**Click-Away Handler for Click Mode:**

Add to `space_preview.lua`:

```lua
--- Sets up a click-away handler to close preview when clicking outside
function space_preview.set_click_away_handler(callback)
    if not canvas then return end

    -- Monitor clicks outside the preview panel
    local click_watcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
        local mouse_pos = hs.mouse.absolutePosition()
        local canvas_frame = canvas:frame()

        -- Check if click is outside canvas
        if mouse_pos.x < canvas_frame.x or
           mouse_pos.x > canvas_frame.x + canvas_frame.w or
           mouse_pos.y < canvas_frame.y or
           mouse_pos.y > canvas_frame.y + canvas_frame.h then
            callback()
            click_watcher:stop()
            return true  -- Consume event
        end
        return false  -- Pass through clicks inside canvas
    end)

    click_watcher:start()
end
```

**Enhanced Features:**

1. **Dual Activation Modes:**
   - **Hover Mode** (default): Preview appears automatically after 300ms hover delay
   - **Click Mode**: Preview appears on menubar click, disappears on click-away
   - User selects preferred mode via `config.spaces.preview.activation_mode`

2. **Visual Feedback:**
   - Window thumbnails show app icon + name
   - Highlight target Space column during drag
   - Smooth hover delay (configurable, default 300ms) for hover mode
   - Fade-in/fade-out animations

3. **Drag-and-Drop:**
   - Click and drag window thumbnail between Space columns
   - Visual indicator showing drag target
   - Calls `hs.spaces.moveWindowToSpace()` on drop
   - Updates preview immediately after move

4. **Smart Layout:**
   - Auto-scales based on number of Spaces
   - Scrollable if too many windows
   - Intelligent positioning (stays on screen)

5. **Additional Info:**
   - Show window title on hover
   - Indicate which monitor each window is on
   - Show "empty" indicator for Spaces with no windows

**Technical Challenges:**

1. **Window Snapshots:** macOS doesn't provide easy window thumbnails
   - **Solution:** Use app icons + window outlines instead
   - Alternative: Use `hs.window.snapshotForID()` if available

2. **Hover Detection (Hover Mode):** `hs.menubar` doesn't have native hover callbacks
   - **Solution:** Use `hs.eventtap` to detect mouse position near menubar
   - Check if mouse is within menubar bounds every 100ms
   - Configurable delay prevents accidental triggers

3. **Click-Away Detection (Click Mode):** Need to close preview when clicking outside
   - **Solution:** Use `hs.eventtap` to monitor global mouse clicks
   - Check if click position is outside canvas bounds
   - Stop watcher and close preview on outside click

4. **Drag Performance:** Canvas redraw on every mouse move
   - **Solution:** Use separate "drag ghost" layer
   - Only update target highlight, not entire canvas

---

### Phase 3: Layout Persistence (Week 3)

#### 3.1 Extend `layout_manager.lua`

**Current Implementation:**
- Saves single "default" layout
- Captures all windows on all monitors

**New Implementation:**
```lua
-- Add Space awareness
function layout_manager.capture_layout(space_id, name)
    name = name or "default"
    local layout = {
        space_id = space_id,
        name = name,
        monitors = {},  -- NEW: per-monitor layouts
        windows = {}
    }

    -- Group windows by monitor
    for _, window in ipairs(hs.window.allWindows()) do
        local monitor_id = get_monitor_for_window(window)
        if not layout.monitors[monitor_id] then
            layout.monitors[monitor_id] = {
                layout_key = get_layout_key(monitor_id),
                windows = {}
            }
        end
        -- ... capture window position
    end

    -- Save to space_storage
    space_storage.save_space_layout(space_id, layout)
end
```

#### 3.2 Extend `window_memory.lua`

**Current Schema:**
```
positions[app_name][monitor_id] = {zone_key, tile_index}
```

**New Schema:**
```
positions[app_name][space_id][monitor_id] = {zone_key, tile_index}
```

**Migration Strategy:**
- Check if loaded data has `space_id` dimension
- If not, migrate to Space 1 (default)
- Write migration function for backward compatibility

---

### Phase 4: Space Switching Logic (Week 3-4)

#### 4.1 Implement Switch Sequence

```lua
function space_manager.switch_to_space(target_space_id)
    if target_space_id == spaces.current_space_id then
        return -- Already on this Space
    end

    debug_log("Switching from Space", spaces.current_space_id, "to", target_space_id)

    -- 1. Capture current Space state
    if config.spaces.capture_on_switch then
        layout_manager.capture_layout(spaces.current_space_id)
    end

    -- 2. Update current Space
    local old_space_id = spaces.current_space_id
    spaces.current_space_id = target_space_id

    -- 3. Restore target Space layout
    layout_manager.restore_layout(target_space_id)

    -- 4. Update menubar
    space_menubar.update(target_space_id, get_total_spaces())

    -- 5. Persist active Space
    space_storage.save_active_space(target_space_id)

    debug_log("Switched to Space", target_space_id)
end
```

#### 4.2 Handle Monitor Changes

When monitors are connected/disconnected:
```lua
-- In handle_screen_change (tiler.lua)
function handle_screen_change()
    -- Existing logic...

    -- NEW: Notify space_manager
    if space_manager then
        space_manager.on_monitor_change(hs.screen.allScreens())
    end
end

-- In space_manager.lua
function space_manager.on_monitor_change(all_screens)
    -- Check if current Space's monitors are still available
    local current_space = spaces.definitions[spaces.current_space_id]
    local available_monitors = get_available_monitors(all_screens)

    -- If monitors changed, update Space definition
    -- Optionally prompt user to reconfigure Space
end
```

---

### Phase 5: Integration & Testing (Week 4)

#### 5.1 Update `init.lua`

```lua
-- Load new modules
local space_manager = require "modules.space_manager"
local space_menubar = require "modules.space_menubar"
local space_storage = require "modules.space_storage"

function init()
    -- ... existing initialization

    if config.spaces and config.spaces.enabled then
        space_storage.init(config)
        space_manager.init(config, tiler, monitor_manager, window_memory)
        space_menubar.init(space_manager)

        -- Restore last active Space
        if config.spaces.restore_on_startup then
            local last_space = space_storage.load_active_space()
            space_manager.switch_to_space(last_space or 1)
        end
    end
end
```

#### 5.2 Testing Checklist

**Core Functionality:**
- [ ] Create multiple Spaces via Mission Control
- [ ] Switch between Spaces via hotkeys
- [ ] Switch between Spaces via menubar click
- [ ] Verify layouts persist per Space across restarts
- [ ] Test window memory per Space
- [ ] Test Space deletion (macOS removes Space)
- [ ] Test migration from non-Spaces config
- [ ] Verify performance (Space switch < 200ms)

**Visual Preview Panel - Hover Mode:**
- [ ] Hover over menubar shows preview after 300ms delay
- [ ] Preview hides when mouse leaves area
- [ ] Hover delay is configurable (test with different values)
- [ ] Preview displays all Spaces with correct window counts
- [ ] Window thumbnails show app icons and names
- [ ] Drag window thumbnail between Space columns
- [ ] Drop window on different Space column moves window
- [ ] Preview updates immediately after window move
- [ ] Preview handles many windows (10+ per Space) gracefully
- [ ] Preview works with empty Spaces (shows "empty" message)
- [ ] Drag visual feedback (highlight target column)

**Visual Preview Panel - Click Mode:**
- [ ] Click menubar toggles preview visibility
- [ ] Preview stays visible until clicked away
- [ ] Click outside preview closes it
- [ ] Click on window thumbnail starts drag (doesn't close preview)
- [ ] Drag-and-drop works same as hover mode
- [ ] ESC key closes preview (optional enhancement)
- [ ] Preview survives Space switches while open

**Multi-Monitor:**
- [ ] Test with multiple monitors (2, 3 monitors)
- [ ] Test with single monitor
- [ ] Test monitor connect/disconnect during runtime
- [ ] Preview shows which monitor each window is on

**Edge Cases:**
- [ ] Test with app that has multiple windows
- [ ] Test with minimized windows
- [ ] Test with fullscreen windows
- [ ] Test hs.spaces API failure handling
- [ ] Test rapid Space switching
- [ ] Test preview while dragging window

---

## Alternative Approaches Considered

### 1. Virtual Spaces Only
**Rejected:** User prefers native macOS Spaces integration despite API caveats.
- Would work independently of Mission Control
- More reliable across macOS versions
- Less integrated with native macOS workflow

### 2. Window Tagging System
**Rejected:**
- Tag windows instead of managing Spaces
- Use `hs.window` filters to show/hide tagged windows
- Simpler but completely bypasses macOS Spaces
- Doesn't meet requirement for macOS Spaces mapping

### 3. Hybrid Approach (Selected)
**Implemented:**
- Direct `hs.spaces` API integration
- Graceful degradation if API fails
- Fall back to layout restoration without window movement
- Detect API failures and notify user

---

## Data Schema

### Space Definition

```lua
{
    space_id = 123456, -- macOS Space ID from hs.spaces
    name = "Work", -- User-defined name
    created_at = 1701234567,
    monitor_ids = {1, 2}, -- Logical monitor IDs from monitor_manager
    macos_space_id = 123456, -- Direct link to macOS Space
}
```

### Space Layout

```lua
{
    space_id = 123456, -- macOS Space ID
    monitors = {
        [1] = {
            layout_key = "4x3",
            custom_offsets = {...}, -- From resize_manager
            zone_positions = {
                -- window_id -> {zone_key, tile_index}
            }
        }
    },
    window_positions = {
        -- Per-window positions for restoration
        {
            app_name = "Arc",
            title = "Gmail",
            monitor_id = 1,
            zone_key = "k",
            tile_index = 1,
            space_id = 123456 -- NEW: Track which Space window belongs to
        }
    }
}
```

---

## Migration Path

### For Existing Users

1. **First Launch with Spaces:**
   - Detect no `spaces.json` file
   - Get current macOS Space ID via `hs.spaces.focusedSpace()`
   - Create entry for current Space as "Default"
   - Migrate existing `window_positions.json` to current Space
   - Migrate existing `layouts.json` to current Space

2. **Configuration Compatibility:**
   - If `config.spaces.enabled = false`, system works exactly as before
   - No breaking changes to existing config

3. **Data Preservation:**
   - Keep old cache files for rollback
   - Create `spaces.json.backup` before migration

---

## Performance Considerations

### Space Switch Performance
- **Target:** < 200ms for full Space switch
- **Optimization:**
  - Batch window movements
  - Use `hs.window.filter` for efficient window queries
  - Cache layout calculations
  - Delay non-critical updates (window memory saves)

### Memory Usage
- Each Space stores ~2-5KB of layout data
- Support up to 10 Spaces = ~50KB total (negligible)

---

## Future Enhancements

### Phase 6 (Optional): Advanced Features

1. **Space Presets:**
   - "Coding" preset: Terminal + Editor + Browser
   - "Design" preset: Figma + Reference + Notes

2. **Auto-Switching:**
   - Switch Space based on app launch
   - Switch based on time of day
   - Triggers: "When Xcode launches, go to Coding Space"

3. **macOS Spaces Sync:**
   - When `hs.spaces` API becomes reliable
   - Two-way binding between virtual and macOS Spaces

4. **Multi-Display Layouts:**
   - Save entire monitor arrangements
   - Detect and auto-apply based on connected monitors

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| hs.spaces API fails on future macOS | MEDIUM | Wrap all API calls in pcall(), graceful degradation to layout-only mode |
| Performance impact on Space switch | MEDIUM | Optimize batch operations, test with 20+ windows, use async where possible |
| Data migration bugs | MEDIUM | Thorough testing, backup mechanism, backward compatibility |
| Space ID changes unexpectedly | LOW | Store Space metadata, re-sync on startup, notify user |
| User confusion (new UX) | LOW | Clear documentation, defaults to disabled, menubar help |
| Conflict with existing layouts | LOW | Separate namespace per Space ID, migration script |

---

## Success Criteria

1. ✅ Detects and tracks all macOS Spaces
2. ✅ Space switching < 200ms via `hs.spaces.gotoSpace()`
3. ✅ Layouts persist per Space across restarts
4. ✅ Menubar indicator always accurate (reflects current Space)
5. ✅ Zero data loss on migration from non-Spaces config
6. ✅ Gracefully handles hs.spaces API failures
7. ✅ Existing users unaffected (when disabled)
8. ✅ Works with user-created macOS Spaces (via Mission Control)

---

## Recommendation

**Implement macOS Spaces Integration via hs.spaces API**

### Rationale:

1. **Native Integration:** Direct integration with macOS Mission Control workflow
2. **User Preference:** Meets requirement for native macOS Spaces mapping
3. **Familiar UX:** Users already understand macOS Spaces
4. **API Availability:** Working on macOS 15+ (user's version)
5. **Graceful Degradation:** Can fall back to layout-only mode if API fails

### Implementation Timeline:

- **Week 1-2:** Core space_manager + storage + hs.spaces integration
- **Week 2-3:** Menubar indicator + visual preview panel with drag-and-drop
- **Week 3-4:** Layout persistence + window_memory extension
- **Week 4-5:** Integration, testing, documentation, polish

**Total Effort:** ~5 weeks part-time or ~2.5 weeks full-time

### Phase Breakdown:

**Phase 1 (Week 1-2):** Foundation
- hs.spaces API integration
- Space detection and tracking
- Basic switching functionality

**Phase 2 (Week 2-3):** Visual Interface
- Menubar Space indicator
- Hover-activated preview panel
- Drag-and-drop window movement
- App icons and window thumbnails

**Phase 3 (Week 3-4):** Persistence
- Per-Space layout storage
- Window memory per Space
- Migration from non-Spaces config

**Phase 4 (Week 4-5):** Polish & Testing
- Error handling and API failures
- Performance optimization
- Comprehensive testing
- Documentation

---

## Implementation Notes

### API Error Handling

Since `hs.spaces` uses private APIs, implement robust error handling:

```lua
local function safe_goto_space(space_id)
    local success, err = pcall(function()
        return hs.spaces.gotoSpace(space_id)
    end)

    if not success then
        hs.alert.show("Failed to switch Space: " .. tostring(err))
        debug_log("hs.spaces.gotoSpace failed:", err)
        -- Fall back to layout restoration without Space switch
        return false
    end
    return true
end
```

### Monitoring API Health

Periodically check if API is functioning:

```lua
function space_manager.check_api_health()
    local success, current_space = pcall(hs.spaces.focusedSpace)
    return success and current_space ~= nil
end
```

---

## References

- [Hammerspoon hs.spaces Documentation](https://www.hammerspoon.org/docs/hs.spaces.html)
- [hs.spaces API Reference](https://commandpost.fcp.cafe/api-references/hammerspoon/hs.spaces/)
- [hs.spaces Source Code](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua)
- [VirtualSpaces.spoon Implementation](https://github.com/brennovich/VirtualSpaces.spoon)
- [restore-spaces Project](https://github.com/tplobo/restore-spaces)

