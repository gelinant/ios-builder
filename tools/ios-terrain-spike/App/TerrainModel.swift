// Owns the throwaway map, the DEM, the two rendering routes and the measurements.
import MapLibre
import Metal
import MetalKit
import SwiftUI
import UIKit

final class TerrainModel: NSObject, ObservableObject, MLNMapViewDelegate, MTKViewDelegate {
    static let styleURL = "https://tiles.openfreemap.org/styles/liberty"
    static let autopilotEnabled = CommandLine.arguments.contains("--autopilot")

    @Published var readout = "starting"
    @Published var mode = "custom"

    private(set) var container: UIView?
    private(set) var mapView: MLNMapView?
    private(set) var overlayView: MTKView?
    let renderer: TerrainRenderer
    private let commandQueue: MTLCommandQueue

    private(set) var block: DEMBlock?
    private(set) var meshes: [String: TerrainMesh] = [:]
    private(set) var meshFootprint: [String: Int] = [:]
    private var meshUpload: [String: Double] = [:]
    private var styleLoaded = false
    private var meshesReady = false
    private var terrainLayer: TerrainCustomLayer?
    private var autopilot: Autopilot?
    private var readoutTimer: Timer?
    private var watchdogFired = false

    private(set) var currentMesh = "-"
    private(set) var probes: [[String: Any]] = []
    private(set) var passInfo: [String: Any] = [:]
    private var passInfoRecorded = false

