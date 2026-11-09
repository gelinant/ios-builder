import Foundation

/// Debug-only document fixture entry. The UI test bundle supplies its CSV path or export text,
/// while the app uses the same security-scoped reader and SavedStore importer as the document
/// picker.
enum SavedTestSupport {
    #if DEBUG
    private static var attempted = false
    private static let roundtripKey = "VelaSavedRoundtripExport"
    #endif

    static func importFixtureIfNeeded(model: SavedModel) {
        #if DEBUG
        guard !attempted else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if value("VelaSavedImportRoundtrip", arguments: arguments) != nil {
            attempted = true
            let exported = UserDefaults.standard.string(forKey: roundtripKey)
            UserDefaults.standard.removeObject(forKey: roundtripKey)
            if let exported {
                model.importFile(text: exported, name: "vela-list-UI-Export-List.json")
            }
            return
        }
        if let exported = value("VelaSavedFixtureText", arguments: arguments) {
            attempted = true
            model.importFile(
                text: exported,
                name: value("VelaSavedFixtureName", arguments: arguments) ?? "SavedFixture.json")
            return
        }
        let path = value("VelaTakeoutFixture", arguments: arguments)
        let fallback = value("VelaTakeoutFixtureText", arguments: arguments)
        guard path != nil || fallback != nil else { return }
        attempted = true
        let url = path.map { URL(fileURLWithPath: $0) }
        let scopedText = url.flatMap { try? SavedDocumentReader.read($0) }
        guard let text = scopedText ?? fallback else { return }
        model.importFile(text: text, name: url?.lastPathComponent ?? "TakeoutFixture.csv")
        #endif
    }

    /// The UI test cannot drive the system share sheet or the document picker (both are remote
    /// processes). When it asks, keep the exact document the export wrote so the next launch can
    /// hand it to the same importer. Debug-only; nothing is stored in a normal run.
    static func rememberExportForRoundtrip(_ body: String) {
        #if DEBUG
        guard value("VelaSavedExportRoundtrip", arguments: ProcessInfo.processInfo.arguments) != nil else { return }
        UserDefaults.standard.set(body, forKey: roundtripKey)
        UserDefaults.standard.synchronize()
        #endif
    }

    #if DEBUG
    private static func value(_ name: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    #endif
}
