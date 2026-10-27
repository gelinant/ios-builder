import SwiftUI
import UIKit

// English for now; the String Catalog keys (I-8) come with the strings script.

/// The route chooser over the bottom of the map, in Android's two presentations: the compact
/// picker (the selected route, its traffic line, Start and Steps) and the expanded sheet (time,
/// stops, avoids, every alternate). Both keep the mode chips pinned and the same Start/Steps
/// actions at the bottom; the content order never changes between them.
struct RoutePickerSheet: View {
    @ObservedObject var model: RouteModel
    let savedPlaces: [SavedMapMarker]
    let onClose: () -> Void
    @State private var placePick: RoutePlacePickKind?
    @State private var expanded = false
    /// A no-op fallback lets the route chooser ship before its navigation host is wired.
    var onStart: () -> Void = {}
    /// Transit uses its own session; nil keeps the original Start callback for embedding previews.
    var onStartTransit: (() -> Void)?

    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var needsUnifiedScroll: Bool {
        sizeCategory.isAccessibilityCategory || verticalSizeClass == .compact
    }

    /// Large text and landscape cannot split a card into a pinned part and a scrolling one without
    /// hiding something: everything scrolls as one column, as Q-2 fixed it.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            expandHandle
            if needsUnifiedScroll {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        modeChips
                        summary
                        expandedBody
                        actions
                    }
                }
                .accessibilityIdentifier("route-scroll")
            } else {
                header
                modeChips
                if expanded {
                    summary
                    ScrollView { expandedBody }
                        .accessibilityIdentifier("route-scroll")
                } else {
                    ScrollView { summary }
                        .accessibilityIdentifier("route-scroll")
                }
                actions
            }
            #if DEBUG
            // MapScreen hides its debug block while a bottom sheet is open. The chooser carries
            // the route state line itself, so the Directions scenarios can still read it here.
            Text(model.debugLine)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityIdentifier("route-debug")
            #endif
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-sheet")
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
        .accessibilityLabel(expanded ? "Collapse the route list" : "Show all routes")
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
            if model.mode == .bicycle && model.bikeSafe && !model.choices.isEmpty {
                Label(VelaL10n.text("settings_bike_safe"), systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("route-bike-safe")
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
                    Text("Timetables from Transitous")
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
                    Text("Finding routes")
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .padding(.vertical, 8)
            } else if let message = model.message {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .accessibilityIdentifier("route-message")
                    Button("Try again", action: model.retry)
                        .frame(minHeight: 44)
                }
                .padding(.vertical, 8)
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
                    Label("from " + (model.reversed ? model.destinationName : fromText),
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
            .accessibilityLabel("Reverse")
            .accessibilityIdentifier("route-swap")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Close")
            .accessibilityIdentifier("route-close")
        }
    }

    private var fromText: String {
        if let origin = model.originName { return origin }
        return model.fromMapCenter ? "the map's center" : "your location"
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
                    .foregroundStyle(m == model.mode ? Color.white : Color(uiColor: .label))
                    .background(m == model.mode ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
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
                AvoidToggle(label: "Avoid highways", on: model.avoidHighways, id: "route-avoid-highways") {
                    model.setAvoidHighways(!model.avoidHighways)
                }
                AvoidToggle(label: "Avoid tolls", on: model.avoidTolls, id: "route-avoid-tolls") {
                    model.setAvoidTolls(!model.avoidTolls)
                }
                AvoidToggle(label: "Avoid ferries", on: model.avoidFerries, id: "route-avoid-ferries") {
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
                    model.mode == .transit ? "Start transit" : VelaL10n.text("place_start"),
                    systemImage: model.mode == .transit ? "tram.fill" : "location.north.line.fill")
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
                        Text("Traffic waits for your tap; this time is the open router's.")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }
                Spacer()
                if !model.trafficRequested {
                    Button("Show traffic", action: model.requestTraffic)
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
                    Text("Counting cameras on this route")
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
                        Text("\(RouteFormat.duration(choice.delaySeconds)) slower than usual with traffic")
                            .font(.caption)
                            .foregroundStyle(delayColor)
                    } else if choice.hasTraffic {
                        Text("Traffic is light")
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

/// The selected route's steps, each with its maneuver's symbol and the distance to the next.
struct StepsSheet: View {
    @ObservedObject var model: RouteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            HStack {
                if let trip = model.activeTransit {
                    Text([trip.departText, trip.arriveText].compactMap { $0 }.joined(separator: " – ")
                        + (trip.durationText.map { " · \($0)" } ?? ""))
                        .font(.headline)
                } else if let active = model.choices.first(where: { $0.id == model.activeIndex }) {
                    Text("\(RouteFormat.duration(active.seconds)) · \(RouteFormat.distance(active.meters))")
                        .font(.headline)
                }
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
                .accessibilityLabel("Close steps")
                .accessibilityIdentifier("steps-close")
            }
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
                    ForEach(model.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(systemName: Self.symbol(step.kind))
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
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("step-row")
                        Divider()
                    }
                    if !model.steps.contains(where: { $0.kind == "ARRIVE" }) && !model.destinationName.isEmpty
                        && (model.hasRoute || model.activeTransit != nil) {
                        HStack(spacing: 12) {
                            Image(systemName: Self.symbol("ARRIVE"))
                                .font(.title3)
                                .frame(width: 28)
                            Text(model.reversed ? "Arrive" : "Arrive at \(model.destinationName)")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
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
                .accessibilityLabel("Lane \(index + 1) of \(lanes.count)")
                .accessibilityValue(
                    "\(Self.directions(lane.arrows)). \(lane.valid ? "Recommended" : "Not recommended")")
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
                        Text("from \(from)")
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
                    Text("Walk" + (leg.durationText.map { " \($0)" } ?? ""))
                } else {
                    HStack(spacing: 6) {
                        LinePill(leg: leg)
                        if let headsign = leg.headsign {
                            Text("towards \(headsign)")
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
