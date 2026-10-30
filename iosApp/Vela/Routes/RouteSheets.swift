import SwiftUI
import UIKit
import CoreLocation
import VelaCore

/// RTE-STEP: the steps sheet has no controller, so it asks the map through these notifications.
/// A request carries the maneuver's own point and the drawn line it belongs to.
enum RouteStepMapLink {
    static let focusRequest = Notification.Name("VelaRouteStepFocusRequest")
    static let focusApplied = Notification.Name("VelaRouteStepFocusApplied")
    static let overviewRequest = Notification.Name("VelaRouteOverviewRequest")
    static let indexKey = "index"
    static let zoomKey = "zoom"
}

struct RouteStepFocusRequest {
    let index: Int
    let target: CLLocationCoordinate2D
    let line: [CLLocationCoordinate2D]
}

struct RouteOverviewRequest {
    let line: [CLLocationCoordinate2D]
}

// English for now; the String Catalog keys (I-8) come with the strings script.

/// The route chooser over the bottom of the map, in Android's two presentations: the compact
/// picker (the selected route, its traffic line, Start and Steps) and the expanded sheet (time,
/// stops, avoids, every alternate). Both keep the mode chips pinned and the same Start/Steps
/// actions at the bottom; the content order never changes between them.
struct RoutePickerSheet: View {
    @ObservedObject var model: RouteModel
    /// Owned by MapScreen so the host frame can grow with the same toggle: compact keeps half
    /// the screen, expanded takes 85 percent and leaves the action rows above the bottom edge.
    @Binding var expanded: Bool
    let savedPlaces: [SavedMapMarker]
    let onClose: () -> Void
    @State private var placePick: RoutePlacePickKind?
    @State private var routeShare: VelaSharePayload?
    /// A no-op fallback lets the route chooser ship before its navigation host is wired.
    var onStart: () -> Void = {}
    /// Transit uses its own session; nil keeps the original Start callback for embedding previews.
    var onStartTransit: (() -> Void)?
    /// The free-drive entry: leaves the planned route and starts a drive with no destination.
    var onFreeDrive: (() -> Void)? = nil

    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The measured viewport of the unified scroll, published in the debug rows so a run can
    /// prove the height instead of inferring it from a frame.
    @State private var scrollViewport: CGSize = .zero

    private var needsUnifiedScroll: Bool {
        sizeCategory.isAccessibilityCategory || verticalSizeClass == .compact
    }

