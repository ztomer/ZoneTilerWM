# ZoneTilerWM — Design Round: Settings & Menubar Consolidation

This document summarizes the final design alignment and layout revisions for ZoneTilerWM's settings and menubar consolidation.

---

## 1. Menubar Unification (The Segmented Widget)

### The Decision
We will combine the three separate menubar status items (Main menu, Spaces widget, and Pomodoro timer) into **a single unified status bar widget** (one custom `NSStatusItem`). This prevents macOS from separating them or injecting other system icons in between, while keeping all existing functionality.

### Visual Representation (Strictly No Emojis)
* **Idle State:** 
  `⧇ [ ● ○ ○ ] [ ○ ○ ]`
  * `⧇` — The classic ZoneTiler glyph (opens the main dropdown menu on click).
  * `[ ● ○ ○ ]` — The existing Spaces bracket widget (filled/hollow style per monitor).
* **Pomodoro Running State:**
  `⧇ [ ● ○ ○ ] [ ○ ○ ] (24:50)`
  * The countdown timer text `(24:50)` slides out to the right of the brackets. No colorful emojis are used (the "no emojis" rule stands).
* **Interactivity:**
  * Clicking the Pomodoro segment toggles (starts/pauses/stops) the session.
  * Clicking a Space number switches to that Space.
  * Clicking the main logo `⧇` or right-clicking anywhere opens the unified dropdown menu.

---

## 2. Settings Sidebar Consolidation (Grouped 13-Tab Structure)

We will keep all existing functionality and retain the SwiftUI navigation sidebar, but dissolve the vague **Input & Output** tab and reorganize the panels into a clear visual hierarchy with headers:

### Grouped Sidebar Layout

* **WORKSPACE & NAVIGATION** *(Core desktop layout and window navigation)*
  * ⚙️ **General** (Launch at login, Working-set, Focus follows mouse, Keyboard layout)
  * 🖌️ **Appearance** (Focus borders, Margins size & screen edge)
  * ◰ **Tiles** (Zones grid editor, Tiling hotkeys, default app zones)
  * 🔍 **Exposé & Hints** (Exposé grid position/nav keys, Window hints)
  * ⧇ **Spaces** (Spaces menubar widgets, switching methods)
  * 🖥️ **Dock Previews** (Dock hover window previews)
* **SHORTCUTS & CLUSTERS** *(Hotkeys, modifier layers, and scratchpads)*
  * ⌨️ **Keys** (Global modifier aliases, keybinds)
  * 🚀 **App Launcher** (Modifier launch layers, hold-to-reveal HUD)
  * 📦 **App Groups** (Window groups, scratchpads)
* **UTILITIES & INTEGRATION** *(Focus helpers and developer automation)*
  * 🔊 **Audio Switcher** (Output devices list, switch hotkey)
  * 🍅 **Pomodoro** (Focus timer periods, CRT break screen)
  * 🤖 **Automation** (MCP server, rules engine)
  * 🛠️ **Advanced** (Solver weights, diagnostics logs)

---

## 3. Specific Panel Relocations (Dissolving "Input & Output")

To clean up the categorization:
1. **Keyboard Layout Detector:** Moved from *Input & Output* to **General** (treated as a global system setting).
2. **Focus Follows Mouse:** Moved from *Input & Output* to **General** (treated as a global window focus behavior setting).
3. **Audio Switcher:** Moved from *Input & Output* to its own dedicated **Audio Switcher** tab under the **Utilities & Integration** group.
4. **Margins:** Stays in **Appearance** (along with Focus Borders), as it sets the visual margins between all visible window frames, not just tile boundaries.
