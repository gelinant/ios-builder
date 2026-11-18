import SwiftUI
import WidgetKit

/// The parked car: its age, and a straight-line distance only when the app wrote a recent
/// position. The distance is never a route or an ETA, and the fix time is shown next to it.
struct VelaParkingWidget: Widget {
    static let kind = "VelaParking"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VelaWidgetProvider()) { entry in
            ParkingWidgetView(entry: entry)
                .velaWidgetBackground()
        }
        .configurationDisplayName(VelaL10n.text("map_parked_car"))
        .description(VelaL10n.text("map_parking_save"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ParkingWidgetView: View {
    let entry: VelaWidgetEntry

    private var parking: WidgetParking? { entry.snapshot?.parking }
    private var location: WidgetSnapshot.WidgetLocation? {
        entry.snapshot?.location
    }

    private var freshLocation: WidgetSnapshot.WidgetLocation? {
        guard let location, location.isFresh(asOf: entry.date) else { return nil }
        return location
    }

    private var distanceText: String? {
        guard let parking, let location = freshLocation else { return nil }
        let meters = location.distanceMeters(
            toLatitude: parking.latitude, longitude: parking.longitude)
        return WidgetUnits.distance(meters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            WidgetHeader(title: VelaL10n.text("map_parked_car"), systemImage: "car.fill")
            if let parking {
                Spacer(minLength: 0)
                Text(parking.savedAt, style: .relative)
                    .font(Design.Typography.metric)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let distanceText, let location = freshLocation {
                    HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
                        Image(systemName: "location.fill")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.accent)
                        Text(distanceText)
                            .font(Design.Typography.rowTitle)
                            .monospacedDigit()
                        Text(VelaL10n.text("mapscreen_sort_distance_item"))
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                    }
                    Text(location.fixedAt, style: .relative)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .lineLimit(1)
                } else {
                    Text(VelaL10n.text("map_parking_no_fix"))
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Link(destination: parking.deepLink) {
                    WidgetActionLabel(title: VelaL10n.text("map_parking_find"))
                }
            } else {
                Spacer(minLength: 0)
                WidgetEmptyState(
                    title: VelaL10n.text("map_parked_car"),
                    detail: VelaL10n.text("settings_parking_history_empty"))
            }
        }
        .widgetPadding()
        .widgetURL(parking?.deepLink)
    }
}

/// The last stop whose board was opened in Vela. It is not a station board the widget keeps
/// refreshed: the app writes one snapshot and the departure times keep their feed timestamp.
struct VelaDeparturesWidget: Widget {
    static let kind = "VelaDepartures"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: VelaWidgetProvider(liveMinutes: 20)
        ) { entry in
            DeparturesWidgetView(entry: entry)
                .velaWidgetBackground()
        }
        .configurationDisplayName(VelaL10n.text("transit_next_departures"))
        .description(VelaL10n.text("transit_the_board_did_not_answer_for"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct DeparturesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VelaWidgetEntry

    private var board: WidgetBoard? { entry.snapshot?.board }

    private var visibleLines: [WidgetBoardLine] {
        Array((board?.lines ?? []).prefix(family == .systemSmall ? 1 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            WidgetHeader(
                title: board?.stopName ?? VelaL10n.text("transit_next_departures"),
                systemImage: "bus.fill")
            if let board {
                if board.lines.isEmpty {
                    Spacer(minLength: 0)
                    WidgetEmptyState(
                        title: VelaL10n.text("transit_no_departures_found_here"),
                        detail: VelaL10n.text("transit_transitous_may_not_cover_this_stop"))
                } else {
                    VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                        ForEach(visibleLines) { line in
                            Link(destination: board.deepLink) {
                                DepartureRow(line: line, date: entry.date)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                BoardAgeLine(board: board, date: entry.date)
                Link(destination: board.deepLink) {
                    WidgetActionLabel(title: VelaL10n.text("transit_refresh"))
                }
            } else {
                Spacer(minLength: 0)
                WidgetEmptyState(
                    title: VelaL10n.text("transit_next_departures"),
                    detail: VelaL10n.text("transit_transitous_may_not_cover_this_stop"))
            }
        }
        .widgetPadding()
        .widgetURL(board?.deepLink)
    }
}

private struct DepartureRow: View {
    let line: WidgetBoardLine
    let date: Date

    private var departure: WidgetDeparture? { line.departures.first }

    private var title: String {
        let headsign = line.headsign?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let headsign, !headsign.isEmpty { return headsign }
        return line.label ?? VelaL10n.text("transit_transit_stop")
    }

    var body: some View {
        HStack(alignment: .center, spacing: Design.Spacing.s) {
            RoundedRectangle(cornerRadius: Design.Radius.xs)
                .fill(LineColor.color(line.color))
                .frame(width: 4, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(title)
                    .font(Design.Typography.detail)
                    .lineLimit(1)
                HStack(spacing: Design.Spacing.xs) {
                    Text(line.label ?? line.mode)
                        .font(Design.Typography.badge)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                    if let departure {
                        Text(departure.realtime
                             ? VelaL10n.text("place_transit_live")
                             : VelaL10n.text("place_transit_scheduled"))
                            .font(Design.Typography.badge)
                            .foregroundStyle(departure.realtime
                                             ? Design.Colors.success
                                             : Design.Colors.secondaryLabel)
                    }
                }
            }
            Spacer(minLength: Design.Spacing.xs)
            if let departure {
                VStack(alignment: .trailing, spacing: Design.Spacing.xxs) {
                    Text(countdown(departure))
                        .font(Design.Typography.rowTitle)
                        .monospacedDigit()
                        .lineLimit(1)
                    if let clock = departure.clockText, !clock.isEmpty {
                        Text(clock)
                            .font(Design.Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(Design.Colors.secondaryLabel)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func countdown(_ departure: WidgetDeparture) -> String {
        let minutes = departure.minutes(from: date)
        if minutes <= 0 { return VelaL10n.text("place_transit_now") }
        return VelaL10n.text("place_transit_in_min", Int64(minutes))
    }

    private var accessibilityText: String {
        guard let departure else { return title }
        let kind = departure.realtime
            ? VelaL10n.text("place_transit_live")
            : VelaL10n.text("place_transit_scheduled")
        return "\(title), \(countdown(departure)), \(kind)"
    }
}

/// The feed time is always shown. Age in minutes is added when the board is stale, and a failed
/// or cached refresh says so instead of showing a live mark it cannot support.
private struct BoardAgeLine: View {
    let board: WidgetBoard
    let date: Date

    private var stale: Bool { board.isStale(asOf: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            if board.refreshFailed || board.offline {
                Text(VelaL10n.text("transit_the_last_board_is_shown_refresh"))
                    .font(Design.Typography.badge)
                    .foregroundStyle(Design.Colors.warning)
                    .lineLimit(2)
            }
            if let fetchedAt = board.fetchedAt {
                HStack(spacing: Design.Spacing.xs) {
                    Text(VelaL10n.text(
                        "transit_updated",
                        fetchedAt.formatted(date: .omitted, time: .shortened)))
                        .font(Design.Typography.badge)
                        .foregroundStyle(stale ? Design.Colors.warning : Design.Colors.secondaryLabel)
                    if stale {
                        Text(fetchedAt, style: .relative)
                            .font(Design.Typography.badge)
                            .foregroundStyle(Design.Colors.warning)
                    }
                }
                .lineLimit(1)
            } else {
                Text(VelaL10n.text("transit_the_board_did_not_answer_for"))
                    .font(Design.Typography.badge)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .lineLimit(2)
            }
        }
    }
}

private struct WidgetHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Design.Typography.badge)
                    .foregroundStyle(Design.Colors.accent)
            }
            Text(title)
                .font(Design.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: Design.Spacing.xs)
            Text("Vela")
                .font(Design.Typography.badge)
                .foregroundStyle(Design.Colors.secondaryLabel)
        }
    }
}

private struct WidgetEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(title)
                .font(Design.Typography.rowTitle)
            Text(detail)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WidgetActionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            Text(title)
                .font(Design.Typography.button)
            Image(systemName: "arrow.up.forward.app")
                .font(Design.Typography.badge)
        }
        .foregroundStyle(Design.Colors.accentFill)
        .padding(.vertical, Design.Spacing.xxs)
        .contentShape(Rectangle())
    }
}

private enum LineColor {
    static func color(_ text: String?) -> Color {
        guard var hex = text?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return Design.Colors.accent
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            return Design.Colors.accent
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// Distance follows the app's unit choice when it is stored, and the system locale otherwise.
/// It formats a value the app already computed; it never turns the value into a travel time.
private enum WidgetUnits {
    static var imperial: Bool {
        UserDefaults(suiteName: "app.vela.ios.vela_units")?.bool(forKey: "imperial") ?? false
    }

    static func distance(_ meters: Double) -> String {
        if imperial {
            let miles = meters / 1_609.344
            if miles < 0.1 {
                return Measurement(value: meters / 0.3048, unit: UnitLength.feet)
                    .formatted(.measurement(width: .abbreviated, usage: .road))
            }
            return Measurement(value: miles, unit: UnitLength.miles)
                .formatted(.measurement(width: .abbreviated, usage: .road))
        }
        if meters < 1000 {
            return Measurement(value: meters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
        }
        return Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

private extension View {
    func widgetPadding() -> some View {
        padding(Design.Padding.page)
    }

    @ViewBuilder
    func velaWidgetBackground() -> some View {
        containerBackground(for: .widget) {
            Design.Colors.surface
        }
    }
}
