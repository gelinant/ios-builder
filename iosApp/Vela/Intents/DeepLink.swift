import CoreSpotlight
import Foundation

enum VelaShortcutKind: String, Equatable, Sendable {
    case home
    case work

    var displayName: String { rawValue.capitalized }
}

enum VelaDeepLink: Equatable, Sendable {
    case search(query: String)
    case savedPlace(placeID: String, listID: String?, directions: Bool)
    case saved
    case parking
    case navigate(VelaShortcutKind)

    static func place(_ placeID: String, listID: String? = nil, directions: Bool = false) -> VelaDeepLink {
        .savedPlace(placeID: placeID, listID: listID, directions: directions)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "vela"
        switch self {
        case .search(let query):
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .savedPlace(let placeID, let listID, let directions):
            components.host = "place"
            components.percentEncodedPath = "/" + Self.pathSegment(placeID)
            var query: [URLQueryItem] = []
            if let listID { query.append(URLQueryItem(name: "list", value: listID)) }
            if directions { query.append(URLQueryItem(name: "directions", value: "1")) }
            components.queryItems = query.isEmpty ? nil : query
        case .saved:
            components.host = "saved"
        case .parking:
            components.host = "parking"
        case .navigate(let shortcut):
            components.host = "navigate"
            components.path = "/" + shortcut.rawValue
        }
        return components.url!
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?%#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum VelaDeepLinkError: Error, Equatable, Sendable {
    case invalidURL
    case unsupportedScheme
    case unknownRoute
    case invalidQuery
    case missingPlaceID
    case invalidShortcut
}

/// The only parser for Vela's internal URLs. It accepts no network URLs and keeps query handling
/// deterministic so App Intents, Spotlight and tests all enter the same MapScreen actions.
enum VelaDeepLinkRouter {
    static func parse(_ text: String) -> Result<VelaDeepLink, VelaDeepLinkError> {
        guard let url = URL(string: text) else { return .failure(.invalidURL) }
        return parse(url)
    }

    static func parse(_ url: URL) -> Result<VelaDeepLink, VelaDeepLinkError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidURL)
        }
        guard components.scheme?.lowercased() == "vela" else { return .failure(.unsupportedScheme) }
        guard components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil, let host = components.host?.lowercased() else {
            return .failure(.invalidURL)
        }
        let query = components.queryItems ?? []
        switch host {
        case "search":
            guard components.path.isEmpty || components.path == "/", query.count == 1,
                  query[0].name == "q", let text = query[0].value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return .failure(.invalidQuery) }
            return .success(.search(query: text))
        case "place":
            guard let placeID = pathComponents(components).first, pathComponents(components).count == 1,
                  !placeID.isEmpty else { return .failure(.missingPlaceID) }
            guard query.allSatisfy({ $0.name == "list" || $0.name == "directions" }),
                  Set(query.map(\.name)).count == query.count else { return .failure(.invalidQuery) }
            var listID: String?
            if let item = query.first(where: { $0.name == "list" }) {
                guard let value = item.value, !value.isEmpty else { return .failure(.invalidQuery) }
                listID = value
            }
            if let item = query.first(where: { $0.name == "directions" }) {
                guard item.value == "1" else { return .failure(.invalidQuery) }
            }
            let directions = query.contains { $0.name == "directions" }
            return .success(.place(placeID, listID: listID, directions: directions))
        case "saved":
            guard pathComponents(components).isEmpty, query.isEmpty else { return .failure(.unknownRoute) }
            return .success(.saved)
        case "parking":
            guard pathComponents(components).isEmpty, query.isEmpty else { return .failure(.unknownRoute) }
            return .success(.parking)
        case "navigate":
            let parts = pathComponents(components)
            guard parts.count == 1, query.isEmpty else { return .failure(.invalidShortcut) }
            guard let shortcut = VelaShortcutKind(rawValue: parts[0].lowercased()) else {
                return .failure(.invalidShortcut)
            }
            return .success(.navigate(shortcut))
        default:
            return .failure(.unknownRoute)
        }
    }

    private static func pathComponents(_ components: URLComponents) -> [String] {
        components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).compactMap {
            String($0).removingPercentEncoding
        }
    }
}

struct VelaDeepLinkRequest: Equatable {
    let id: Int
    let outcome: Result<VelaDeepLink, VelaDeepLinkError>
}

/// Scene-facing queue. A sequence number delivers the same URL twice, while consume prevents a
/// SwiftUI onAppear replay from performing an already handled request.
final class VelaDeepLinkCenter: ObservableObject {
    @Published private(set) var pending: VelaDeepLinkRequest?
    private var sequence = 0

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-VelaOpenURL"), index + 1 < arguments.count {
            let text = arguments[index + 1]
            if let url = URL(string: text) {
                open(url)
            } else {
                publish(.failure(.invalidURL))
            }
        }
        #endif
    }

    func open(_ url: URL) {
        publish(VelaDeepLinkRouter.parse(url))
    }

    func openSpotlightActivity(_ activity: NSUserActivity) {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let url = URL(string: identifier) else {
            publish(.failure(.invalidURL))
            return
        }
        open(url)
    }

    func consume(_ request: VelaDeepLinkRequest) {
        if pending?.id == request.id { pending = nil }
    }

    private func publish(_ outcome: Result<VelaDeepLink, VelaDeepLinkError>) {
        sequence += 1
        pending = VelaDeepLinkRequest(id: sequence, outcome: outcome)
    }
}
