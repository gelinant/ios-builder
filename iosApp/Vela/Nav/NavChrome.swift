import SwiftUI
import UIKit

/// The drive's top maneuver card, recenter control and bottom ETA strip.
struct NavChrome: View {
    @ObservedObject var model: NavModel
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 10) {
            if !model.arrived {
                banner
            }
            #if DEBUG
            VStack(alignment: .leading, spacing: 3) {
                NavDebugLabel(text: model.debugLine, id: "nav-debug")
                NavDebugLabel(text: model.voiceDebugLine, id: "nav-voice-debug")
            }
            #endif
            if model.starved && model.navigating {
                Label("Searching for GPS", systemImage: "location.slash")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
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
            VStack(spacing: 2) {
                Text(RouteFormat.duration(model.remainingSeconds))
                    .font(.title3.weight(.bold))
                Text("\(RouteFormat.distance(model.remainingDistance)) · \(NavFormat.arrival(after: model.remainingSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let speed = model.speedMps {
                    Text(NavFormat.speed(speed, limitKmh: model.speedLimitKmh))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Label("You have arrived", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
            if !model.destinationName.isEmpty {
                Text(model.destinationName)
            }
            if !model.destinationAddress.isEmpty && model.destinationAddress != model.destinationName {
                Text(model.destinationAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(RouteFormat.duration(model.tripSeconds)) · \(RouteFormat.distance(model.tripDistance))")
                .font(.headline)
            Button("Done", action: model.stop)
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

    static func speed(_ metersPerSecond: Double, limitKmh: Double?) -> String {
        let imperial = Locale.current.measurementSystem == .us
        let value = imperial ? metersPerSecond * 2.236936 : metersPerSecond * 3.6
        var text = "\(Int(value.rounded())) \(imperial ? "mph" : "km/h")"
        if let limitKmh {
            let limit = imperial ? limitKmh / 1.609344 : limitKmh
            text += " · limit \(Int(limit.rounded()))"
        }
        return text
    }
}
