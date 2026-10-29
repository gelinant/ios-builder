import SwiftUI
import VelaCore

/// The fuel line under the action pills, as Android places the pump row: price per litre first
/// (bold), then the matched forecourt's brand and report age, then the cheaper forecourt nearby
/// when the Fuel Finder file supports one. Google's US price has no report time and no brand.
struct PlaceFuelSection: View {
    let card: PlaceCard

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "fuelpump.fill")
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    priceLine(now: context.date)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("place-fuel")
                if let nearby = card.fuelNearby {
                    Text(nearbyLine(nearby))
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("place-fuel-nearby")
                }
            }
        }
    }

    private func priceLine(now: Date) -> Text {
        let price = Text(card.fuelPrice ?? "").fontWeight(.semibold)
        var detail = ""
        if let brand = card.fuelBrand, !brand.isEmpty {
            detail += " · \(brand)"
        }
        if let at = card.fuelPriceAt {
            let days = Int(FuelGb.shared.daysAgo(
                atSec: at, nowSec: Int64(now.timeIntervalSince1970),
                zoneId: TimeZone.current.identifier))
            detail += " · \(ageText(days))"
        }
        return price + Text(detail).foregroundColor(Color(uiColor: .secondaryLabel))
    }

    private func ageText(_ days: Int) -> String {
        switch days {
        case 0: return "Updated today"
        case 1: return "Updated yesterday"
        default: return "Updated \(days) days ago"
        }
    }

    private func nearbyLine(_ nearby: FuelNearbyRow) -> String {
        let grade = card.fuelGrade ?? "E10"
        let price = FuelGb.shared.formatPence(hundredths: Int32(nearby.pence))
        let brand = nearby.brand.map { " at \($0)" } ?? ""
        return "Cheaper nearby: \(price)p/\(grade)\(brand), \(distance(nearby.meters))"
    }

    private func distance(_ meters: Double) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", meters / 1_000)
    }
}

/// The countdown under the status line: "Closes in 25 min" below an hour, "Closed today" when the
/// weekly hours say so. Permanent and temporary closures stay on the sheet's existing red status,
/// so this never repeats them.
struct PlaceClosingLine: View {
    let card: PlaceCard

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = ClosingTime.shared.status(
                statusText: card.statusText,
                openNow: Int32(card.openNow.map { $0 ? 1 : 0 } ?? -1),
                hours: card.hours,
                permanentlyClosed: card.permanentlyClosed,
                temporarilyClosed: card.temporarilyClosed,
                nowEpochSec: Int64(context.date.timeIntervalSince1970),
                zoneId: TimeZone.current.identifier)
            if status.closingSoon {
                Text(VelaL10n.text("place_closes_in_min", String(describing: (status.closesInMinutes))))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(uiColor: .systemOrange))
                    .accessibilityIdentifier("place-closing")
            } else if status.closedToday && !saysClosedToday {
                Text(VelaL10n.text("place_closed_today"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .accessibilityIdentifier("place-closing")
            }
        }
    }

    private var saysClosedToday: Bool {
        card.statusText?.lowercased().contains("closed today") ?? false
    }
}
