// Throwaway G-1 app: one map, a projection switch, and an optional autopilot that measures the
// globe. It is not part of Vela and shares no code with iosApp/ (docs/ios/GLOBE-SPIKE.md).
import SwiftUI

@main
struct GlobeSpikeApp: App {
    @StateObject private var model = GlobeModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: GlobeModel

    var body: some View {
        ZStack(alignment: .top) {
            GlobeMapView(model: model)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Picker("Projection", selection: Binding(
                    get: { model.projection },
                    set: { model.setProjection($0) }
                )) {
                    Text("Mercator").tag("mercator")
                    Text("Globe").tag("globe")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("projection")

                Text(model.readout)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("camera-readout")
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
