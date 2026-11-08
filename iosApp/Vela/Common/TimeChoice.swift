import SwiftUI
import UIKit

/// The one time control of the app. The route sheet, the transit options, the trip screen, the stop
/// board, the trip detail and the saved route picker present the same three modes, the same date
/// picker, the same +15 minutes button and the same Apply, in the same order. Each surface passes
/// its own identifiers, so the scenarios written for that surface keep working.
///
/// The line under the buttons always names the current query: the mode, the clock time, the device
/// zone and, after an Apply, the minute the request was sent. A stale answer therefore cannot be
/// mistaken for a fresh one.
struct TimeChoiceBar: View {
    @ObservedObject var model: TimeChoiceModel

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 6) {
                        modeButton(TimeChoiceModel.now, label: VelaL10n.text("place_leave_now"), id: model.ids.now)
                        modeButton(TimeChoiceModel.depart, label: VelaL10n.text("place_depart_at"), id: model.ids.depart)
                        modeButton(TimeChoiceModel.arrive, label: VelaL10n.text("place_arrive_by"), id: model.ids.arrive)
                    }
                } else {
                    HStack(spacing: 6) {
                        modeButton(TimeChoiceModel.now, label: VelaL10n.text("place_leave_now"), id: model.ids.now)
                        modeButton(TimeChoiceModel.depart, label: VelaL10n.text("place_depart_at"), id: model.ids.depart)
                        modeButton(TimeChoiceModel.arrive, label: VelaL10n.text("place_arrive_by"), id: model.ids.arrive)
                    }
                }
            }
            if model.editing != nil {
                DatePicker(
                    VelaL10n.text("time_date_and_time"),
                    selection: $model.draft,
                    displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .accessibilityIdentifier(model.ids.date)
                HStack(spacing: 12) {
                    Button("+15 min") {
                        model.addFifteenMinutes()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(model.ids.plus)
                    Spacer(minLength: 0)
                    Button(VelaL10n.text("transit_apply_time")) {
                        model.apply()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(model.ids.apply)
                }
            }
            Text(model.status)
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(model.ids.label)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("time-choice")
    }

    private func modeButton(_ choice: Int32, label: String, id: String) -> some View {
        Button {
            model.choose(choice)
        } label: {
            Text(label)
                .font(.caption)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .multilineTextAlignment(.center)
                .background(
                    (model.editing ?? model.mode) == choice
                        ? Color.accentColor.opacity(0.2)
                        : Color(uiColor: .secondarySystemBackground),
                    in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits((model.editing ?? model.mode) == choice ? .isSelected : [])
    }
}
