#if DEBUG
import Foundation

/// Debug-only banner data for NavBannerUITests. The shared route model carries lanes, road
/// numbers and shields, but a live fixture drive does not always include them, so the scenario
/// opts in with `-VelaNavBannerFixture YES` and gets a known three-lane approach. The optional
/// `-VelaShieldRegion FR|GB` picks the shield style to draw; production reads the device region.
enum NavBannerTestSupport {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var enabled: Bool {
        guard let index = arguments.firstIndex(of: "-VelaNavBannerFixture"),
              index + 1 < arguments.count else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

    static var shieldRegion: String? {
        guard let index = arguments.firstIndex(of: "-VelaShieldRegion"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1].uppercased()
    }

    static func applyIfNeeded(to model: NavModel) {
        guard enabled, model.navigating, !model.arrived else { return }
        let region = shieldRegion ?? NavShield.region
        let refs: (maneuver: String, next: String, current: String, currentLabel: String)
        switch region {
        case "FR":
            refs = ("A7", "D907", "N7", "N7")
        case "GB":
            refs = ("M25", "A1", "A1", "A1")
        default:
            refs = ("US 50", "CA 99", "I 80", "I 80 E")
        }
        model.applyBannerFixture(
            ref: refs.maneuver,
            nextRef: refs.next,
            currentLabel: refs.currentLabel,
            currentRef: refs.current,
            lanes: [
                NavBannerLane(arrows: ["left"], valid: false),
                NavBannerLane(arrows: ["straight", "left"], valid: true),
                NavBannerLane(arrows: ["straight"], valid: true),
                NavBannerLane(arrows: ["right"], valid: false),
            ])
    }
}
#endif
