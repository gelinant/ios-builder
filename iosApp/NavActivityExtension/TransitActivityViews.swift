import SwiftUI

struct TransitActivityLockScreenView: View {
    let state: TransitActivityAttributes.ContentState
    let destinationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.arrived {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(TransitActivityPalette.accent)
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
                HStack(alignment: .top, spacing: 8) {
                    TransitActivityLinePill(state: state)
                    if !state.direction.isEmpty {
                        Text("towards \(state.direction)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    TransitActivityDelayBadge(minutes: state.delayMinutes)
                }

                Text(state.instruction)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if state.stopsRemaining >= 0 {
                    Text(TransitActivityFormat.stops(state.stopsRemaining))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: state.progress)
                    .tint(TransitActivityPalette.fill(state.lineColorHex))

                HStack(alignment: .top, spacing: 12) {
                    TransitActivityTimeColumn(
                        title: state.boarded ? "Departed" : "Board",
                        scheduled: state.scheduledDeparture,
                        estimated: state.estimatedDeparture)
                    Spacer(minLength: 0)
                    TransitActivityTimeColumn(
                        title: "Get off",
                        scheduled: state.scheduledArrival,
                        estimated: state.estimatedArrival)
                    Spacer(minLength: 0)
                    TransitActivityArrival(state: state)
                }
            }
        }
        .padding(16)
    }
}
