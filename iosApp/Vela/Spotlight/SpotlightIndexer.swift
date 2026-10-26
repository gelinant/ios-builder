import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import VelaCore

enum SpotlightDomain: String, Equatable, Sendable {
    case savedPlaces = "saved-places"
    case shortcuts = "shortcuts"
    case parking
}

struct SpotlightRecord: Equatable, Sendable {
    let route: VelaDeepLink
    let domain: SpotlightDomain
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double

    var searchableItem: CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = subtitle
        attributes.contentURL = route.url
        attributes.latitude = NSNumber(value: latitude)
        attributes.longitude = NSNumber(value: longitude)
        attributes.supportsNavigation = NSNumber(value: true)
        attributes.keywords = [title] + (subtitle.map { [$0] } ?? [])
        let item = CSSearchableItem(
            uniqueIdentifier: route.url.absoluteString,
            domainIdentifier: domain.rawValue,
            attributeSet: attributes)
        return item
    }

    static func records(for state: SavedState) -> [SpotlightRecord] {
        let content = VelaSavedContent.snapshot(state)
        var records = content.savedPlaces.map {
            SpotlightRecord(
                route: $0.deepLink, domain: .savedPlaces, title: $0.name, subtitle: $0.address,
                latitude: $0.latitude, longitude: $0.longitude)
        }
        if let home = content.home {
            records.append(shortcutRecord(home, kind: .home))
        }
        if let work = content.work {
            records.append(shortcutRecord(work, kind: .work))
        }
        if let parking = state.parking {
            records.append(SpotlightRecord(
                route: .parking, domain: .parking, title: "Parked car", subtitle: "Saved parking place",
                latitude: parking.lat, longitude: parking.lng))
        }
        return records
    }

    private static func shortcutRecord(_ place: VelaSavedReference, kind: VelaShortcutKind) -> SpotlightRecord {
        let subtitle = [place.name, place.address].compactMap { $0 }.joined(separator: ", ")
        return SpotlightRecord(
            route: .navigate(kind), domain: .shortcuts, title: kind.displayName,
            subtitle: subtitle.isEmpty ? nil : subtitle, latitude: place.latitude, longitude: place.longitude)
    }
}

/// Keeps one local Core Spotlight index in sync with SavedStore. Every batch replaces only Vela's
/// three domains, which also removes stale entries after a place, shortcut or parking deletion.
final class SpotlightIndexer: ObservableObject {
    @Published private(set) var debugLine = "records=0 indexed=0 deleted=0 errors=0 rev=0"

    private let store: SavedStore
    private let index: CSSearchableIndex
    private var observing: Task<Void, Never>?
    private var lastRecords: [SpotlightRecord]?
    private var revision = 0
    private var errorCount = 0

    init(store: SavedStore, index: CSSearchableIndex = .default()) {
        self.store = store
        self.index = index
    }

    func start() {
        #if DEBUG
        if let command = Self.testCommand {
            // A relaunched UI test issues a new command even if the process kept the old task.
            observing?.cancel()
            observing = Task { @MainActor [weak self] in
                await self?.apply(command == "add" ? [Self.fixture] : [])
            }
            return
        }
        #endif
        guard observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in store.state {
                await self.apply(SpotlightRecord.records(for: state))
            }
        }
    }

    @MainActor private func apply(_ records: [SpotlightRecord]) async {
        guard records != lastRecords else { return }
        guard CSSearchableIndex.isIndexingAvailable() else {
            errorCount += 1
            updateDebug(records: records.count, indexed: 0, deleted: 0)
            return
        }
        do {
            try await deleteDomains()
            if !records.isEmpty {
                try await add(records.map(\.searchableItem))
            }
            lastRecords = records
            revision += 1
            updateDebug(records: records.count, indexed: records.count, deleted: 1)
        } catch {
            errorCount += 1
            updateDebug(records: records.count, indexed: 0, deleted: 0)
        }
    }

    @MainActor private func updateDebug(records: Int, indexed: Int, deleted: Int) {
        debugLine = "records=\(records) indexed=\(indexed) deleted=\(deleted) errors=\(errorCount) rev=\(revision)"
    }

    private func deleteDomains() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: SpotlightDomain.allCases.map(\.rawValue)) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func add(_ items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(items) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private static var testCommand: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaSpotlightTest"), index + 1 < arguments.count else {
            return nil
        }
        let command = arguments[index + 1].lowercased()
        return command == "add" || command == "delete" ? command : nil
    }

    private static let fixture = SpotlightRecord(
        route: .place("spotlight-fixture"), domain: .savedPlaces,
        title: "Davis Food Co-op", subtitle: "620 G St, Davis, CA 95616",
        latitude: 38.5449, longitude: -121.7405)
}

extension SpotlightDomain: CaseIterable {}
