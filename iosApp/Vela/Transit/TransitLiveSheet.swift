import SwiftUI
import UIKit
import VelaCore

/// T-2's transit panel: the reachable area and the colored lines with their delays. Both are loaded
/// by an explicit button, never a timer, and both say where their answer came from. The preview is
/// the same descriptor the map layer draws, shown here so the panel works without the map lot; it
/// is not a second map.
struct TransitLiveSheet: View {
    @StateObject private var model: TransitLiveModel
    /// SELECTION-SYNC: every row reads and writes the one selection. A row tapped here moves the
    /// map halo; a symbol tapped on the map opens this panel on the matching tab.
    @ObservedObject private var selection = EntitySelection.shared
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
                ScrollViewReader { proxy in
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
                    .onChange(of: selection.revision, initial: true) { _, _ in
                        scrollToSelection(proxy)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(VelaL10n.text("transit_transit_live"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("place_close"), action: onClose)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-live-close")
                }
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-live-sheet")
        .onAppear {
            model.start()
            focusTabForSelection()
        }
    }

    /// A map tap on a vehicle or a line opens this panel on the tab that owns the row, so the
    /// highlighted row is visible without hunting through the three tabs.
    private func focusTabForSelection() {
        guard let value = selection.value else { return }
        switch value.kind {
        case .vehicle: tab = 2
        case .line: tab = 1
        case .stop: tab = 0
        default: break
        }
    }

    /// The row id of the current selection, in the tab that owns it. A row the panel does not list
    /// (a place, a saved pin) has no id, and the scroll is a no-op.
    private var selectionRowId: String? {
        guard let value = selection.value else { return nil }
        switch value.kind {
        case .vehicle: return "selection-vehicle-\(value.id)"
        case .line: return "selection-line-\(value.id)"
        case .stop: return "selection-stop-\(value.id)"
        default: return nil
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = selectionRowId else { return }
        withAnimation(nil) { proxy.scrollTo(id, anchor: .center) }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            tabButton("Reachability", value: 0, id: "transit-live-tab-reach")
            tabButton("Live lines", value: 1, id: "transit-live-tab-lines")
            tabButton("Vehicles", value: 2, id: "transit-live-tab-vehicles")
            Spacer(minLength: 0)
            if model.isRateLimited || model.isBudgetExhausted {
                Text(VelaL10n.text("transit_limit_reached"))
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
            Text(VelaL10n.text("transit_reachable_in"))
                .font(.headline)
            HStack(spacing: 8) {
                ForEach([10, 20, 30, 45], id: \.self) { minutes in
                    Button(VelaL10n.text("transit_min_3", String(describing: (minutes)))) { model.setMinutes(minutes) }
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
                Label(VelaL10n.text("transit_show_reachable_area"), systemImage: "circle.dashed")
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("transit-live-reach-load")

            // T2-REACH: the full screen carries the 15/30/45/60 choice, the stop list and the
            // honesty note; this tab keeps the quick hull preview next to it.
            Button {
                TransitReachLink.shared.open(
                    originLat: originLat, originLng: originLng, originName: "",
                    service: nil)
            } label: {
                Label(VelaL10n.text("transit_reach_open_full"), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("transit-live-reach-full")

            Text(VelaL10n.text("transit_a_hull_drawn_around_the_stops"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let area = model.area {
                TransitPreviewCanvas(area: area)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("transit-live-canvas")
                Text(VelaL10n.text("transit_stops_within_min_from", String(describing: (area.stops.count)), String(describing: (area.maxMinutes)), String(describing: (originName.isEmpty ? VelaL10n.text("transit_this_point") : originName))))
                    .font(.subheadline)
                ForEach(area.stops.prefix(40), id: \.stopId) { stop in
                    reachStopRow(stop)
                }
            } else if model.reachLoading {
                ProgressView(VelaL10n.text("transit_asking_transitous"))
            } else if !model.reachError.isEmpty {
                Text(errorText(model.reachError, kind: "reachability"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transit-live-reach-error")
            }

        }
        .padding(16)
    }

    /// One reachable stop. The row is also the list side of a stop selection: tapping it puts the
    /// map halo on the stop and centres there when the stop is off screen.
    private func reachStopRow(_ stop: TransitReachStop) -> some View {
        let selected = selection.matches(
            kind: .stop, id: stop.stopId, latitude: stop.lat, longitude: stop.lng)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(VelaL10n.text("transit_min_4", String(describing: (stop.minutes))))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 52, alignment: .leading)
            Text(stop.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            if stop.transfers > 0 {
                Text(VelaL10n.text("transit_transfers_count", Int(stop.transfers)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            if selected {
                selection.clear()
            } else {
                selection.select(
                    kind: .stop, id: stop.stopId, label: stop.name,
                    latitude: stop.lat, longitude: stop.lng, source: .list)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VelaL10n.text("transit_minutes_changes", String(describing: (stop.name)), String(describing: (stop.minutes)), String(describing: (stop.transfers))))
        .accessibilityValue(selected ? "selected" : "unselected")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("transit-live-reach-stop")
        .id("selection-stop-\(stop.stopId)")
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
            Text(VelaL10n.text("transit_lines_in_service"))
                .font(.headline)
            Button {
                model.loadLines(lat: originLat, lng: originLng)
            } label: {
                Label(VelaL10n.text("transit_load_live_lines"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("transit-live-lines-load")

            Text(VelaL10n.text("transit_a_color_is_the_agency_s"))
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
                    Text(VelaL10n.text("transit_only_the_first_stretches_are_drawn", String(describing: (model.linesSegments))))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                delayLegend
            } else if model.linesLoading {
                ProgressView(VelaL10n.text("transit_asking_transitous"))
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
        let selected = selection.isSelected(.line, id: line.label)
        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(transitHex: line.colorHex) ?? .gray)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.label)
                        .font(.subheadline.weight(.semibold))
                    if let destination = line.destination, !destination.isEmpty {
                        Text(VelaL10n.text("transit_nav_towards", String(describing: (destination))))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(line.feedColorHex == nil ? VelaL10n.text("transit_vela_mode_color") : VelaL10n.text("transit_agency_color"))
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
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { selectLineRow(line, selected: selected) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(line))
        .accessibilityValue(selected ? "selected" : "unselected")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("transit-live-line")
        .id("selection-line-\(line.label)")
    }

    /// A line row selects the line on the map and opens its card, so the two surfaces name the
    /// same entity. The anchor is the first vertex the feed sent; a line with no path falls back
    /// to the panel's origin.
    private func selectLineRow(_ line: TransitLiveLine, selected: Bool) {
        if selected {
            selection.clear()
            return
        }
        let vertex = line.paths.first?.first
        let latitude = vertex?.lat ?? originLat
        let longitude = vertex?.lng ?? originLng
        selection.select(
            kind: .line, id: line.label, label: line.label,
            latitude: latitude, longitude: longitude, source: .list)
        TransitLineLink.shared.open(
            line: line.label, direction: line.destination,
            stop: TransitLineStopRef(
                stopId: nil, name: line.destination ?? line.label,
                latitude: latitude, longitude: longitude))
    }

    @ViewBuilder private func liveBadge(_ line: TransitLiveLine) -> some View {
        if line.live {
            Text(VelaL10n.text("place_transit_live"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green, in: Capsule())
                .accessibilityIdentifier("transit-live-live-badge")
        } else {
            Text(VelaL10n.text("place_transit_scheduled"))
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
            Text(VelaL10n.text("transit_no_delay_data"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-live-delay-none")
        }
    }

    private func accessibilityLabel(_ line: TransitLiveLine) -> String {
        var parts = [
            line.label,
            line.destination.map { VelaL10n.text("transit_nav_towards", $0) }
                ?? VelaL10n.text("transit_no_direction"),
        ]
        parts.append(line.live
                     ? VelaL10n.text("place_transit_live")
                     : VelaL10n.text("place_transit_scheduled"))
        if let minutes = line.delayMinutes?.intValue {
            parts.append(delayText(minutes))
            parts.append(delayBandText(line.delayLevel))
        } else {
            parts.append(VelaL10n.text("transit_no_delay_data"))
        }
        return parts.joined(separator: ", ")
    }

    private func delayText(_ minutes: Int) -> String {
        if minutes == 0 { return VelaL10n.text("transit_on_time") }
        return minutes > 0
            ? VelaL10n.text("transit_min_late", Int64(minutes))
            : VelaL10n.text("transit_min_early", Int64(-minutes))
    }

    private func delayBandText(_ level: String) -> String {
        switch level {
        case "green": return VelaL10n.text("transit_delay_under_2")
        case "amber": return VelaL10n.text("transit_delay_2_to_5")
        case "red": return VelaL10n.text("transit_delay_over_5")
        default: return VelaL10n.text("transit_unknown")
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
            legendDot(.green, VelaL10n.text("transit_legend_under_2_min"))
            legendDot(.orange, VelaL10n.text("transit_legend_2_to_5_min"))
            legendDot(.red, VelaL10n.text("transit_legend_over_5_min"))
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
            return VelaL10n.text("transit_live_error_rate_limited", kind)
        case "budget_exhausted":
            return VelaL10n.text("transit_live_error_budget")
        case "no_service":
            return VelaL10n.text("transit_live_error_no_service")
        default:
            return VelaL10n.text("transit_live_error_default", kind)
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
