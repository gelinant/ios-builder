import SwiftUI
import UIKit

/// Driving with no destination: the speed, the posted limit, the road under the car and the
/// switches a mounted phone needs. It shares the guided drive's camera, voice mode and saved
/// settings; it has no route, no ETA, no Live Activity and no resume record.
struct FreeDriveChrome: View {
    @ObservedObject var model: NavModel
    let onLocate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                speedPill
                Spacer(minLength: 0)
                circleButton(
                    symbol: model.simpleMap ? "map.fill" : "map",
                    label: "Simple map",
                    value: model.simpleMap ? "on" : "off",
                    identifier: "free-simple-map",
                    action: model.toggleSimpleMap)
                circleButton(
                    symbol: voiceSymbol,
                    label: voiceModeLabel,
                    value: voiceModeLabel,
                    identifier: "free-voice",
                    action: model.toggleVoice)
                circleButton(
                    symbol: "location.fill",
                    label: "Show my location",
                    value: nil,
                    identifier: "free-locate",
                    action: onLocate)
                circleButton(
                    symbol: "xmark",
                    label: "Leave free driving",
                    value: nil,
                    identifier: "free-exit",
                    action: model.stopFreeDrive)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            #if DEBUG
            HStack {
                Text(model.debugLine)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("free-debug")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            #endif
            Spacer(minLength: 0)
            if !model.currentRoadLabel.isEmpty {
                HStack(spacing: 6) {
                    if !model.currentRoadRef.isEmpty {
                        NavShieldView(
                            label: model.currentRoadRef,
                            onDark: false,
                            identifier: "free-road-shield")
                    }
                    Text(model.currentRoadLabel)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("free-road")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("free-road-pill")
            }
            HStack {
                Link(destination: MapDefaults.attributionURL) {
                    Text(VelaL10n.text("map_osm_attribution"))
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("free-drive-chrome")
    }

    private func circleButton(
        symbol: String,
        label: String,
        value: String?,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 46, height: 46)
        }
        .background(.regularMaterial, in: Circle())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(identifier)
    }

    private var voiceSymbol: String {
        if !model.voiceMuted { return "speaker.wave.2.fill" }
        return model.voiceAlertsOnly ? "bell.badge.fill" : "speaker.slash.fill"
    }

    private var voiceModeLabel: String {
        if !model.voiceMuted { return VelaL10n.text("settings_voice_mode_on") }
        return VelaL10n.text(model.voiceAlertsOnly ? "settings_voice_mode_alerts" : "settings_voice_mode_off")
    }

    private var speedPill: some View {
        let speed = model.speedMps ?? 0
        let over = model.speeding
        let color = over ? Color.red : Color.primary
        return HStack(spacing: 9) {
            if let limit = model.speedLimitKmh {
                Text("\(NavFormat.limitValue(limit, imperial: model.imperial))")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .systemBackground), in: Circle())
                    .overlay(Circle().stroke(Color.red, lineWidth: 3))
                    .accessibilityIdentifier("free-speed-limit")
            }
            VStack(spacing: 0) {
                Text("\(NavFormat.speedValue(speed, imperial: model.imperial))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityIdentifier("free-speed-value")
                Text(NavFormat.speedUnit(imperial: model.imperial))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("free-speed")
    }
}
