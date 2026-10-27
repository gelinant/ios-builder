import Foundation
import VelaCore

struct OfflineRow: Identifiable, Equatable {
    let id: String
    let name: String
    let sizeMb: Int
    let installed: Bool
    let installedBytes: Int64
    let updateMb: Int
    let updatable: Bool
}

struct OfflineCategoryRow: Identifiable, Equatable {
    let id: String
    let packBytes: Int64
    let placesBytes: Int64
    let basemapBytes: Int64
}

/// SwiftUI's mirror of OfflineStore. It also owns the process's one NWPathMonitor.
final class OfflineModel: ObservableObject {
    @Published private(set) var rows: [OfflineRow] = []
    @Published private(set) var loading = false
    @Published private(set) var currentRegionId: String?
    @Published private(set) var downloadingId: String?
    @Published private(set) var stage = ""
    @Published private(set) var progress = 0
    @Published private(set) var completedPieces = 0
    @Published private(set) var pieceCount = 0
    @Published private(set) var completedId: String?
    @Published private(set) var errorKey: String?
    @Published private(set) var networkAvailable = true
    @Published private(set) var googleDisabled = false
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var packBytes: Int64 = 0
    @Published private(set) var placesBytes: Int64 = 0
    @Published private(set) var basemapBytes: Int64 = 0
    @Published private(set) var glyphBytes: Int64 = 0
    @Published private(set) var regionBytes: [OfflineCategoryRow] = []
    @Published private(set) var worldInstalled = false
    @Published private(set) var updatingId: String?
    @Published private(set) var updatedId: String?
    @Published private(set) var updateDeltaPieces = 0
    @Published private(set) var updateFullPieces = 0
    @Published private(set) var revision = 0

    private let store: OfflineStore?
    private var networkMonitor: OfflineNetworkMonitor?
    private var observing: Task<Void, Never>?

    init(store: OfflineStore?) {
        self.store = store
        if let store {
            networkMonitor = OfflineNetworkMonitor(store: store)
            #if DEBUG
            OfflineFixtureSupport.install(store: store)
            #endif
        }
    }

    var installedRows: [OfflineRow] { rows.filter(\.installed) }
    var currentRegionName: String? {
        guard let currentRegionId else { return nil }
        return rows.first { $0.id == currentRegionId }?.name
    }

    var debugLine: String {
        "regions=\(rows.count) installed=\(installedRows.count) pack=\(packBytes) places=\(placesBytes) map=\(basemapBytes) glyphs=\(glyphBytes) total=\(totalBytes) world=\(worldInstalled ? 1 : 0) rev=\(revision)"
    }

    var downloadDebugLine: String {
        "downloading=\(downloadingId ?? "-") stage=\(stage.isEmpty ? "-" : stage) pct=\(progress) pieces=\(completedPieces)/\(pieceCount) error=\(errorKey ?? "-")"
    }

    var updateDebugLine: String {
        "updating=\(updatingId ?? "-") delta=\(updateDeltaPieces) full=\(updateFullPieces)"
    }

    func categories(_ id: String) -> OfflineCategoryRow? {
        regionBytes.first { $0.id == id }
    }

    func start() {
        guard let store, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func refresh() { store?.refresh() }
    func onLocation(latitude: Double, longitude: Double) { store?.onLocation(lat: latitude, lng: longitude) }
    func download(_ id: String) { store?.download(regionId: id) }
    func update(_ id: String) { store?.update(regionId: id) }
    func cancel() { store?.cancelDownload() }
    func delete(_ id: String) { store?.delete(regionId: id) }
    func deleteCategory(_ id: String, category: String) {
        store?.deleteCategory(regionId: id, category: category)
    }
    func setGoogleDisabled(_ disabled: Bool) {
        googleDisabled = disabled
        store?.setGoogleDisabled(disabled: disabled)
    }

    #if DEBUG
    func blockNetworkForTest() {
        if let store { OfflineTestSupport.block(store: store) }
    }

    func suspendDownloadForTest() {
        URLSessionRegionDownloader.shared.suspendActiveDownloadForTest()
    }

    /// The UI fixture's second manifest revision, so a delta update can be driven without a bake.
    func useUpdateFixtureManifest() {
        if let store { OfflineFixtureSupport.activateUpdate(store: store) }
    }
    #endif

    private func apply(_ state: OfflineState) {
        loading = state.loading
        rows = state.regions.map {
            OfflineRow(
                id: $0.id, name: $0.name, sizeMb: Int($0.sizeMb), installed: $0.installed,
                installedBytes: $0.installedBytes, updateMb: Int($0.updateMb),
                updatable: $0.updatable)
        }
        currentRegionId = state.currentRegionId
        downloadingId = state.downloadingId
        stage = state.downloadStage
        progress = Int(state.downloadProgress)
        completedPieces = Int(state.downloadCompletedPieces)
        pieceCount = Int(state.downloadPieceCount)
        completedId = state.completedId
        errorKey = state.errorKey
        networkAvailable = state.networkAvailable
        googleDisabled = state.googleDisabled
        totalBytes = state.totalBytes
        packBytes = state.packBytes
        placesBytes = state.placesBytes
        basemapBytes = state.basemapBytes
        glyphBytes = state.glyphBytes
        regionBytes = state.regionBytes.map {
            OfflineCategoryRow(
                id: $0.id, packBytes: $0.packBytes, placesBytes: $0.placesBytes,
                basemapBytes: $0.basemapBytes)
        }
        worldInstalled = state.worldInstalled
        updatingId = state.updatingId
        updatedId = state.updatedId
        updateDeltaPieces = Int(state.updateDeltaPieces)
        updateFullPieces = Int(state.updateFullPieces)
        revision = Int(state.revision)
    }
}
