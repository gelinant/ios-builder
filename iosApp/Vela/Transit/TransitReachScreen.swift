import SwiftUI
import UIKit
import VelaCore

/// "Reachable in N minutes": the four budgets, the reachable stops sorted by travel time with
/// their changes, and one action that publishes Vela's convex hull through the existing overlay
/// mailbox. The screen says in words that the outline is a hull of reachable stops and not an
/// official isochrone, that each budget change is one heavy Transitous request cached five
/// minutes, and that offline or NoGoogle means no area at all rather than a stale one.
struct TransitReachScreen: View {
    @StateObject private var model: TransitReachModel
    private let onClose: () -> Void

    init(model: TransitReachModel, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    #if DEBUG
                    Text(model.debugLine)
                        .font(.caption2.monospaced())
                        .lineLimit(3)
                        .accessibilityIdentifier("transit-reach-debug")
                    #endif
                    origin
                    minutesRow
                    Text(VelaL10n.text("transit_reach_not_official"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transit-reach-disclaimer")
                    Text(VelaL10n.text("transit_reach_network_note"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    mapAction
                    content
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(VelaL10n.text(
                "transit_reach_title", String(describing: model.minutes)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("place_close"), action: onClose)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-reach-close")
                }
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-reach-screen")
        .onAppear { model.start() }
    }

    private var origin: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "location.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(VelaL10n.text(
                "transit_reach_from",
                model.originName.isEmpty ? VelaL10n.text("transit_this_point") : model.originName))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("transit-reach-origin")
            Spacer(minLength: 0)
        }
    }

    private var minutesRow: some View {
        HStack(spacing: 8) {
            ForEach(TransitReachModel.minuteOptions, id: \.self) { minutes in
                Button(VelaL10n.text("transit_min_3", String(describing: minutes))) {
                    model.setMinutes(minutes)
                }
                .buttonStyle(.bordered)
                .tint(model.minutes == minutes ? Color.accentColor : Color.secondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("transit-reach-minutes-\(minutes)")
            }
            Spacer(minLength: 0)
        }
    }

    private var mapAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.publishHull()
            } label: {
                Label(VelaL10n.text("transit_reach_show_hull"), systemImage: "circle.dashed")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canPublishHull)
            .accessibilityIdentifier("transit-reach-map")
            if model.hullPublished {
                Text(VelaL10n.text("transit_reach_published"))
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("transit-reach-published")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.isBlocked {
            needsTransitous
        } else if model.loading && model.area == nil {
            ProgressView(VelaL10n.text("transit_reach_loading"))
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("transit-reach-loading")
        } else if let area = model.area {
            if area.stops.isEmpty {
                emptyState(area)
            } else {
                result(area)
            }
            if !model.errorKey.isEmpty {
                errorText(model.errorKey)
            }
        } else if !model.errorKey.isEmpty {
            errorText(model.errorKey)
            retryButton
        } else {
            ProgressView(VelaL10n.text("transit_reach_loading"))
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func result(_ area: TransitReachArea) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(VelaL10n.text(
                "transit_reach_stops_within",
                String(describing: area.stops.count),
                String(describing: area.maxMinutes)))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("transit-reach-summary")
            TransitReachPreview(area: area)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(VelaL10n.text("transit_reach_not_official"))
                .accessibilityIdentifier("transit-reach-canvas")
            ForEach(model.stops, id: \.stopId) { stop in
                stopRow(stop)
            }
        }
    }

