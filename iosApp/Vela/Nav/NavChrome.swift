import SwiftUI
import UIKit
import VelaCore

/// The drive's top maneuver card, recenter control and bottom ETA strip.
struct NavChrome: View {
    @ObservedObject var model: NavModel
    /// MapScreen owns the sheet presentation; the drive only asks for it.
    var onAddStop: (() -> Void)? = nil
    @StateObject private var appearance = AppearanceSettings.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var instructionBase: CGFloat = 17
    @State private var confirmEnd = false
    /// The waypoint card's serial the driver has dismissed, so the next stop shows again.
    @State private var dismissedStopSerial: Int64 = 0
    /// The card's horizontal offset while a swipe rides the finger.
    @State private var bannerOffset: CGFloat = 0
    /// DRIVE-SEARCH: the field overlays the banner and never owns the drive.
    @State private var driveSearchOpen = false
    /// Set only by the explicit voice button, so the microphone never opens by itself.
    @State private var driveSearchVoice = false

    private var largeText: Bool { typeSize.isAccessibilitySize }

    private var showsWaypoint: Bool {
        model.reachedStopLabel != nil && model.reachedStopSerial != dismissedStopSerial && !model.arrived
    }

    var body: some View {
        VStack(spacing: 10) {
            if !model.arrived {
                banner
            }
            if showsWaypoint, let label = model.reachedStopLabel {
                waypointArrival(label)
            }
            #if DEBUG
            VStack(alignment: .leading, spacing: 3) {
                NavDebugLabel(text: model.debugLine, id: "nav-debug")
                NavDebugLabel(text: model.voiceDebugLine, id: "nav-voice-debug")
                NavDebugLabel(text: appearance.debugLine, id: "nav-chrome-debug")
            }
            if NavTestSupport.robustness {
                HStack(spacing: 8) {
                    Button("No GPS") { model.simulateGpsLoss() }
                        .accessibilityIdentifier("nav-test-starve")
                    Button("GPS back") { model.restoreGps() }
                        .accessibilityIdentifier("nav-test-gps")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
            if NavTestSupport.notifications {
                Button("Notification tap") { model.simulateNotificationTap() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("nav-test-notify-open")
            }
            #endif
            if model.roadAlertKind != nil {
                roadAlert
            }
            if model.fasterRouteOffered {
                fasterRoute
            } else if model.trafficDelaySeconds >= 30 {
                trafficDelay
            }
            if model.paused && model.navigating {
                Label(VelaL10n.text("nav_paused"), systemImage: "pause.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("nav-paused")
            }
            if model.starved && model.navigating && !model.paused {
                Label(VelaL10n.text("nav_gps_lost"), systemImage: "location.slash")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("nav-starved")
            }
            Spacer()
            if model.cameraDetached && model.navigating {
                Button(VelaL10n.text("mapscreen_recenter")) { model.recenter() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("nav-recenter")
            }
            if model.arrived {
                arrival
            } else {
                HStack {
                    if model.speedMps != nil && appearance.speedDisplay {
                        speedPill
                    }
                    vehicleBadge
                    Spacer()
                }
                HStack(spacing: 8) {
                    if !model.currentRoadLabel.isEmpty && !model.previewing
                        && appearance.detail != .minimal && !largeText {
                        currentRoadPill
                    }
                    Spacer(minLength: 0)
                    if model.stopsRecalculating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(VelaL10n.text("nav_rerouting"))
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("nav-stop-recalc")
                    } else if let onAddStop {
                        Button(action: onAddStop) {
                            Label(VelaL10n.text("place_add_stop"), systemImage: "plus.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("nav-add-stop")
                    }
                    if SearchActions.model != nil && !model.arrived {
                        Button {
                            driveSearchVoice = false
                            driveSearchOpen = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(VelaL10n.text("place_search_along_route"))
                        .accessibilityIdentifier("drive-search-open")
                        Button {
                            driveSearchVoice = true
                            driveSearchOpen = true
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(VelaL10n.text("search_voice_cd"))
                        .accessibilityIdentifier("drive-search-mic")
                    }
                }
                bottomBar
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        // The field overlays the banner without becoming a sibling in a new stack: the card's
        // geometry, its drag gesture and the bottom controls stay exactly where they were.
        .overlay(alignment: .top) {
            if driveSearchOpen, let search = SearchActions.model {
                DriveSearchOverlay(
                    model: model,
                    search: search,
                    startVoice: driveSearchVoice,
                    onClose: {
                        driveSearchOpen = false
                        driveSearchVoice = false
                    })
            }
        }
        // The field sits at the top; the keyboard must not lift the banner or the bottom strip
        // out of reach, exactly as the browser chrome already does.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .confirmationDialog(VelaL10n.text("nav_end_confirm_title"), isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(VelaL10n.text("nav_end_confirm_title"), role: .destructive, action: model.stop)
                .accessibilityIdentifier("nav-end-confirm")
            Button(VelaL10n.text("nav_keep_navigating"), role: .cancel) {}
        }
    }

    private var banner: some View {
        let preview = model.previewing
        let kind = preview ? model.previewKind : model.maneuverKind
        let instruction = preview ? model.previewText : model.maneuverText
        let rerouting = model.offRoute && !preview
        return HStack(alignment: .top, spacing: largeText ? 8 : 14) {
            if rerouting {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(width: 40, height: 40)
                    // The spinner is decorative: it must not swallow the banner's drag.
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("nav-rerouting")
            } else {
                Image(systemName: StepsSheet.symbol(kind))
                    .font(.system(size: (largeText ? 26 : 36) * appearance.iconSize.scale, weight: .semibold))
                    .foregroundStyle(preview ? Color.primary : Color.white)
                    .frame(width: 40 * appearance.iconSize.scale, height: 40 * appearance.iconSize.scale)
            }
            // At accessibility sizes the text column gives up its inner gaps: the card has a third
            // of the screen and the instruction keeps its two lines and its size.
            VStack(alignment: .leading, spacing: largeText ? 2 : 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(rerouting ? VelaL10n.text("nav_rerouting") : RouteFormat.distance(
                        preview ? model.previewDistance : model.distanceToNext))
                        .font(largeText ? Font.headline.weight(.bold) : Font.title2.weight(.bold))
                        .foregroundStyle(preview ? Color.primary : Color.white)
                        .lineLimit(largeText ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    // At accessibility sizes the maneuver's sign rides on the distance row
                    // instead of taking a row of its own: the card owes a third of the screen to
                    // the map, and the sign is the road the turn enters.
                    if largeText {
                        if !rerouting {
                            shieldRow(
                                ref: preview ? model.previewRef : model.maneuverRef,
                                instruction: instruction,
                                onDark: !preview)
                        }
                    } else if !rerouting && !preview && !model.currentRoadRef.isEmpty
                        && model.currentRoadRef != model.maneuverRef {
                        NavShieldView(
                            label: model.currentRoadRef,
                            onDark: true,
                            identifier: "nav-current-road-shield")
                    }
                }
                if !rerouting && !largeText {
                    shieldRow(
                        ref: preview ? model.previewRef : model.maneuverRef,
                        instruction: instruction,
                        onDark: !preview)
                    Text(instruction)
                        .font(.system(
                            size: instructionBase * (largeText ? 15.0 / 17.0 : 1) * appearance.labelSize.scale,
                            weight: .semibold))
                        .foregroundStyle(preview ? Color.primary : Color.white)
                        .lineLimit(largeText ? 2 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        // The AX scenario waits for the instruction before it measures the card:
                        // a card read before the maneuver text arrives is not the card the
                        // driver reads.
                        .accessibilityIdentifier("nav-instruction")
                    if !preview && !model.nextManeuverText.isEmpty && appearance.detail == .full {
                        HStack(spacing: 5) {
                            Text(thenWord)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                            if !model.nextManeuverRef.isEmpty {
                                NavShieldView(
                                    label: model.nextManeuverRef,
                                    onDark: true,
                                    identifier: "nav-next-shield")
                            }
                            // The next maneuver is a hint, not the instruction: one line at any
                            // size. Its second line at AX was what pushed the card past the third
                            // of the screen; the whole sentence stays in the steps sheet.
                            Text(model.nextManeuverText)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("nav-then")
                    }
                    // The destination's closing hour as Android's flash message says it: one line
                    // under the maneuver, never a second card. Absent without a real status.
                    if let closing = model.closingHint?.text {
                        Text(closing)
                            .font(largeText ? Font.caption2 : Font.caption)
                            .foregroundStyle(preview ? Color.secondary : Color.white.opacity(0.9))
                            .lineLimit(1)
                            .accessibilityIdentifier("nav-closing")
                    }
                    if preview {
                        Text(VelaL10n.text("nav_preview_tap_resume"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.secondary)
                            .accessibilityIdentifier("nav-preview-hint")
                    }
                }
                // Lanes belong to the maneuver in hand, not to the route fetch. While a replan
                // is running the driver still sees the lanes of the turn being approached, under
                // the "Rerouting" line, instead of a blank card.
                if !visibleLanes.isEmpty {
                    laneRow(visibleLanes, onDark: !preview)
                }
            }
            Spacer(minLength: 0)
        }
        // At accessibility sizes the card must stay inside a third of the screen: the green panel
        // gives up its padding rather than the instruction shrinking.
        .padding(largeText ? 4 : 16)
        .frame(maxWidth: .infinity)
        .background(
            preview ? Color(uiColor: .secondarySystemBackground) : Color(red: 0, green: 0.396, blue: 0.31),
            in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .offset(x: bannerOffset)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.previewing { model.exitPreview() }
        }
        .highPriorityGesture(bannerDrag)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-banner")
        .accessibilityValue(model.previewing ? VelaL10n.text("nav_preview_tap_resume") : "")
    }

    /// The sign row: an exit tab when the instruction names one, then the road number the
    /// maneuver enters. Neither is invented: absent data shows nothing.
    @ViewBuilder
    private func shieldRow(ref: String, instruction: String, onDark: Bool) -> some View {
        if NavShield.exitLabel(in: instruction) != nil || !ref.isEmpty {
            HStack(spacing: 6) {
                if let exit = NavShield.exitLabel(in: instruction) {
                    Text(exit)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.12, green: 0.49, blue: 0.20), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityIdentifier("nav-exit")
                }
                if !ref.isEmpty {
                    NavShieldView(label: ref, onDark: onDark, identifier: "nav-shield")
                }
            }
        }
    }

    /// Per-lane arrows, bright only for the lanes that serve this maneuver. The shared route
    /// carries no lane data on many roads; then the row is absent, never guessed from a hint.
    private func laneRow(_ lanes: [NavBannerLane], onDark: Bool) -> some View {
        let bright = onDark ? Color.white : Color.primary
        let dim = onDark ? Color.white.opacity(0.4) : Color.secondary
        return HStack(spacing: 4) {
            ForEach(Array(lanes.prefix(8).enumerated()), id: \.offset) { index, lane in
                HStack(spacing: 0) {
                    ForEach(Array(lane.arrows.prefix(2).enumerated()), id: \.offset) { _, arrow in
                        Image(systemName: laneSymbol(arrow))
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .frame(minWidth: 22, minHeight: 22)
                .foregroundStyle(lane.valid ? bright : dim)
                .background(
                    lane.valid ? bright.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VelaL10n.text("route_lane_of", String(describing: (index + 1)), String(describing: (lanes.count))))
                .accessibilityValue(
                    "\(laneDirections(lane.arrows)). \(lane.valid ? VelaL10n.text("transit_recommended") : VelaL10n.text("transit_not_recommended"))")
                .accessibilityIdentifier("nav-lane-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-lanes")
    }

    private var visibleLanes: [NavBannerLane] {
        if model.previewing { return model.previewLanes }
        #if DEBUG
        if model.bannerFixture && !model.maneuverLanes.isEmpty { return model.maneuverLanes }
        #endif
        guard !model.maneuverLanes.isEmpty else { return [] }
        // A replan does not erase the lanes of the turn the car is still approaching.
        if model.offRoute { return model.maneuverLanes }
        let showMeters = max(800, (model.speedMps ?? 0) * 30)
        return model.distanceToNext <= showMeters ? model.maneuverLanes : []
    }

    private var thenWord: String {
        let word = VelaL10n.text("nav_compound_then")
        return word.prefix(1).uppercased() + String(word.dropFirst())
    }

    private func laneSymbol(_ arrow: String) -> String {
        switch arrow {
        case "left", "sharp left": return "arrow.turn.up.left"
        case "right", "sharp right": return "arrow.turn.up.right"
        case "slight left", "merge to left": return "arrow.up.left"
        case "slight right", "merge to right": return "arrow.up.right"
        case "uturn": return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }

    private func laneDirections(_ arrows: [String]) -> String {
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

    private var bannerDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                bannerOffset = value.translation.width
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                guard horizontal else {
                    withAnimation(.spring(response: 0.25)) { bannerOffset = 0 }
                    return
                }
                if value.translation.width <= -110 {
                    commitSwipe(next: true)
                } else if value.translation.width >= 110 {
                    commitSwipe(next: false)
                } else {
                    withAnimation(.spring(response: 0.25)) { bannerOffset = 0 }
                }
            }
    }

    /// Slides the previewed card out like a pager, swaps the step, and slides the new card in
    /// from the other edge. Below the threshold the card springs back and guidance never moved.
    private func commitSwipe(next: Bool) {
        guard model.navigating else {
            withAnimation(.spring(response: 0.25)) { bannerOffset = 0 }
            return
        }
        let width = UIScreen.main.bounds.width
        withAnimation(.easeIn(duration: 0.12)) { bannerOffset = next ? -width : width }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            if next {
                model.previewNext()
            } else {
                model.previewPrevious()
            }
            bannerOffset = next ? width : -width
            withAnimation(.easeOut(duration: 0.2)) { bannerOffset = 0 }
        }
    }

    /// The stop just passed: the voice has said it; the card shows the same line and lets the drive
    /// carry on to the next leg. It dismisses itself so it cannot sit over the map for the rest of
    /// the trip.
    private func waypointArrival(_ label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(NavStringsRegistry.shared.current().reachedStop(label: label))
                    .font(.headline)
                if model.stopsAhead > 0 && !model.nextStopLabel.isEmpty {
                    Text(VelaL10n.text("nav_bar_to_stop", model.nextStopLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(VelaL10n.text("nav_maneuver_continue")) {
                dismissedStopSerial = model.reachedStopSerial
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("nav-waypoint-continue")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-waypoint")
        .task(id: model.reachedStopSerial) {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled { dismissedStopSerial = model.reachedStopSerial }
        }
    }

    private var roadAlert: some View {
        Label(model.roadAlertText, systemImage: roadAlertSymbol)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.65, green: 0.31, blue: 0.08), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nav-camera-alert")
    }

    private var roadAlertSymbol: String {
        switch model.roadAlertKind {
        case "BRIDGE_OPEN", "BRIDGE_PLANNED": return "water.waves"
        case "SPEEDING": return "speedometer"
        default: return "camera.fill"
        }
    }

    private var fasterRoute: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(VelaL10n.text("mapscreen_faster_route_title"), systemImage: "bolt.fill")
                .font(.headline)
            Text(VelaL10n.text(
                "mapscreen_faster_route_saves", RouteFormat.duration(model.fasterSavingSeconds)))
                .font(.subheadline)
            HStack(spacing: 12) {
                Button(VelaL10n.text("mapscreen_faster_route_title"), action: model.acceptFasterRoute)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("nav-faster-accept")
                Button(VelaL10n.text("mapscreen_dismiss"), action: model.dismissFasterRoute)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("nav-faster-dismiss")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-traffic")
    }

    private var trafficDelay: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.fill")
            Text(VelaL10n.text("place_live_traffic"))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("+\(RouteFormat.duration(model.trafficDelaySeconds))")
                .font(.headline)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-traffic-delay")
    }

    /// The road under the car, above the bottom bar. A freeway shows the number the shared label
    /// builder chose; the number's shield already sits on the top card.
    private var currentRoadPill: some View {
        Text(model.currentRoadLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(largeText ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier("nav-current-road")
    }

    private var hasStopAhead: Bool {
        model.stopsAhead > 0 && !model.nextStopLabel.isEmpty
    }

    /// On, Alerts only, Off. Android's speaker button cycles the same three states.
    private var voiceSymbol: String {
        if !model.voiceMuted { return "speaker.wave.2.fill" }
        return model.voiceAlertsOnly ? "bell.badge.fill" : "speaker.slash.fill"
    }

    private var voiceModeLabel: String {
        if !model.voiceMuted { return VelaL10n.text("settings_voice_mode_on") }
        return VelaL10n.text(model.voiceAlertsOnly ? "settings_voice_mode_alerts" : "settings_voice_mode_off")
    }

    private var imperialSpeed: Bool {
        appearance.speedUnit.isImperial(modelImperial: model.imperial)
    }

    private var vehicleBadge: some View {
        Image(systemName: appearance.vehicle.symbol)
            .font(.system(size: 16 * appearance.iconSize.scale, weight: .semibold))
            .foregroundStyle(appearance.vehicle == .arrow ? Color.primary : Design.Colors.accentFill)
            .frame(width: 34 * appearance.iconSize.scale, height: 34 * appearance.iconSize.scale)
            .background(.regularMaterial, in: Circle())
            .accessibilityLabel(appearance.vehicle.title)
            .accessibilityIdentifier("nav-vehicle-icon")
    }

    private var speedPill: some View {
        let speed = model.speedMps ?? 0
        let color = model.speeding ? Color.red : Color.primary
        return HStack(spacing: 9) {
            if let limit = model.speedLimitKmh {
                Text("\(NavFormat.limitValue(limit, imperial: imperialSpeed))")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .systemBackground), in: Circle())
                    .overlay(Circle().stroke(Color.red, lineWidth: 3))
                    .accessibilityIdentifier("nav-speed-limit")
            }
            VStack(spacing: 0) {
                Text("\(NavFormat.speedValue(speed, imperial: imperialSpeed))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityIdentifier("nav-speed-value")
                Text(NavFormat.speedUnit(imperial: imperialSpeed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nav-speed-unit")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-speed")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                confirmEnd = true
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(VelaL10n.text("nav_end_confirm_end"))
            .accessibilityIdentifier("nav-end")
            Button(action: model.togglePause) {
                Image(systemName: model.paused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .frame(width: 44, height: 48)
            }
            .accessibilityLabel(VelaL10n.text(model.paused ? "nav_resume" : "nav_pause"))
            .accessibilityIdentifier(model.paused ? "nav-resume" : "nav-pause")
            if model.navigating {
                Button(action: model.toggleOverview) {
                    Image(systemName: model.overview ? "location.fill" : "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .frame(width: 44, height: 48)
                }
                .accessibilityLabel(model.overview ? VelaL10n.text("nav_back_to_drive") : VelaL10n.text("nav_overview_remaining"))
                .accessibilityIdentifier("nav-overview")
            }
            VStack(spacing: 2) {
                if hasStopAhead {
                    // With stops the bar counts to the next one, as on Android: the stop's
                    // figures are the headline and the whole trip stays on the line below.
                    Text(RouteFormat.duration(model.nextStopSeconds))
                        .font(.title3.weight(.bold))
                        .lineLimit(largeText ? 2 : 1)
                        .accessibilityIdentifier("nav-stop-eta")
                    Text("\(RouteFormat.distance(model.nextStopDistance)) · \(NavFormat.arrival(after: model.nextStopSeconds))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(largeText ? 2 : 1)
                        .accessibilityIdentifier("nav-stop-figures")
                    Text(VelaL10n.text("nav_bar_to_stop", model.nextStopLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(largeText ? 2 : 1)
                        .accessibilityIdentifier("nav-next-stop")
                    Text(VelaL10n.text(
                        "nav_bar_trip",
                        RouteFormat.duration(model.remainingSeconds),
                        NavFormat.arrival(after: model.remainingSeconds)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(largeText ? 2 : 1)
                        .accessibilityIdentifier("nav-trip")
                } else {
                    Text(RouteFormat.duration(model.remainingSeconds))
                        .font(.title3.weight(.bold))
                        .lineLimit(largeText ? 2 : 1)
                    Text("\(RouteFormat.distance(model.remainingDistance)) · \(NavFormat.arrival(after: model.remainingSeconds))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(largeText ? 2 : 1)
                }
            }
            .frame(maxWidth: .infinity)
            Button(action: model.toggleVoice) {
                Image(systemName: voiceSymbol)
                    .font(.title3)
                    .frame(width: 44, height: 48)
            }
            .accessibilityLabel(voiceModeLabel)
            .accessibilityValue(voiceModeLabel)
            .accessibilityIdentifier("nav-voice")
            Button(action: model.toggleNorthUp) {
                Image(systemName: model.northUp ? "location.north.fill" : "location.north.line")
                    .font(.title3)
                    .frame(width: 40, height: 48)
            }
            .accessibilityLabel(VelaL10n.text("nav_toggle_heading_up"))
            .accessibilityIdentifier("nav-heading")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-bottom")
    }

    private var arrival: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(VelaL10n.text("nav_arrived"), systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
            if !model.destinationName.isEmpty {
                Text(model.destinationName)
                    .font(.body)
            }
            if !model.destinationAddress.isEmpty && model.destinationAddress != model.destinationName {
                Text(model.destinationAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VelaL10n.text("nav_trip_time"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(RouteFormat.duration(model.tripSeconds))
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(VelaL10n.text("nav_distance"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(RouteFormat.distance(model.tripDistance))
                        .font(.headline)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nav-arrival-figures")
            if model.parkingOffer {
                if model.parkingSaved {
                    Label(VelaL10n.text("map_parking_saved"), systemImage: "parkingsign.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("nav-parking-saved")
                } else {
                    Button {
                        _ = model.saveParkingHere()
                    } label: {
                        Label(VelaL10n.text("map_parking_save"), systemImage: "parkingsign.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("nav-save-parking")
                }
            }
            Button(VelaL10n.text("nav_done"), action: model.stop)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("nav-done")
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-arrival")
    }
}

#if DEBUG
private struct NavDebugLabel: View {
    let text: String
    let id: String

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier(id)
            .allowsHitTesting(false)
    }
}
#endif

enum NavFormat {
    static func arrival(after seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date().addingTimeInterval(seconds))
    }

    static func speedValue(_ metersPerSecond: Double, imperial: Bool) -> Int {
        Int((metersPerSecond * (imperial ? 2.236936 : 3.6)).rounded())
    }

    static func speedUnit(imperial: Bool) -> String {
        imperial ? "mph" : "km/h"
    }

    static func limitValue(_ kmh: Double, imperial: Bool) -> Int {
        Int((imperial ? kmh * 0.621371 : kmh).rounded())
    }
}
