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

                // The step buttons flank the instruction, so the view keeps its height.
                HStack(spacing: 8) {
                    TransitActivityStepButton(state: state, command: .previous)
                    Text(state.instruction)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TransitActivityStepButton(state: state, command: .next)
                }
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

/// Previous or Next as a 44 pt round button. The intent runs in the app process, which moves the
/// shared session and publishes the new state back to this activity. A button at either end of
/// the trip is disabled; its VoiceOver label names the step it goes to.
struct TransitActivityStepButton: View {
    let state: TransitActivityAttributes.ContentState
    let command: TransitStepCommand

    private var target: String? {
        command == .previous ? state.previousStepTitle : state.nextStepTitle
    }

    var body: some View {
        Button(intent: TransitStepIntent(command, sessionId: state.sessionId)) {
            Image(systemName: command == .previous ? "chevron.backward" : "chevron.forward")
                .font(.body.weight(.bold))
                .frame(width: 44, height: 44)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch (command, target) {
        case (.previous, let step?): return "Previous step: \(step)"
        case (.previous, nil): return "No previous step"
        case (.next, let step?): return "Next step: \(step)"
        case (.next, nil): return "No next step"
        }
    }
}
