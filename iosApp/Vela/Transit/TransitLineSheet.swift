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

    /// A load that never settles must not leave the sheet silent: after this delay the spinner
    /// gives way to the reason, which is the sheet's answer in every other empty state.
    private static let loadingBudgetNanos: UInt64 = 6_000_000_000
    @State private var loadingTimedOut = false
    @State private var settleTask: Task<Void, Never>?

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
            .navigationTitle(model.label.isEmpty ? VelaL10n.text("shape_line") : VelaL10n.text("transit_line", String(describing: (model.label))))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(VelaL10n.text("place_close"), action: close)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-line-close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Label(VelaL10n.text("transit_refresh"), systemImage: "arrow.clockwise")
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
        .onChange(of: model.loading, initial: true) { _, loading in
            settleTask?.cancel()
            loadingTimedOut = false
            guard loading, model.stops.isEmpty else { return }
            settleTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.loadingBudgetNanos)
                if !Task.isCancelled { loadingTimedOut = true }
            }
        }
        .onDisappear { settleTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.label.isEmpty ? VelaL10n.text("shape_line") : VelaL10n.text("transit_line", String(describing: (model.label))))
                        .font(.title2.weight(.bold))
                    Text(model.direction.isEmpty ? model.stopName : VelaL10n.text("transit_nav_towards", String(describing: (model.direction))))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if model.live {
                    Text(VelaL10n.text("place_transit_live"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 24)
                        .background(Capsule().stroke(.green, lineWidth: 1))
                        .accessibilityLabel(VelaL10n.text("transit_live_data_from_the_feed"))
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
                VelaL10n.text("transit_line_2", String(describing: (model.label)))
                    + (model.colorSource == "feed" ? VelaL10n.text("transit_agency_color_2") : VelaL10n.text("transit_vela_mode_color")))
            .accessibilityIdentifier("transit-line-badge")
    }

    // MARK: Direction

    @ViewBuilder
    private var directionSwitch: some View {
        if model.directions.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text(VelaL10n.text("transit_direction"))
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
                            .accessibilityLabel(VelaL10n.text("transit_direction_2", String(describing: (direction))))
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
            .accessibilityLabel(VelaL10n.text("transit_runs_from_to", String(describing: (model.fromName)), String(describing: (model.toName))))
            .accessibilityIdentifier("transit-line-termini")
        }
    }

    // MARK: Departures

    @ViewBuilder
    private var departures: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VelaL10n.text("transit_next_departures"))
                .font(.headline)
            if model.departures.isEmpty {
                Text(VelaL10n.text("transit_the_feed_lists_no_departure_for"))
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
            Text(departure.live ? VelaL10n.text("place_transit_live") : VelaL10n.text("place_transit_scheduled"))
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

    /// The sheet always answers the two questions a line raises: where the run goes, or why its
    /// stops cannot be shown. The ribbon and the reason are exclusive, and every state that has no
    /// stops lands on the reason, including an error key and a load that never settles. The
    /// identifier sits on the text, never on a container: a container is not published as an
    /// element, which made the note invisible to VoiceOver and to the UI scenario.
    @ViewBuilder
    private var sequence: some View {
        if model.errorKey != nil || model.sequenceUnavailable || model.stops.isEmpty {
            if model.loading && !loadingTimedOut && model.errorKey == nil {
                loadingRow
            } else {
                noSequence
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(VelaL10n.text("transit_the_whole_line"))
                        .font(.headline)
                    Text(VelaL10n.text("transit_stops_2", String(describing: (model.stops.count))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if model.position?.estimated == true {
                        Text(VelaL10n.text("transit_estimated_not_gps"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                if model.direction.isEmpty {
                    Text(VelaL10n.text("transit_from_to", String(describing: (model.fromName)), String(describing: (model.toName))))
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

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(VelaL10n.text("transit_loading_the_line"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-line-loading")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    /// The reason, plus the error card when the feed refused the board. The reason text carries
    /// `transit-line-no-sequence` in every case, so a sheet without a ribbon always says why.
    private var noSequence: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let key = model.errorKey {
                errorNote(key)
            }
            Text(VelaL10n.text("transit_the_stops_of_this_run"))
                .font(.headline)
            Text(VelaL10n.text("transit_transitous_did_not_send_this_run"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("transit-line-no-sequence")
            if model.errorKey == nil {
                Button {
                    model.refresh()
                } label: {
                    Label(VelaL10n.text("transit_refresh"), systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("transit-line-no-sequence-retry")
            }
        }
    }

    private func errorNote(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title(for: key), systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("transit-line-error")
            Text(detail(for: key))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func title(for key: String) -> String {
        switch key {
        case "no_departures": return VelaL10n.text("transit_no_departures_found_here")
        case "no_line": return VelaL10n.text("transit_line_error_no_line_title")
        case "budget_exhausted": return VelaL10n.text("transit_line_error_budget_title")
        case "no_service": return VelaL10n.text("transit_line_error_no_service_title")
        default: return VelaL10n.text("transit_line_error_default_title")
        }
    }

    private func detail(for key: String) -> String {
        switch key {
        case "no_departures":
            return VelaL10n.text("transit_line_error_no_departures_detail")
        case "no_line":
            return VelaL10n.text("transit_line_error_no_line_detail")
        case "budget_exhausted":
            return VelaL10n.text("transit_line_error_budget_detail")
        case "no_service":
            return VelaL10n.text("transit_line_error_no_service_detail")
        default:
            return VelaL10n.text("transit_line_error_default_detail")
        }
    }

    // MARK: Map action and notes

    private var mapAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.sendWholeLineToMap()
            } label: {
                Label(VelaL10n.text("transit_see_the_whole_line_on_the"), systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: model.color))
            .disabled(model.stops.isEmpty)
            .accessibilityIdentifier("transit-line-map")

            if model.mapSent {
                Text(VelaL10n.text("transit_the_whole_line_was_sent_to"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-line-map-sent")
            }
            if model.stops.isEmpty {
                Text(VelaL10n.text("transit_without_the_stop_sequence_there_is"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.shapeSource == "stops" {
                Text(VelaL10n.text("transit_the_feed_sent_no_drawn_shape"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-line-shape-source")
            }
        }
    }

    private var footnote: some View {
        Text(VelaL10n.text("transit_colors_times_and_live_marks_come"))
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
