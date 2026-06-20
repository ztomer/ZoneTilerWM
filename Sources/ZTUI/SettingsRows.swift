// SettingsRows.swift — shared two-column settings rows (NumberRow: label + editable field + stepper;
// SliderRow: label + slider). Used across all the settings panes. Split out of FeatureSettings.swift.

import SwiftUI

private let colorNames = ["green", "red", "blue", "yellow", "orange", "purple", "white", "black", "gray"]
private let swatchColor: [String: Color] = [
    "green": .green, "red": .red, "blue": .blue, "yellow": .yellow, "orange": .orange,
    "purple": .purple, "white": .white, "black": .black, "gray": .gray,
]

/// Label + editable number field + stepper: type a precise value OR nudge it. Replaces the
/// stepper-only rows so a value can be entered directly. Trailing-aligned to match the grouped
/// Form's native two-column rhythm (label left, control right). Shared across the settings tabs.
struct NumberRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String = ""

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", value: Binding(
                    get: { value },
                    set: { value = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .frame(width: 48).multilineTextAlignment(.trailing)
                if !suffix.isEmpty { Text(suffix).foregroundColor(.secondary) }
                Stepper("", value: $value, in: range, step: step).labelsHidden()
            }
        }
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String = ""

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ), in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                .labelsHidden()
                .frame(width: 140)
                
                Text("\(value)\(suffix)")
                    .frame(width: 48, alignment: .trailing)
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
}

/// Label + a row of tappable colour swatches (the nine config colour names). Replaces a
/// name-dropdown so the choice is visual and direct (the selected swatch is ringed).
struct ColorSwatchRow: View {
    let label: String
    let selected: String
    let set: (String) -> Void

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                ForEach(colorNames, id: \.self) { name in
                    Circle().fill(swatchColor[name] ?? .gray)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))   // edge for white/black
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: name == selected ? 2.5 : 0))
                        .overlay(name == selected   // checkmark so selection reads without relying on the ring color
                                 ? Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                     .foregroundColor(["white", "yellow", "gray"].contains(name) ? .black : .white)
                                 : nil)
                        .contentShape(Circle())
                        .onTapGesture { set(name) }
                        .help(name)
                }
            }
        }
    }
}
