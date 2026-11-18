import Foundation

/// The widget's one extra route, `vela://board`. It opens the last stop whose board was written to
/// the App Group by reopening that board, so the widget does not need MapScreen to know about a new
/// link case. Every other URL goes back to `VelaDeepLinkCenter` unchanged.
@MainActor
enum WidgetDeepLink {
    static let boardHost = "board"

    /// Returns true when the URL belonged to the widget and was handled.
    static func open(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "vela",
              url.host?.lowercased() == boardHost,
              url.path.isEmpty || url.path == "/" else { return false }
        guard let board = WidgetSnapshotStore.shared?.load()?.board else { return false }
        AppGraph.session.board.open(
            lat: board.latitude, lng: board.longitude, name: board.stopName)
        return true
    }
}
