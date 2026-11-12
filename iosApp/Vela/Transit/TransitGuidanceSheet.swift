import SwiftUI
import UIKit

/// The one transit surface for a running trip, folded into the map's bottom sheet (DESIGN.md 3.7).
/// It has three detents: at peek it is a thin permanent bar so the map stays usable while the trip
/// runs, at the medium (tall) detent it is the GO step-by-step guidance, and at the expanded
/// detent it is the full guidance card with the trip's details. The bottom sheet never covers the
/// whole window, so the map and its chrome stay visible behind each detent, and ending or closing
/// the trip returns the map to browse.
struct TransitGuidanceSheet: View {
    @ObservedObject var model: TransitModel
    @Binding var detent: SheetDetent
    /// Called with the measured height so the map can move its bottom inset with the sheet.
    var onHeightChange: ((CGFloat) -> Void)?

    /// The detents the guidance sheet rests on, shortest first. The medium detent holds GO and the
    /// tallest holds the full card details; Design.Sheet supplies the fractions.
    static let detents: [SheetDetent] = [.peek, .tall, .expanded]

    /// The GO model for the tall detent, built once from the active trip so the trip survives
    /// collapsing to the peek bar and expanding again.
    @StateObject private var go: TransitGoModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: TransitModel, detent: Binding<SheetDetent>,
         onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.model = model
        self._detent = detent
        self.onHeightChange = onHeightChange
        let trip = model.goTrip
        let destination = model.destinationName.isEmpty ? "the destination" : model.destinationName
        let network = AppGraph.session.offline?.state.value.networkAvailable ?? true
        let go = TransitGoModel(
            trip: trip,
            destinationName: destination,
            networkAvailable: network)
        // A GO step moves the shared session too, and through it the Live Activity.
        go.onStep = { [weak model] command in model?.step(command) }
        _go = StateObject(wrappedValue: go)
    }

    var body: some View {
        SheetSurface(detent: $detent, detents: Self.detents,
                     showsGrabber: detent != .tall,
                     onHeightChange: onHeightChange) {
            content
        }
        .dynamicTypeSize(.xSmall ... .accessibility3)
    }

    // MARK: Content by detent

    @ViewBuilder
    private var content: some View {
        switch detent {
        case .tall:
            goView
        case .expanded:
            detailView
        default:
            peekBar
        }
    }

    /// The permanent bar: the line, the direction, the current action, a live countdown, GO and
    /// End. It fills the peek detent and is vertically centered, so collapsing the sheet to peek
    /// leaves the map usable while the trip keeps running. Tapping the bar reopens the details.
    private var peekBar: some View {
        Group {
            if let state = model.content {
                HStack(alignment: .center, spacing: Design.Spacing.m) {
                    TransitActivityLinePill(state: state)
                    VStack(alignment: .leading, spacing: 2) {
                        if !state.direction.isEmpty {
                            Text(VelaL10n.text("transit_nav_towards", String(describing: (state.direction))))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                        Text(state.instruction)
                            .font(.subheadline)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(2)
                    }
                    Spacer(minLength: Design.Spacing.s)
                    VStack(alignment: .trailing, spacing: 2) {
                        TransitActivityDelayBadge(minutes: state.delayMinutes)
                        countdown(state)
                    }
                    goButton
                    endButton
                }
                .padding(.horizontal, Design.Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { setDetent(.expanded) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("transit-card-actions-inline")
            } else {
                HStack(spacing: Design.Spacing.s) {
                    Text(model.destinationName)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: Design.Spacing.s)
                    endButton
                }
                .padding(.horizontal, Design.Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    /// A live read of how long until the trip arrives, from the shared session's overall arrival.
    @ViewBuilder
    private func countdown(_ state: TransitActivityAttributes.ContentState) -> some View {
        if let date = state.overallArrivalDate {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let minutes = Int(ceil(date.timeIntervalSince(context.date) / 60))
                if minutes > 0 {
                    Text(VelaL10n.text("transit_min", String(describing: (minutes))))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                } else if minutes == 0 {
                    Text(VelaL10n.text("place_transit_now"))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                } else if let text = state.overallArrivalText, !text.isEmpty {
                    Text(text).font(.subheadline.monospacedDigit())
                }
            }
        } else if let text = state.overallArrivalText, !text.isEmpty {
            Text(text).font(.subheadline.monospacedDigit())
        }
    }

    /// The GO guidance, the same screen a standalone host presents full-screen but embedded in the
    /// medium detent. Its sub-surfaces route into this sheet instead of the full-screen host.
    private var goView: some View {
        TransitGoScreen(
            model: go,
            transit: model,
            onClose: { setDetent(.expanded) },
            onNextDepartures: openBoardForCurrentRide,
            onLeaveLater: { _, epochSec in model.setTimeMode(1, epochSec: epochSec) },
            onWholeTrip: { setDetent(.expanded) },
            // The medium detent keeps the guidance (action, countdown, pill and rail) as the
            // focus; the full-screen host keeps its own GL map.
            showsEmbeddedMap: false)
            .onAppear {
                TransitStepCommands.go = go
            }
            .onDisappear {
                if TransitStepCommands.go === go { TransitStepCommands.go = nil }
                model.closeBoard()
            }
    }

    /// The full guidance card with the trip's details. Its GO action expands the sheet to medium
    /// instead of presenting the full-screen host.
    private var detailView: some View {
        TransitGuidanceCard(model: model, goAction: { setDetent(.tall) }, anchorsToTop: true)
    }

    // MARK: Actions

    private var goButton: some View {
        Button {
            setDetent(.tall)
        } label: {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.subheadline.weight(.bold))
                .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
        }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: Design.Size.hitTarget)
        .accessibilityLabel(VelaL10n.text("transit_open_go_step_by_step_guidance"))
        .accessibilityIdentifier("transit-go-open")
    }

    private var endButton: some View {
        Button(role: .destructive, action: model.stop) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
        }
        .buttonStyle(.bordered)
        .frame(minHeight: Design.Size.hitTarget)
        .accessibilityLabel(VelaL10n.text("nav_end_confirm_end"))
        .accessibilityIdentifier("transit-end")
    }

    /// "Next departures" of the ride being shown opens the T-1 stop board, the same surface GO's
    /// full-screen host opens on the boarding stop of the current ride.
    private func openBoardForCurrentRide() {
        guard let trip = model.activeTrip ?? model.tripScreenTrip,
              let step = trip.steps.first(where: { $0.line != nil }),
              let board = step.boardStop,
              let location = board.location else { return }
        model.openBoard(
            latitude: location.lat,
            longitude: location.lng,
            name: board.name)
    }

    private func setDetent(_ target: SheetDetent) {
        guard target != detent else { return }
        withAnimation(Design.Motion.animation(Design.Motion.sheetSpring, reduceMotion: reduceMotion)) {
            detent = target
        }
    }
}