    private func stopRow(_ stop: TransitReachStop) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(VelaL10n.text("transit_min_3", String(describing: stop.minutes)))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 56, alignment: .leading)
            Text(stop.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(changesText(Int(stop.transfers)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VelaL10n.text(
            "transit_reach_row_label",
            stop.name,
            String(describing: stop.minutes),
            changesText(Int(stop.transfers))))
        .accessibilityIdentifier("transit-reach-stop")
    }

    private func emptyState(_ area: TransitReachArea) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VelaL10n.text(
                "transit_reach_empty",
                String(describing: area.maxMinutes),
                area.originName.isEmpty ? VelaL10n.text("transit_this_point") : area.originName))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-reach-empty")
            retryButton
        }
    }

    private var needsTransitous: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VelaL10n.text("transit_reach_needs_transitous"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-reach-needs-network")
            Text(VelaL10n.text("transit_reach_offline_detail"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            retryButton
        }
    }

    private var retryButton: some View {
        Button(VelaL10n.text("transit_reach_retry")) {
            model.retry()
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .disabled(model.isBlocked)
        .accessibilityIdentifier("transit-reach-retry")
    }

    private func errorText(_ key: String) -> some View {
        Text(errorSentence(key))
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityIdentifier("transit-reach-error")
    }

    private func errorSentence(_ key: String) -> String {
        switch key {
        case "rate_limited":
            return VelaL10n.text("transit_live_error_rate_limited", "reachability")
        case "budget_exhausted":
            return VelaL10n.text("transit_live_error_budget")
        case "failed":
            return VelaL10n.text("transit_reach_failed")
        case "needs_transitous":
            return VelaL10n.text("transit_reach_needs_transitous")
        default:
            return VelaL10n.text("transit_reach_failed")
        }
    }

    private func changesText(_ transfers: Int) -> String {
        if transfers < 0 { return VelaL10n.text("transit_reach_changes_unknown") }
        if transfers == 0 { return VelaL10n.text("transit_reach_no_change") }
        if transfers == 1 { return VelaL10n.text("transit_reach_one_change") }
        return VelaL10n.text("transit_reach_changes", String(describing: transfers))
    }
}

/// The hull and its dots as a small preview, drawn only from the feed's coordinates. It is not a
/// second map: no tiles and no invented geography. The real overlay goes through the shared hub.
private struct TransitReachPreview: View {
    let area: TransitReachArea

    var body: some View {
        Canvas { context, size in
            let points = area.hull + area.stops.map { LatLng(lat: $0.lat, lng: $0.lng) }
            guard let project = ReachProjection(points: points, size: size) else { return }
            if area.hull.count >= 3 {
                let corners = area.hull.map(project.point)
                var path = Path()
                path.move(to: corners[0])
                for corner in corners.dropFirst() { path.addLine(to: corner) }
                path.closeSubpath()
                context.fill(path, with: .color(Color.blue.opacity(0.16)))
                context.stroke(path, with: .color(Color.blue.opacity(0.85)), lineWidth: 1.5)
            }
            for stop in area.stops {
                let center = project.point(LatLng(lat: stop.lat, lng: stop.lng))
                let rect = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: rect), with: .color(.blue))
            }
            let origin = project.point(LatLng(lat: area.originLat, lng: area.originLng))
            let originRect = CGRect(x: origin.x - 4, y: origin.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: originRect), with: .color(.orange))
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    /// Fits the points into the canvas with one scale, so the hull keeps its shape. North is up.
    private struct ReachProjection {
        private let minLat: Double
        private let maxLat: Double
        private let minLng: Double
        private let maxLng: Double
        private let scale: Double
        private let offsetX: Double
        private let offsetY: Double

        init?(points: [LatLng], size: CGSize) {
            guard let first = points.first else { return nil }
            var minLat = first.lat, maxLat = first.lat
            var minLng = first.lng, maxLng = first.lng
            for point in points {
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
                minLng = min(minLng, point.lng)
                maxLng = max(maxLng, point.lng)
            }
            let spanLat = max(maxLat - minLat, 0.0005)
            let spanLng = max(maxLng - minLng, 0.0005)
            let padding = 18.0
            scale = min((size.width - padding * 2) / spanLng, (size.height - padding * 2) / spanLat)
            offsetX = (size.width - spanLng * scale) / 2
            offsetY = (size.height - spanLat * scale) / 2
            self.minLat = minLat
            self.maxLat = maxLat
            self.minLng = minLng
            self.maxLng = maxLng
        }

        func point(_ point: LatLng) -> CGPoint {
            CGPoint(
                x: offsetX + (point.lng - minLng) * scale,
                y: offsetY + (maxLat - point.lat) * scale)
        }
    }
}

/// THE entry point for the reachability screen, the same shape as `TransitLineLink`: the caller
/// passes the origin and the shared service, the link presents the sheet and owns its lifetime.
/// No map file changes. A future hook is one call from the transit panel or the map menu:
///
///     TransitReachLink.shared.open(
///         originLat: lat, originLng: lng, originName: name, service: live)
@MainActor
final class TransitReachLink {
    static let shared = TransitReachLink()

    private var host: UIViewController?
    private init() {}

    func open(
        originLat: Double,
        originLng: Double,
        originName: String,
        service: TransitLiveService?,
        offline: OfflineStore? = AppGraph.session.offline
    ) {
        let model = TransitReachModel(
            service: service,
            offline: offline,
            originLat: originLat,
            originLng: originLng,
            originName: originName)
        let screen = TransitReachScreen(model: model) { [weak self] in
            self?.close()
        }
        let controller = UIHostingController(rootView: screen)
        controller.modalPresentationStyle = .pageSheet
        controller.view.accessibilityIdentifier = "transit-reach-host"
        if let presentation = controller.sheetPresentationController {
            presentation.detents = [.large()]
            presentation.prefersGrabberVisible = true
        }
        host = controller
        topViewController()?.present(controller, animated: !LaunchOptions.current.deterministic)
    }

    func close() {
        let controller = host
        host = nil
        controller?.dismiss(animated: !LaunchOptions.current.deterministic)
    }

    private func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        if let navigation = root as? UINavigationController {
            return topViewController(navigation.visibleViewController)
        }
        if let tabs = root as? UITabBarController {
            return topViewController(tabs.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(presented)
        }
        return root
    }
}
