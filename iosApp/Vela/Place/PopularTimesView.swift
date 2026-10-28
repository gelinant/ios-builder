import SwiftUI
import UIKit

/// One live busyness reading: the hour Google says is happening now. Only a source that really
/// carries live data may build one; the shared popular-times payload is the typical week.
struct BusyNow: Equatable {
    let dayOfWeek: Int
    let hour: Int
    let occupancy: Int
}

/// Google's weekly popular times. The day selector reads the typical histogram Google sends. A
/// live "now" reading is shown only when [live] is present; otherwise the section says that the
/// bars are typical, instead of presenting a typical hour as live.
struct PopularTimesView: View {
    let days: [BusyDay]
    var live: BusyNow? = nil

    @State private var selectedDay = BusyDay.today

    private var shownDay: BusyDay? {
        days.first { $0.dayOfWeek == selectedDay } ?? days.first
    }

    private var liveHere: BusyNow? {
        guard let live, let day = shownDay, live.dayOfWeek == day.dayOfWeek else { return nil }
        return day.hours.contains { $0.hour == live.hour } ? live : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Popular times")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(days) { day in
                        let selected = day.dayOfWeek == shownDay?.dayOfWeek
                        Button { selectedDay = day.dayOfWeek } label: {
                            Text(dayLabel(day.dayOfWeek))
                                .font(.caption.weight(selected ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .frame(minWidth: 44, minHeight: 44)
                                .foregroundStyle(selected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                                .background(
                                    day.dayOfWeek == BusyDay.today ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(fullDayLabel(day.dayOfWeek))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("popular-day-\(day.dayOfWeek)")
                    }
                }
            }
            if let day = shownDay {
                if let live = liveHere {
                    Text("Right now: \(busynessLabel(live.occupancy))")
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityIdentifier("popular-live-note")
                } else {
                    // The parsed payload is Google's typical week: no live reading reached us for
                    // this hour, so the section names what the bars are rather than faking one.
                    Text("Typical busyness for \(fullDayLabel(day.dayOfWeek)), not live")
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityIdentifier("popular-typical-note")
                }
                BusyChart(
                    hours: day.hours,
                    dayName: fullDayLabel(day.dayOfWeek),
                    liveHour: liveHere?.hour)
            }
        }
        .onAppear { selectToday() }
        .onChange(of: days) { _, _ in selectToday() }
    }

    private func selectToday() {
        selectedDay = days.contains { $0.dayOfWeek == BusyDay.today } ? BusyDay.today : (days.first?.dayOfWeek ?? BusyDay.today)
    }

    private func dayLabel(_ day: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.indices.contains(day % 7) ? symbols[day % 7] : String(day)
    }

    private func fullDayLabel(_ day: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.indices.contains(day % 7) ? symbols[day % 7] : String(day)
    }
}

private func busynessLabel(_ occupancy: Int) -> String {
    switch occupancy {
    case ..<20: return "Not busy"
    case ..<40: return "Not too busy"
    case ..<60: return "A little busy"
    case ..<85: return "Usually busy"
    default: return "Very busy"
    }
}

private struct BusyChart: View {
    let hours: [BusyHour]
    let dayName: String
    /// The hour with a real live reading, nil when only typical bars exist.
    let liveHour: Int?

    @Environment(\.sizeCategory) private var sizeCategory

    private var labelStride: Int { sizeCategory.isAccessibilityCategory ? 6 : 3 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours) { hour in
                    let live = liveHour == hour.hour
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(live ? Color.accentColor : Color(uiColor: .secondaryLabel).opacity(0.35))
                            .frame(height: max(2, CGFloat(hour.occupancy) * 0.62))
                        Text(hour.hour % labelStride == 0 ? visualLabel(hour.hour) : " ")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(width: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(live ? "\(dayName), \(spokenLabel(hour.hour)), live" : "\(dayName), \(spokenLabel(hour.hour))")
                    .accessibilityValue("\(hour.occupancy)% occupied")
                    .accessibilityIdentifier(live ? "popular-current-hour" : "popular-hour-\(hour.hour)")
                }
            }
        }
    }

    private func visualLabel(_ hour: Int) -> String {
        if AppGraph.uses24HourClock() { return String(hour) }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour < 12 ? "a" : "p")"
    }

    private func spokenLabel(_ hour: Int) -> String {
        if AppGraph.uses24HourClock() { return "\(hour):00" }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(hour < 12 ? "AM" : "PM")"
    }
}
