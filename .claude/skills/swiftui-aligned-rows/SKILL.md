---
name: swiftui-aligned-rows
description: Lay out rows of controls in SwiftUI (settings/forms/hotkey lists) so their columns align even when content (alias names, glyphs, picker labels) varies in width. Use when settings rows "read as messy"/ragged, when a Picker/Menu won't respect its width, or when aligning label|value|control columns across rows.
---

# Aligning variable-width rows in SwiftUI

## The core gotcha
A SwiftUI **menu `Picker` (and `Menu`) ignores `.frame(width:)`** — it sizes itself to its *selected
label*. So a single Picker whose label has variable-width content (e.g. `mash` vs `mash_shift`,
`⌃⌘` vs `⇧⌃⌥⌘`) will overflow and shove everything after it right → ragged columns. **Widening the
frame is only a band-aid** (works until a longer value appears).

## The fix: split into fixed-width columns; don't let a Picker carry the visible value
Lay the row out as explicit fixed-width columns, and make the dropdown a **chevron-only `Menu`** (it
selects, it doesn't display the value):

```swift
HStack(spacing: 8) {
    Text(label).frame(width: LabelW, alignment: .leading)        // fixed
    Spacer(minLength: 12)
    // value split into fixed columns so every row lines up:
    Text(primary).frame(width: PrimaryW, alignment: .leading)    // e.g. alias name — left
    Text(secondary).foregroundColor(.secondary)
        .frame(width: SecondaryW, alignment: .leading)           // e.g. glyphs — left
    Menu {                                                       // the selector — right
        ForEach(options, id: \.self) { o in Button { onSelect(o) } label: { optionLabel(o) } }
    } label: {
        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundColor(.secondary)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)        // ← critical: suppress the built-in chevron, or you get TWO
    .fixedSize()
    .frame(width: SelectorW, alignment: .trailing)
    // trailing controls (also fixed widths) …
}
```

Keep the column widths in **one shared enum** (`enum RowMetrics { static let label/primary/... }`) and
**one reusable view** for the value+selector, so every row on every tab shares the exact columns. Never
hardcode a per-row picker width — that's how stragglers drift out of alignment.

## Checklist
- [ ] Variable-width value is split into fixed-width `Text` columns (left-aligned), not inside a Picker.
- [ ] Dropdown is a chevron-only `Menu` with `.menuIndicator(.hidden)` (single chevron) in a fixed,
      right-aligned column.
- [ ] Widths live in a shared metrics enum; one reusable component is used everywhere (grep for stray
      `Picker(...).frame(width:)` choosing the same value — those are stragglers).
- [ ] Verify with a headless render of each affected tab/pane and eyeball the columns at true scale.

## Canonical implementation in this repo
`Sources/ZTUI/EditorViews.swift` → `ModifierSelector` + `KeyRowMetrics` (alias | glyphs | selector).
Used by every hotkey/modifier row. Render a settings tab to verify: `ZT_RENDER_UI=<tab>:/tmp/x.png`.
(See memory `swiftui-aligned-modifier-rows`.)
