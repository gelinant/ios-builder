import Foundation

/// Debug-only document fixture entry. The UI test bundle supplies its CSV path, while the app uses
/// the same security-scoped reader and SavedStore importer as the document picker.
enum SavedTestSupport {
    #if DEBUG
    private static var attempted = false
    #endif

    static func importFixtureIfNeeded(model: SavedModel) {
        #if DEBUG
        guard !attempted else { return }
        let arguments = ProcessInfo.processInfo.arguments
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

    #if DEBUG
    private static func value(_ name: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    #endif
}
