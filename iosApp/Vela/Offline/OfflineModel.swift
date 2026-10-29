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
    @Published private(set) var downloads = 0
    /// Debug fixture state last read from the store, plus how many times the manifest button ran.
    @Published private(set) var fixtureDebugLine = ""
    private var fixtureTaps = 0
    /// The framed-area picker (OFF-AREA). [areaPicking] owns the map overlay and [areaPlan] the
    /// live estimate. After confirmation the plan stays for the progress card, which survives
    /// closing the sheet because the download itself lives in the store.
    @Published private(set) var areaPicking = false
    @Published private(set) var areaEstimating = false
    @Published private(set) var areaPlan: OfflineAreaPlan?
    @Published private(set) var areaId: String?
    /// The picker's switches bind straight to these, and every change is written to the store
    /// before the estimate refreshes. [applyingState] keeps the store's own echo from writing back.
    @Published var areaPlaces = true {
        didSet {
            guard !applyingState, areaPlaces != oldValue else { return }
            store?.setAreaPlaces(enabled: areaPlaces)
            refreshAreaPlan()
        }
    }
    @Published var areaCameras = true {
        didSet {
            guard !applyingState, areaCameras != oldValue else { return }
            store?.setAreaCameras(enabled: areaCameras)
            refreshAreaPlan()
        }
    }
    @Published var areaAddresses = true {
        didSet {
            guard !applyingState, areaAddresses != oldValue else { return }
            store?.setAreaAddresses(enabled: areaAddresses)
            refreshAreaPlan()
        }
    }
    @Published private(set) var areaCameraRows = -1
    @Published private(set) var areaAddressRows = -1
    @Published private(set) var areaDataStage = ""
    @Published var areaReportVisible = false

    private let store: OfflineStore?
    private var networkMonitor: OfflineNetworkMonitor?
    private var observing: Task<Void, Never>?
    private var areaViewport: MapViewport?
    private var areaTask: Task<Void, Never>?
    private var areaGeneration = 0
    /// True while a store state is being mirrored, so the switch observers do not write it back.
    private var applyingState = false

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
        "downloading=\(downloadingId ?? "-") stage=\(stage.isEmpty ? "-" : stage) pct=\(progress) pieces=\(completedPieces)/\(pieceCount) downloads=\(downloads) error=\(errorKey ?? "-")"
    }

    /// Stable across the whole process: one region download means one run, whatever the sheet shows.
    var sessionDebugLine: String {
        "downloads=\(downloads) pieces=\(completedPieces)/\(pieceCount) installed=\(installedRows.count) "
            + "updatable=\(rows.filter(\.updatable).count) world=\(worldInstalled ? 1 : 0)"
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

    // MARK: - Framed area (OFF-AREA)

    var areaDownloading: Bool { areaId != nil && downloadingId != nil }
    var areaReady: Bool { areaId != nil && downloadingId == nil && completedId != nil }

    var areaDebugLine: String {
        "area=\(areaId ?? "-") stage=\(stage.isEmpty ? "-" : stage) pct=\(progress) "
            + "pieces=\(completedPieces)/\(pieceCount) cameras=\(areaCameraRows) "
            + "addresses=\(areaAddressRows) data=\(areaDataStage.isEmpty ? "-" : areaDataStage) "
            + "prefs=\(areaPlaces ? 1 : 0)\(areaCameras ? 1 : 0)\(areaAddresses ? 1 : 0) "
            + "error=\(errorKey ?? "-")"
    }

    /// Called from the sheet's "Download an area" row; the map passes its live viewport. The
    /// switches are re-read from the store's persisted preferences here, so a second picker (or a
    /// new launch) cannot show a value the download would not honor.
    func startAreaPick(viewport: MapViewport?) {
        areaViewport = viewport
        areaPlan = nil
        areaReportVisible = false
        areaPicking = true
        if let store {
            let preferences = store.areaPreferences()
            applyingState = true
            areaPlaces = preferences.places
            areaCameras = preferences.cameras
            areaAddresses = preferences.addresses
            applyingState = false
        }
        refreshAreaPlan()
    }

    /// The map moved while picking: the estimate follows after a short debounce.
    func areaViewportChanged(_ viewport: MapViewport) {
        guard areaPicking else { return }
        areaViewport = viewport
        refreshAreaPlan()
    }

    func refreshAreaPlan() {
        guard let store, let viewport = areaViewport else { return }
        areaGeneration += 1
        let generation = areaGeneration
        areaTask?.cancel()
        areaEstimating = true
        areaTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let plan = try? await store.planArea(
                south: viewport.south, west: viewport.west,
                north: viewport.north, east: viewport.east)
            guard let self, !Task.isCancelled, generation == self.areaGeneration else { return }
            self.areaPlan = plan
            self.areaEstimating = false
        }
    }

    func confirmArea() {
        guard let store, let viewport = areaViewport, let plan = areaPlan, plan.canDownload else { return }
        areaPicking = false
        areaTask?.cancel()
        areaReportVisible = true
        store.downloadArea(
            south: viewport.south, west: viewport.west, north: viewport.north, east: viewport.east)
    }

    func cancelAreaPick() {
        areaTask?.cancel()
        areaPicking = false
        areaEstimating = false
        areaPlan = nil
    }

    func hideAreaReport() { areaReportVisible = false }

    #if DEBUG
    /// Clears installed offline data and any pending plan. Used by the UI scenarios so one test
    /// never inherits another's region, failed plan or fixture URLs.
    func resetOfflineForTest() {
        store?.resetForFixture()
    }

    func blockNetworkForTest() {
        if let store { OfflineTestSupport.block(store: store) }
    }

    func suspendDownloadForTest() {
        URLSessionRegionDownloader.shared.suspendActiveDownloadForTest()
    }

    /// The UI fixture's second manifest revision, so a delta update can be driven without a bake.
    func useUpdateFixtureManifest() {
        fixtureTaps += 1
        if let store {
            OfflineFixtureSupport.activateUpdate(store: store)
            fixtureDebugLine = "taps=\(fixtureTaps) " + store.fixtureSummary()
        } else {
            fixtureDebugLine = "taps=\(fixtureTaps) store=missing"
        }
    }
    #endif

    private func apply(_ state: OfflineState) {
        applyingState = true
        defer { applyingState = false }
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
        downloads = Int(state.downloads)
        #if DEBUG
        if OfflineFixtureSupport.isEnabled, let store {
            fixtureDebugLine = "taps=\(fixtureTaps) " + store.fixtureSummary()
        }
        #endif
        areaId = state.areaId
        areaPlaces = state.areaPlaces
        areaCameras = state.areaCameras
        areaAddresses = state.areaAddresses
        areaCameraRows = Int(state.areaCameraRows)
        areaAddressRows = Int(state.areaAddressRows)
        areaDataStage = state.areaDataStage
        revision = Int(state.revision)
    }
}
