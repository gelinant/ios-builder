import SwiftUI
import WidgetKit

/// The two Vela Home Screen widgets: the parked car and the last stop whose board was opened.
/// The app and this extension share only `WidgetSnapshot.swift` through the App Group; nothing
/// here links VelaCore, MapLibre or any network client.
@main
struct VelaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VelaParkingWidget()
        VelaDeparturesWidget()
    }
}
