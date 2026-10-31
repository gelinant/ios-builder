#if DEBUG
import Foundation
import VelaCore

/// A recorded Transitous `/api/v1/plan` reply, parsed by the production parser. It only feeds the
/// Debug scenarios (`-VelaTransitFixture`, `-VelaTransitTransfer`), so no fixture ever reaches a
/// real trip search.
enum TransitPlanFixture {
    /// The Paris reply kept in `Transit/Fixtures/paris-transfer-plan.json`: a two-ride trip with a
    /// transfer between Metro 1 and RER A (walk, Metro 1, transfer walk, RER A, final walk).
    static func parisTransfer() -> TransitItinerary? { load("paris-transfer-plan") }

    static func load(_ name: String) -> TransitItinerary? {
        guard let url = bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return Transitous.shared.parsePlanForFixture(
            json: json,
            originLat: 48.8566, originLng: 2.3522,
            destinationLat: 48.8974, destinationLng: 2.2385).first
    }

    /// The app bundle that carries the JSON: the hosted test bundle asks for the app's class bundle.
    private static var bundle: Bundle {
        Bundle(for: TransitModel.self)
    }
}
#endif
