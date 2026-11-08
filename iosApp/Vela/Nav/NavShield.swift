import SwiftUI

/// A road number pulled out of a maneuver's `ref`, ready to draw as a sign. The shared route
/// model carries the ref string but no country, so the shield family follows the device region:
/// the United States and Canada use the shared interstate/US/state shapes, France the autoroute,
/// nationale and departementale colours, and the United Kingdom motorway and A-road styles.
struct NavShieldDescriptor: Equatable {
    enum Family: Equatable {
        case interstate, usRoute, state, motorway, aRoad, autoroute, nationale, departementale, generic
    }

    let family: Family
    let number: String
    let direction: String?
    let raw: String
}

enum NavShield {
    /// The device's region, or the scenario's debug override. A route that crosses a border keeps
    /// the device style: the shared maneuver has no country field to switch on mid-drive.
    static var region: String {
        #if DEBUG
        if let regionOverride = NavBannerTestSupport.shieldRegion, !regionOverride.isEmpty {
            return regionOverride
        }
        #endif
        return Locale.current.region?.identifier.uppercased() ?? "US"
    }

    static func parse(_ label: String, region: String = NavShield.region) -> NavShieldDescriptor {
        let raw = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = raw.uppercased()
        let direction = trailingDirection(upper)
        let core = direction == nil ? upper : String(upper.dropLast(2)).trimmingCharacters(in: .whitespaces)
        let number = core.firstMatch(of: /\d+[A-Z]?/).map { String($0.output) } ?? ""
        let prefix = String(core.prefix { $0.isLetter })
        switch region {
        case "FR":
            if prefix == "A" { return .init(family: .autoroute, number: number, direction: direction, raw: raw) }
            if prefix == "N" { return .init(family: .nationale, number: number, direction: direction, raw: raw) }
            if prefix == "D" { return .init(family: .departementale, number: number, direction: direction, raw: raw) }
        case "GB", "UK":
            if prefix == "M" { return .init(family: .motorway, number: number, direction: direction, raw: raw) }
            if prefix == "A" {
                let motorway = core.contains("(M)")
                return .init(family: motorway ? .motorway : .aRoad, number: number, direction: direction, raw: raw)
            }
        default:
            if prefix == "I" { return .init(family: .interstate, number: number, direction: direction, raw: raw) }
            if prefix == "US" || prefix == "USHWY" {
                return .init(family: .usRoute, number: number, direction: direction, raw: raw)
            }
            if statePrefixes.contains(prefix) || ["SR", "HWY"].contains(prefix) {
                return .init(family: .state, number: number, direction: direction, raw: raw)
            }
        }
        return .init(family: .generic, number: number, direction: direction, raw: raw)
    }

    /// "Exit 71" in an instruction becomes its own green tab, as on Android. Nil when the sign
    /// text names no exit, so nothing is invented.
    static func exitLabel(in instruction: String) -> String? {
        guard let match = instruction.firstMatch(of: /(?i)\bexit\s+([\w-]+)/) else { return nil }
        return "Exit \(match.1)"
    }

    private static func trailingDirection(_ text: String) -> String? {
        guard let match = text.firstMatch(of: /\s([NSEW])$/), text.count >= 3 else { return nil }
        return String(match.1)
    }

    private static let statePrefixes: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN",
        "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
        "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT",
        "VT", "VA", "WA", "WV", "WI", "WY", "ON", "QC", "BC", "AB", "MB", "SK", "NS", "NB", "NL",
        "PE", "NT", "YT", "NU",
    ]
}

/// A drawable route badge. The sign keeps real road-sign colours in light and dark mode; only the
/// generic chip follows the card's ink, so it never disappears on the green banner.
struct NavShieldView: View {
    let label: String
    var region: String = NavShield.region
    var onDark = true
    var identifier: String = "nav-shield"

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var k: CGFloat { min(max(scale, 1), 1.5) }
    private var ink: Color { onDark ? .white : .primary }

