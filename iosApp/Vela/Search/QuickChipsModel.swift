import Foundation
import SwiftUI
import VelaCore

/// One quick-search chip: Android's stable English query, its label key and the SF Symbol the
/// iOS row draws. The key never follows the locale, so a saved order survives a language change.
struct QuickCategory: Identifiable, Equatable {
    let key: String
    let query: String
    let labelKey: String
    let icon: String

    var id: String { QuickCategory.slug(key) }
    var label: String { VelaL10n.text(labelKey) }

    static func slug(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Android's catalog (`QuickCategories.catalog`), same order and same 16 chips. Bars is left
    /// out while "Hide adult categories" is on, because that filter drops every bar result.
    static func catalog(fuelQuery: String, hideBars: Bool) -> [QuickCategory] {
        let chips = [
            QuickCategory(key: "Restaurants", query: "Restaurants", labelKey: "cat_restaurants", icon: "fork.knife"),
            QuickCategory(key: "Coffee", query: "Coffee", labelKey: "cat_coffee", icon: "cup.and.saucer.fill"),
            QuickCategory(key: "Gas station", query: fuelQuery, labelKey: "cat_gas", icon: "fuelpump.fill"),
            QuickCategory(key: "Groceries", query: "Groceries", labelKey: "cat_groceries", icon: "cart.fill"),
            QuickCategory(key: "Things to do", query: "Things to do", labelKey: "cat_things_to_do", icon: "ticket.fill"),
            QuickCategory(key: "Hotels", query: "Hotels", labelKey: "cat_hotels", icon: "bed.double.fill"),
            QuickCategory(key: "Bars", query: "Bars", labelKey: "cat_bars", icon: "wineglass.fill"),
            QuickCategory(key: "EV charging station", query: "EV charging station", labelKey: "cat_ev", icon: "bolt.car.fill"),
            QuickCategory(key: "Parking", query: "Parking", labelKey: "cat_parking", icon: "parkingsign.circle.fill"),
            QuickCategory(key: "Pharmacy", query: "Pharmacy", labelKey: "cat_pharmacy", icon: "cross.case.fill"),
            QuickCategory(key: "ATMs", query: "ATMs", labelKey: "cat_atms", icon: "banknote.fill"),
            QuickCategory(key: "Parks", query: "Parks", labelKey: "cat_parks", icon: "tree.fill"),
            QuickCategory(key: "Hospitals", query: "Hospitals", labelKey: "cat_hospitals", icon: "cross.fill"),
            QuickCategory(key: "Banks", query: "Banks", labelKey: "cat_banks", icon: "building.columns.fill"),
            QuickCategory(key: "Post office", query: "Post office", labelKey: "cat_post_offices", icon: "envelope.fill"),
            QuickCategory(key: "Campgrounds", query: "Campgrounds", labelKey: "cat_campgrounds", icon: "tent.fill"),
        ]
        return hideBars ? chips.filter { $0.key != "Bars" } : chips
    }

    /// The region's word for the fuel chip, as Android's `CategoryQuery.fuel`: "Gas station"
    /// searches the utility in the UK and Ireland, so those regions ask for petrol.
    static func fuelQuery(region: String? = Locale.current.region?.identifier) -> String {
        let petrol = ["GB", "IE", "AU", "NZ", "IN", "ZA", "SG", "MY", "PK", "KE", "NG"]
        return petrol.contains(region?.uppercased() ?? "") ? "Petrol station" : "Gas station"
    }
}

/// SwiftUI's side of the Kotlin `QuickChipsStore`: the saved order and hidden set in
/// `vela_settings` (Android's keys), shared by the map row, its More menu and the editor.
/// Main thread only, like the other models.
final class QuickChipsModel: ObservableObject {
    static let shared = QuickChipsModel()

    @Published private(set) var order: [String] = []
    @Published private(set) var hidden: Set<String> = []
    private var started = false

    private var store: QuickChipsStore? { AppGraph.session.quickChips }
    private var hideBars: Bool { AppGraph.session.settings?.state.value.hideAdult ?? false }

    /// Every chip in the saved order, switched-off ones included (the More menu and the editor).
    var arranged: [QuickCategory] {
        let catalog = QuickCategory.catalog(fuelQuery: QuickCategory.fuelQuery(), hideBars: hideBars)
        let byKey = Dictionary(uniqueKeysWithValues: catalog.map { ($0.key, $0) })
        let defaultKeys = catalog.map { $0.key }
        let keys: [String]
        if let store {
            keys = QuickChips.shared.arrange(defaults: defaultKeys, order: order)
        } else {
            keys = defaultKeys
        }
        return keys.compactMap { byKey[$0] }
    }

    /// What the row shows: the arranged list less the chips switched off.
    var visible: [QuickCategory] {
        arranged.filter { !hidden.contains($0.key) }
    }

    var customized: Bool { !order.isEmpty || !hidden.isEmpty }

    func start() {
        guard !started else { return }
        started = true
        refresh()
    }

    func toggle(_ key: String, shown: Bool) {
        guard let store else { return }
        store.setShown(key: key, shown: shown)
        refresh()
    }

    /// Moves a chip one row up (negative) or down (positive), held at both ends.
    func move(_ key: String, delta: Int) {
        guard let store else { return }
        store.move(key: key, delta: Int32(delta))
        refresh()
    }

    /// Drag-to-reorder from the editor's List. [destination] is the pre-removal insertion index
    /// SwiftUI reports, so a downward move is one place lower.
    func move(from source: Int, to destination: Int) {
        var keys = arranged.map { $0.key }
        guard keys.indices.contains(source) else { return }
        let key = keys.remove(at: source)
        let target = destination > source ? destination - 1 : destination
        keys.insert(key, at: min(max(target, 0), keys.count))
        store?.setOrder(keys: keys)
        refresh()
    }

    func reset() {
        store?.reset()
        refresh()
    }

    private func refresh() {
        if let state = store?.state.value {
            order = state.order
            hidden = Set(state.hidden)
        } else {
            order = []
            hidden = []
        }
    }
}
