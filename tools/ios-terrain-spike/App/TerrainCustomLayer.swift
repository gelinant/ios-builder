// Custom style layer route: MapLibre hands us the render encoder of its own pass, the projection
// matrix and the camera, so terrain can sit below the style's roads and labels.
import MapLibre
import UIKit

final class TerrainCustomLayer: MLNCustomStyleLayer {
    private let renderer: TerrainRenderer
    private weak var model: TerrainModel?
    private var loggedMissingEncoder = false

    init(identifier: String, renderer: TerrainRenderer, model: TerrainModel) {
        self.renderer = renderer
        self.model = model
        super.init(identifier: identifier)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func didMove(to mapView: MLNMapView) {
        log("custom layer attached")
    }

    override func willMove(from mapView: MLNMapView) {}

    override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        renderer.lastContext = context
        guard let model, model.mode == "custom" else { return }
        guard let encoder = renderEncoder, let pass = renderPassDesc else {
            if !loggedMissingEncoder {
                loggedMissingEncoder = true
                log("custom layer has no encoder or render pass")
            }
            return
        }
        renderer.preparePipeline(renderPass: pass)
        model.recordPassInfo(pass: pass)
        let drawStart = CACurrentMediaTime()
        renderer.draw(encoder: encoder, context: context)
        model.recordCustomFrame(encodeMilliseconds: (CACurrentMediaTime() - drawStart) * 1000)
    }
}
