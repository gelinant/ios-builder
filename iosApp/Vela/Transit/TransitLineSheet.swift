import SwiftUI
import UIKit
import VelaCore

/// One line, one direction, one stop: the sheet any transit surface opens through
/// `TransitLineLink.open(line:direction:stop:)`. It answers, in this order: the line's color and
/// badge, its direction switcher, its two termini, the next departures, then the whole run as a
/// ribbon with the estimated vehicle position. A feed that cannot give the sequence says so and
/// only the departures it sent are shown.
struct TransitLineSheet: View {
    @ObservedObject var model: TransitLineModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    directionSwitch
                    termini
                    departures
                    Divider()
                    sequence
                    mapAction
                    footnote
                    #if DEBUG
                    Text(model.debugLine)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transit-line-debug")
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(model.label.isEmpty ? "Line" : "Line \(model.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: close)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-line-close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("transit-line-refresh")
                }
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-line-sheet")
        .onAppear { model.start() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.label.isEmpty ? "Line" : "Line \(model.label)")
                        .font(.title2.weight(.bold))
                    Text(model.direction.isEmpty ? model.stopName : "towards \(model.direction)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if model.live {
                    Text("Live")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 24)
                        .background(Capsule().stroke(.green, lineWidth: 1))
                        .accessibilityLabel("Live data from the feed")
                }
            }
            Text(model.colorSourceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-line-color-source")
        }
    }

    private var badge: some View {
        Text(model.label)
            .font(.title3.weight(.bold))
            .foregroundStyle(contrastText(for: model.colorHex))
            .frame(minWidth: 56, minHeight: 42)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: model.color)))
            .accessibilityLabel(
                "Line \(model.label), "
                    + (model.colorSource == "feed" ? "agency color" : "Vela mode color"))
            .accessibilityIdentifier("transit-line-badge")
    }

    // MARK: Direction

    @ViewBuilder
    private var directionSwitch: some View {
        if model.directions.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Direction")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.directions.enumerated()), id: \.offset) { index, direction in
                            let selected = direction == model.direction
                            Button {
                                model.selectDirection(direction)
                            } label: {
                                Text(direction)
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .foregroundStyle(selected ? contrastText(for: model.colorHex) : Color.primary)
                                    .background(
                                        Capsule()
                                            .fill(selected ? Color(uiColor: model.color) : Color(uiColor: .secondarySystemBackground)))
                            }
                            .accessibilityLabel("Direction \(direction)")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                            .accessibilityIdentifier("transit-line-direction-\(index)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Termini

    @ViewBuilder
    private var termini: some View {
        if !model.fromName.isEmpty || !model.toName.isEmpty {
            HStack(spacing: 8) {
                Text(model.fromName.isEmpty ? model.stopName : model.fromName)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.toName)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Runs from \(model.fromName) to \(model.toName)")
            .accessibilityIdentifier("transit-line-termini")
        }
    }

    // MARK: Departures

    @ViewBuilder
    private var departures: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next departures")
                .font(.headline)
            if model.departures.isEmpty {
                Text("The feed lists no departure for this line at this stop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.departures.prefix(5).enumerated()), id: \.offset) { _, departure in
                            departureChip(departure)
                        }
                    }
                }
            }
        }
    }

    private func departureChip(_ departure: TransitLineDeparture) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.minutesText(departure))
                .font(.callout.weight(.bold))
                .monospacedDigit()
            Text(model.clockText(departure))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(departure.live ? "Live" : "Scheduled")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(departure.live ? Color.green : Color.secondary)
        }
        .padding(10)
        .frame(minHeight: 68, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(model.minutesText(departure)), \(model.clockText(departure)), "
                + (departure.live ? "live" : "scheduled"))
        .accessibilityIdentifier("transit-line-departure")
    }

    // MARK: Sequence

    @ViewBuilder
    private var sequence: some View {
        if let key = model.errorKey {
            errorNote(key)
        } else if model.loading && model.stops.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading the line")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        } else if model.sequenceUnavailable || model.stops.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("The stops of this run")
                    .font(.headline)
                Text("Transitous did not send this run's stop sequence. Only the departures above are shown; Vela does not invent the stops in between.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("transit-line-no-sequence")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The whole line")
                        .font(.headline)
                    Text("\(model.stops.count) stops")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if model.position?.estimated == true {
                        Text("Estimated, not GPS")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                if model.direction.isEmpty {
                    Text("From \(model.fromName) to \(model.toName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TransitRouteRibbon(
                    stops: model.stops,
                    position: model.position,
                    color: Color(uiColor: model.color),
                    colorHex: model.colorHex)
            }
        }
    }

    private func errorNote(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title(for: key), systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(detail(for: key))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("transit-line-error")
    }

    private func title(for key: String) -> String {
        switch key {
        case "no_departures": return "No departures at this stop"
        case "no_line": return "This line is not on the board"
        case "budget_exhausted": return "Vela reached its daily share"
        case "no_service": return "Transitous is not available here"
        default: return "The feed did not answer"
        }
    }

    private func detail(for key: String) -> String {
        switch key {
        case "no_departures":
            return "Transitous lists no departure for this stop. Vela shows nothing rather than an invented time."
        case "no_line":
            return "The feed's board for this stop does not carry this line and direction. Open the stop board to see what it serves."
        case "budget_exhausted":
            return "Vela stops before the published Transitous fair-use limit. Try again later; nothing is refreshed automatically."
        case "no_service":
            return "The line sheet could not reach the Transitous client. No stored answer is shown as live."
        default:
            return "The last answer could not be used. The sheet keeps no time and no stop from a failed request."
        }
    }

    // MARK: Map action and notes

    private var mapAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.sendWholeLineToMap()
            } label: {
                Label("See the whole line on the map", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: model.color))
            .disabled(model.stops.isEmpty)
            .accessibilityIdentifier("transit-line-map")

            if model.mapSent {
                Text("The whole line was sent to the map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-line-map-sent")
            }
            if model.stops.isEmpty {
                Text("Without the stop sequence there is no line to draw.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.shapeSource == "stops" {
                Text("The feed sent no drawn shape for this line. The map gets the stop chain, not rails.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-line-shape-source")
            }
        }
    }

    private var footnote: some View {
        Text("Colors, times and live marks come from the Transitous open feed. The vehicle marker is Vela's estimate between two of the feed's own times; Transitous publishes no vehicle position.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)
    }

    private func close() {
        model.close()
        onClose()
    }

    /// Black or white on the line color, from its own luminance.
    private func contrastText(for hex: String) -> Color {
        guard let ui = UIColor(transitHex: hex) else { return .white }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? .black : .white
    }
}
