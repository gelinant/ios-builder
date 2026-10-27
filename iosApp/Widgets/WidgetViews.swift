import SwiftUI
import WidgetKit

/// One Home Screen entry. The entry date drives the departure countdowns; the snapshot is the last
/// payload the app wrote, never a fresh network answer.
struct VelaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the App Group on each timeline build. The provider makes no network request: WidgetKit
/// timelines are best effort and a missing payload shows a setup state.
struct VelaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> VelaWidgetEntry {
        VelaWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (VelaWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : WidgetSnapshotStore.shared?.load()
        completion(VelaWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VelaWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.shared?.load()
        var entries: [VelaWidgetEntry] = []
        if snapshot?.board != nil {
            // One entry per minute for 15 minutes keeps the "3 min" labels honest without waking
            // the extension. After that WidgetKit rebuilds the timeline from the same payload.
            for minute in 0..<15 {
                entries.append(VelaWidgetEntry(
                    date: now.addingTimeInterval(TimeInterval(minute * 60)),
                    snapshot: snapshot))
            }
        } else {
            entries.append(VelaWidgetEntry(date: now, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Home and Work

struct VelaShortcutsWidget: Widget {
    static let kind = "VelaShortcuts"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VelaWidgetProvider()) { entry in
            ShortcutsWidgetView(entry: entry)
                .velaWidgetBackground()
        }
        .configurationDisplayName("Home and Work")
        .description("Your saved Home and Work with their addresses.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ShortcutsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VelaWidgetEntry

    private var shortcuts: [WidgetShortcut] {
        Array((entry.snapshot?.shortcuts ?? []).prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Places")
            if shortcuts.isEmpty {
                WidgetEmptyState(
                    title: "No shortcuts",
                    detail: "Set Home and Work in Vela, Saved.")
            } else if family == .systemSmall {
                ForEach(shortcuts) { shortcut in
                    Link(destination: shortcut.deepLink) {
                        ShortcutCell(shortcut: shortcut, compact: true)
                    }
                }
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shortcuts) { shortcut in
                        Link(destination: shortcut.deepLink) {
                            ShortcutCell(shortcut: shortcut, compact: false)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetPadding()
        .widgetURL(shortcuts.first?.deepLink)
    }
}

private struct ShortcutCell: View {
    let shortcut: WidgetShortcut
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: shortcut.kind == .home ? "house.fill" : "briefcase.fill")
                    .font(.caption2)
                Text(shortcut.name)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(1)
            }
            if let address = shortcut.address, !address.isEmpty {
                Text(address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shortcut.name), \(shortcut.address ?? "")")
    }
}

// MARK: - Parked car

struct VelaParkingWidget: Widget {
    static let kind = "VelaParking"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VelaWidgetProvider()) { entry in
            ParkingWidgetView(entry: entry)
                .velaWidgetBackground()
        }
        .configurationDisplayName("Parked car")
        .description("Where you parked and how long ago, with a tap to open it in Vela.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ParkingWidgetView: View {
    let entry: VelaWidgetEntry

    private var parking: WidgetParking? { entry.snapshot?.parking }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Parked car", systemImage: "car.fill")
            if let parking {
                Link(destination: parking.deepLink) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parked")
                            .font(.subheadline.weight(.semibold))
                        Text(parking.savedAt, style: .relative)
                            .font(.title3.weight(.bold))
                        Text(parking.coordinateText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("Parked car since \(parking.ageText(from: entry.date))")
                Spacer(minLength: 0)
                Text("Tap to find my car")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                WidgetEmptyState(
                    title: "No parked car",
                    detail: "Use Vela's parking button after you park.")
            }
        }
        .widgetPadding()
        .widgetURL(parking?.deepLink)
    }
}

// MARK: - Next departures

struct VelaDeparturesWidget: Widget {
    static let kind = "VelaDepartures"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VelaWidgetProvider()) { entry in
            DeparturesWidgetView(entry: entry)
                .velaWidgetBackground()
        }
        .configurationDisplayName("Next departures")
        .description("The last stop you opened in Vela, with the update time the feed reported.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct DeparturesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VelaWidgetEntry

    private var board: WidgetBoard? { entry.snapshot?.board }

    private var visibleLines: [WidgetBoardLine] {
        Array((board?.lines ?? []).prefix(family == .systemSmall ? 2 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: board?.stopName ?? "Departures", systemImage: "bus.fill")
            if let board {
                if board.lines.isEmpty {
                    WidgetEmptyState(
                        title: "No departures",
                        detail: "Open the stop in Vela to refresh.")
                } else {
                    ForEach(visibleLines) { line in
                        Link(destination: board.deepLink) {
                            DepartureRow(line: line, date: entry.date)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(board.isStale(asOf: entry.date)
                     ? board.updatedText() + ", not refreshed"
                     : board.updatedText())
                    .font(.caption2)
                    .foregroundStyle(board.isStale(asOf: entry.date) ? Color.orange : Color.secondary)
                    .lineLimit(1)
            } else {
                WidgetEmptyState(
                    title: "No stop chosen",
                    detail: "Open a stop's departures in Vela once.")
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

    var body: some View {
        HStack(spacing: 6) {
            Text(line.label ?? "?")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(LineColor.color(line.color), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
            Text(line.headsign ?? "Unknown direction")
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let departure {
                Text(departure.minutesText(from: date))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Text(departure.realtime ? "Live" : "Sched.")
                    .font(.caption2)
                    .foregroundStyle(departure.realtime ? Color.green : Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let departure else { return line.headsign ?? "Departure" }
        let kind = departure.realtime ? "live" : "scheduled"
        return "\(line.label ?? ""), \(line.headsign ?? ""), "
            + "\(departure.minutesText(from: date)), \(kind)"
    }
}

private enum LineColor {
    static func color(_ text: String?) -> Color {
        guard var hex = text?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return .accentColor
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return .accentColor }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Chrome

private struct WidgetHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Vela")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WidgetEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
    }
}

private extension View {
    func widgetPadding() -> some View {
        padding(12)
    }

    @ViewBuilder
    func velaWidgetBackground() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.13, blue: 0.20), Color(red: 0.06, green: 0.08, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
    }
}
