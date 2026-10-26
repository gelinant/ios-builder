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
                                .padding(.vertical, 5)
                                .foregroundStyle(selected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                                .background(
                                    day.dayOfWeek == BusyDay.today ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("popular-day-\(day.dayOfWeek)")
                    }
                }
            }
            if let day = shownDay {
                BusyChart(hours: day.hours, highlightCurrentHour: day.dayOfWeek == BusyDay.today)
                    .frame(height: 86)
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
}

private struct BusyChart: View {
    let hours: [BusyHour]
    let highlightCurrentHour: Bool

    private let currentHour = Calendar.current.component(.hour, from: Date())

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(hours) { hour in
                let current = highlightCurrentHour && hour.hour == currentHour
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(current ? Color.accentColor : Color(uiColor: .secondaryLabel).opacity(0.35))
                        .frame(height: max(2, CGFloat(hour.occupancy) * 0.62))
                    Text(hour.hour % 3 == 0 ? label(hour.hour) : " ")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(current ? "popular-current-hour" : "popular-hour-\(hour.hour)")
            }
        }
    }

    private func label(_ hour: Int) -> String {
        if AppGraph.uses24HourClock() { return String(hour) }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour < 12 ? "a" : "p")"
    }
}
