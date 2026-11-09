import SwiftUI

struct TransitActivityLinePill: View {
    let state: TransitActivityAttributes.ContentState
    var compact = false

    var body: some View {
        if state.lineName.isEmpty {
            Image(systemName: state.legKind == "WALK" ? "figure.walk" : "tram.fill")
                .font(.system(size: compact ? 14 : 18, weight: .semibold))
                .frame(width: compact ? 24 : 30, height: compact ? 20 : 26)
        } else {
            Text(state.lineName)
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 2 : 4)
                .foregroundStyle(TransitActivityPalette.text(
                    fill: state.lineColorHex, explicit: state.lineTextColorHex))
                .background(TransitActivityPalette.fill(state.lineColorHex), in: RoundedRectangle(cornerRadius: 5))
        }
    }
}

struct TransitActivityDelayBadge: View {
    let minutes: Int?

    var body: some View {
        if let minutes {
            Text(text(minutes))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(minutes > 0 ? Color.orange : Color.green)
                .background((minutes > 0 ? Color.orange : Color.green).opacity(0.15), in: Capsule())
        }
    }

    private func text(_ value: Int) -> String {
        if value > 0 { return "\(value) min late" }
        if value < 0 { return "\(-value) min early" }
        return "Live"
    }
}

struct TransitActivityTimeColumn: View {
    let title: String
    let scheduled: String?
    let estimated: String?

    var body: some View {
        if scheduled != nil || estimated != nil {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(estimated ?? scheduled ?? "")
                    .font(.subheadline.weight(.semibold))
                if let estimated, let scheduled, scheduled != estimated {
                    Text(scheduled)
                        .font(.caption2)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                } else {
                    Text(estimated == nil ? "Scheduled" : "Live")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TransitActivityArrival: View {
    let state: TransitActivityAttributes.ContentState

    var body: some View {
        if state.overallArrivalDate != nil || state.overallArrivalText != nil {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Arrive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // Transitous formats this in the stop's timezone. A Date is only the fallback
                // because rendering it in the device timezone can disagree with the leg times.
                if let text = state.overallArrivalText {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                } else if let date = state.overallArrivalDate {
                    Text(date, style: .time)
                        .font(.subheadline.weight(.semibold))
                }
                Text(state.overallArrivalIsEstimate ? "Live estimate" : "Scheduled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum TransitActivityFormat {
    static func stops(_ count: Int) -> String {
        count == 1 ? "1 stop remaining" : "\(count) stops remaining"
    }
}
