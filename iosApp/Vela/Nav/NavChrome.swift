import SwiftUI
import UIKit

/// The drive's top maneuver card, recenter control and bottom ETA strip.
struct NavChrome: View {
    @ObservedObject var model: NavModel
    @State private var confirmEnd = false
    /// The waypoint card's serial the driver has dismissed, so the next stop shows again.
    @State private var dismissedStopSerial: Int64 = 0

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
                Button("Re-center") { model.recenter() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("nav-recenter")
            }
            if model.arrived {
                arrival
            } else {
                HStack {
                    if model.speedMps != nil {
                        speedPill
                    }
                    Spacer()
                }
                bottomBar
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .confirmationDialog("End navigation?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End navigation", role: .destructive, action: model.stop)
                .accessibilityIdentifier("nav-end-confirm")
            Button("Keep navigating", role: .cancel) {}
        }
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 14) {
            if model.offRoute {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("nav-rerouting")
            } else {
                Image(systemName: StepsSheet.symbol(model.maneuverKind))
                    .font(.system(size: 36, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.offRoute ? "Rerouting..." : RouteFormat.distance(model.distanceToNext))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                if !model.offRoute {
                    Text(model.maneuverText)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.nextManeuverText.isEmpty {
                        Text("Then \(model.nextManeuverText)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0, green: 0.396, blue: 0.31), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-banner")
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
        Label(model.roadAlertText, systemImage: "camera.fill")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.65, green: 0.31, blue: 0.08), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nav-camera-alert")
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

    private var speedPill: some View {
        let speed = model.speedMps ?? 0
        let color = model.speeding ? Color.red : Color.primary
        return HStack(spacing: 9) {
            if let limit = model.speedLimitKmh {
                Text("\(NavFormat.limitValue(limit, imperial: model.imperial))")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .systemBackground), in: Circle())
                    .overlay(Circle().stroke(Color.red, lineWidth: 3))
                    .accessibilityIdentifier("nav-speed-limit")
            }
            VStack(spacing: 0) {
                Text("\(NavFormat.speedValue(speed, imperial: model.imperial))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityIdentifier("nav-speed-value")
                Text(NavFormat.speedUnit(imperial: model.imperial))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            .accessibilityLabel("End")
            .accessibilityIdentifier("nav-end")
            Button(action: model.togglePause) {
                Image(systemName: model.paused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .frame(width: 44, height: 48)
            }
            .accessibilityLabel(VelaL10n.text(model.paused ? "nav_resume" : "nav_pause"))
            .accessibilityIdentifier(model.paused ? "nav-resume" : "nav-pause")
            VStack(spacing: 2) {
                Text(RouteFormat.duration(model.remainingSeconds))
                    .font(.title3.weight(.bold))
                Text("\(RouteFormat.distance(model.remainingDistance)) · \(NavFormat.arrival(after: model.remainingSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !model.nextStopLabel.isEmpty {
                    Text(VelaL10n.text("nav_bar_to_stop", model.nextStopLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("nav-next-stop")
                }
            }
            .frame(maxWidth: .infinity)
            Button(action: model.toggleVoice) {
                Image(systemName: model.voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .frame(width: 44, height: 48)
            }
            .accessibilityLabel(model.voiceMuted ? "Unmute voice" : "Mute voice")
            .accessibilityIdentifier("nav-voice")
            Button(action: model.toggleNorthUp) {
                Image(systemName: model.northUp ? "location.north.fill" : "location.north.line")
                    .font(.title3)
                    .frame(width: 40, height: 48)
            }
            .accessibilityLabel("Toggle heading up")
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

private enum NavFormat {
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
