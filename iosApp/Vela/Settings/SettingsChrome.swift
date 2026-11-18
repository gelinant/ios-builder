import SwiftUI

/// Shared chrome for the Settings and About screens.
///
/// The two pages are the only full-height group lists in the app, so they share one section
/// header, one chevron and one hint style. Values come from `Design`, never from literals.
/// See `docs/ios/DESIGN.md` sections 3.1, 3.2 and 3.5.

/// Section header: caption, uppercase, secondary. Sits 24 pt under the previous block, 8 pt
/// above its first row, which the grouped `Form` already supplies.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Design.Typography.caption.weight(.semibold))
            .foregroundStyle(Design.Colors.secondaryLabel)
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Trailing chevron of a row that opens another screen. Decorative for VoiceOver: the row
/// itself carries the button trait.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(Design.Typography.caption.weight(.semibold))
            .foregroundStyle(Design.Colors.secondaryLabel)
            .flipsForRightToLeftLayoutDirection(true)
            .accessibilityHidden(true)
    }
}

/// The trailing value of a row: one line at `detail`, secondary, never truncated at AX3.
struct SettingsValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Design.Typography.detail)
            .foregroundStyle(Design.Colors.secondaryLabel)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A hint under its control. `listRowInsets` trims the grouped row gap above it so it reads as
/// part of the row above, at the 4 pt pair of `Design.Spacing.xs`.
struct SettingsHintStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Design.Typography.detail)
            .foregroundStyle(Design.Colors.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: Design.Padding.rowH,
                bottom: Design.Padding.rowV,
                trailing: Design.Padding.rowH))
    }
}

extension View {
    /// Applies the Settings hint role. See `SettingsHintStyle`.
    func settingsHint() -> some View {
        modifier(SettingsHintStyle())
    }
}

/// The two-line label of a row that opens a screen: title at `rowTitle`, subtitle at `caption`.
/// Used by Settings (appearance, quick chips, about) and by the About hub.
struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Text(title)
                .font(Design.Typography.rowTitle)
                .foregroundStyle(Design.Colors.label)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The tap target of a contextual row: 44 pt minimum, full width, leading aligned.
struct SettingsRowFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: Design.Size.hitTarget, alignment: .leading)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Applies the full-width 44 pt tap target of a Settings row.
    func settingsRowFrame() -> some View {
        modifier(SettingsRowFrame())
    }
}

/// The search field of the About hub: 44 pt tall, sunken surface, `Radius.m`, icon 16.
struct SettingsSearchField: View {
    let placeholder: String
    @Binding var text: String
    let identifier: String

    var body: some View {
        HStack(spacing: Design.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(Design.Typography.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, Design.Spacing.m)
        .frame(minHeight: Design.Size.hitTarget)
        .background(Design.Colors.surfaceSunken, in: RoundedRectangle(cornerRadius: Design.Radius.m))
        .listRowInsets(EdgeInsets(
            top: Design.Spacing.s,
            leading: Design.Padding.rowH,
            bottom: Design.Spacing.s,
            trailing: Design.Padding.rowH))
        .listRowBackground(Color.clear)
    }
}
