import SwiftUI
import UIKit
import VelaCore

/// T-2's transit panel: the reachable area and the colored lines with their delays. Both are loaded
/// by an explicit button, never a timer, and both say where their answer came from. The preview is
/// the same descriptor the map layer draws, shown here so the panel works without the map lot; it
/// is not a second map.
struct TransitLiveSheet: View {
    @StateObject private var model: TransitLiveModel
    private let originLat: Double
    private let originLng: Double
    private let originName: String
    private let service: TransitLiveService?
    private let onClose: () -> Void

    @State private var tab = 0

    init(
        service: TransitLiveService?,
        originLat: Double,
        originLng: Double,
        originName: String,
        onClose: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: TransitLiveModel(service: service))
        self.originLat = originLat
        self.originLng = originLng
        self.originName = originName
        self.service = service
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabs
                Divider()
                ScrollView {
                    if tab == 0 {
                        reachTab
                    } else if tab == 1 {
                        linesTab
                    } else {
                        // TRANSIT-INTERP: the estimated vehicles, on their own tab and switch.
                        TransitVehiclePanel(
                            live: service, lat: originLat, lng: originLng, originName: originName)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Transit live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-live-close")
                }
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-live-sheet")
        .onAppear { model.start() }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            tabButton("Reachability", value: 0, id: "transit-live-tab-reach")
            tabButton("Live lines", value: 1, id: "transit-live-tab-lines")
            tabButton("Vehicles", value: 2, id: "transit-live-tab-vehicles")
            Spacer(minLength: 0)
            if model.isRateLimited || model.isBudgetExhausted {
                Text("Limit reached")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transit-live-limit")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func tabButton(_ title: String, value: Int, id: String) -> some View {
        Button(title) { tab = value }
            .buttonStyle(.bordered)
            .tint(tab == value ? Color.accentColor : Color.secondary)
            .frame(minHeight: 44)
            .accessibilityIdentifier(id)
    }

    // MARK: Reachability

    private var reachTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if DEBUG
            Text(model.reachDebugLine)
                .font(.caption2.monospaced())
                .accessibilityIdentifier("transit-live-reach-debug")
            #endif
            Text("Reachable in")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach([10, 20, 30, 45], id: \.self) { minutes in
                    Button("\(minutes) min") { model.setMinutes(minutes) }
                        .buttonStyle(.bordered)
                        .tint(model.minutes == minutes ? Color.accentColor : Color.secondary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-live-minutes-\(minutes)")
                }
                Spacer(minLength: 0)
            }
            Button {
                model.loadReach(lat: originLat, lng: originLng)
            } label: {
                Label("Show reachable area", systemImage: "circle.dashed")
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("transit-live-reach-load")

            Text("A hull drawn around the stops Transitous reached, not an official isochrone polygon. It can cover a block or a bay between two stops.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let area = model.area {
                TransitPreviewCanvas(area: area)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("transit-live-canvas")
                Text("\(area.stops.count) stops within \(area.maxMinutes) min from \(originName.isEmpty ? "this point" : originName).")
                    .font(.subheadline)
                ForEach(area.stops.prefix(40), id: \.stopId) { stop in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(stop.minutes) min")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(width: 52, alignment: .leading)
                        Text(stop.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if stop.transfers > 0 {
                            Text("\(stop.transfers) change\(stop.transfers == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stop.name), \(stop.minutes) minutes, \(stop.transfers) changes")
                    .accessibilityIdentifier("transit-live-reach-stop")
                }
            } else if model.reachLoading {
                ProgressView("Asking Transitous")
            } else if !model.reachError.isEmpty {
                Text(errorText(model.reachError, kind: "reachability"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transit-live-reach-error")
            }

        }
        .padding(16)
    }

    // MARK: Live lines

    private var linesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if DEBUG
            Text(model.linesDebugLine)
                .font(.caption2.monospaced())
                .lineLimit(2)
                .accessibilityIdentifier("transit-live-lines-debug")
            #endif
            Text("Lines in service")
                .font(.headline)
            Button {
                model.loadLines(lat: originLat, lng: originLng)
            } label: {
                Label("Load live lines", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("transit-live-lines-load")

            Text("A color is the agency's own when the feed sent one, otherwise Vela's mode color. A delay color needs a scheduled time and a real time; without both the row stays gray. The API has no vehicle position.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !model.lines.isEmpty {
                TransitPreviewCanvas(lines: model.lines)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("transit-live-lines-canvas")
                ForEach(model.lines, id: \.label) { line in
                    lineRow(line)
                }
                if model.linesTruncated {
                    Text("Only the first \(model.linesSegments) stretches are drawn.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                delayLegend
            } else if model.linesLoading {
                ProgressView("Asking Transitous")
            } else if !model.linesError.isEmpty {
                Text(errorText(model.linesError, kind: "lines"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transit-live-lines-error")
            }

        }
        .padding(16)
    }

    private func lineRow(_ line: TransitLiveLine) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(transitHex: line.colorHex) ?? .gray)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.label)
                        .font(.subheadline.weight(.semibold))
                    if let destination = line.destination, !destination.isEmpty {
                        Text("towards \(destination)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(line.feedColorHex == nil ? "Vela mode color" : "Agency color")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                liveBadge(line)
                delayBadge(line)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(line))
        .accessibilityIdentifier("transit-live-line")
    }

    @ViewBuilder private func liveBadge(_ line: TransitLiveLine) -> some View {
        if line.live {
            Text("Live")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green, in: Capsule())
                .accessibilityIdentifier("transit-live-live-badge")
        } else {
            Text("Scheduled")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-live-scheduled-badge")
        }
    }

    @ViewBuilder private func delayBadge(_ line: TransitLiveLine) -> some View {
        if let minutes = line.delayMinutes?.intValue {
            Text(delayText(minutes))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(delayColor(line.delayLevel))
                .accessibilityIdentifier("transit-live-delay")
        } else {
            Text("No delay data")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-live-delay-none")
        }
    }

    private func accessibilityLabel(_ line: TransitLiveLine) -> String {
        var parts = [line.label, line.destination.map { "towards \($0)" } ?? "no direction"]
        parts.append(line.live ? "live" : "scheduled")
        if let minutes = line.delayMinutes?.intValue {
            parts.append(delayText(minutes))
            parts.append(delayBandText(line.delayLevel))
        } else {
            parts.append("no delay data")
        }
        return parts.joined(separator: ", ")
    }

    private func delayText(_ minutes: Int) -> String {
        if minutes == 0 { return "On time" }
        return minutes > 0 ? "\(minutes) min late" : "\(-minutes) min early"
    }

    private func delayBandText(_ level: String) -> String {
        switch level {
        case "green": return "under 2 minutes"
        case "amber": return "2 to 5 minutes"
        case "red": return "over 5 minutes"
        default: return "unknown"
        }
    }

    private func delayColor(_ level: String) -> Color {
        switch level {
        case "green": return .green
        case "amber": return .orange
        case "red": return .red
        default: return .secondary
        }
    }

    private var delayLegend: some View {
        HStack(spacing: 12) {
            legendDot(.green, "under 2 min")
            legendDot(.orange, "2 to 5 min")
            legendDot(.red, "over 5 min")
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("transit-live-delay-legend")
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func errorText(_ key: String, kind: String) -> String {
        switch key {
        case "rate_limited":
            return "Transitous asked Vela to slow down. The last \(kind) answer stays on screen; nothing is retried automatically."
        case "budget_exhausted":
            return "Vela reached its own daily share of Transitous requests. It will not ask again until the 24-hour window passes."
        case "no_service":
            return "The transit service is not available in this build."
        default:
            return "Transitous did not answer for the \(kind). The last answer stays on screen."
        }
    }
}

/// The descriptor as a small preview: the hull and its dots, or the line paths with their colors.
/// It is deliberately not a second map: no tiles, no labels, no invented geography.
private struct TransitPreviewCanvas: View {
    var area: TransitReachArea? = nil
    var lines: [TransitLiveLine]? = nil

    var body: some View {
        Canvas { context, size in
            if let area {
                drawArea(area, in: context, size: size)
            } else if let lines {
                drawLines(lines, in: context, size: size)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func drawArea(_ area: TransitReachArea, in context: GraphicsContext, size: CGSize) {
        let points = area.hull + area.stops.map { LatLng(lat: $0.lat, lng: $0.lng) }
        guard let project = Projection(points: points, size: size) else { return }
        if area.hull.count >= 3 {
            var path = Path()
            let hull = area.hull.map(project.point)
            path.move(to: hull[0])
            for point in hull.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            context.fill(path, with: .color(Color.blue.opacity(0.18)))
            context.stroke(path, with: .color(Color.blue.opacity(0.8)), lineWidth: 1.5)
        }
        for stop in area.stops {
            let center = project.point(LatLng(lat: stop.lat, lng: stop.lng))
            let rect = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: rect), with: .color(.blue))
        }
    }

    private func drawLines(_ lines: [TransitLiveLine], in context: GraphicsContext, size: CGSize) {
        let all = lines.flatMap { $0.paths.flatMap { $0 } }
        guard let project = Projection(points: all, size: size) else { return }
        for line in lines {
            for path in line.paths where path.count >= 2 {
                var drawn = Path()
                drawn.move(to: project.point(path[0]))
                for point in path.dropFirst() { drawn.addLine(to: project.point(point)) }
                context.stroke(
                    drawn,
                    with: .color(Color(transitHex: line.colorHex) ?? .gray),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Fits geographic points into the canvas with one scale, so a path keeps its shape.
    private struct Projection {
        private let minLat: Double
        private let maxLat: Double
        private let minLng: Double
        private let maxLng: Double
        private let size: CGSize
        private let scale: Double
        private let offsetX: Double
        private let offsetY: Double

        init?(points: [LatLng], size: CGSize) {
            guard let first = points.first else { return nil }
            var minLat = first.lat, maxLat = first.lat
            var minLng = first.lng, maxLng = first.lng
            for point in points {
                minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
                minLng = min(minLng, point.lng); maxLng = max(maxLng, point.lng)
            }
            let spanLat = max(maxLat - minLat, 0.0005)
            let spanLng = max(maxLng - minLng, 0.0005)
            let padding = 18.0
            scale = min((size.width - padding * 2) / spanLng, (size.height - padding * 2) / spanLat)
            offsetX = (size.width - spanLng * scale) / 2
            offsetY = (size.height - spanLat * scale) / 2
            self.minLat = minLat; self.maxLat = maxLat
            self.minLng = minLng; self.maxLng = maxLng
            self.size = size
        }

        func point(_ point: LatLng) -> CGPoint {
            let x = offsetX + (point.lng - minLng) * scale
            // North is up.
            let y = offsetY + (maxLat - point.lat) * scale
            return CGPoint(x: x, y: y)
        }
    }
}

private extension Color {
    init?(transitHex: String) {
        var hex = transitHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1)
    }
}
