import SwiftUI
import WidgetKit

/// The three Vela Home Screen widgets. The app and this extension share only
/// `WidgetSnapshot.swift` through the App Group; nothing here links VelaCore.
@main
struct VelaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VelaShortcutsWidget()
        VelaParkingWidget()
        VelaDeparturesWidget()
    }
}
