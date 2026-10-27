import SwiftUI
import UIKit

/// Google's weekly popular times. Today is selected and marked, and its current-hour bar uses the
/// accent color. The other days are selectable without another request.
struct PopularTimesView: View {
    let days: [BusyDay]

    @State private var selectedDay = BusyDay.today

    private var shownDay: BusyDay? {
        days.first { $0.dayOfWeek == selectedDay } ?? days.first
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
                BusyChart(
                    hours: day.hours,
                    dayName: fullDayLabel(day.dayOfWeek),
                    highlightCurrentHour: day.dayOfWeek == BusyDay.today)
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

private struct BusyChart: View {
    let hours: [BusyHour]
    let dayName: String
    let highlightCurrentHour: Bool

    @Environment(\.sizeCategory) private var sizeCategory
    private let currentHour = Calendar.current.component(.hour, from: Date())

    private var labelStride: Int { sizeCategory.isAccessibilityCategory ? 6 : 3 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours) { hour in
                    let current = highlightCurrentHour && hour.hour == currentHour
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(current ? Color.accentColor : Color(uiColor: .secondaryLabel).opacity(0.35))
                            .frame(height: max(2, CGFloat(hour.occupancy) * 0.62))
                        Text(hour.hour % labelStride == 0 ? visualLabel(hour.hour) : " ")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(width: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: hour.hour, current: current))
                    .accessibilityValue("\(hour.occupancy)% occupied")
                    .accessibilityIdentifier(current ? "popular-current-hour" : "popular-hour-\(hour.hour)")
                }
            }
        }
    }

    private func accessibilityLabel(for hour: Int, current: Bool) -> String {
        let time = "\(dayName), \(spokenLabel(hour))"
        return current ? "\(time), current hour" : time
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
