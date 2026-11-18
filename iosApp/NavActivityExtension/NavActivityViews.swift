import SwiftUI

struct NavActivityLockScreenView: View {
    let state: NavActivityAttributes.ContentState
    let destinationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    state.mode == .drive ? "Driving" : "Walking",
                    systemImage: state.mode == .drive ? "car.fill" : "figure.walk")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NavActivityPalette.accent)
                Spacer()
                if state.offRoute {
                    Label("Rerouting", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NavActivityPalette.accent)
                }
            }

            if state.arrived {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(NavActivityPalette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You have arrived")
                            .font(.title3.weight(.bold))
                        if !destinationName.isEmpty {
                            Text(destinationName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    NavActivityManeuverImage(state: state, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NavActivityFormat.distance(state.distanceToNextManeuverMeters))
                            .font(.title.weight(.bold))
                        Text(state.instruction)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        if !state.streetName.isEmpty && state.streetName != state.instruction {
                            Text(state.streetName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                ProgressView(value: state.progress)
                    .tint(NavActivityPalette.accent)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NavActivityFormat.distance(state.remainingDistanceMeters))
                            .font(.headline)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(state.arrivalDate, style: .time)
                            .font(.headline)
                        Text("\(NavActivityFormat.duration(state.remainingDurationSeconds)) ETA")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .foregroundStyle(.primary)
    }
}

struct NavActivityManeuverImage: View {
    let state: NavActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: size * 1.2, height: size * 1.2)
            .foregroundStyle(state.arrived ? NavActivityPalette.accent : .white)
            .background(
                state.arrived ? Color.clear : NavActivityPalette.accent,
                in: RoundedRectangle(cornerRadius: max(4, size * 0.22)))
    }

    private var symbol: String {
        if state.arrived { return "checkmark.circle.fill" }
        if state.offRoute { return "arrow.triangle.2.circlepath" }
        switch state.maneuverKind {
        case "DEPART": return "circle.circle"
        case "ARRIVE": return "mappin.circle.fill"
        case "TURN_LEFT", "SHARP_LEFT": return "arrow.turn.up.left"
        case "TURN_RIGHT", "SHARP_RIGHT": return "arrow.turn.up.right"
        case "SLIGHT_LEFT", "KEEP_LEFT", "FORK_LEFT", "RAMP_LEFT": return "arrow.up.left"
        case "SLIGHT_RIGHT", "KEEP_RIGHT", "FORK_RIGHT", "RAMP_RIGHT": return "arrow.up.right"
        case "UTURN": return "arrow.uturn.down"
        case "MERGE": return "arrow.merge"
        case "ROUNDABOUT", "EXIT_ROUNDABOUT": return "arrow.triangle.2.circlepath"
        default: return "arrow.up"
        }
    }
}

enum NavActivityPalette {
    /// Matches AccentColor in the app asset catalog (#149387).
    static let accent = Color(red: 0x14 / 255.0, green: 0x93 / 255.0, blue: 0x87 / 255.0)
}

enum NavActivityFormat {
    static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        let rounded = max(60, (seconds / 60).rounded() * 60)
        return formatter.string(from: rounded) ?? "\(Int(rounded / 60)) min"
    }

    static func distance(_ meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        let number = NumberFormatter()
        if Locale.current.measurementSystem != .us {
            if meters < 1000 {
                number.maximumFractionDigits = 0
                formatter.numberFormatter = number
                return formatter.string(from: Measurement(
                    value: (meters / 10).rounded() * 10, unit: UnitLength.meters))
            }
            number.maximumFractionDigits = meters < 10_000 ? 1 : 0
            formatter.numberFormatter = number
            return formatter.string(from: Measurement(value: meters / 1000, unit: UnitLength.kilometers))
        }
        let miles = meters / 1609.344
        if miles < 0.1 {
            number.maximumFractionDigits = 0
            formatter.numberFormatter = number
            return formatter.string(from: Measurement(
                value: (meters * 3.28084 / 10).rounded() * 10, unit: UnitLength.feet))
        }
        number.maximumFractionDigits = miles < 10 ? 1 : 0
        formatter.numberFormatter = number
        return formatter.string(from: Measurement(value: miles, unit: UnitLength.miles))
    }
}
