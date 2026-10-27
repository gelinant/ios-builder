import Foundation
import VelaCore

/// One downloadable speech engine, mirrored from the shared Android catalog (`AsrCatalog` in
/// `:core-common`) through `IosAsrCatalog`. The id is the single source of truth: it names the
/// release asset, the on-disk directory and the model files.
struct AsrEntry: Identifiable, Hashable {
    let id: String

    var name: String { IosAsrCatalog.shared.displayName(id: id) }
    var modelType: String { IosAsrCatalog.shared.modelType(id: id) }
    var sizeMb: Int { Int(IosAsrCatalog.shared.sizeMb(id: id)) }
    var downloadUrl: String { IosAsrCatalog.shared.downloadUrl(id: id) }
    var sha256: String { IosAsrCatalog.shared.sha256(id: id) }
    var expectedBytes: Int64 { IosAsrCatalog.shared.bytes(id: id) }
    var files: [String] { IosAsrCatalog.shared.files(id: id) }
    var whisperPrefix: String { IosAsrCatalog.shared.whisperPrefix(id: id) }
}

enum AsrCatalogView {
    /// Same order and ids as Android. Never duplicated by hand.
    static let all: [AsrEntry] = IosAsrCatalog.shared.ids().map { AsrEntry(id: $0) }

    static func entry(_ id: String) -> AsrEntry? { all.first { $0.id == id } }

    static func defaultEngine(language: String) -> AsrEntry? {
        entry(IosAsrCatalog.shared.defaultId(lang: language))
    }
}

/// Where a downloaded voice-search model lives: `Application Support/VelaAsr/<engine id>/`, with
/// the exact file names of the Android archives. As on Android, the installed set comes from the
/// filesystem, never from a stored list, so an interrupted download is never offered.
enum AsrLayout {
    static func storeRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VelaAsr", isDirectory: true)
    }

    static func directory(id: String, root: URL = storeRoot()) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    /// True only when every model file is present and non-empty.
    static func isComplete(_ entry: AsrEntry, root: URL = storeRoot()) -> Bool {
        let dir = directory(id: entry.id, root: root)
        return entry.files.allSatisfy { fileSize(dir.appendingPathComponent($0).path) > 0 }
    }

    /// Bytes of a file, or 0 when it is missing.
    static func fileSize(_ path: String) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    /// Every catalog engine whose files are complete, in catalog order.
    static func installed(root: URL = storeRoot()) -> [String] {
        AsrCatalogView.all.filter { isComplete($0, root: root) }.map { $0.id }
    }

    /// The file paths the recognizer loads, for an engine that passed [isComplete].
    static func files(_ entry: AsrEntry, root: URL = storeRoot()) -> [String: String] {
        let dir = directory(id: entry.id, root: root)
        return Dictionary(uniqueKeysWithValues: entry.files.map {
            ($0, dir.appendingPathComponent($0).path)
        })
    }
}

/// The downloaded engines, the user's pick and the one-time installs. One download at a time.
final class AsrStore: ObservableObject {
    static let shared = AsrStore()

    @Published private(set) var installed: [String] = []
    @Published private(set) var selectedId: String?
    @Published private(set) var downloadingId: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var installing = false
    @Published private(set) var lastError: String?

    let root: URL
    private let defaults: UserDefaults
    private let installer = AsrInstaller()
    private static let selectedKey = "app.vela.ios.asr.engine"

    init(root: URL = AsrLayout.storeRoot(), defaults: UserDefaults = .standard) {
        self.root = root
        self.defaults = defaults
        refresh()
        #if DEBUG
        if LaunchOptionsAsr.fixture { installFixtureFromBundle() }
        #endif
    }

    var entries: [AsrEntry] { AsrCatalogView.all }

    /// The id of the engine the current language should run, or nil when none is installed.
    func engineId(forLanguage lang: String) -> String? {
        AsrSelection.shared.forRecognition(installed: installed, selected: selectedId, lang: lang)
    }

    func entry(_ id: String) -> AsrEntry? { AsrCatalogView.entry(id) }

    func isInstalled(_ id: String) -> Bool { installed.contains(id) }

    func isInUse(_ id: String) -> Bool {
        selectedId == id || (selectedId == nil && installed.first == id)
    }

    func files(for entry: AsrEntry) -> [String: String] {
        AsrLayout.files(entry, root: root)
    }

    func select(_ id: String) {
        guard isInstalled(id) else { return }
        defaults.set(id, forKey: Self.selectedKey)
        selectedId = id
        objectWillChange.send()
    }

    func refresh() {
        let update = { [weak self] in
            guard let self else { return }
            self.selectedId = self.defaults.string(forKey: Self.selectedKey)
            self.installed = AsrLayout.installed(root: self.root)
            self.objectWillChange.send()
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    /// Download and install one engine, then make it the pick when nothing was installed before.
    func install(_ id: String) {
        guard downloadingId == nil, let entry = AsrCatalogView.entry(id),
              let url = URL(string: entry.downloadUrl) else { return }
        downloadingId = id
        installing = false
        progress = 0
        lastError = nil
        let hadNone = installed.isEmpty
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.installer.install(
                    entry: entry, url: url, root: self.root,
                    progress: { value in DispatchQueue.main.async { self.progress = value } },
                    installing: { DispatchQueue.main.async {
                        self.installing = true
                        self.progress = 0.92
                    } })
                await MainActor.run {
                    self.downloadingId = nil
                    self.installing = false
                    self.progress = 1
                    self.refresh()
                    if hadNone && self.isInstalled(id) { self.select(id) }
                }
            } catch {
                await MainActor.run {
                    self.downloadingId = nil
                    self.installing = false
                    self.progress = 0
                    self.lastError = error.localizedDescription
                    self.refresh()
                }
            }
        }
    }

    func remove(_ id: String) {
        guard downloadingId != id else { return }
        try? FileManager.default.removeItem(at: AsrLayout.directory(id: id, root: root))
        if selectedId == id { defaults.removeObject(forKey: Self.selectedKey) }
        refresh()
    }

    #if DEBUG
    /// Copies the engine shipped in the test bundle, when `-VelaAsrFixture YES` is set. The fixture
    /// exists in Debug builds only and never in the archive or the IPA.
    private func installFixtureFromBundle() {
        let id = LaunchOptionsAsr.fixtureId
        guard let entry = AsrCatalogView.entry(id),
              let source = Bundle.main.resourceURL?
                .appendingPathComponent("AsrFixture", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true),
              FileManager.default.fileExists(atPath: source.path) else { return }
        if AsrLayout.isComplete(entry, root: root) {
            refresh()
            return
        }
        let destination = AsrLayout.directory(id: id, root: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
        refresh()
    }
    #endif
}

/// Debug launch switches for voice search. Release builds ignore all of them.
enum LaunchOptionsAsr {
    static var fixture: Bool { flag("VelaAsrFixture") }

    static var fixtureId: String {
        let value = string("VelaAsrFixtureId")
        return value.isEmpty ? "whisper-tiny" : value
    }

    /// Text used in place of a recording, for the UI scenarios (the CI simulator has no usable
    /// microphone). Never read in Release.
    static var injectedText: String? {
        let value = string("VelaVoiceQuery")
        return value.isEmpty ? nil : value
    }

    private static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func string(_ key: String) -> String {
        value(key)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func flag(_ key: String) -> Bool {
        guard let value = value(key)?.lowercased() else { return false }
        return value == "yes" || value == "true" || value == "1"
    }
}
