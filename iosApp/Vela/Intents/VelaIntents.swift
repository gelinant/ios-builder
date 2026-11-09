import AppIntents
import Foundation
import UIKit

struct NavigateHomeIntent: AppIntent {
    static var title: LocalizedStringResource { "Navigate Home" }
    static var description: IntentDescription { IntentDescription("Opens directions to your saved Home in Vela.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch VelaIntentPlanner.navigate(.home, snapshot: VelaSavedContent.current) {
        case .success(let link):
            try await openVelaLink(link)
            return .result(dialog: "Opening Home in Vela.")
        case .failure(let error):
            try await openVelaLink(.saved)
            return .result(
                dialog: IntentDialog(stringLiteral: error.errorDescription ?? "Set Home in Saved first."))
        }
    }
}

struct NavigateWorkIntent: AppIntent {
    static var title: LocalizedStringResource { "Navigate to Work" }
    static var description: IntentDescription { IntentDescription("Opens directions to your saved Work in Vela.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch VelaIntentPlanner.navigate(.work, snapshot: VelaSavedContent.current) {
        case .success(let link):
            try await openVelaLink(link)
            return .result(dialog: "Opening Work in Vela.")
        case .failure(let error):
            try await openVelaLink(.saved)
            return .result(
                dialog: IntentDialog(stringLiteral: error.errorDescription ?? "Set Work in Saved first."))
        }
    }
}

struct WhereIsMyCarIntent: AppIntent {
    static var title: LocalizedStringResource { "Where Is My Car?" }
    static var description: IntentDescription { IntentDescription("Opens your saved parking place in Vela.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch VelaIntentPlanner.parking(snapshot: VelaSavedContent.current) {
        case .success(let link):
            try await openVelaLink(link)
            return .result(dialog: "Opening your parked car in Vela.")
        case .failure(let error):
            try await openVelaLink(.saved)
            return .result(
                dialog: IntentDialog(stringLiteral: error.errorDescription ?? "No parked car is saved."))
        }
    }
}

struct SearchVelaIntent: AppIntent {
    static var title: LocalizedStringResource { "Search Vela" }
    static var description: IntentDescription { IntentDescription("Opens Vela search results for a place or address.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Search query", requestValueDialog: "What do you want to search for?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Vela for \(\.$query)")
    }

    init() {}
    init(query: String) { self.query = query }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch VelaIntentPlanner.search(query) {
        case .success(let link):
            try await openVelaLink(link)
            return .result(dialog: "Opening search in Vela.")
        case .failure(let error):
            throw error
        }
    }
}

struct NavigateToPlaceIntent: AppIntent {
    static var title: LocalizedStringResource { "Navigate to a Saved Place" }
    static var description: IntentDescription { IntentDescription("Opens directions to a Vela saved place or list entry.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Saved place", requestValueDialog: "Which saved place?")
    var place: SavedPlaceAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$place) with Vela")
    }

    init() {}
    init(place: SavedPlaceAppEntity) { self.place = place }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let link = VelaDeepLink.place(place.placeID, listID: place.listID, directions: true)
        try await openVelaLink(link)
        return .result(dialog: "Opening the saved place in Vela.")
    }
}

struct SavedPlaceAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Saved Place" }
    static var defaultQuery: SavedPlaceEntityQuery { SavedPlaceEntityQuery() }

    let id: String
    let placeID: String
    let listID: String?
    let name: String
    let address: String?

    init(_ reference: VelaSavedReference) {
        id = reference.entityID
        placeID = reference.placeID
        listID = reference.listID
        name = reference.name
        address = reference.address
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(address ?? "")")
    }
}

/// OpenURLIntent starts at iOS 18. The iOS 17 path opens the same internal URL through UIKit.
@MainActor
private func openVelaLink(_ link: VelaDeepLink) async throws {
    let opened = await UIApplication.shared.open(link.url)
    if !opened { throw VelaIntentError.cannotOpen }
}

struct SavedPlaceEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SavedPlaceAppEntity] {
        VelaSavedContent.entities(identifiers: identifiers)
    }

    @MainActor
    func suggestedEntities() async throws -> [SavedPlaceAppEntity] {
        VelaSavedContent.entities()
    }
}
