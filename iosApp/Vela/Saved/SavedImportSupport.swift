import Foundation
import VelaCore

/// One list an import would write, for the merge/replace question.
struct SavedPendingListItem: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let existingCount: Int
    let exists: Bool
}

/// The staged import SwiftUI asks about: parsed, not written.
struct SavedPendingImportItem {
    let source: String
    let title: String
    let count: Int
    let lists: [SavedPendingListItem]

    init(_ pending: SavedPendingImport) {
        source = pending.source
        title = pending.title
        count = Int(pending.count)
        lists = pending.lists.map { list in
            SavedPendingListItem(
                title: list.title,
                count: Int(list.count),
                existingCount: Int(list.existingCount),
                exists: list.existingListId != nil)
        }
    }

    var question: String {
        if lists.count > 1 { return "\(lists.count) lists are already saved" }
        return "\(title) is already saved"
    }

    var detail: String {
        let places = count == 1 ? "1 place" : "\(count) places"
        return "Merge adds only the places the list does not have; Replace keeps its name, icon and "
            + "color and writes the imported \(places)."
    }
}

/// Debug-only entries for the UI scenario, and the install point for nothing else. A release build
/// has no fixture argument and no shortcut around the real import path.
enum SavedImportSupport {
    #if DEBUG
    private static var installed = false
    #endif

    static func install(model: SavedModel) {
        #if DEBUG
        guard !installed else { return }
        installed = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-VelaSavedNoGoogle") {
            // The same global the Privacy switch writes, set for this process only so the scenario
            // cannot leave the next test with Google off.
            NoGoogle.shared.enabled = true
        }
        if let path = value("VelaSavedKmlFixture", arguments: arguments),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            model.importKml(data: data, name: URL(fileURLWithPath: path).lastPathComponent)
        }
        #endif
    }

    #if DEBUG
    private static func value(_ name: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
    #endif
}
