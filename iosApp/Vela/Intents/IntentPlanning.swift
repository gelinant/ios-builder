import Foundation

struct VelaSavedReference: Equatable, Hashable, Sendable {
    let placeID: String
    let listID: String?
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double

    var deepLink: VelaDeepLink { .place(placeID, listID: listID) }
    var entityID: String { deepLink.url.absoluteString }
}

struct VelaIntentSnapshot: Equatable, Sendable {
    let home: VelaSavedReference?
    let work: VelaSavedReference?
    let hasParking: Bool
    let savedPlaces: [VelaSavedReference]

    init(home: VelaSavedReference? = nil, work: VelaSavedReference? = nil,
         hasParking: Bool = false, savedPlaces: [VelaSavedReference] = []) {
        self.home = home
        self.work = work
        self.hasParking = hasParking
        self.savedPlaces = savedPlaces
    }
}

enum VelaIntentError: Error, Equatable, LocalizedError {
    case emptyQuery
    case missingShortcut(VelaShortcutKind)
    case missingParking
    case missingPlace
    case cannotOpen

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter a place or address to search for."
        case .missingShortcut(let shortcut):
            return "\(shortcut.displayName) is not set. Choose a \(shortcut.displayName) place in Saved."
        case .missingParking:
            return "No parked car is saved. Use Vela's parking button after parking."
        case .missingPlace:
            return "This saved place no longer exists. Choose another place in Saved."
        case .cannotOpen:
            return "Vela could not open this link."
        }
    }
}

/// Validation is independent of AppIntents and UIKit so the exact Siri and shortcut decisions can
/// be exercised by hosted unit tests. Missing Home, Work and parking also have a Saved setup URL.
enum VelaIntentPlanner {
    static func search(_ query: String) -> Result<VelaDeepLink, VelaIntentError> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyQuery) }
        return .success(.search(query: trimmed))
    }

    static func navigate(_ shortcut: VelaShortcutKind,
                         snapshot: VelaIntentSnapshot) -> Result<VelaDeepLink, VelaIntentError> {
        let reference = shortcut == .home ? snapshot.home : snapshot.work
        guard reference != nil else { return .failure(.missingShortcut(shortcut)) }
        return .success(.navigate(shortcut))
    }

    static func parking(snapshot: VelaIntentSnapshot) -> Result<VelaDeepLink, VelaIntentError> {
        guard snapshot.hasParking else { return .failure(.missingParking) }
        return .success(.parking)
    }
}
