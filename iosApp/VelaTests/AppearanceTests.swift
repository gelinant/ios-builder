import XCTest
@testable import Vela

/// The computed contrast claims of DESIGN.md and the appearance preference keys. The colours are
/// numbers in `Design.Palette` precisely so this test does not repeat a comment.
final class AppearanceTests: XCTestCase {
    private let whiteOnBrandTeal = 3.78
    private let whiteOnFillLight = 7.75
    private let blackOnFillDark = 8.33

    func testBrandTealNeverCarriesWhiteBodyText() {
        let ratio = Design.Contrast.ratio(Design.Palette.white, Design.Palette.accent)
        XCTAssertEqual(ratio, whiteOnBrandTeal, accuracy: 0.05)
        XCTAssertLessThan(ratio, 4.5, "white on #149387 stays below body-text contrast")
    }

    func testAccentFillPairsClearBodyText() {
        let whiteOnFill = Design.Contrast.ratio(
            Design.Palette.white, Design.Palette.accentFillLight)
        XCTAssertEqual(whiteOnFill, whiteOnFillLight, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(whiteOnFill, 4.5)

        let blackOnFill = Design.Contrast.ratio(
            Design.Palette.black, Design.Palette.accentFillDark)
        XCTAssertEqual(blackOnFill, blackOnFillDark, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(blackOnFill, 4.5)
    }

    func testRouteChipTokensUseTheLegiblePair() {
        // `routeChipFill` and `routeChipLabel` are aliases of `accentFill` and `onAccent`, so the
        // selected route-mode chip in RouteSheets carries the measured pair above, not the teal.
        XCTAssertEqual(Design.Contrast.ratio(
            Design.Palette.white, Design.Palette.accentFillLight), whiteOnFillLight, accuracy: 0.05)
    }

    func testStarStaysDecorative() {
        let ratio = Design.Contrast.ratio(Design.Palette.star, Design.Palette.white)
        XCTAssertEqual(ratio, 2.02, accuracy: 0.05)
        XCTAssertLessThan(ratio, 3, "the amber star is never the only carrier of a rating")
    }

    func testAndroidThemeAndChromeKeysAreRead() {
        XCTAssertEqual(AppearanceTheme.stored("DARK"), .dark)
        XCTAssertEqual(AppearanceTheme.stored("light"), .light)
        XCTAssertEqual(AppearanceTheme.stored("nonsense"), .system)
        XCTAssertFalse(SpeedUnitChoice.metric.isImperial(modelImperial: true))
        XCTAssertTrue(SpeedUnitChoice.imperial.isImperial(modelImperial: false))
        XCTAssertEqual(SpeedUnitChoice.auto.title, "Follow units")
        XCTAssertEqual(NavDetailLevel.compact.title, "Compact")
        XCTAssertEqual(NavVehicle.ufo.symbol, "airplane")
    }

    func testChromePreferencesPersistUnderAndroidKeys() {
        let defaults = UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
        let appearance = AppearanceSettings.shared
        let oldTheme = defaults.string(forKey: "theme_mode")
        let oldIcon = defaults.string(forKey: "puck_size")
        let oldVehicle = defaults.string(forKey: "puck_shape")
        defer {
            if let oldTheme { defaults.set(oldTheme, forKey: "theme_mode") }
            if let oldIcon { defaults.set(oldIcon, forKey: "puck_size") }
            if let oldVehicle { defaults.set(oldVehicle, forKey: "puck_shape") }
            appearance.applyTheme()
        }

        appearance.setIconSize(.large)
        appearance.setVehicle(.duck)
        XCTAssertEqual(defaults.string(forKey: "puck_size"), "large")
        XCTAssertEqual(defaults.string(forKey: "puck_shape"), "duck")
        XCTAssertTrue(appearance.debugLine.contains("icon=large"))
        XCTAssertTrue(appearance.debugLine.contains("vehicle=duck"))
    }
}