    private var measuring = false
    private var measureStart = 0.0
    private var measureCpuStart = 0.0
    private var measureCustomFrames = 0
    private var measureOverlayFrames = 0
    private var measureEncodeMs = 0.0
    private var customFramesTotal = 0
    private var overlayFramesTotal = 0

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("no Metal device")
        }
        renderer = TerrainRenderer(device: device)
        commandQueue = queue
        super.init()
        startReadoutTimer()
        buildDEM()
        DispatchQueue.main.asyncAfter(deadline: .now() + 150) { [weak self] in
            guard let self, !self.meshesReady || !self.styleLoaded else { return }
            guard !self.watchdogFired else { return }
            self.watchdogFired = true
            self.finishWithError("timed out: styleLoaded=\(self.styleLoaded) meshesReady=\(self.meshesReady)")
        }
    }

    func makeContainer() -> UIView {
        if let container { return container }
        let container = UIView()
        container.backgroundColor = .black

        let map = MLNMapView(frame: .zero, styleURL: URL(string: Self.styleURL))
        map.delegate = self
        map.minimumZoomLevel = 1
        map.maximumZoomLevel = 20
        map.maximumPitch = 60
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(map)
        mapView = map

        let overlay = MTKView(frame: .zero, device: renderer.device)
        overlay.delegate = self
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.framebufferOnly = true
        overlay.colorPixelFormat = .bgra8Unorm
        overlay.depthStencilPixelFormat = .depth32Float
        overlay.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        overlay.isOpaque = false
        overlay.layer.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.preferredFramesPerSecond = 60
        overlay.enableSetNeedsDisplay = false
        overlay.isPaused = true
        container.addSubview(overlay)
        overlayView = overlay

        self.container = container
        return container
    }

    // MARK: - DEM and meshes

    private func buildDEM() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let block = try DEMBlock.fetchAndDecode()
                let baseFootprint = processFootprintBytes()
                let mesh128 = TerrainMeshBuilder.build(block: block, cellsPerTile: 128)
                let footprint128 = processFootprintBytes()
                let mesh256 = TerrainMeshBuilder.build(block: block, cellsPerTile: 256)
                let footprint256 = processFootprintBytes()
                let mesh512 = TerrainMeshBuilder.build(block: block, cellsPerTile: 512)
                let footprint512 = processFootprintBytes()
                DispatchQueue.main.async {
                    self.block = block
                    self.meshes = ["128": mesh128, "256": mesh256, "512": mesh512]
                    self.meshFootprint = [
                        "128": footprint128 - baseFootprint,
                        "256": footprint256 - baseFootprint,
                        "512": footprint512 - baseFootprint,
                    ]
                    self.meshesReady = true
                    self.setMesh("256")
                    log("dem ready: \(block.downloadedBytes) bytes, download+decode \(String(format: "%.0f", block.downloadMilliseconds)) ms")
                    self.startIfReady()
                }
            } catch {
                log("dem failed: \(error)")
                DispatchQueue.main.async { self.finishWithError("DEM failed: \(error)") }
            }
        }
    }

    func setMesh(_ name: String) {
        guard let mesh = meshes[name] else { return }
        renderer.setMesh(mesh)
        meshUpload[name] = renderer.uploadMilliseconds
        currentMesh = name
        updateReadout()
    }

    // MARK: - Style

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        log("style loaded, \(style.layers.count) layers")
        installRoute(style: style)
        installTerrain(style: style)
        styleLoaded = true
        startIfReady()
    }

    private func installTerrain(style: MLNStyle) {
        let layer = TerrainCustomLayer(identifier: "spike-terrain", renderer: renderer, model: self)
        let roads = style.layers.first(where: { $0.identifier == "road_area_pattern" })
        if let roads {
            style.insertLayer(layer, below: roads)
        } else {
            style.addLayer(layer)
        }
        terrainLayer = layer
        log("terrain layer inserted")
    }

    private func installRoute(style: MLNStyle) {
        let coordinates: [[Double]] = [
            [6.7968, 45.8908],
            [6.8270, 45.9000],
            [6.8490, 45.9120],
            [6.8694, 45.9240],
            [6.8870, 45.9350],
            [6.9050, 45.9440],
        ]
        let geoJSON: [String: Any] = [
            "type": "Feature",
            "properties": [String: Any](),
            "geometry": [
                "type": "LineString",
                "coordinates": coordinates,
            ],
        ]
        let url = SpikeFiles.documents.appendingPathComponent("spike-route.geojson")
        if let data = try? JSONSerialization.data(withJSONObject: geoJSON) {
            try? data.write(to: url)
        }
        let source = MLNShapeSource(identifier: "spike-route", url: url, options: nil)
        style.addSource(source)
        let line = MLNLineStyleLayer(identifier: "spike-route-line", source: source)
        line.lineColor = NSExpression(forConstantValue: UIColor(red: 1, green: 0.22, blue: 0.12, alpha: 1))
        line.lineWidth = NSExpression(forConstantValue: 5)
        line.lineOpacity = NSExpression(forConstantValue: 0.95)
        line.lineCap = NSExpression(forConstantValue: "round")
        let labels = style.layers.first(where: { $0.identifier == "waterway_line_label" })
        if let labels {
            style.insertLayer(line, below: labels)
        } else {
            style.addLayer(line)
        }
        log("route line inserted")
    }

    // MARK: - Readout and readiness

    private func startReadoutTimer() {
        readoutTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateReadout()
        }
    }

    private func updateReadout() {
        guard let map = mapView else { return }
        let camera = map.camera
        readout = String(
            format: "%.2f %.2f z%.2f p%.0f h%.0f | %@ %@ | %@",
            camera.centerCoordinate.latitude,
            camera.centerCoordinate.longitude,
            map.zoomLevel,
            camera.pitch,
            camera.heading,
            mode,
            currentMesh,
            meshInfo()
        )
    }

    private func meshInfo() -> String {
        guard let mesh = renderer.mesh else { return "no mesh" }
        return "\(mesh.triangleCount / 1000)k tris"
    }

    private func startIfReady() {
        guard styleLoaded, meshesReady, autopilot == nil else { return }
        guard Self.autopilotEnabled else {
            updateReadout()
            return
        }
        let pilot = Autopilot(model: self)
        autopilot = pilot
        pilot.start()
    }

    // MARK: - Camera helpers used by the autopilot

    func setCamera(latitude: Double, longitude: Double, zoom: Double, pitch: Double, heading: Double) {
        guard let map = mapView else { return }
        map.setCenter(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            zoomLevel: zoom,
            direction: heading,
            animated: false
        )
        var camera = map.camera
        camera.pitch = pitch
        map.setCamera(camera, animated: false)
    }

    func animateCamera(latitude: Double, longitude: Double, seconds: Double) {
        guard let map = mapView else { return }
        var camera = map.camera
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        map.setCamera(camera, withDuration: seconds, animationTimingFunction: CAMediaTimingFunction(name: .linear))
    }

    /// Runs on the main thread: MapLibre's coordinate conversion is not safe from the render
    /// thread that calls the custom layer, so the probe reads the context captured by the last
    /// frame instead of running inside draw().
    func runProbe(_ name: String) {
        guard let context = renderer.lastContext, let map = mapView, let block else { return }
        var entry = CameraProbe.run(context: context, mapView: map, block: block)
        entry["state"] = name
        probes.append(entry)
        log("probe \(name): max \(String(format: "%.2f", entry["maxErrorPx"] as? Double ?? -1)) px")
    }

    // MARK: - Render routes

    func recordPassInfo(pass: MTLRenderPassDescriptor) {
        guard !passInfoRecorded else { return }
        passInfoRecorded = true
        let depth = pass.depthAttachment.texture
        let color = pass.colorAttachments[0].texture
        passInfo = [
            "customLayerClass": "MLNCustomStyleLayer",
            "sameRenderPass": true,
            "depthAttachment": depth != nil,
            "depthFormat": depth.map { Int($0.pixelFormat.rawValue) } ?? -1,
            "colorFormat": color.map { Int($0.pixelFormat.rawValue) } ?? -1,
            "providesProjectionMatrix": true,
            "providesCamera": true,
        ]
        log("map pass: depth \(depth != nil) format \(passInfo["depthFormat"] ?? -1), colour \(passInfo["colorFormat"] ?? -1)")
    }

    func recordCustomFrame(encodeMilliseconds: Double) {
        customFramesTotal += 1
        if measuring {
            measureCustomFrames += 1
            measureEncodeMs += encodeMilliseconds
        }
    }

    func recordOverlayFrame() {
        overlayFramesTotal += 1
        if measuring { measureOverlayFrames += 1 }
    }

    func setMode(_ value: String) {
        mode = value
        overlayView?.isPaused = value != "overlay"
        updateReadout()
        log("mode \(value)")
    }

    func draw(in view: MTKView) {
        guard mode == "overlay", let context = renderer.lastContext,
              let pass = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        renderer.preparePipeline(renderPass: pass)
        let started = CACurrentMediaTime()
        renderer.draw(encoder: encoder, context: context)
        let encodeMs = (CACurrentMediaTime() - started) * 1000
        encoder.endEncoding()
        if let drawable = view.currentDrawable {
            buffer.present(drawable)
        }
        buffer.commit()
        recordOverlayFrame()
        if measuring { measureEncodeMs += encodeMs }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    // MARK: - Measurements

    func beginMeasurement() {
        measureCustomFrames = 0
        measureOverlayFrames = 0
        measureEncodeMs = 0
        measureStart = CACurrentMediaTime()
        measureCpuStart = processCPUSeconds()
        measuring = true
    }

    func endMeasurement() -> [String: Any] {
        measuring = false
        let seconds = CACurrentMediaTime() - measureStart
        let cpu = processCPUSeconds() - measureCpuStart
        let frames = mode == "custom" ? measureCustomFrames : measureOverlayFrames
        let result: [String: Any] = [
            "mode": mode,
            "mesh": currentMesh,
            "frames": frames,
            "seconds": seconds,
            "fps": Double(frames) / max(seconds, 0.001),
            "cpuMsPerFrame": cpu * 1000 / Double(max(frames, 1)),
            "encodeMsPerFrame": measureEncodeMs / Double(max(frames, 1)),
        ]
        log("measure \(mode) \(currentMesh): \(frames) frames, \(String(format: "%.1f", result["fps"] as? Double ?? 0)) fps, cpu \(String(format: "%.2f", result["cpuMsPerFrame"] as? Double ?? 0)) ms/frame")
        return result
    }

    func makeReport(extra: [String: Any]) -> [String: Any] {
        var report: [String: Any] = [
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "device": UIDevice.current.model,
            "system": UIDevice.current.systemVersion,
            "screenScale": Double(UIScreen.main.scale),
            "styleURL": Self.styleURL,
            "mapLibre": "6.31.0",
            "dem": [
                "sourceClass": DEMBlock.tileName,
                "zoom": DEMBlock.zoom,
                "originX": DEMBlock.originX,
                "originY": DEMBlock.originY,
                "tilesPerSide": DEMBlock.tilesPerSide,
                "downloadedBytes": block?.downloadedBytes ?? 0,
                "downloadAndDecodeMs": block?.downloadMilliseconds ?? 0,
            ],
            "pass": passInfo,
            "cameraLimits": [
                "maximumPitch": mapView?.maximumPitch ?? 0,
                "minimumZoom": mapView?.minimumZoomLevel ?? 0,
                "maximumZoom": mapView?.maximumZoomLevel ?? 0,
            ],
            "probes": probes,
            "footprintBytes": processFootprintBytes(),
        ]
        var meshReport: [String: Any] = [:]
        for name in ["128", "256", "512"] {
            guard let mesh = meshes[name] else { continue }
            meshReport[name] = [
                "triangles": mesh.triangleCount,
                "gridVerticesPerSide": mesh.gridVerticesPerSide,
                "arrayBytes": mesh.arrayBytes,
                "buildMs": mesh.buildMilliseconds,
                "uploadMs": meshUpload[name] ?? 0,
                "footprintDeltaBytes": meshFootprint[name] ?? 0,
            ]
        }
        report["meshes"] = meshReport
        for (key, value) in extra { report[key] = value }
        report["endedAt"] = ISO8601DateFormatter().string(from: Date())
        return report
    }

    func finish(extra: [String: Any]) {
        SpikeFiles.writeJSON("terrain-report.json", makeReport(extra: extra))
        SpikeFiles.write("terrain-done")
        log("done")
    }

    func finishWithError(_ message: String) {
        log("error \(message)")
        SpikeFiles.writeJSON("terrain-report.json", makeReport(extra: ["error": message]))
        SpikeFiles.write("terrain-done")
    }
}
