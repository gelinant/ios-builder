import SwiftUI
import UIKit

/// Compact in-app guidance for the selected transit itinerary. The same scheduled/live fields feed
/// this card and ActivityKit, so neither surface can silently turn a timetable into a live estimate.
struct TransitGuidanceCard: View {
    @ObservedObject var model: TransitModel

    @State private var showsTrip = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            if let state = model.content {
                VStack(alignment: .leading, spacing: 12) {
                    if state.arrived {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(TransitActivityPalette.accent)
                            VStack(alignment: .leading) {
                                Text("You have arrived")
                                    .font(.headline)
                                Text(model.destinationName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                            }
                            Spacer()
                            Button("Done", action: model.stop)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("transit-end")
                        }
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            TransitActivityLinePill(state: state)
                            if !state.direction.isEmpty {
                                Text("towards \(state.direction)")
                                    .font(.caption)
                                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            TransitActivityDelayBadge(minutes: state.delayMinutes)
                            Button("Trip") { showsTrip = true }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("transit-trip-open")
                            Button("End", role: .destructive, action: model.stop)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("transit-end")
                        }

                        if model.walkActive {
                            walkGuidance
                        } else {
                            Text(state.instruction)
                                .font(.title3.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if state.stopsRemaining >= 0 {
                            Text(TransitActivityFormat.stops(state.stopsRemaining))
                                .font(.subheadline)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
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
                        Text("Updates require Vela to be running. They stop after force-quit.")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    #if DEBUG
                    Text(model.debugLine)
                        .font(.caption2.monospaced())
                        .lineLimit(2)
                        .accessibilityIdentifier("transit-debug")
                    if !model.arrived {
                        Button("Next leg (preview)", action: model.advanceForPreview)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("transit-next")
                    }
                    #endif
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("transit-card")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .fullScreenCover(isPresented: $showsTrip) {
            TransitTripScreen(
                model: model.trip,
                destination: model.destinationName,
                live: model.live,
                onClose: {
                    model.trip.close()
                    showsTrip = false
                })
            .onAppear {
                model.trip.onAdopt = { [weak model] chosen in model?.adoptAlternative(chosen) }
                if let trip = model.tripScreenTrip { model.trip.open(trip: trip) }
            }
        }
    }

    /// The walking leg's turn-by-turn, derived from the leg's own path when the planner gave no
    /// street-level steps. The source line says so instead of implying named streets.
    private var walkGuidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.walkInstruction)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("transit-walk-instruction")
                Spacer(minLength: 4)
                if model.walkDistanceM > 1 {
                    Text("in \(RouteFormat.distance(model.walkDistanceM))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                Text(model.walkTarget.isEmpty ? "Walk" : "Walk to \(model.walkTarget)")
                if model.walkRemainingM >= 0 {
                    Text("· \(RouteFormat.distance(model.walkRemainingM)) left")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            if !model.walkNamed {
                Text("Turn-by-turn from the walk path. Street names are unavailable for this leg.")
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("transit-walk-source")
            }
        }
    }
}
