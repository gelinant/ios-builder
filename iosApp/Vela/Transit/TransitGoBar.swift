import SwiftUI
import UIKit

/// FICHE-BARRE: the permanent bottom bar of a running GO trip. Once GO has been opened at least
/// once (`TransitModel.goEngaged`), the map keeps the browse chrome usable and this compact bar
/// replaces the full guidance card, so the traveller can search or navigate during the trip.
/// Tapping the bar reopens the GO sheet; Trip and End stay one tap away.
///
/// The bar reads the same `transit.content` as the guidance card and the Live Activity, so no
/// surface can silently diverge from the plan. When the session ends, `goEngaged` clears and the
/// map goes back to the plain browser chrome.
struct TransitGoBar: View {
    @ObservedObject var model: TransitModel

    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var showsTrip = false

    /// At an accessibility size the two actions collapse to icons, each still a 44 pt target
    /// with its own VoiceOver label, exactly like the guidance card's wrapped actions.
    private var wrapsActions: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        // The bar has nothing to show without a running session; it must never shrink the chrome.
        Group {
            if let content = model.content {
                bar(content)
            }
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

    private func bar(_ content: TransitActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Design.Spacing.s) {
                // The reopen surface: the ride and its progress, in the trip's own line colour.
                Button {
                    model.openGo()
                } label: {
                    HStack(spacing: Design.Spacing.s) {
                        TransitActivityLinePill(state: content, compact: true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(model.walkActive && !model.walkInstruction.isEmpty
                                     ? model.walkInstruction : content.instruction)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(wrapsActions ? 3 : 2)
                                if !content.direction.isEmpty {
                                    Text(VelaL10n.text("transit_nav_towards",
                                                       String(describing: (content.direction))))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            HStack(spacing: 8) {
                                if content.stopsRemaining >= 0 {
                                    Text(TransitActivityFormat.stops(content.stopsRemaining))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let arrival = content.estimatedArrival ?? content.scheduledArrival {
                                    Text(VelaL10n.text("navservice_notif_eta",
                                                       String(describing: (arrival))))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        ProgressView(value: content.progress)
                            .tint(TransitActivityPalette.fill(content.lineColorHex))
                            .frame(width: 64)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transit-go-open")
                .accessibilityLabel(VelaL10n.text("transit_open_go_step_by_step_guidance"))

                tripButton
                endButton
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-go-bar")
    }

    private var tripButton: some View {
        Button {
            showsTrip = true
        } label: {
            Group {
                if wrapsActions {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(VelaL10n.text("mapvm_trip_default_name"))
                }
            }
            .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .layoutPriority(1)
        .accessibilityLabel(VelaL10n.text("mapvm_trip_default_name"))
        .accessibilityIdentifier("transit-trip-open")
    }

    private var endButton: some View {
        Button(role: .destructive, action: model.stop) {
            Group {
                if wrapsActions {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(VelaL10n.text("nav_end_confirm_end"))
                }
            }
            .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .layoutPriority(1)
        .accessibilityLabel(VelaL10n.text("nav_end_confirm_end"))
        .accessibilityIdentifier("transit-end")
    }
}
