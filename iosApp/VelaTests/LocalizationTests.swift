import XCTest
@testable import Vela

final class LocalizationTests: XCTestCase {
    func testRealCatalogLabelsAndEnglishFallback() {
        XCTAssertEqual(VelaL10n.text("search_placeholder", language: "fr"), "Rechercher")
        XCTAssertEqual(VelaL10n.text("place_directions", language: "fr"), "Itinéraire")
        XCTAssertEqual(VelaL10n.text("place_call", language: "fr"), "Appeler")
        XCTAssertEqual(VelaL10n.text("place_website", language: "fr"), "Site web")
        XCTAssertEqual(VelaL10n.text("settings_title", language: "de"), "Einstellungen")
        XCTAssertEqual(VelaL10n.text("settings_title", language: "kmr"), "Sazkarî")
        // Arabic now has its own title; the English fallback is asserted below on a locale that
        // genuinely lacks the key.
        XCTAssertEqual(VelaL10n.text("settings_title", language: "ar"), "الإعدادات")
        XCTAssertEqual(VelaL10n.text("settings_title", language: "en-GB"), "Settings")
        XCTAssertEqual(VelaL10n.text("missing_test_key", language: "fr"), "missing_test_key")
    }

    func testSwiftIntUsesLongIntegerSpecifiers() {
        XCTAssertEqual(VelaL10n.text("place_photo_number", language: "en", Int(7)), "Photo 7")
        // Foundation applies English grouping; the full 64-bit value must survive.
        XCTAssertEqual(
            VelaL10n.text("place_photo_number", language: "en", Int(4_294_967_296)),
            "Photo 4,294,967,296")
        XCTAssertEqual(VelaL10n.text("topcard_more_stops", language: "en", Int(1)), "+1 more stop")
        XCTAssertEqual(VelaL10n.text("topcard_more_stops", language: "en", Int(2)), "+2 more stops")
    }

    func testAreaPickCellsUsesCountAsSecondArgument() {
        XCTAssertEqual(
            VelaL10n.text("area_pick_cells", language: "en", "12 MB", Int(1)),
            "Get offline directions and places for just this area: about 12 MB (1 part of the region)")
        XCTAssertEqual(
            VelaL10n.text("area_pick_cells", language: "en", "12 MB", Int(3)),
            "Get offline directions and places for just this area: about 12 MB (3 parts of the region)")
    }

    func testPreferenceAndCatalogLanguageMapping() {
        XCTAssertEqual(DevicePlatformLocale.preferenceTag("pt-PT"), "pt")
        XCTAssertEqual(DevicePlatformLocale.preferenceTag("zh-Hant-TW"), "zh-TW")
        XCTAssertEqual(DevicePlatformLocale.preferenceTag("iw"), "he")
        XCTAssertEqual(VelaL10n.catalogLanguage(for: "fr-FR"), "fr")
        XCTAssertEqual(VelaL10n.catalogLanguage(for: "pt"), "pt-PT")
        XCTAssertEqual(VelaL10n.catalogLanguage(for: "zh-TW"), "zh-Hant")
        XCTAssertEqual(VelaL10n.catalogLanguage(for: "unsupported"), "en")
        XCTAssertEqual(VelaL10n.languages.count, 24)
    }
}
