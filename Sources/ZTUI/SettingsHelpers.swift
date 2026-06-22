// SettingsHelpers.swift — small shared building blocks for the settings panes (extracted from
// SettingsGroups.swift to keep both files under the 500-LOC ceiling): the tiling-modifier glyph
// string, the visual key-cap shortcut views, the toggle-in-header Section, and the bool binding.

import SwiftUI
import ZTSystem

/// Resolved tiling-modifier glyphs (e.g. "⌃⌘") for "hold X" trigger hints.
func tilingGlyphs(_ model: SettingsModel) -> String { ModGlyph.string(model.config.tilerModifier) }

/// Renders a shortcut as visual key caps (kbd-style boxes) — so the UI SHOWS the shortcut instead of
/// describing it in prose. `tokens` are resolved modifier tokens (ctrl/cmd/…); `key` is an optional
/// trailing key.
struct KeyCaps: View {
    let tokens: [String]
    var key: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModGlyph.order.filter(tokens.contains), id: \.self) { cap(ModGlyph.glyph[$0] ?? $0) }
            if let key, !key.isEmpty { cap(key.uppercased()) }
        }
    }
    private func cap(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 18, minHeight: 20).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.30), lineWidth: 0.5))
    }
}

/// One line that SHOWS a shortcut: leading text · key caps · trailing text.
struct ShortcutLine: View {
    let lead: String
    let tokens: [String]
    var key: String? = nil
    let trail: String
    var body: some View {
        HStack(spacing: 6) {
            Text(lead).font(.caption).foregroundColor(.secondary)
            KeyCaps(tokens: tokens, key: key)
            Text(trail).font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }
}

/// A Form section whose enable toggle lives IN the header (instead of a row that just restates the
/// title), with the explanation as a footer rather than a header-duplicating caption. Extra controls
/// go in `content` and are typically only built when `isOn`.
struct ToggleSection<Content: View>: View {
    let title: String
    @Binding var isOn: Bool
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String, isOn: Binding<Bool>, footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.title = title; self._isOn = isOn; self.footer = footer; self.content = content
    }

    var body: some View {
        // The toggle is the section's first row (its de-facto header) — one label for the feature,
        // no duplicate title row or header-restating caption. (A Toggle in a Section `header:` does
        // not reliably reflect its bound state, so it lives in the body.)
        Section {
            Toggle(isOn: $isOn) { Text(title).font(.body.weight(.semibold)) }
                .toggleStyle(.switch)
            content()
        } footer: {
            if let footer { Text(footer).font(.caption).foregroundColor(.secondary) }
        }
    }
}

/// Bool binding from a config keypath + a model setter (the common toggle wiring).
func boolBind(_ model: SettingsModel, _ keyPath: KeyPath<ConfigLoader.LoadedConfig, Bool>,
              _ setter: @escaping (Bool) -> Void) -> Binding<Bool> {
    Binding(get: { model.config[keyPath: keyPath] }, set: { setter($0) })
}
