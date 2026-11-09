import SwiftUI

/// One row in the short map actions sheet. The identifier stays the one the former map button
/// carried, so a scenario or a VoiceOver user finds the same action in its new place.
struct MapActionItem: Identifiable {
    let id: String
    let symbol: String
    let title: String
    /// Why the row is disabled. Nil means the action is available.
    let reason: String?
}

/// The single secondary map control opens this sheet. Google Maps keeps the map bare and puts
/// the secondary destinations behind one control; this sheet is that control's short list.
///
/// It lists every action whatever the map state. The rows that need a clear map stay visible and
/// explain why they are disabled instead of disappearing, so the list never reshuffles.
struct MapActionsSheet: View {
    let items: [MapActionItem]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(VelaL10n.text("map_actions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("nav_done")) { dismiss() }
                        .accessibilityIdentifier("map-actions-close")
                }
            }
        }
        // Short by default, tall enough for AX5. The map keeps the lower half of the window.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ item: MapActionItem) -> some View {
        Button {
            onSelect(item.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.m) {
                Image(systemName: item.symbol)
                    .font(.system(size: Design.Size.icon, weight: .semibold))
                    .foregroundStyle(Design.Colors.accent)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text(item.title)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.label)
                    if let reason = item.reason {
                        Text(reason)
                            .font(Design.Typography.detail)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Design.Size.hitTarget)
            .contentShape(Rectangle())
        }
        .disabled(item.reason != nil)
        .accessibilityIdentifier(item.id)
        .accessibilityHint(item.reason ?? "")
    }
}