    /// Large text and landscape cannot split a card into a pinned part and a scrolling one without
    /// hiding something: the rows below the grabber scroll as one column, as Q-2 fixed it. The
    /// grabber stays pinned, not for layout but for the accessibility tree: with the scroll as the
    /// sheet's only accessible child, SwiftUI hoisted the sheet's `route-sheet` identifier onto
    /// that scroll view and `route-scroll` vanished. One real sibling keeps the sheet container
    /// and gives the scroll its own element. The debug lines stay inside the scroll: at AX5 they
    /// were the rows that ate the half-height viewport when they also sat above it.
    var body: some View {
        Group {
            if needsUnifiedScroll {
                unifiedScroll
            } else {
                splitBody
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .sheet(item: $placePick) { kind in
            RoutePlacePicker(kind: kind, model: model, savedPlaces: savedPlaces)
        }
        .sheet(item: $routeShare) { payload in
            ActivityView(items: payload.items, subject: payload.subject)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-sheet")
    }

    /// The large-text and landscape presentation: the grabber pinned, then one scroll for every
    /// other row, debug lines included. The scroll's measured container carries `route-scroll`;
    /// the container spans the real viewport, so a drag aimed at it reaches the same content.
    private var unifiedScroll: some View {
        VStack(alignment: .leading, spacing: 10) {
            expandHandle
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        debugRows
                        header
                        modeChips
                        summary
                        expandedBody
                        actions
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onAppear { scrollViewport = proxy.size }
                .onChange(of: proxy.size) { _, size in scrollViewport = size }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route-scroll")
        }
    }

    /// Portrait at normal text: the header and the modes stay pinned, the selected route or the
    /// expanded body scrolls between them and the action row.
    private var splitBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            expandHandle
            debugRows
            header
            modeChips
            if expanded {
                summary
                ScrollView { expandedBody }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("route-scroll")
            } else {
                ScrollView { summary }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("route-scroll")
            }
            actions
        }
    }

    /// Kept at the top: at the bottom of a half-height sheet SwiftUI pushed it under the edge,
    /// which hid the route state from the scenarios in VAL-1. MapScreen hides its debug block
    /// while a bottom sheet is open, so the chooser carries the route state line itself.
    @ViewBuilder private var debugRows: some View {
        #if DEBUG
        Text(model.debugLine)
            .font(.caption2.monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("route-debug")
        Text(shareDebugValue)
            .font(.caption2.monospaced())
            .lineLimit(2)
            .accessibilityLabel(shareDebugValue)
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("route-share-debug")
        Text(scrollDebugValue)
            .font(.caption2.monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("route-scroll-debug")
        #endif
    }

    /// The unified branch's measured viewport. The split branch keeps its own scroll view and
    /// reports zero here, which is why the scenario reads the line only at accessibility sizes.
    private var scrollDebugValue: String {
        #if DEBUG
        "scroll=\(Int(scrollViewport.width))x\(Int(scrollViewport.height))" +
            " unified=\(needsUnifiedScroll ? 1 : 0)"
        #else
        ""
        #endif
    }

    /// The grabber doubles as the compact/expanded switch, so the presentation is reachable by
    /// touch, VoiceOver and the UI tests alike.
    private var expandHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(spacing: 2) {
                Capsule()
                    .fill(Color(uiColor: .tertiaryLabel))
                    .frame(width: 36, height: 5)
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel(expanded ? VelaL10n.text("route_collapse_the_route_list") : VelaL10n.text("route_show_all_routes"))
        .accessibilityValue(expanded ? "expanded" : "compact")
        .accessibilityIdentifier("route-expand")
    }

    @ViewBuilder private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.mode == .drive || model.mode == .transit {
                RouteTimeOptions(model: model)
            }
            if model.mode != .transit || !model.waypoints.isEmpty {
                RouteStopsOptions(model: model, onAdd: { placePick = .waypoint })
            }
            if model.mode == .drive && model.avoidSupported {
                avoids
            }
            if model.mode == .drive, let onFreeDrive {
                Divider()
                Button(action: onFreeDrive) {
                    Label(VelaL10n.text("map_drive_without_a_destination"), systemImage: "steeringwheel")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("route-free-drive")
            }
            ForEach(model.choices) { choice in
                RouteChoiceRow(
                    choice: choice,
                    rank: RouteRank.label(choices: model.choices, index: choice.id),
                    selected: choice.id == model.activeIndex,
                    showsCameras: model.avoidCameras && model.canAvoidCameras
                ) {
                    model.select(choice.id)
                }
                Divider()
            }
            if model.mode == .transit {
                ForEach(model.transit) { trip in
                    TransitChoiceRow(trip: trip, selected: trip.id == model.activeIndex) {
                        model.select(trip.id)
                    }
                    Divider()
                }
                if !model.transit.isEmpty {
                    Text(VelaL10n.text("route_timetables_from_transitous"))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .padding(.top, 8)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-expanded")
    }

    /// The selected route, always visible in both presentations: its time, distance, why it is
    /// the pick, and the traffic line (live, typical, or the on-demand offer).
    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.loading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(VelaL10n.text("saved_finding_routes"))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .padding(.vertical, 8)
            } else if let message = model.message {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .accessibilityIdentifier("route-message")
                    Button(VelaL10n.text("voice_error_retry"), action: model.retry)
                        .frame(minHeight: 44)
                }
                .padding(.vertical, 8)
            }
            if model.mode == .bicycle {
                RouteBikeProfileStep(model: model)
            }
            if let active = model.activeChoice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(RouteFormat.duration(active.seconds))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(RouteChoiceRow.delayColor(active))
                    Text(RouteFormat.distance(active.meters))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                RouteCameraRow(model: model, choice: active)
                if model.canAvoidCameras && model.mode != .transit {
                    cameraAvoids
                }
                if let rank = RouteRank.label(choices: model.choices, index: model.activeIndex) {
                    Text(rank)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityIdentifier("route-rank")
                }
                if let via = active.via {
                    Text(VelaL10n.text("exp_chooser_via", via))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let warning = model.closingHint {
                    RouteClosingRow(warning: warning)
                }
                if let detour = model.fuelDetourHint {
                    RouteFuelRow(detour: detour)
                }
                RouteTrafficRow(model: model, choice: active)
            } else if let trip = model.activeTransit {
                let line = [trip.durationText ?? RouteFormat.duration(trip.seconds),
                            [trip.departText, trip.arriveText].compactMap { $0 }.joined(separator: " – ")]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                Text(line)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("route-summary")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(expanded || needsUnifiedScroll ? "route-summary" : "route-compact")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.reversed ? fromText : model.destinationName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("route-destination")
                Button {
                    placePick = .origin
                } label: {
                    Label(VelaL10n.text("route_from_prefix") + (model.reversed ? model.destinationName : fromText),
                          systemImage: "chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("route-origin-button")
            }
            Spacer()
            Button(action: model.swap) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title3)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(VelaL10n.text("saved_reverse"))
            .accessibilityIdentifier("route-swap")
            Button {
                routeShare = RouteShare.payload(model)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(VelaL10n.text("settings_trip_share"))
            .accessibilityIdentifier("route-share")
            .accessibilityValue(shareDebugValue)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(VelaL10n.text("place_close"))
            .accessibilityIdentifier("route-close")
        }
    }

    private var fromText: String {
        if let origin = model.originName { return origin }
        return model.fromMapCenter
            ? VelaL10n.text("route_use_map_center")
            : VelaL10n.text("mapscreen_your_location")
    }

    /// DEBUG builds expose the payload on the share button: the activity sheet is a remote
    /// process, so the UI scenario reads what Vela handed it, then checks the sheet opened.
    private var shareDebugValue: String {
        #if DEBUG
        RouteShare.payload(model).debugText
        #else
        ""
        #endif
    }

    private var modeChips: some View {
        HStack(spacing: 6) {
            ForEach(RouteMode.allCases) { m in
                Button {
                    model.setMode(m)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: m.symbol)
                        Text(model.modeSeconds[m].map(RouteFormat.duration) ?? m.label)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(m == model.mode ? Design.Colors.routeChipLabel : Color(uiColor: .label))
                    .background(m == model.mode ? Design.Colors.routeChipFill : Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(m.label)
                .accessibilityIdentifier("route-mode-\(m.rawValue)")
            }
        }
    }

    private var avoids: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                AvoidToggle(label: VelaL10n.text("car_setting_avoid_highways"), on: model.avoidHighways, id: "route-avoid-highways") {
                    model.setAvoidHighways(!model.avoidHighways)
                }
                AvoidToggle(label: VelaL10n.text("car_setting_avoid_tolls"), on: model.avoidTolls, id: "route-avoid-tolls") {
                    model.setAvoidTolls(!model.avoidTolls)
                }
                AvoidToggle(label: VelaL10n.text("car_setting_avoid_ferries"), on: model.avoidFerries, id: "route-avoid-ferries") {
                    model.setAvoidFerries(!model.avoidFerries)
                }
            }
        }
    }

    /// The camera choice of Android's picker: the per-trip "Avoid cameras" switch and, nested
    /// under it, the side-street attempt. Both are the same sticky preferences as Settings.
    private var cameraAvoids: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                AvoidToggle(label: "Avoid cameras",
                            on: model.avoidCameras, id: "route-avoid-cameras") {
                    model.setAvoidCameras(!model.avoidCameras)
                }
                if model.avoidCameras && model.mode == .drive {
                    AvoidToggle(label: "Side streets around cameras",
                                on: model.cameraSideStreets, id: "route-camera-side-streets") {
                        model.setCameraSideStreets(!model.cameraSideStreets)
                    }
                }
            }
        }
    }

    private func start() {
        model.prepareNavigation()
        if model.mode == .transit, let onStartTransit {
            onStartTransit()
        } else {
            onStart()
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: start) {
                Label(
                    model.mode == .transit ? VelaL10n.text("transit_start_transit") : VelaL10n.text("place_start"),
                    systemImage: model.mode == .transit ? VelaL10n.text("saved_tram_fill") : VelaL10n.text("saved_location_north_line_fill"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .disabled(!model.hasRoute)
            .accessibilityIdentifier("route-start")
            Button {
                model.setShowsSteps(true)
            } label: {
                Label(VelaL10n.text("place_steps"), systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(!model.hasRoute)
            .accessibilityIdentifier("route-steps")
        }
    }
}

/// The picker's closing row in plain Swift numbers, copied out of the Kotlin warning.
struct RouteClosingHint: Equatable {
    let name: String
    let closesAtMinuteOfDay: Int
    let arrivesAtMinuteOfDay: Int
    let beforeArrival: Bool
}

/// The picker's fuel row: the forecourt's brand, its price line and how far off the route it is.
struct RouteFuelHint: Equatable {
    let brand: String?
    let price: String
    let meters: Double
}

extension RouteModel {
    /// The destination's arrival warning the shared store publishes for the selected route. It is
    /// recomputed with every route set, so a recalculation that no longer matches hides the row.
    var closingHint: RouteClosingHint? {
        guard let warning = AppGraph.session.route.state.value.closingHint else { return nil }
        return RouteClosingHint(
            name: warning.name,
            closesAtMinuteOfDay: Int(warning.closesAtMinuteOfDay),
            arrivesAtMinuteOfDay: Int(warning.arrivesAtMinuteOfDay),
            beforeArrival: warning.beforeArrival)
    }

    /// The cheap forecourt on the selected route, from a fresh Fuel Finder file only.
    var fuelDetourHint: RouteFuelHint? {
        guard let detour = AppGraph.session.route.state.value.fuelHint else { return nil }
        return RouteFuelHint(brand: detour.brand, price: detour.price, meters: detour.offRouteMeters)
    }
}

/// The wording of the two travel hints, shared by the picker and the navigation banner so both
/// name the same hours. Times follow the device clock; distances stay metric, as the Fuel Finder
/// prices are pence per litre.
enum TravelHintText {
    static func clock(_ minuteOfDay: Int, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let hour = ((minuteOfDay / 60) % 24 + 24) % 24
        let minute = ((minuteOfDay % 60) + 60) % 60
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func closing(
        name: String,
        closesAtMinuteOfDay: Int,
        arrivesAtMinuteOfDay: Int,
        beforeArrival: Bool,
        locale: Locale = .current
    ) -> String {
        let who = name.isEmpty ? "The destination" : name
        let closes = clock(closesAtMinuteOfDay, locale: locale)
        let arrives = clock(arrivesAtMinuteOfDay, locale: locale)
        if beforeArrival {
            return "\(who) closes at \(closes), before you arrive around \(arrives)"
        }
        return "\(who) closes at \(closes) and you arrive around \(arrives)"
    }

    static func fuelDetour(brand: String?, price: String, meters: Double) -> String {
        let at = brand.map { "\($0), " } ?? ""
        return "Cheaper fuel on the route: \(at)\(price), \(fuelDistance(meters)) off the route"
    }

    /// The detour rule caps the distance at 500 m, so meters never need a kilometers branch.
    static func fuelDistance(_ meters: Double) -> String {
        "\(Int(meters.rounded())) m"
    }
}

/// The picker's closing row: the destination locks its doors within an hour of the arrival, or
/// before it. The value comes from the place's own status; no status means no row.
private struct RouteClosingRow: View {
    let warning: RouteClosingHint

    var body: some View {
        Label {
            Text(TravelHintText.closing(
                name: warning.name,
                closesAtMinuteOfDay: warning.closesAtMinuteOfDay,
                arrivesAtMinuteOfDay: warning.arrivesAtMinuteOfDay,
                beforeArrival: warning.beforeArrival))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "clock")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color(uiColor: .systemOrange))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("route-closing")
    }
}

/// The picker's fuel row: the cheapest fresh forecourt within 500 m of the line, with its price
/// and how far off the route it sits. Without the file nothing is claimed.
private struct RouteFuelRow: View {
    let detour: RouteFuelHint

    var body: some View {
        Label {
            Text(TravelHintText.fuelDetour(
                brand: detour.brand,
                price: detour.price,
                meters: detour.meters))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "fuelpump.fill")
        }
        .font(.caption)
        .foregroundStyle(Color(uiColor: .secondaryLabel))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("route-fuel-detour")
    }
}

/// Android's chooser wording for one row: "Fastest route now" for the quickest of several,
/// "About the same time" within a minute of it, else how much slower it is. No traffic word on
/// foot or by bike, since neither source knows live traffic (SPEC 4.3).
enum RouteRank {
    static func label(choices: [RouteChoice], index: Int) -> String? {
        guard choices.count > 1, index >= 0, index < choices.count else { return nil }
        let fastestIndex = choices.indices.min { choices[$0].seconds < choices[$1].seconds } ?? 0
        let fastest = choices[fastestIndex].seconds
        if index == fastestIndex { return VelaL10n.text("exp_chooser_fastest") }
        let delta = choices[index].seconds - fastest
        if delta < 60 { return VelaL10n.text("exp_chooser_alts_same") }
        return VelaL10n.text("exp_chooser_slower", RouteFormat.duration(delta))
    }
}

/// The traffic line of the picker. Live means Google answered `durationInTrafficSeconds`; a
/// typical range is labeled as such, and an unanswered on-demand trip says so. Nothing here
/// ever turns a free-flow estimate into a live claim.
private struct RouteTrafficRow: View {
    @ObservedObject var model: RouteModel
    let choice: RouteChoice

    var body: some View {
        if model.mode == .drive && model.trafficOnTap && !model.googleOff {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "car.side.fill")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityIdentifier(choice.hasTraffic ? "route-traffic-live" : "route-traffic-typical")
                    if !model.trafficRequested && !choice.hasTraffic && choice.typicalLowSeconds == nil {
                        Text(VelaL10n.text("route_traffic_waits_for_your_tap_this"))
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }
                Spacer()
                if !model.trafficRequested {
                    Button(VelaL10n.text("place_show_traffic"), action: model.requestTraffic)
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("route-traffic-show")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route-traffic-row")
        }
    }

    private var status: String {
        if choice.hasTraffic {
            if choice.delaySeconds >= 60 {
                return "Live traffic: \(RouteFormat.duration(choice.delaySeconds)) slower than usual"
            }
            return "Live traffic, no delays right now"
        }
        if let low = choice.typicalLowSeconds, let high = choice.typicalHighSeconds {
            let a = RouteFormat.duration(low)
            let b = RouteFormat.duration(high)
            return a == b ? "Typical \(a), not live traffic" : "Typical \(a) to \(b), not live traffic"
        }
        if model.trafficRequested {
            return "Times without live traffic. Google returned no live ETA for this trip."
        }
        return "Times without live traffic."
    }
}


/// The camera line of the picker: how many plate cameras the selected route passes, and, when
/// the camera preference led to another route, how many it avoids with the added time and
/// distance. It never says "avoids" when the router handed back the same road: the store then
/// reports zero, so nothing is claimed here.
private struct RouteCameraRow: View {
    @ObservedObject var model: RouteModel
    let choice: RouteChoice

    var body: some View {
        if model.avoidCameras && model.canAvoidCameras && model.mode != .transit {
            VStack(alignment: .leading, spacing: 2) {
                if model.camerasAvoided > 0 {
                    Text(avoidedText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemGreen))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("route-camera-avoided")
                }
                if let cameras = choice.cameras {
                    Text(Self.camerasText(cameras))
                        .font(.caption)
                        .foregroundStyle(cameras > 0 ? Color(uiColor: .systemOrange) : Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("route-camera-row")
                } else {
                    Text(VelaL10n.text("route_counting_cameras_on_this_route"))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityIdentifier("route-camera-row")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route-camera")
        }
    }

    static func camerasText(_ count: Int) -> String {
        if count <= 0 { return "No plate cameras on this route" }
        return count == 1 ? "Passes 1 plate camera" : "Passes \(count) plate cameras"
    }

    private var avoidedText: String {
        let count = model.camerasAvoided
        let cameras = count == 1 ? "1 camera" : "\(count) cameras"
        var extra: [String] = []
        if model.cameraDetourSeconds >= 30 {
            extra.append(RouteFormat.duration(model.cameraDetourSeconds))
        }
        if model.cameraDetourMeters >= 50 {
            extra.append(RouteFormat.distance(model.cameraDetourMeters))
        }
        let baseline = model.cameraBaselineIsFastest ? "the fastest route" : "the route without this preference"
        if extra.isEmpty {
            return "Avoids \(cameras), no extra time or distance over \(baseline)"
        }
        return "Avoids \(cameras): \(extra.joined(separator: " and ")) more than \(baseline)"
    }
}

private struct AvoidToggle: View {
    let label: String
    let on: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: on ? "checkmark" : "plus")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minHeight: 44)
                .background(on ? Color.accentColor.opacity(0.2) : Color(uiColor: .secondarySystemBackground),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct RouteChoiceRow: View {
    let choice: RouteChoice
    let rank: String?
    let selected: Bool
    var showsCameras: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(RouteFormat.duration(choice.seconds))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(delayColor)
                        Text(RouteFormat.distance(choice.meters))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if let rank {
                        Text(rank)
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .accessibilityIdentifier("route-rank")
                    }
                    if let via = choice.via {
                        Text(VelaL10n.text("exp_chooser_via", via))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if choice.delaySeconds >= 60 {
                        Text(VelaL10n.text("saved_slower_than_usual_with_traffic", String(describing: (RouteFormat.duration(choice.delaySeconds)))))
                            .font(.caption)
                            .foregroundStyle(delayColor)
                    } else if choice.hasTraffic {
                        Text(VelaL10n.text("saved_traffic_is_light"))
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if showsCameras, let cameras = choice.cameras {
                        Text(RouteCameraRow.camerasText(cameras))
                            .font(.caption)
                            .foregroundStyle(cameras > 0 ? Color(uiColor: .systemOrange) : Color(uiColor: .secondaryLabel))
                            .accessibilityIdentifier("route-row-cameras")
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("route-row")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The time's color by how much the traffic adds: red from ten minutes, amber from two.
    static func delayColor(_ choice: RouteChoice) -> Color {
        if choice.delaySeconds >= 600 { return Color(uiColor: .systemRed) }
        if choice.delaySeconds >= 120 { return Color(uiColor: .systemOrange) }
        return Color(uiColor: .label)
    }

    private var delayColor: Color { Self.delayColor(choice) }
}

/// The selected route's steps. Tapping one frames that maneuver on the map and keeps the step
/// in a compact card, so the driver can walk the list one turn at a time; "Whole route" fits the
/// planned line again. Neither action starts guidance.
struct StepsSheet: View {
    @ObservedObject var model: RouteModel

    /// The step being previewed, or nil for the full list.
    @State private var focusedStep: Int?
    @State private var appliedIndex: Int?
    @State private var appliedZoom: Double?

    var body: some View {
        VStack(spacing: 0) {
            if focusedStep != nil {
                Spacer(minLength: 0)
            }
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: RouteStepMapLink.focusApplied)) { note in
            guard let index = note.userInfo?[RouteStepMapLink.indexKey] as? Int else { return }
            appliedIndex = index
            appliedZoom = note.userInfo?[RouteStepMapLink.zoomKey] as? Double
        }
        .onChange(of: model.activeIndex) { _ in
            focusedStep = nil
            appliedIndex = nil
            appliedZoom = nil
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            header
            #if DEBUG
            Text(focusDebug)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityLabel(focusDebug)
                .accessibilityIdentifier("step-focus-debug")
            #endif
            if let focusedStep, model.steps.indices.contains(focusedStep) {
                focusedBody(focusedStep)
            } else {
                listBody
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("steps-sheet")
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier("steps-title")
            Spacer()
            Button {
                model.setShowsSteps(false)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(VelaL10n.text("steps_close_cd"))
            .accessibilityIdentifier("steps-close")
        }
    }

    private var title: String {
        if let trip = model.activeTransit {
            return [trip.departText, trip.arriveText].compactMap { $0 }.joined(separator: " – ")
                + (trip.durationText.map { " · \($0)" } ?? "")
        }
        if let focusedStep, model.steps.indices.contains(focusedStep) {
            return VelaL10n.text("steps_focus_title", String(describing: (focusedStep + 1)), String(describing: (model.steps.count)))
        }
        if let active = model.choices.first(where: { $0.id == model.activeIndex }) {
            return "\(RouteFormat.duration(active.seconds)) · \(RouteFormat.distance(active.meters))"
        }
        return VelaL10n.text("place_steps")
    }

    /// The focused step stays in the sheet while the map shows the junction; the rest of the
    /// list is collapsed so the card only takes the height it needs.
    private func focusedBody(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StepLine(step: model.steps[index], highlighted: true)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("step-focused")
            HStack(spacing: 8) {
                Button {
                    focus(index - 1)
                } label: {
                    Label(VelaL10n.text("steps_previous"), systemImage: "chevron.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(index <= 0)
                .accessibilityIdentifier("step-previous")
                Button {
                    focus(index + 1)
                } label: {
                    Label(VelaL10n.text("steps_next"), systemImage: "chevron.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(index >= model.steps.count - 1)
                .accessibilityIdentifier("step-next")
                Button {
                    wholeRoute()
                } label: {
                    Label(VelaL10n.text("steps_whole_route"), systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("step-whole-route")
            }
        }
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let trip = model.activeTransit {
                    ForEach(Array(trip.legs.enumerated()), id: \.offset) { _, leg in
                        TransitLegView(leg: leg)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("step-row")
                        Divider()
                    }
                }
                ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                    Button {
                        focus(index)
                    } label: {
                        StepLine(step: step, highlighted: focusedStep == index)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("step-row")
                    .accessibilityHint(VelaL10n.text("steps_focus_hint"))
                    Divider()
                }
                if !model.steps.contains(where: { $0.kind == "ARRIVE" }) && !model.destinationName.isEmpty
                    && (model.hasRoute || model.activeTransit != nil) {
                    HStack(spacing: 12) {
                        Image(systemName: Self.symbol("ARRIVE"))
                            .font(.title3)
                            .frame(width: 28)
                        Text(model.reversed ? VelaL10n.text("route_arrive") : VelaL10n.text("place_arrive_approx", String(describing: (model.destinationName))))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var activeLine: [CLLocationCoordinate2D] {
        model.lines.first(where: { $0.index == model.activeIndex })?.coordinates ?? []
    }

    private func focus(_ index: Int) {
        guard model.steps.indices.contains(index) else { return }
        let step = model.steps[index]
        let target = CLLocationCoordinate2D(latitude: step.latitude, longitude: step.longitude)
        guard CLLocationCoordinate2DIsValid(target) else { return }
        focusedStep = index
        NotificationCenter.default.post(
            name: RouteStepMapLink.focusRequest,
            object: RouteStepFocusRequest(index: index, target: target, line: activeLine))
    }

    private func wholeRoute() {
        focusedStep = nil
        appliedIndex = nil
        appliedZoom = nil
        NotificationCenter.default.post(
            name: RouteStepMapLink.overviewRequest,
            object: RouteOverviewRequest(line: activeLine))
    }

    private var focusDebug: String {
        let zoom = appliedZoom.map { String(format: "%.1f", $0) } ?? "0.0"
        return "step_focus=\(focusedStep == nil ? 0 : 1) step_index=\(focusedStep ?? appliedIndex ?? -1)"
            + " step_zoom=\(zoom)"
    }

    /// The SF Symbol of a `ManeuverType` name.
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "DEPART": return "circle.circle"
        case "ARRIVE": return "mappin.circle.fill"
        case "TURN_LEFT", "SHARP_LEFT": return "arrow.turn.up.left"
        case "TURN_RIGHT", "SHARP_RIGHT": return "arrow.turn.up.right"
        case "SLIGHT_LEFT", "KEEP_LEFT", "FORK_LEFT": return "arrow.up.left"
        case "SLIGHT_RIGHT", "KEEP_RIGHT", "FORK_RIGHT": return "arrow.up.right"
        case "RAMP_LEFT": return "arrow.up.left"
        case "RAMP_RIGHT": return "arrow.up.right"
        case "UTURN": return "arrow.uturn.down"
        case "MERGE": return "arrow.merge"
        case "ROUNDABOUT", "EXIT_ROUNDABOUT": return "arrow.triangle.2.circlepath"
        default: return "arrow.up"
        }
    }
}

/// One step's row, shared by the full list and the focused card. The focused card washes the row
/// so the step the map is showing stays identified after the list collapses.
private struct StepLine: View {
    let step: RouteStep
    var highlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: StepsSheet.symbol(step.kind))
                    .font(.title3)
                if step.exit > 0 {
                    Text("\(step.exit)")
                        .font(.caption2.weight(.bold))
                        .offset(x: 6, y: 4)
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let ref = step.ref {
                        Text(ref)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(uiColor: .label), lineWidth: 1))
                    }
                    Text(step.instruction)
                }
                if !step.lanes.isEmpty {
                    LanesView(lanes: step.lanes)
                } else if let hint = step.laneHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                if step.meters > 0 && step.kind != "ARRIVE" {
                    Text(RouteFormat.distance(step.meters))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, highlighted ? 8 : 0)
        .background(highlighted ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A maneuver's lanes, left to right: the lanes to use bright, the others dimmed.
private struct LanesView: View {
    let lanes: [RouteStep.Lane]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { index, lane in
                HStack(spacing: 0) {
                    ForEach(Array(lane.arrows.prefix(2).enumerated()), id: \.offset) { _, arrow in
                        Image(systemName: Self.symbol(arrow))
                            .font(.caption)
                    }
                }
                .frame(minWidth: 22, minHeight: 22)
                .foregroundStyle(lane.valid ? Color.white : Color.white.opacity(0.4))
                .background(Color(uiColor: lane.valid ? .systemBlue : .systemGray), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VelaL10n.text("route_lane_of", String(describing: (index + 1)), String(describing: (lanes.count))))
                .accessibilityValue(
                    "\(Self.directions(lane.arrows)). \(lane.valid ? VelaL10n.text("transit_recommended") : VelaL10n.text("transit_not_recommended"))")
                .accessibilityIdentifier("step-lane-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("step-lanes")
    }

    private static func directions(_ arrows: [String]) -> String {
        guard !arrows.isEmpty else { return "No direction indicated" }
        return arrows.map { arrow in
            switch arrow {
            case "straight": return "straight ahead"
            case "uturn": return "U-turn"
            case "none": return "no turn"
            default: return arrow.replacingOccurrences(of: "_", with: " ")
            }
        }.joined(separator: " or ")
    }

    /// The SF Symbol of an OSRM lane indication.
    static func symbol(_ arrow: String) -> String {
        switch arrow {
        case "left", "sharp left": return "arrow.turn.up.left"
        case "right", "sharp right": return "arrow.turn.up.right"
        case "slight left": return "arrow.up.left"
        case "slight right": return "arrow.up.right"
        case "uturn": return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }
}

/// One transit itinerary in the chooser: its times and its legs as line pills.
private struct TransitChoiceRow: View {
    let trip: TransitChoice
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(trip.seconds > 0 ? RouteFormat.duration(trip.seconds) : (trip.durationText ?? ""))
                            .font(.title3.weight(.semibold))
                        Text([trip.departText, trip.arriveText].compactMap { $0 }.joined(separator: " – "))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(trip.legs.enumerated()), id: \.offset) { i, leg in
                                if i > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }
                                LinePill(leg: leg)
                            }
                        }
                    }
                    if let from = trip.legs.first(where: { $0.kind != "WALK" })?.from {
                        Text(VelaL10n.text("place_origin_plain", String(describing: (from))))
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transit-row")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A leg as a pill: the vehicle's symbol and the line name on the line's color; a walk as a
/// figure and its minutes.
private struct LinePill: View {
    let leg: TransitChoice.Leg

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: TransitLegView.symbol(leg.kind))
            if leg.kind == "WALK" {
                if let d = leg.durationText { Text(d) }
            } else if let line = leg.line {
                Text(line).fontWeight(.semibold)
            }
        }
        .font(.caption)
        .padding(.horizontal, leg.kind == "WALK" ? 0 : 6)
        .padding(.vertical, 2)
        .foregroundStyle(leg.kind == "WALK" ? Color(uiColor: .label) : (Color(hex: leg.textColor) ?? .white))
        .background(leg.kind == "WALK" ? Color.clear : (Color(hex: leg.color) ?? Color(uiColor: .systemBlue)),
                    in: RoundedRectangle(cornerRadius: 4))
    }
}

/// One walk or ride of the selected itinerary in the steps sheet.
private struct TransitLegView: View {
    let leg: TransitChoice.Leg

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.symbol(leg.kind))
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                if leg.kind == "WALK" {
                    Text(VelaL10n.text("place_mode_walk") + (leg.durationText.map { " \($0)" } ?? ""))
                } else {
                    HStack(spacing: 6) {
                        LinePill(leg: leg)
                        if let headsign = leg.headsign {
                            Text(VelaL10n.text("transit_nav_towards", String(describing: (headsign))))
                                .lineLimit(1)
                        }
                    }
                    if let from = leg.from {
                        Text([leg.departText, from].compactMap { $0 }.joined(separator: "  "))
                    }
                    let ride = [leg.durationText, leg.stops > 0 ? "\(leg.stops) stops" : nil, leg.delayText]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !ride.isEmpty {
                        Text(ride)
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if let to = leg.to {
                        Text([leg.arriveText, to].compactMap { $0 }.joined(separator: "  "))
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    /// The SF Symbol of a `TransitMode` name.
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "WALK": return "figure.walk"
        case "BUS": return "bus.fill"
        case "TRAM": return "tram.fill"
        case "SUBWAY": return "tram.fill.tunnel"
        case "TRAIN": return "train.side.front.car"
        case "FERRY": return "ferry.fill"
        default: return "tram.fill"
        }
    }
}

private extension Color {
    /// A `#rrggbb` color, nil for anything else.
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
