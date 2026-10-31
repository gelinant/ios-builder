import SwiftUI
import UIKit

/// The three tabs of the one transit surface. The board, the line ribbon and the trip screen are
/// no longer separate sheets: they are the body of this shell, under one header and one close.
enum TransitShellTab: Int, CaseIterable, Identifiable {
    case stops
    case trip
    case nearby

    var id: Int { rawValue }

    var key: String {
        switch self {
        case .stops: return "stops"
        case .trip: return "trip"
        case .nearby: return "nearby"
        }
    }

    var title: String {
        switch self {
        case .stops: return VelaL10n.text("transit_shell_stops")
        case .trip: return VelaL10n.text("transit_shell_trip")
        case .nearby: return VelaL10n.text("transit_shell_nearby")
        }
    }
}

/// The one header of the shell: the line as identity (badge in its own colour), where it goes, and
/// the next departure. A surface that has no line leaves [label] empty and the badge gives way to
/// the stop's own name, so the header never invents a colour.
struct TransitShellHeader {
    let label: String
    let colorHex: String?
    let direction: String
    let countdown: String
    let subtitle: String
    let live: Bool

    init(label: String = "", colorHex: String? = nil, direction: String = "",
         countdown: String = "", subtitle: String = "", live: Bool = false) {
        self.label = label
        self.colorHex = colorHex
        self.direction = direction
        self.countdown = countdown
        self.subtitle = subtitle
        self.live = live
    }

