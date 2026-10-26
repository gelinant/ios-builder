import ActivityKit
import SwiftUI
import WidgetKit

/// Shares X-1's WidgetKit extension so sideloading needs only one extension profile. The driving
/// widget and its behavior remain independent from this transit ActivityConfiguration.
struct TransitGuidanceActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransitActivityAttributes.self) { context in
            TransitActivityLockScreenView(
                state: context.state,
                destinationName: context.attributes.destinationName)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        TransitActivityLinePill(state: context.state)
                        if !context.state.direction.isEmpty {
                            Text(context.state.direction)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TransitActivityArrival(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(context.state.instruction)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            TransitActivityDelayBadge(minutes: context.state.delayMinutes)
                        }
                        if context.state.stopsRemaining >= 0 {
                            Text(TransitActivityFormat.stops(context.state.stopsRemaining))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            TransitActivityTimeColumn(
                                title: "Board",
                                scheduled: context.state.scheduledDeparture,
                                estimated: context.state.estimatedDeparture)
                            Spacer()
                            TransitActivityTimeColumn(
                                title: "Get off",
                                scheduled: context.state.scheduledArrival,
                                estimated: context.state.estimatedArrival)
                        }
                        ProgressView(value: context.state.progress)
                            .tint(TransitActivityPalette.fill(context.state.lineColorHex))
                    }
                }
            } compactLeading: {
                TransitActivityLinePill(state: context.state, compact: true)
            } compactTrailing: {
                if context.state.legKind == "WALK" {
                    Image(systemName: "figure.walk")
                        .foregroundStyle(TransitActivityPalette.accent)
                } else if context.state.stopsRemaining >= 0 {
                    Text("\(context.state.stopsRemaining)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TransitActivityPalette.accent)
                } else {
                    Image(systemName: "tram.fill")
                        .foregroundStyle(TransitActivityPalette.accent)
                }
            } minimal: {
                TransitActivityLinePill(state: context.state, compact: true)
            }
        }
    }
}
