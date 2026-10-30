import SwiftUI
import UIKit
import VelaCore

/// The route ribbon: one vertical line in the line's own color, one dot per stop, the passed
/// stops dimmed, the next stop marked, and the vehicle's estimated position inserted between the
/// two calls that bracket the clock. Every value comes from `TransitLineStore`; this view only
/// lays it out. Neutrals are the system's, so the ribbon reads on light and dark backgrounds.
struct TransitRouteRibbon: View {
    let stops: [TransitLineStop]
    let position: TransitLinePosition?
    let color: Color
    let colorHex: String

    private let timeWidth: CGFloat = 62
    private let railWidth: CGFloat = 24
    private let dotTop: CGFloat = 12

    private var lineX: CGFloat { timeWidth + 8 + (railWidth - 6) / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                if markerBeforeFirst, index == 0 {
                    vehicleRow(fraction: markerFraction)
                }
                stopRow(stop, index: index)
                if let after = markerAfter, after == index {
                    vehicleRow(fraction: markerFraction)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-line-ribbon")
    }

    // MARK: Vehicle marker placement

    private var markerFraction: Double {
        guard let position else { return 0 }
        return min(max(position.fraction, 0), 1)
    }

    private var markerBeforeFirst: Bool {
        guard let position, position.estimated else { return false }
        return position.beforeStart
    }

    /// The stop the vehicle has just left, or the last one when the run is finished.
    private var markerAfter: Int? {
        guard let position, position.estimated, !position.beforeStart else { return nil }
        if position.finished { return stops.count - 1 }
        return min(max(Int(position.fromIndex), 0), max(stops.count - 1, 0))
    }

    private var markerDetail: String {
        guard let position else { return "" }
        if position.beforeStart {
            return VelaL10n.text("transit_ribbon_before", position.nextStopName)
        }
        if position.finished {
            return VelaL10n.text("transit_ribbon_finished", position.nextStopName)
        }
        let minutes = max(1, (position.secondsToNextStop + 59) / 60)
        return VelaL10n.text(
            "transit_ribbon_progress",
            Int64(position.fraction * 100),
            position.nextStopName,
            Int64(minutes))
    }

    // MARK: Rows

    private func stopRow(_ stop: TransitLineStop, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(stop.clockText ?? "--")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(stop.passed ? Color.secondary : Color.primary)
                if let scheduled = stop.scheduledText {
                    Text(scheduled)
                        .font(.caption2)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
                if stop.hasDelay {
                    Text(delayText(Int(stop.delayMin)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(delayColor(Int(stop.delayMin)))
                }
            }
            .frame(width: timeWidth, alignment: .trailing)

            Color.clear.frame(width: railWidth, height: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(stop.next ? .body.weight(.semibold) : .body)
                    .foregroundStyle(stop.passed ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let code = stop.code, !code.isEmpty {
                        Text(VelaL10n.text("place_transit_stop_id", String(describing: (code))))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if stop.canceled {
                        Text(VelaL10n.text("place_transit_cancelled"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    if stop.passed {
                        Text(VelaL10n.text("transit_passed"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if stop.next {
                        Text(VelaL10n.text("transit_nav_next"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color)
                    }
                }
                if !stop.transferLines.isEmpty {
                    transferBadges(stop.transferLines)
                }
            }
            .opacity(stop.passed ? 0.55 : 1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .background(alignment: .topLeading) { rail(top: index == 0, bottom: index == stops.count - 1) }
        .overlay(alignment: .topLeading) {
            dot(stop, terminus: index == 0 || index == stops.count - 1)
                .offset(x: timeWidth + 8 + (railWidth - 22) / 2, y: dotTop)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: stop))
        .accessibilityIdentifier("transit-line-stop")
    }

    /// The rail behind one row: a clear gap above the first dot and below the last one, the line
    /// color everywhere else, so consecutive rows join into one continuous line.
    private func rail(top: Bool, bottom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: top ? dotTop + 11 : 0)
            Rectangle()
                .fill(color.opacity(0.9))
                .frame(width: 6)
            Color.clear.frame(height: bottom ? dotTop + 11 : 0)
        }
        .padding(.leading, lineX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dot(_ stop: TransitLineStop, terminus: Bool) -> some View {
        ZStack {
            if stop.next {
                Circle().fill(color).frame(width: 22, height: 22)
                Circle().fill(Color(uiColor: .systemBackground)).frame(width: 9, height: 9)
            } else if terminus {
                Circle().fill(color).frame(width: 20, height: 20)
                Circle().fill(Color(uiColor: .systemBackground)).frame(width: 7, height: 7)
            } else if stop.passed {
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .overlay(Circle().strokeBorder(color.opacity(0.8), lineWidth: 2))
                    .frame(width: 13, height: 13)
            } else {
                Circle().fill(color).frame(width: 15, height: 15)
            }
        }
        .frame(width: 22, height: 22)
    }

    private func transferBadges(_ lines: [TransitLineBadge]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(contrastText(for: line.colorHex))
                    .padding(.horizontal, 6)
                    .frame(minHeight: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(uiColor: UIColor(transitHex: line.colorHex) ?? .systemGray)))
            }
            Text(VelaL10n.text("transit_transfer"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VelaL10n.text("transit_transfer_to") + lines.map { VelaL10n.text("transit_line_4", String(describing: ($0.label))) }.joined(separator: ", "))
    }

    private func vehicleRow(fraction: Double) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear.frame(width: timeWidth, height: 1)
            Color.clear.frame(width: railWidth, height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(VelaL10n.text("transit_estimated_position"))
                    .font(.subheadline.weight(.semibold))
                Text(markerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .background(alignment: .topLeading) { rail(top: false, bottom: false) }
        .overlay(alignment: .topLeading) {
            ZStack {
                Capsule().fill(color).frame(width: 44, height: 18)
                Image(systemName: "tram.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(contrastText(for: colorHex))
            }
            .offset(x: timeWidth + 8 + (railWidth - 44) / 2, y: 6 + CGFloat(fraction) * 26)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VelaL10n.text("transit_estimated_vehicle_position_not_gps") + markerDetail)
        .accessibilityIdentifier("transit-line-vehicle")
    }

    private func delayText(_ minutes: Int) -> String {
        if minutes > 0 { return VelaL10n.text("transit_min_late", Int64(minutes)) }
        if minutes < 0 { return VelaL10n.text("transit_min_early", Int64(-minutes)) }
        return VelaL10n.text("transit_on_time")
    }

    private func delayColor(_ minutes: Int) -> Color {
        abs(minutes) < 2 ? .green : (abs(minutes) <= 5 ? .orange : .red)
    }

    private func accessibilityLabel(for stop: TransitLineStop) -> String {
        var parts: [String] = [stop.name]
        if let clock = stop.clockText { parts.append(clock) }
        if stop.passed { parts.append("Passed") }
        if stop.next { parts.append("Next stop") }
        if stop.canceled { parts.append("Canceled") }
        if stop.hasDelay { parts.append(delayText(Int(stop.delayMin))) }
        if !stop.transferLines.isEmpty {
            parts.append("Transfer to " + stop.transferLines.map { "line \($0.label)" }.joined(separator: ", "))
        }
        return parts.joined(separator: ". ")
    }

    /// Black or white on the line color, from its own luminance: the badge and the marker stay
    /// readable whatever color the agency publishes.
    private func contrastText(for hex: String) -> Color {
        guard let ui = UIColor(transitHex: hex) else { return .white }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? .black : .white
    }
}