    var hasLine: Bool { !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// THE transit container. One close, one primary action, one segmented body. Every transit entry
/// point (the stop board, a line tapped on the map, the trip screen) renders this same view, so the
/// chrome and the reading order cannot drift apart again.
struct TransitShell<Stops: View, Trip: View, Nearby: View>: View {
    let header: TransitShellHeader
    @Binding var tab: TransitShellTab
    let primaryTitle: String?
    let primaryIdentifier: String
    let primarySystemImage: String
    let primaryDisabled: Bool
    let onPrimary: (() -> Void)?
    /// A second, icon-only action kept for the live panel entry point. Nil on surfaces without it.
    let secondaryTitle: String?
    let secondaryIdentifier: String?
    let onSecondary: (() -> Void)?
    let closeIdentifier: String
    let surfaceIdentifier: String
    let badgeIdentifier: String
    let tabIdentifierPrefix: String
    let onClose: () -> Void

    @ObservedObject private var selection = EntitySelection.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    private let stops: () -> Stops
    private let trip: () -> Trip
    private let nearby: () -> Nearby

    init(
        header: TransitShellHeader,
        tab: Binding<TransitShellTab>,
        primaryTitle: String? = nil,
        primaryIdentifier: String = "transit-shell-primary",
        primarySystemImage: String = "arrow.triangle.turn.up.right.diamond.fill",
        primaryDisabled: Bool = false,
        onPrimary: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryIdentifier: String? = nil,
        onSecondary: (() -> Void)? = nil,
        closeIdentifier: String = "transit-shell-close",
        surfaceIdentifier: String = "transit-shell",
        badgeIdentifier: String = "transit-shell-badge",
        tabIdentifierPrefix: String = "transit-shell-tab-",
        onClose: @escaping () -> Void,
        @ViewBuilder stops: @escaping () -> Stops,
        @ViewBuilder trip: @escaping () -> Trip,
        @ViewBuilder nearby: @escaping () -> Nearby
    ) {
        self.header = header
        _tab = tab
        self.primaryTitle = primaryTitle
        self.primaryIdentifier = primaryIdentifier
        self.primarySystemImage = primarySystemImage
        self.primaryDisabled = primaryDisabled
        self.onPrimary = onPrimary
        self.secondaryTitle = secondaryTitle
        self.secondaryIdentifier = secondaryIdentifier
        self.onSecondary = onSecondary
        self.closeIdentifier = closeIdentifier
        self.surfaceIdentifier = surfaceIdentifier
        self.badgeIdentifier = badgeIdentifier
        self.tabIdentifierPrefix = tabIdentifierPrefix
        self.onClose = onClose
        self.stops = stops
        self.trip = trip
        self.nearby = nearby
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            headerBlock
            segmentedControl
            Divider()
            Group {
                switch tab {
                case .stops: stops()
                case .trip: trip()
                case .nearby: nearby()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if DEBUG
            debugLine
            #endif
        }
        .background(Color(uiColor: .systemBackground))
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(surfaceIdentifier)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
            }
            .accessibilityLabel(VelaL10n.text("place_close"))
            .accessibilityIdentifier(closeIdentifier)

            Spacer(minLength: 0)

            if let secondaryTitle, let secondaryIdentifier, let onSecondary {
                Button(action: onSecondary) {
                    Label(secondaryTitle, systemImage: "map")
                        .labelStyle(.iconOnly)
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                }
                .accessibilityLabel(secondaryTitle)
                .accessibilityIdentifier(secondaryIdentifier)
            }

            if let primaryTitle, let onPrimary {
                Button(action: onPrimary) {
                    Label(primaryTitle, systemImage: primarySystemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: Design.Size.hitTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(primaryDisabled)
                .accessibilityIdentifier(primaryIdentifier)
            }
        }
        .padding(.horizontal, Design.Spacing.s)
        .padding(.top, Design.Spacing.s)
    }

    private var headerBlock: some View {
        HStack(alignment: .center, spacing: Design.Spacing.m) {
            if header.hasLine {
                badge
            }
            VStack(alignment: .leading, spacing: 2) {
                if header.hasLine {
                    Text(VelaL10n.text("transit_line", header.label))
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                } else if !header.subtitle.isEmpty {
                    Text(header.subtitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                }
                if !header.direction.isEmpty {
                    Text(VelaL10n.text("transit_nav_towards", header.direction))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("transit-shell-direction")
                }
                if header.hasLine && !header.subtitle.isEmpty && header.subtitle != header.direction {
                    Text(header.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !header.countdown.isEmpty {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(VelaL10n.text("transit_shell_next"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(header.countdown)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(header.hasLine ? lineColor : Color.primary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VelaL10n.text("transit_next_departure_in", header.countdown))
                .accessibilityIdentifier("transit-shell-countdown")
            }
            if header.live {
                Text(VelaL10n.text("place_transit_live"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .background(Capsule().stroke(.green, lineWidth: 1))
            }
        }
        .padding(.horizontal, Design.Spacing.m)
        .padding(.vertical, Design.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-shell-header")
    }

    private var badge: some View {
        Text(header.label)
            .font(.title3.weight(.bold))
            .foregroundStyle(contrastText(for: header.colorHex))
            .frame(minWidth: 56, minHeight: 42)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(lineColor))
            .accessibilityIdentifier(badgeIdentifier)
    }

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(TransitShellTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(tab == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: Design.Size.hitTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == item ? contrastText(for: header.colorHex) : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(tab == item ? lineColor : Color.clear))
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                .accessibilityIdentifier("\(tabIdentifierPrefix)\(item.key)")
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground)))
        .padding(.horizontal, Design.Spacing.m)
        .padding(.bottom, Design.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-shell-tabs")
    }

    #if DEBUG
    private var debugLine: some View {
        Text(
            "shell_tabs=\(TransitShellTab.allCases.count) shell_tab=\(tab.key)"
                + " shell_selection=\(selection.value == nil ? 0 : 1)"
                + " shell_kind=\(selection.value?.kind.rawValue ?? "-")")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Spacing.m)
            .padding(.bottom, 4)
            .accessibilityIdentifier("transit-shell-debug")
    }
    #endif

    // MARK: Colour

    private var lineColor: Color {
        guard let hex = header.colorHex, let ui = UIColor(transitHex: hex) else {
            return Color(uiColor: .secondarySystemBackground)
        }
        return Color(uiColor: ui)
    }

    private func contrastText(for hex: String?) -> Color {
        guard let hex, let ui = UIColor(transitHex: hex) else { return .primary }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? .black : .white
    }
}

/// A tab with no content of its own. It names what the surface does not have instead of inventing
/// a list, which is the same honesty rule the rest of the transit language follows.
struct TransitShellEmptyTab: View {
    let title: String
    let message: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
