import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NavActivityExtension: WidgetBundle {
    var body: some Widget {
        NavDrivingActivity()
        TransitGuidanceActivity()
    }
}

struct NavDrivingActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavActivityAttributes.self) { context in
            NavActivityLockScreenView(
                state: context.state,
                destinationName: context.attributes.destinationName)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NavActivityManeuverImage(state: context.state, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NavActivityFormat.distance(
                                context.state.distanceToNextManeuverMeters))
                                .font(.headline)
                            Text(context.state.mode == .drive ? "Driving" : "Walking")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.arrivalDate, style: .time)
                            .font(.headline)
                        Text(context.state.arrived
                             ? "Arrived"
                             : NavActivityFormat.duration(context.state.remainingDurationSeconds))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            if context.state.offRoute {
                                Label("Rerouting", systemImage: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(NavActivityPalette.accent)
                            } else {
                                Text(context.state.streetName.isEmpty
                                     ? context.state.instruction
                                     : context.state.streetName)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text("\(NavActivityFormat.distance(context.state.remainingDistanceMeters)) left")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        ProgressView(value: context.state.progress)
                            .tint(NavActivityPalette.accent)
                    }
                }
            } compactLeading: {
                NavActivityManeuverImage(state: context.state, size: 18)
            } compactTrailing: {
                Text(context.state.arrived
                     ? "Done"
                     : NavActivityFormat.distance(context.state.distanceToNextManeuverMeters))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NavActivityPalette.accent)
            } minimal: {
                NavActivityManeuverImage(state: context.state, size: 18)
            }
        }
    }
}
