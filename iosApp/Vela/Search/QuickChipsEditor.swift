import SwiftUI

/// Settings > Search > Quick search buttons, as on Android: one row per chip in the user's order,
/// a switch that takes it off the rows and a handle that moves it. A switched-off chip keeps its
/// place, so switching it back on puts it where it was. Reset restores the default set.
struct QuickChipsEditor: View {
    @ObservedObject var model: QuickChipsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(VelaL10n.text("settings_quick_chips_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(model.arranged) { chip in
                        row(chip)
                    }
                    .onMove { source, destination in
                        guard let from = source.first else { return }
                        model.move(from: from, to: destination)
                    }
                }
                Section {
                    Button(VelaL10n.text("settings_quick_chips_reset")) {
                        model.reset()
                    }
                    .disabled(!model.customized)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("quick-chips-reset")
                }
            }
            .navigationTitle(VelaL10n.text("settings_quick_chips"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .accessibilityIdentifier("quick-chips-done")
                }
            }
            .accessibilityIdentifier("quick-chips-editor")
            .onAppear { model.start() }
        }
    }

    private func row(_ chip: QuickCategory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: chip.icon)
                .frame(width: 22)
                .foregroundStyle(model.hidden.contains(chip.key) ? Color.secondary : Color.primary)
            Text(chip.label)
                .foregroundStyle(model.hidden.contains(chip.key) ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                model.move(chip.key, delta: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isFirst(chip))
            .accessibilityLabel(VelaL10n.text("search_move_up", String(describing: (chip.label))))
            .accessibilityIdentifier("quick-chip-up-\(chip.id)")
            Button {
                model.move(chip.key, delta: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isLast(chip))
            .accessibilityLabel(VelaL10n.text("search_move_down", String(describing: (chip.label))))
            .accessibilityIdentifier("quick-chip-down-\(chip.id)")
            Toggle("", isOn: Binding(
                get: { !model.hidden.contains(chip.key) },
                set: { model.toggle(chip.key, shown: $0) }))
                .labelsHidden()
                .accessibilityLabel(chip.label)
                .accessibilityIdentifier("quick-chip-toggle-\(chip.id)")
        }
        .frame(minHeight: 44)
    }

    private func isFirst(_ chip: QuickCategory) -> Bool {
        model.arranged.first?.key == chip.key
    }

    private func isLast(_ chip: QuickCategory) -> Bool {
        model.arranged.last?.key == chip.key
    }
}
