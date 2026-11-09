import Foundation
import SwiftUI
import UIKit

/// Compact in-app guidance for the selected transit itinerary. The same scheduled/live fields feed
/// this card and ActivityKit, so neither surface can silently turn a timetable into a live estimate.
struct TransitGuidanceCard: View {
    @ObservedObject var model: TransitModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showsTrip = false
    @State private var showsLegs = false

    /// At an accessibility size the three actions cannot share the direction's row without
    /// crowding or leaving the card. They wrap under it and collapse to icons there, each still a
    /// 44 pt target with its own VoiceOver label.
    private var wrapsActions: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        // A11Y-SPLIT: the card used to be one VStack pinned to the bottom. Above AX1 its content
        // grew taller than the window, the stack centred it and both edges left the screen, which
        // pushed the detail entry (last row of the card) out of reach. The card now measures the
        // window, pins the line summary, the three actions and the debug hooks at its top and
        // scrolls only the detail rows below them.
        GeometryReader { proxy in
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                if let state = model.content {
                    card(state, maxHeight: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .sheet(isPresented: $showsLegs) {
            TransitDetailSheet(
                model: model,
                onClose: { showsLegs = false },
                onStart: {
                    model.startIfAvailable()
                    showsLegs = false
                })
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showsTrip) {
            TransitTripScreen(
                model: model.trip,
                destination: model.destinationName,
                live: model.live,
                transit: model,
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

    /// The card's frame. A normal text size keeps the intrinsic height the card always had; an
    /// accessibility size fills the height it was given so the pinned header cannot leave the
    /// window, and the detail rows scroll in the space left below it.
    private func card(_ state: TransitActivityAttributes.ContentState,
                      maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.arrived {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(TransitActivityPalette.accent)
                    VStack(alignment: .leading) {
                        Text(VelaL10n.text("transit_nav_arrived"))
                            .font(.headline)
                        Text(model.destinationName)
                            .font(.subheadline)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    Spacer()
                    Button(VelaL10n.text("settings_trip_select_done"), action: model.stop)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("transit-end")
                }
            } else if wrapsActions {
                VStack(alignment: .leading, spacing: Design.Spacing.s) {
                    HStack(alignment: .top, spacing: Design.Spacing.s) {
                        lineSummary(state)
                        Spacer(minLength: Design.Spacing.s)
                        TransitActivityDelayBadge(minutes: state.delayMinutes)
                    }
                    HStack(spacing: Design.Spacing.s) {
                        tripButton(compact: true)
                        TransitGoButton(model: model, compact: true)
                        endButton(compact: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("transit-card-actions-wrapped")
                    .accessibilityValue("wrapped")
                }
                debugHooks
                ScrollView { details(state) }
            } else {
                HStack(alignment: .top, spacing: Design.Spacing.s) {
                    lineSummary(state)
                    Spacer(minLength: Design.Spacing.s)
                    TransitActivityDelayBadge(minutes: state.delayMinutes)
                    tripButton(compact: false)
                    TransitGoButton(model: model)
                    endButton(compact: false)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("transit-card-actions-inline")
                .accessibilityValue("inline")
                details(state)
                debugHooks
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity,
               maxHeight: wrapsActions ? maxHeight : nil,
               alignment: .top)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-card")
    }

    /// The rows below the header: the step, the remaining stop count, the progress and the two
    /// scheduled or live times. They are the ones that grow with Dynamic Type.
    @ViewBuilder
    private func details(_ state: TransitActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    title: state.boarded ? VelaL10n.text("transit_departed") : VelaL10n.text("transit_board"),
                    scheduled: state.scheduledDeparture,
                    estimated: state.estimatedDeparture)
                Spacer(minLength: 0)
                TransitActivityTimeColumn(
                    title: VelaL10n.text("transit_get_off_title"),
                    scheduled: state.scheduledArrival,
                    estimated: state.estimatedArrival)
                Spacer(minLength: 0)
                TransitActivityArrival(state: state)
            }
            Text(VelaL10n.text("transit_updates_require_vela_to_be_running"))
                .font(.caption2)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The debug hooks the transit scenarios tap. They sit in the pinned header so a screenshot
    /// or a tap never depends on how far the detail rows scrolled.
    @ViewBuilder
    private var debugHooks: some View {
        #if DEBUG
        // The map's own invisible debug line already publishes `transit-debug` while a session
        // runs. Repeating it here gave the scenarios two matching nodes.
        if !model.arrived {
            Button("Next leg (preview)", action: model.advanceForPreview)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("transit-next")
        }
        // The production steps sheet needs the route chooser; the fixture scenario has none, so
        // this opens the same sheet on the recorded trip for the UI test.
        if model.detail != nil,
           ProcessInfo.processInfo.arguments.contains("-VelaTransitFixture") {
            Button("Legs") { showsLegs = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("transit-detail-open")
        }
        #endif
    }

    @ViewBuilder
    private func lineSummary(_ state: TransitActivityAttributes.ContentState) -> some View {
        TransitActivityLinePill(state: state)
        if !state.direction.isEmpty {
            Text(VelaL10n.text("transit_nav_towards", String(describing: (state.direction))))
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(2)
        }
    }

    private func tripButton(compact: Bool) -> some View {
        Button {
            showsTrip = true
        } label: {
            Group {
                if compact {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(VelaL10n.text("mapvm_trip_default_name"))
                }
            }
            // A11Y-SPLIT: the floor belongs to the label. On the Button the bordered style kept
            // its own 34 point height, which is the frame the sheet's own Trip button inherited
            // whenever the scenarios resolved this card's duplicate first.
            .frame(minWidth: Design.Size.hitTarget,
                   minHeight: Design.Size.hitTarget)
        }
        .buttonStyle(.bordered)
        .layoutPriority(1)
        .accessibilityLabel(VelaL10n.text("mapvm_trip_default_name"))
        .accessibilityIdentifier("transit-trip-open")
    }

    private func endButton(compact: Bool) -> some View {
        Button(role: .destructive, action: model.stop) {
            Group {
                if compact {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(VelaL10n.text("nav_end_confirm_end"))
                }
            }
            .frame(minWidth: Design.Size.hitTarget,
                   minHeight: Design.Size.hitTarget)
        }
        .buttonStyle(.bordered)
        .layoutPriority(1)
        .accessibilityLabel(VelaL10n.text("nav_end_confirm_end"))
        .accessibilityIdentifier("transit-end")
    }

    /// The walking leg's turn-by-turn, derived from the leg's own path when the planner gave no
    /// street-level steps. The source line says so instead of implying named streets.
    private var tripButton: some View {
        Button(VelaL10n.text("mapvm_trip_default_name")) { showsTrip = true }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .layoutPriority(1)
            .accessibilityIdentifier("transit-trip-open")
    }

    private var endButton: some View {
        Button(VelaL10n.text("nav_end_confirm_end"), role: .destructive, action: model.stop)
            .buttonStyle(.bordered)
            .layoutPriority(1)
            .accessibilityIdentifier("transit-end")
    }

    private var walkGuidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.walkInstruction)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("transit-walk-instruction")
                Spacer(minLength: 4)
                if model.walkDistanceM > 1 {
                    Text(VelaL10n.text("transit_in", String(describing: (RouteFormat.distance(model.walkDistanceM)))))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                Text(model.walkTarget.isEmpty ? VelaL10n.text("place_mode_walk") : VelaL10n.text("transit_walk_to", String(describing: (model.walkTarget))))
                if model.walkRemainingM >= 0 {
                    Text(VelaL10n.text("transit_left", String(describing: (RouteFormat.distance(model.walkRemainingM)))))
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            if !model.walkNamed {
                Text(VelaL10n.text("transit_turn_by_turn_from_the_walk"))
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("transit-walk-source")
            }
        }
    }
}