    var body: some View {
        let ref = NavShield.parse(label, region: region)
        HStack(spacing: 3) {
            badge(ref)
            if let direction = ref.direction {
                Text(direction)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(onDark ? Color.white.opacity(0.75) : Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ref.raw)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func badge(_ ref: NavShieldDescriptor) -> some View {
        switch ref.family {
        case .interstate:
            ZStack {
                InterstateShape()
                    .fill(Color(red: 0.0, green: 0.247, blue: 0.529))
                InterstateShape()
                    .fill(Color(red: 0.69, green: 0.118, blue: 0.18))
                    .mask(alignment: .top) {
                        Rectangle().frame(height: 9 * k)
                    }
                number(ref, color: .white, padTop: 4 * k)
            }
            .frame(width: 36 * k, height: 32 * k)
        case .usRoute:
            ZStack {
                USRouteShape().fill(.white)
                USRouteShape().stroke(.black, lineWidth: 1.5 * k)
                number(ref, color: .black)
            }
            .frame(width: 32 * k, height: 32 * k)
        case .state:
            ZStack {
                RoundedRectangle(cornerRadius: 6 * k)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 6 * k).stroke(.black, lineWidth: 1.5 * k))
                number(ref, color: .black)
            }
            .frame(width: 30 * k, height: 28 * k)
        case .motorway:
            ZStack {
                RoundedRectangle(cornerRadius: 5 * k).fill(Color(red: 0.0, green: 0.30, blue: 0.62))
                number(ref, color: .white)
            }
            .frame(width: 34 * k, height: 26 * k)
        case .aRoad:
            ZStack {
                RoundedRectangle(cornerRadius: 5 * k)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 5 * k).stroke(.black, lineWidth: 1.5 * k))
                number(ref, color: .black)
            }
            .frame(width: 34 * k, height: 26 * k)
        case .autoroute:
            ZStack {
                RoundedRectangle(cornerRadius: 3 * k).fill(Color(red: 0.0, green: 0.32, blue: 0.65))
                number(ref, color: .white)
            }
            .frame(width: 32 * k, height: 26 * k)
        case .nationale:
            ZStack {
                RoundedRectangle(cornerRadius: 3 * k).fill(Color(red: 0.78, green: 0.11, blue: 0.14))
                number(ref, color: .white)
            }
            .frame(width: 32 * k, height: 26 * k)
        case .departementale:
            ZStack {
                RoundedRectangle(cornerRadius: 3 * k).fill(Color(red: 0.95, green: 0.80, blue: 0.0))
                number(ref, color: .black)
            }
            .frame(width: 32 * k, height: 26 * k)
        case .generic:
            Text(ref.raw)
                .font(.system(size: 11 * k, weight: .bold))
                .foregroundStyle(ink)
                .padding(.horizontal, 6 * k)
                .padding(.vertical, 3 * k)
                .overlay(RoundedRectangle(cornerRadius: 5 * k).stroke(ink, lineWidth: 1.2 * k))
        }
    }

    private func number(_ ref: NavShieldDescriptor, color: Color, padTop: CGFloat = 0) -> some View {
        Text(ref.number)
            .font(.system(size: (ref.number.count >= 3 ? 11 : 13) * k, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, padTop)
    }
}

/// The US interstate silhouette: flat shoulders curving to a soft point.
private struct InterstateShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        let cr = w * 0.16
        path.move(to: CGPoint(x: cr, y: 0))
        path.addLine(to: CGPoint(x: w - cr, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: cr), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h * 0.42))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w, y: h * 0.66),
            control2: CGPoint(x: w * 0.72, y: h * 0.86))
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.42),
            control1: CGPoint(x: w * 0.28, y: h * 0.86),
            control2: CGPoint(x: 0, y: h * 0.66))
        path.addLine(to: CGPoint(x: 0, y: cr))
        path.addQuadCurve(to: CGPoint(x: cr, y: 0), control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}

/// The US route shield outline.
private struct USRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.1, y: 0))
        path.addLine(to: CGPoint(x: w * 0.9, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.16), control: CGPoint(x: w, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.55))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h), control: CGPoint(x: w * 0.78, y: h * 0.86))
        path.addQuadCurve(to: CGPoint(x: w * 0.08, y: h * 0.55), control: CGPoint(x: w * 0.22, y: h * 0.86))
        path.addLine(to: CGPoint(x: 0, y: h * 0.16))
        path.addQuadCurve(to: CGPoint(x: w * 0.1, y: 0), control: CGPoint(x: 0, y: h * 0.05))
        path.closeSubpath()
        return path
    }
}
