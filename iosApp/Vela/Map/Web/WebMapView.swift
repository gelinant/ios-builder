import CoreLocation
import QuartzCore
import UIKit
import WebKit

// The main map view. It hosts one WKWebView running the bundled MapLibre GL JS with 3D terrain,
// and keeps the subset of MapLibre Native's `MLNMapView` API the app was written against.
//
// Swift is the source of truth: the camera, the style model (WebMapStyle.swift) and every
// annotation live here and are mirrored to the page as commands. The page reports camera
// changes, gestures and, as soon as a finger lands, the rendered features under it, so the
// synchronous feature and projection queries the tap code makes are answered locally.

enum MLNUserTrackingMode: UInt {
    case none = 0
    case follow = 1
    case followWithHeading = 2
    case followWithCourse = 3
}

protocol MLNMapViewDelegate: AnyObject {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle)
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool)
    func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool)
    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?)
    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView?
    func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation)
    func mapView(_ mapView: MLNMapView, didDeselect annotation: MLNAnnotation)
    func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool
    func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat
    func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat
    func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor
    func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor
}

extension MLNMapViewDelegate {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {}
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {}
    func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {}
    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {}
    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? { nil }
    func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {}
    func mapView(_ mapView: MLNMapView, didDeselect annotation: MLNAnnotation) {}
    func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { false }
    func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat { 1 }
    func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 3 }
    func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor { .black }
    func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
        UIColor.systemBlue.withAlphaComponent(0.2)
    }
}

/// A camera: centre, zoom, heading and pitch. MapLibre Native expressed the distance as an
/// altitude; the zoom is kept as is so a camera read and written back is exact.
final class MLNMapCamera: NSObject {
    var centerCoordinate: CLLocationCoordinate2D
    var heading: CLLocationDirection
    var pitch: CGFloat
    var zoomLevel: Double
    private let viewHeight: Double

    init(center: CLLocationCoordinate2D, zoomLevel: Double, heading: CLLocationDirection,
         pitch: CGFloat, viewHeight: Double = 800) {
        centerCoordinate = center
        self.zoomLevel = zoomLevel
        self.heading = heading
        self.pitch = pitch
        self.viewHeight = max(viewHeight, 1)
        super.init()
    }

    convenience init(lookingAtCenter center: CLLocationCoordinate2D, altitude: CLLocationDistance,
                     pitch: CGFloat, heading: CLLocationDirection) {
        self.init(center: center, zoomLevel: 0, heading: heading, pitch: pitch)
        self.altitude = altitude
    }

    /// Metres from the camera to the ground at the centre, projected on the vertical.
    var altitude: CLLocationDistance {
        get {
            let distancePoints = 0.5 * viewHeight / tan(WebMapProjection.fieldOfView / 2)
            let metersPerPoint = WebMapProjection.metersPerPoint(
                zoom: zoomLevel, latitude: centerCoordinate.latitude)
            return distancePoints * metersPerPoint * cos(Double(pitch) * .pi / 180)
        }
        set {
            let distancePoints = 0.5 * viewHeight / tan(WebMapProjection.fieldOfView / 2)
            let ground = max(newValue, 1) / max(cos(Double(pitch) * .pi / 180), 0.05)
            let metersPerPoint = ground / distancePoints
            let circumference = WebMapProjection.earthCircumference
                * cos(centerCoordinate.latitude * .pi / 180)
            zoomLevel = log2(max(circumference / (512 * metersPerPoint), 1e-9))
        }
    }
}

/// GL JS's Mercator camera, in UIKit points: 512-point world at z0, a 36.87 degree vertical field
/// of view, the principal point at the centre of the padded viewport. With terrain the page keeps
/// the centre on the ground, so a point at the centre's elevation projects the same way.
struct WebMapProjection {
    static let fieldOfView = 0.6435011087932844
    static let earthCircumference = 40_075_016.686

    var center: CLLocationCoordinate2D
    var zoom: Double
    var bearing: Double
    var pitch: Double
    var size: CGSize
    var inset: UIEdgeInsets

    static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
        earthCircumference * cos(latitude * .pi / 180) / (512 * pow(2, zoom))
    }

    static func mercatorX(_ longitude: Double) -> Double {
        (longitude + 180) / 360
    }

    static func mercatorY(_ latitude: Double) -> Double {
        let clamped = max(-85.051129, min(85.051129, latitude))
        let s = sin(clamped * .pi / 180)
        return 0.5 - log((1 + s) / (1 - s)) / (4 * .pi)
    }

    static func latitude(mercatorY y: Double) -> Double {
        let n = Double.pi - 2 * Double.pi * max(0, min(1, y))
        return 180 / .pi * atan(0.5 * (exp(n) - exp(-n)))
    }

    var worldSize: Double { 512 * pow(2, zoom) }

    var principal: CGPoint {
        CGPoint(x: inset.left + (size.width - inset.left - inset.right) / 2,
                y: inset.top + (size.height - inset.top - inset.bottom) / 2)
    }

    private var focal: Double {
        0.5 * Double(max(size.height, 1)) / tan(Self.fieldOfView / 2)
    }

    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        let world = worldSize
        var dx = (Self.mercatorX(coordinate.longitude) - Self.mercatorX(center.longitude)) * world
        if dx > world / 2 { dx -= world }
        if dx < -world / 2 { dx += world }
        let dy = (Self.mercatorY(coordinate.latitude) - Self.mercatorY(center.latitude)) * world
        let b = bearing * .pi / 180
        let xr = dx * cos(b) + dy * sin(b)
        let yr = -dx * sin(b) + dy * cos(b)
        let p = pitch * .pi / 180
        let d = focal
        let depth = d - yr * sin(p)
        guard depth > 1e-6 else { return CGPoint(x: -1e6, y: -1e6) }
        let origin = principal
        let x = Double(origin.x) + xr * d / depth
        let y = Double(origin.y) + yr * cos(p) * d / depth
        guard x.isFinite, y.isFinite else { return CGPoint(x: -1e6, y: -1e6) }
        return CGPoint(x: x, y: y)
    }

    /// The unwrapped Mercator position under a screen point; points above the horizon are pinned
    /// just below it.
    func mercator(for point: CGPoint) -> (x: Double, y: Double) {
        let origin = principal
        let sx = Double(point.x - origin.x)
        let sy = Double(point.y - origin.y)
        let p = pitch * .pi / 180
        let d = focal
        let denominator = max(cos(p) * d + sy * sin(p), 0.02 * d)
        let yr = sy * d / denominator
        let xr = sx * (d - yr * sin(p)) / d
        let b = bearing * .pi / 180
        let dx = xr * cos(b) - yr * sin(b)
        let dy = xr * sin(b) + yr * cos(b)
        let world = worldSize
        return (Self.mercatorX(center.longitude) + dx / world, Self.mercatorY(center.latitude) + dy / world)
    }

    func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
        let m = mercator(for: point)
        var longitude = m.x * 360 - 180
        while longitude > 180 { longitude -= 360 }
        while longitude < -180 { longitude += 360 }
        return CLLocationCoordinate2D(latitude: Self.latitude(mercatorY: m.y), longitude: longitude)
    }

    var visibleBounds: MLNCoordinateBounds {
        let w = size.width
        let h = size.height
        let samples = [
            CGPoint(x: 0, y: 0), CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: 0),
            CGPoint(x: 0, y: h / 2), CGPoint(x: w, y: h / 2),
            CGPoint(x: 0, y: h), CGPoint(x: w / 2, y: h), CGPoint(x: w, y: h),
        ]
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for sample in samples {
            let m = mercator(for: sample)
            minX = min(minX, m.x)
            maxX = max(maxX, m.x)
            minY = min(minY, m.y)
            maxY = max(maxY, m.y)
        }
        var west = minX * 360 - 180
        var east = maxX * 360 - 180
        if east - west >= 360 {
            west = -180
            east = 180
        }
        return MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: Self.latitude(mercatorY: maxY), longitude: west),
            ne: CLLocationCoordinate2D(latitude: Self.latitude(mercatorY: minY), longitude: east))
    }
}

/// The script handler holds its target weakly; WKUserContentController retains handlers.
private final class WebMapMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: MLNMapView?

    init(_ target: MLNMapView) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        target?.receive(body)
    }
}

final class MLNMapView: UIView {
    weak var delegate: MLNMapViewDelegate?
    private(set) var style: MLNStyle?

    var styleURL: URL? {
        get { currentStyleURL }
        set {
            currentStyleURL = newValue
            loadStyle()
        }
    }

    // Ornaments the app hides and replaces with its own chrome.
    let compassView = UIView()
    let scaleBar = UIView()
    let logoView = UIImageView()
    let attributionButton = UIButton(type: .infoLight)

    var toleranceForSnappingToNorth: CGFloat = 7 { didSet { sendOptions() } }
    var isRotateEnabled = true { didSet { sendOptions() } }
    var isPitchEnabled = true { didSet { sendOptions() } }
    var isScrollEnabled = true { didSet { sendOptions() } }
    var isZoomEnabled = true { didSet { sendOptions() } }
    var minimumZoomLevel: Double = 0 { didSet { sendOptions() } }
    var maximumZoomLevel: Double = 22 { didSet { sendOptions() } }
    var minimumPitch: CGFloat = 0 { didSet { sendOptions() } }
    var maximumPitch: CGFloat = 60 { didSet { sendOptions() } }

    /// The deformed terrain. It is always on for the main map; the elevation tiles need a network,
    /// and without one the page keeps drawing the flat map.
    var terrainEnabled = true { didSet { sendTerrain() } }
    var terrainExaggeration: Double = 1.2 { didSet { sendTerrain() } }

    var contentInset: UIEdgeInsets = .zero {
        didSet {
            guard oldValue != contentInset else { return }
            cameraRevision += 1
            webSend(["op": "padding", "seq": cameraSeq, "padding": paddingJSON])
        }
    }

    // MARK: Camera mirror

    private var mirrorCenter = MapDefaults.initialCenter
    private var mirrorZoom = MapDefaults.initialZoom
    private var mirrorBearing = 0.0
    private var mirrorPitch = 0.0
    /// Bumped by every camera command; page reports carrying an older value are stale.
    private var cameraSeq = 0
    /// Bumped by every camera change from either side, to tell whether a touch snapshot still
    /// describes the screen.
    private var cameraRevision = 0

    // MARK: Page

    private var webView: WKWebView!
    private var pageReady = false
    private var outbox: [[String: Any]] = []
    private var flushScheduled = false
    private var webGLRetries = 0
    #if DEBUG
    /// The Mapbox spike's FPS probe runs once per process, after the first style load.
    private var fpsProbeScheduled = false
    #endif
    private var lastLayoutSize = CGSize.zero
    private var currentStyleURL: URL?
    private var pendingStyle: MLNStyle?
    private var styleGeneration = 0
    private var requests: [String: WebMapResources.Request] = [:]
    private var queryCallbacks: [String: () -> Void] = [:]
    private var querySequence = 0
    /// Holds the single-tap recognizers back until a double tap has failed, as MapLibre Native's
    /// own recognizers did, and gives the page time to answer the touch snapshot.
    private let doubleTapGate = UITapGestureRecognizer()
    /// Fires as a finger lands and asks the page for the features under it, so they are stored
    /// before any tap handler runs.
    private let touchDown = UILongPressGestureRecognizer()

    // MARK: Features under the last touch

    private struct TouchSnapshot {
        let point: CGPoint
        let coordinate: CLLocationCoordinate2D
        let revision: Int
        let time: CFTimeInterval
        let buckets: [Int: [[String: Any]]]
    }

    private var touchSnapshot: TouchSnapshot?
    private var snapshotCount = 0
    private var pageErrors = 0
    private var lastPageError = "-"
    private var decodedBuckets: [Int: [(layer: String, feature: MLNFeature)]] = [:]
    private static let snapshotBuckets = [0, 10, 22]

    // MARK: Annotations

    private final class MarkerEntry {
        let id: String
        let annotation: MLNAnnotation
        var view: MLNAnnotationView?
        var imageKey = ""
        var size = CGSize.zero
        var offset = CGVector.zero

        init(id: String, annotation: MLNAnnotation) {
            self.id = id
            self.annotation = annotation
        }
    }

    private var annotationList: [MLNAnnotation] = []
    private var markers: [ObjectIdentifier: MarkerEntry] = [:]
    private var markerSequence = 0
    private var markerImageData: [String: String] = [:]
    private var sentMarkerImages = Set<String>()
    private var pendingMarkerRefresh = Set<ObjectIdentifier>()
    private var markerRefreshScheduled = false
    private var shapesScheduled = false
    private var selected: MLNAnnotation?

    // MARK: User location

    private var locationManagerStorage: CLLocationManager?

    private var locationManager: CLLocationManager {
        if let manager = locationManagerStorage { return manager }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 5
        locationManagerStorage = manager
        return manager
    }

    private var trackingMode: MLNUserTrackingMode = .none
    private(set) var userLocation: MLNUserLocation?

    var showsUserLocation = false {
        didSet {
            guard oldValue != showsUserLocation else { return }
            if showsUserLocation {
                if userLocation == nil { userLocation = MLNUserLocation() }
            } else {
                userLocation = nil
            }
            updateLocationServices()
            sendUserLocation()
        }
    }

    var userTrackingMode: MLNUserTrackingMode {
        get { trackingMode }
        set { setUserTrackingMode(newValue, animated: true, completionHandler: nil) }
    }

    // MARK: - Lifecycle

    init(frame: CGRect, styleURL: URL?) {
        super.init(frame: frame)
        commonInit()
        if let styleURL {
            self.styleURL = styleURL
        }
    }

    override convenience init(frame: CGRect) {
        self.init(frame: frame, styleURL: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        for request in requests.values { request.cancel() }
        locationManagerStorage?.stopUpdatingLocation()
        locationManagerStorage?.stopUpdatingHeading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "vela")
    }

    private func commonInit() {
        backgroundColor = .white
        clipsToBounds = true
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.suppressesIncrementalRendering = false
        configuration.userContentController.add(WebMapMessageProxy(self), name: "vela")
        let web = WKWebView(frame: bounds, configuration: configuration)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.minimumZoomScale = 1
        web.scrollView.maximumZoomScale = 1
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.navigationDelegate = self
        web.isAccessibilityElement = false
        web.accessibilityElementsHidden = true
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        insertSubview(web, at: 0)
        webView = web

        for ornament in [compassView, scaleBar, logoView, attributionButton] as [UIView] {
            ornament.isHidden = true
            addSubview(ornament)
        }

        doubleTapGate.numberOfTapsRequired = 2
        doubleTapGate.cancelsTouchesInView = false
        doubleTapGate.delaysTouchesBegan = false
        doubleTapGate.delaysTouchesEnded = false
        doubleTapGate.delegate = self
        super.addGestureRecognizer(doubleTapGate)

        touchDown.minimumPressDuration = 0
        touchDown.cancelsTouchesInView = false
        touchDown.delaysTouchesBegan = false
        touchDown.delaysTouchesEnded = false
        touchDown.delegate = self
        touchDown.addTarget(self, action: #selector(fingerLanded(_:)))
        super.addGestureRecognizer(touchDown)

        loadPage()
    }

    override func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        // A single tap added by the app or a world layer waits for the double-tap gate, so the
        // page's touch snapshot is in before the tap handler queries features.
        if let tap = gestureRecognizer as? UITapGestureRecognizer, tap !== doubleTapGate,
           tap.numberOfTapsRequired == 1, tap.numberOfTouchesRequired == 1 {
            tap.require(toFail: doubleTapGate)
        }
        super.addGestureRecognizer(gestureRecognizer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = bounds
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            cameraRevision += 1
            webSend(["op": "resize"])
        }
    }

    // MARK: - Page document

    private static let pageHTML: String? = {
        func resource(_ name: String, _ ext: String) -> URL? {
            let bundle = Bundle.main
            for directory in [nil, "webmap", "terrain", "Resources/webmap", "Resources/terrain"] as [String?] {
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: directory) {
                    return url
                }
            }
            return nil
        }
        guard let htmlURL = resource("webmap", "html"),
              let html = try? String(contentsOf: htmlURL, encoding: .utf8),
              let libraryURL = resource("maplibre-gl", "js"),
              let library = try? String(contentsOf: libraryURL, encoding: .utf8),
              let cssURL = resource("maplibre-gl", "css"),
              let css = try? String(contentsOf: cssURL, encoding: .utf8),
              let scriptURL = resource("webmap", "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else { return nil }
        return html
            .replacingOccurrences(of: "<link rel=\"stylesheet\" href=\"maplibre-gl.css\" />",
                                  with: "<style>\(css)</style>")
            .replacingOccurrences(of: "<script src=\"maplibre-gl.js\"></script>",
                                  with: "<script>\(library)</script>")
            .replacingOccurrences(of: "<script src=\"webmap.js\"></script>",
                                  with: "<script>\(script)</script>")
    }()

    private func loadPage() {
        pageReady = false
        outbox.removeAll()
        guard let html = Self.pageHTML else { return }
        webView.loadHTMLString(html, baseURL: URL(string: WebMapURLs.pageOrigin))
    }

    // MARK: - Commands to the page

    func webSend(_ command: [String: Any]) {
        guard pageReady else { return }
        outbox.append(command)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        guard pageReady, !outbox.isEmpty else { return }
        let batch = outbox.filter { JSONSerialization.isValidJSONObject($0) }
        outbox.removeAll()
        guard !batch.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: batch),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.vela && window.vela.run(\(json));", completionHandler: nil)
    }

    private var paddingJSON: [String: Any] {
        ["top": Double(contentInset.top), "bottom": Double(contentInset.bottom),
         "left": Double(contentInset.left), "right": Double(contentInset.right)]
    }

    private var optionsJSON: [String: Any] {
        [
            "minZoom": max(0, minimumZoomLevel),
            "maxZoom": min(24, max(maximumZoomLevel, minimumZoomLevel)),
            "minPitch": Double(minimumPitch),
            "maxPitch": min(85, Double(maximumPitch)),
            "bearingSnap": Double(toleranceForSnappingToNorth),
            "rotate": isRotateEnabled,
            "pitch": isPitchEnabled,
            "scroll": isScrollEnabled,
            "zoom": isZoomEnabled,
        ]
    }

    private func sendOptions() {
        webSend(["op": "options", "options": optionsJSON])
    }

    private func sendTerrain() {
        webSend(["op": "terrain", "on": terrainEnabled, "exaggeration": terrainExaggeration])
    }

    /// A fresh page gets the whole state: the map, the style document, its images, the markers,
    /// the shapes and the puck.
    private func sendInitialState() {
        outbox.removeAll()
        sentMarkerImages.removeAll()
        webSend([
            "op": "init",
            "lng": mirrorCenter.longitude, "lat": mirrorCenter.latitude,
            "zoom": mirrorZoom, "bearing": mirrorBearing, "pitch": mirrorPitch,
            "padding": paddingJSON, "options": optionsJSON,
            "terrain": terrainEnabled, "exaggeration": terrainExaggeration,
        ])
        if let style {
            webSend(["op": "style", "gen": style.generation, "style": style.pageDocument()])
        } else if let pendingStyle {
            webSend(["op": "style", "gen": pendingStyle.generation, "style": pendingStyle.pageDocument()])
        }
        for entry in markers.values { sendMarker(entry) }
        scheduleShapes()
        sendUserLocation()
        if let selected { showCallout(for: selected) }
    }

    // MARK: - Messages from the page

    fileprivate func receive(_ body: [String: Any]) {
        switch body["e"] as? String {
        case "ready":
            pageReady = true
            sendInitialState()
        case "created":
            webGLRetries = 0
            delegate?.mapView(self, regionDidChangeAnimated: false)
        case "styleLoaded":
            styleLoaded(generation: body["gen"] as? Int ?? -1)
        case "move":
            applyPageCamera(body, final: false)
        case "moveend":
            applyPageCamera(body, final: true)
        case "gesture":
            userGesture(body["kind"] as? String ?? "")
        case "touch":
            storeSnapshot(body)
        case "queryResult":
            storeSnapshot(body)
            if let id = body["id"] as? String, let callback = queryCallbacks.removeValue(forKey: id) {
                callback()
            }
        case "fetch":
            if let id = body["id"] as? String, let url = body["url"] as? String {
                startRequest(id: id, url: url)
            }
        case "cancel":
            if let id = body["id"] as? String { requests.removeValue(forKey: id)?.cancel() }
        case "fatal":
            // A loaded simulator can refuse the first WebGL context; one fresh page is a slow start.
            if webGLRetries < 1 {
                webGLRetries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.loadPage() }
            }
        case "fpsState":
            #if DEBUG
            MapFpsProbe.shared.settled(state: body["state"] as? String ?? "-",
                                       milliseconds: number(body["ms"]) ?? 0)
            #endif
            break
        case "fps":
            #if DEBUG
            MapFpsProbe.shared.report(renders: body["renders"] as? Int ?? 0,
                                      ticks: body["ticks"] as? Int ?? 0,
                                      milliseconds: number(body["ms"]) ?? 0)
            #endif
            break
        case "error":
            pageErrors += 1
            lastPageError = String(((body["where"] as? String ?? "-") + ":" + (body["message"] as? String ?? "-"))
                .replacingOccurrences(of: " ", with: "_").prefix(80))
            #if DEBUG
            NSLog("[webmap] %@: %@", body["where"] as? String ?? "-", body["message"] as? String ?? "-")
            #endif
        default:
            break
        }
    }

    private func number(_ value: Any?) -> Double? {
        guard let value = (value as? NSNumber)?.doubleValue, value.isFinite else { return nil }
        return value
    }

    private func applyPageCamera(_ body: [String: Any], final: Bool) {
        guard (body["seq"] as? Int) == cameraSeq else { return }
        if let lng = number(body["lng"]), let lat = number(body["lat"]) {
            mirrorCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let zoom = number(body["zoom"]) { mirrorZoom = zoom }
        if let bearing = number(body["bearing"]) { mirrorBearing = Self.normalized(bearing) }
        if let pitch = number(body["pitch"]) { mirrorPitch = pitch }
        cameraRevision += 1
        if final {
            delegate?.mapView(self, regionDidChangeAnimated: true)
        }
    }

    private func userGesture(_ kind: String) {
        switch trackingMode {
        case .none:
            break
        case .follow:
            if kind == "dragstart" { setUserTrackingMode(.none, animated: false, completionHandler: nil) }
        case .followWithHeading, .followWithCourse:
            if kind == "dragstart" || kind == "rotatestart" {
                setUserTrackingMode(.none, animated: false, completionHandler: nil)
            }
        }
    }

    // MARK: - Style loading

    private func loadStyle() {
        styleGeneration += 1
        let generation = styleGeneration
        style = nil
        pendingStyle = nil
        guard let url = currentStyleURL else { return }
        let finish: (Data?) -> Void = { [weak self] data in
            guard let data,
                  let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            DispatchQueue.main.async {
                guard let self, generation == self.styleGeneration else { return }
                let loaded = MLNStyle(document: document, generation: generation)
                loaded.mapView = self
                self.pendingStyle = loaded
                self.webSend(["op": "style", "gen": generation, "style": loaded.pageDocument()])
            }
        }
        if url.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async {
                finish(try? Data(contentsOf: url))
            }
        } else {
            URLSession.shared.dataTask(with: url) { data, _, _ in finish(data) }.resume()
        }
    }

    private func styleLoaded(generation: Int) {
        if let pending = pendingStyle, pending.generation == generation {
            pendingStyle = nil
            style = pending
            delegate?.mapView(self, didFinishLoading: pending)
            #if DEBUG
            scheduleFpsProbeIfRequested()
            #endif
        } else if let style, style.generation == generation {
            // The same document again on a fresh page: its images went with the old one.
            for command in style.allImageCommands() { webSend(command) }
        }
    }

    #if DEBUG
    /// `-VelaFpsProbe <seconds>` (MapFpsProbe): the scripted bearing turn, once, on this map.
    private func scheduleFpsProbeIfRequested() {
        guard let delay = MapFpsProbe.delay, !fpsProbeScheduled else { return }
        fpsProbeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MapFpsProbe.shared.started()
            self?.webSend(["op": "fpsProbe", "seconds": MapFpsProbe.seconds, "degrees": MapFpsProbe.degrees])
        }
    }
    #endif

    /// The page's state for the debug lines: whether it runs, how many touch snapshots arrived,
    /// where the last one landed and how many features it carried.
    var webMapDebugLine: String {
        let snapshot = touchSnapshot
        let point = snapshot.map { String(format: "%.0f,%.0f", $0.point.x, $0.point.y) } ?? "-"
        let counts = Self.snapshotBuckets.map { String(snapshot?.buckets[$0]?.count ?? -1) }
            .joined(separator: "/")
        return "web_ready=\(pageReady ? 1 : 0) web_style=\(style?.generation ?? -1)"
            + " web_touch=\(snapshotCount) web_touch_at=\(point) web_touch_n=\(counts)"
            + " web_errors=\(pageErrors) web_error=\(lastPageError)"
    }

    // MARK: - Data requests

    private func startRequest(id: String, url: String) {
        let request = WebMapResources.shared.load(url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.requests.removeValue(forKey: id) != nil else { return }
                switch result {
                case .data(let base64):
                    self.webSend(["op": "res", "id": id, "b64": base64])
                case .failure(let status):
                    self.webSend(["op": "rej", "id": id, "status": status])
                }
            }
        }
        requests[id] = request
    }

    // MARK: - Camera

    var centerCoordinate: CLLocationCoordinate2D {
        get { mirrorCenter }
        set { setCenter(newValue, animated: false) }
    }

    var zoomLevel: Double {
        get { mirrorZoom }
        set { setZoomLevel(newValue, animated: false) }
    }

    var direction: CLLocationDirection {
        get { mirrorBearing }
        set { setDirection(newValue, animated: false) }
    }

    var camera: MLNMapCamera {
        get {
            MLNMapCamera(center: mirrorCenter, zoomLevel: mirrorZoom, heading: mirrorBearing,
                         pitch: CGFloat(mirrorPitch), viewHeight: Double(bounds.height))
        }
        set { setCamera(newValue, animated: false) }
    }

    private static let animationDuration: TimeInterval = 0.3

    func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        moveCamera(center: coordinate, duration: animated ? Self.animationDuration : 0)
    }

    func setCenter(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double, animated: Bool) {
        moveCamera(center: coordinate, zoom: zoomLevel, duration: animated ? Self.animationDuration : 0)
    }

    func setCenter(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double,
                   direction: CLLocationDirection, animated: Bool) {
        moveCamera(center: coordinate, zoom: zoomLevel, bearing: direction,
                   duration: animated ? Self.animationDuration : 0)
    }

    func setCenter(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double,
                   direction: CLLocationDirection, animated: Bool,
                   completionHandler: (() -> Void)?) {
        moveCamera(center: coordinate, zoom: zoomLevel, bearing: direction,
                   duration: animated ? Self.animationDuration : 0, completion: completionHandler)
    }

    func setZoomLevel(_ zoomLevel: Double, animated: Bool) {
        moveCamera(zoom: zoomLevel, duration: animated ? Self.animationDuration : 0)
    }

    func setDirection(_ direction: CLLocationDirection, animated: Bool) {
        moveCamera(bearing: direction, duration: animated ? Self.animationDuration : 0)
    }

    func resetNorth() {
        setDirection(0, animated: true)
    }

    func setCamera(_ camera: MLNMapCamera, animated: Bool) {
        setCamera(camera, withDuration: animated ? Self.animationDuration : 0,
                  animationTimingFunction: nil, completionHandler: nil)
    }

    func setCamera(_ camera: MLNMapCamera, withDuration duration: TimeInterval,
                   animationTimingFunction: CAMediaTimingFunction?,
                   completionHandler: (() -> Void)? = nil) {
        moveCamera(center: camera.centerCoordinate, zoom: camera.zoomLevel, bearing: camera.heading,
                   pitch: Double(camera.pitch), duration: duration, completion: completionHandler)
    }

    func fly(to camera: MLNMapCamera, completionHandler: (() -> Void)? = nil) {
        setCamera(camera, withDuration: 1.0, animationTimingFunction: nil,
                  completionHandler: completionHandler)
    }

    private static func normalized(_ bearing: Double) -> Double {
        var value = bearing.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    private func moveCamera(center: CLLocationCoordinate2D? = nil, zoom: Double? = nil,
                            bearing: Double? = nil, pitch: Double? = nil,
                            duration: TimeInterval, completion: (() -> Void)? = nil) {
        var command: [String: Any] = ["op": "camera"]
        if let center, CLLocationCoordinate2DIsValid(center),
           center.latitude.isFinite, center.longitude.isFinite {
            mirrorCenter = center
            command["lng"] = center.longitude
            command["lat"] = center.latitude
        }
        if let zoom, zoom.isFinite {
            let floor = max(0, minimumZoomLevel)
            mirrorZoom = max(floor, min(min(24, maximumZoomLevel), zoom))
            command["zoom"] = mirrorZoom
        }
        if let bearing, bearing.isFinite {
            mirrorBearing = Self.normalized(bearing)
            command["bearing"] = mirrorBearing
        }
        if let pitch, pitch.isFinite {
            mirrorPitch = max(Double(minimumPitch), min(Double(min(maximumPitch, 85)), pitch))
            command["pitch"] = mirrorPitch
        }
        cameraSeq += 1
        cameraRevision += 1
        command["seq"] = cameraSeq
        command["duration"] = Int(duration * 1000)
        webSend(command)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
        }
    }

    private var projection: WebMapProjection {
        WebMapProjection(center: mirrorCenter, zoom: mirrorZoom, bearing: mirrorBearing,
                         pitch: mirrorPitch, size: bounds.size, inset: contentInset)
    }

    var visibleCoordinateBounds: MLNCoordinateBounds {
        projection.visibleBounds
    }

    func metersPerPoint(atLatitude latitude: CLLocationDegrees) -> CLLocationDistance {
        WebMapProjection.metersPerPoint(zoom: mirrorZoom, latitude: latitude)
    }

    func convert(_ coordinate: CLLocationCoordinate2D, toPointTo view: UIView?) -> CGPoint {
        let point = projection.point(for: coordinate)
        guard let view, view !== self else { return point }
        return convert(point, to: view)
    }

    func convert(_ point: CGPoint, toCoordinateFrom view: UIView?) -> CLLocationCoordinate2D {
        let local = (view == nil || view === self) ? point : convert(point, from: view)
        // The page's own answer for the touched point includes the terrain under it.
        if let snapshot = touchSnapshot, snapshot.revision == cameraRevision,
           hypot(snapshot.point.x - local.x, snapshot.point.y - local.y) <= 3,
           CLLocationCoordinate2DIsValid(snapshot.coordinate) {
            return snapshot.coordinate
        }
        return projection.coordinate(for: local)
    }

    func cameraThatFitsCoordinateBounds(_ bounds: MLNCoordinateBounds) -> MLNMapCamera {
        cameraThatFitsCoordinateBounds(bounds, edgePadding: .zero)
    }

    /// The camera that shows [bounds] inside the content inset plus [insets], at the current
    /// heading and pitch. Solved on the real projection, so a tilted camera still fits.
    func cameraThatFitsCoordinateBounds(_ bounds: MLNCoordinateBounds,
                                        edgePadding insets: UIEdgeInsets) -> MLNMapCamera {
        let padding = UIEdgeInsets(
            top: contentInset.top + insets.top, left: contentInset.left + insets.left,
            bottom: contentInset.bottom + insets.bottom, right: contentInset.right + insets.right)
        let size = self.bounds.size.width > 0 ? self.bounds.size : CGSize(width: 390, height: 844)
        let available = CGSize(width: max(1, size.width - padding.left - padding.right),
                               height: max(1, size.height - padding.top - padding.bottom))
        let target = CGPoint(x: padding.left + available.width / 2, y: padding.top + available.height / 2)
        let samples = [
            bounds.sw, bounds.ne,
            CLLocationCoordinate2D(latitude: bounds.sw.latitude, longitude: bounds.ne.longitude),
            CLLocationCoordinate2D(latitude: bounds.ne.latitude, longitude: bounds.sw.longitude),
            CLLocationCoordinate2D(latitude: (bounds.sw.latitude + bounds.ne.latitude) / 2,
                                   longitude: bounds.sw.longitude),
            CLLocationCoordinate2D(latitude: (bounds.sw.latitude + bounds.ne.latitude) / 2,
                                   longitude: bounds.ne.longitude),
            CLLocationCoordinate2D(latitude: bounds.sw.latitude,
                                   longitude: (bounds.sw.longitude + bounds.ne.longitude) / 2),
            CLLocationCoordinate2D(latitude: bounds.ne.latitude,
                                   longitude: (bounds.sw.longitude + bounds.ne.longitude) / 2),
        ]
        let maxZoom = min(24, maximumZoomLevel)
        let minZoom = max(0, minimumZoomLevel)
        // A flat first guess from the Mercator box.
        let x0 = WebMapProjection.mercatorX(bounds.sw.longitude)
        let x1 = WebMapProjection.mercatorX(bounds.ne.longitude)
        let y0 = WebMapProjection.mercatorY(bounds.ne.latitude)
        let y1 = WebMapProjection.mercatorY(bounds.sw.latitude)
        let width = max(abs(x1 - x0) * 512, 1e-9)
        let height = max(abs(y1 - y0) * 512, 1e-9)
        var zoom = log2(min(Double(available.width) / width, Double(available.height) / height))
        zoom = max(minZoom, min(maxZoom, zoom.isFinite ? zoom : maxZoom))
        var center = CLLocationCoordinate2D(
            latitude: WebMapProjection.latitude(mercatorY: (y0 + y1) / 2),
            longitude: ((x0 + x1) / 2) * 360 - 180)
        for _ in 0..<10 {
            let view = WebMapProjection(center: center, zoom: zoom, bearing: mirrorBearing,
                                        pitch: mirrorPitch, size: size, inset: contentInset)
            let points = samples.map(view.point(for:))
            if points.contains(where: { $0.x <= -1e5 }) {
                zoom = max(minZoom, zoom - 1)
                continue
            }
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 0
            let boxWidth = max(maxX - minX, 1e-6)
            let boxHeight = max(maxY - minY, 1e-6)
            let scale = min(available.width / boxWidth, available.height / boxHeight)
            let middle = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let principal = view.principal
            center = view.coordinate(for: CGPoint(x: principal.x + (middle.x - target.x),
                                                  y: principal.y + (middle.y - target.y)))
            let step = log2(Double(scale))
            let next = max(minZoom, min(maxZoom, zoom + (step.isFinite ? step : 0)))
            let settled = abs(next - zoom) < 0.005
                && abs(middle.x - target.x) < 0.5 && abs(middle.y - target.y) < 0.5
            zoom = next
            if settled { break }
        }
        return MLNMapCamera(center: center, zoomLevel: zoom, heading: mirrorBearing,
                            pitch: CGFloat(mirrorPitch), viewHeight: Double(size.height))
    }

    func setVisibleCoordinateBounds(_ bounds: MLNCoordinateBounds, animated: Bool) {
        setVisibleCoordinateBounds(bounds, edgePadding: .zero, animated: animated, completionHandler: nil)
    }

    func setVisibleCoordinateBounds(_ bounds: MLNCoordinateBounds, edgePadding insets: UIEdgeInsets,
                                    animated: Bool, completionHandler: (() -> Void)?) {
        let fitted = cameraThatFitsCoordinateBounds(bounds, edgePadding: insets)
        setCamera(fitted, withDuration: animated ? Self.animationDuration : 0,
                  animationTimingFunction: nil, completionHandler: completionHandler)
    }

    func showAnnotations(_ annotations: [MLNAnnotation], animated: Bool) {
        showAnnotations(annotations, edgePadding: UIEdgeInsets(top: 100, left: 100, bottom: 100, right: 100),
                        animated: animated, completionHandler: nil)
    }

    func showAnnotations(_ annotations: [MLNAnnotation], edgePadding insets: UIEdgeInsets,
                         animated: Bool, completionHandler: (() -> Void)?) {
        let coordinates = annotations.flatMap { annotation -> [CLLocationCoordinate2D] in
            if let multi = annotation as? MLNMultiPoint { return multi.coordinates }
            return [annotation.coordinate]
        }.filter(CLLocationCoordinate2DIsValid)
        guard let first = coordinates.first else {
            completionHandler?()
            return
        }
        if coordinates.count == 1 {
            moveCamera(center: first, duration: animated ? Self.animationDuration : 0,
                       completion: completionHandler)
            return
        }
        setVisibleCoordinateBounds(GeoJSON.bounds(of: coordinates), edgePadding: insets,
                                   animated: animated, completionHandler: completionHandler)
    }

    // MARK: - Rendered features

    private func storeSnapshot(_ body: [String: Any]) {
        guard let x = number(body["x"]), let y = number(body["y"]) else { return }
        var buckets: [Int: [[String: Any]]] = [:]
        if let features = body["f"] as? [String: Any] {
            for (key, value) in features {
                guard let half = Int(key), let list = value as? [[String: Any]] else { continue }
                buckets[half] = list
            }
        }
        var coordinate = kCLLocationCoordinate2DInvalid
        if let lng = number(body["lng"]), let lat = number(body["lat"]) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        snapshotCount += 1
        touchSnapshot = TouchSnapshot(
            point: CGPoint(x: x, y: y), coordinate: coordinate, revision: cameraRevision,
            time: CACurrentMediaTime(), buckets: buckets)
        decodedBuckets.removeAll()
    }

    @objc private func fingerLanded(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, recognizer.numberOfTouches == 1, pageReady else { return }
        let point = recognizer.location(in: self)
        webSend(["op": "query", "id": "touch", "x": Double(point.x), "y": Double(point.y)])
    }

    /// True when the features under [point] arrived since the finger landed there.
    func hasTouchSnapshot(near point: CGPoint) -> Bool {
        guard let snapshot = touchSnapshot else { return false }
        return CACurrentMediaTime() - snapshot.time < 30
            && hypot(snapshot.point.x - point.x, snapshot.point.y - point.y) <= 8
    }

    /// Asks the page for the features under [point] and calls back once the answer is stored,
    /// for a query that does not follow a touch (VoiceOver's "select at centre").
    func queryFeatures(at point: CGPoint, completion: @escaping () -> Void) {
        guard pageReady else {
            completion()
            return
        }
        querySequence += 1
        let id = "a\(querySequence)"
        queryCallbacks[id] = completion
        webSend(["op": "query", "id": id, "x": Double(point.x), "y": Double(point.y)])
    }

    private func decoded(_ bucket: Int) -> [(layer: String, feature: MLNFeature)] {
        if let cached = decodedBuckets[bucket] { return cached }
        let list = (touchSnapshot?.buckets[bucket] ?? []).compactMap { json -> (layer: String, feature: MLNFeature)? in
            guard let layer = json["l"] as? String, let feature = GeoJSON.feature(from: json) else { return nil }
            return (layer, feature)
        }
        decodedBuckets[bucket] = list
        return list
    }

    private func features(around center: CGPoint, half: CGFloat, rect: CGRect?,
                          layers: Set<String>?) -> [MLNFeature] {
        guard let snapshot = touchSnapshot,
              CACurrentMediaTime() - snapshot.time < 30,
              hypot(snapshot.point.x - center.x, snapshot.point.y - center.y) <= 8 else { return [] }
        let wanted = Int(half.rounded(.up))
        let bucket = Self.snapshotBuckets.first { $0 >= wanted } ?? Self.snapshotBuckets.last!
        var out: [MLNFeature] = []
        for entry in decoded(bucket) {
            if let layers, !layers.contains(entry.layer) { continue }
            // A wider stored box than the one asked for: a point must still fall in the rect.
            if let rect, bucket > wanted, let point = entry.feature as? MLNPointFeature {
                let screen = convert(point.coordinate, toPointTo: self)
                if !rect.insetBy(dx: -2, dy: -2).contains(screen) { continue }
            }
            out.append(entry.feature)
        }
        return out
    }

    func visibleFeatures(at point: CGPoint) -> [MLNFeature] {
        visibleFeatures(at: point, styleLayerIdentifiers: nil)
    }

    func visibleFeatures(at point: CGPoint, styleLayerIdentifiers: Set<String>?) -> [MLNFeature] {
        features(around: point, half: 0, rect: nil, layers: styleLayerIdentifiers)
    }

    func visibleFeatures(at point: CGPoint, styleLayerIdentifiers: Set<String>?,
                         predicate: NSPredicate?) -> [MLNFeature] {
        visibleFeatures(at: point, styleLayerIdentifiers: styleLayerIdentifiers)
    }

    func visibleFeatures(in rect: CGRect) -> [MLNFeature] {
        visibleFeatures(in: rect, styleLayerIdentifiers: nil)
    }

    func visibleFeatures(in rect: CGRect, styleLayerIdentifiers: Set<String>?) -> [MLNFeature] {
        features(around: CGPoint(x: rect.midX, y: rect.midY), half: min(rect.width, rect.height) / 2,
                 rect: rect, layers: styleLayerIdentifiers)
    }

    func visibleFeatures(in rect: CGRect, styleLayerIdentifiers: Set<String>?,
                         predicate: NSPredicate?) -> [MLNFeature] {
        visibleFeatures(in: rect, styleLayerIdentifiers: styleLayerIdentifiers)
    }

    // MARK: - Annotations

    var annotations: [MLNAnnotation]? {
        annotationList.isEmpty ? nil : annotationList
    }

    var selectedAnnotations: [MLNAnnotation] {
        get { selected.map { [$0] } ?? [] }
        set {
            if let first = newValue.first {
                selectAnnotation(first, animated: false, completionHandler: nil)
            } else if let selected {
                deselectAnnotation(selected, animated: false)
            }
        }
    }

    private static func isShapeAnnotation(_ annotation: MLNAnnotation) -> Bool {
        if annotation is MLNPointCollection { return false }
        return annotation is MLNMultiPoint || annotation is MLNMultiPolyline
            || annotation is MLNMultiPolygon || annotation is MLNShapeCollection
    }

    func addAnnotation(_ annotation: MLNAnnotation) {
        addAnnotations([annotation])
    }

    func addAnnotations(_ annotations: [MLNAnnotation]) {
        var shapesChanged = false
        for annotation in annotations where !annotationList.contains(where: { $0 === annotation }) {
            annotationList.append(annotation)
            (annotation as? MLNShape)?.webMapOwner = self
            if Self.isShapeAnnotation(annotation) {
                shapesChanged = true
            } else {
                createMarker(for: annotation)
            }
        }
        if shapesChanged { scheduleShapes() }
    }

    func removeAnnotation(_ annotation: MLNAnnotation) {
        removeAnnotations([annotation])
    }

    func removeAnnotations(_ annotations: [MLNAnnotation]) {
        var shapesChanged = false
        for annotation in annotations {
            guard let index = annotationList.firstIndex(where: { $0 === annotation }) else { continue }
            annotationList.remove(at: index)
            if let shape = annotation as? MLNShape, shape.webMapOwner === self { shape.webMapOwner = nil }
            if selected === annotation { deselectAnnotation(annotation, animated: false) }
            if Self.isShapeAnnotation(annotation) {
                shapesChanged = true
            } else if let entry = markers.removeValue(forKey: ObjectIdentifier(annotation)) {
                entry.view?.webMapOwner = nil
                webSend(["op": "markerRemove", "id": entry.id])
            }
        }
        if shapesChanged { scheduleShapes() }
    }

    func view(for annotation: MLNAnnotation) -> MLNAnnotationView? {
        markers[ObjectIdentifier(annotation)]?.view
    }

    func selectAnnotation(_ annotation: MLNAnnotation, animated: Bool, completionHandler: (() -> Void)?) {
        // Selecting the selected annotation again is silent, as in MapLibre Native: the delegate's
        // select handler may itself select it.
        if selected === annotation {
            completionHandler?()
            return
        }
        if let current = selected, current !== annotation {
            deselectAnnotation(current, animated: false)
        }
        selected = annotation
        view(for: annotation)?.isSelected = true
        showCallout(for: annotation)
        delegate?.mapView(self, didSelect: annotation)
        completionHandler?()
    }

    func selectAnnotation(_ annotation: MLNAnnotation, animated: Bool) {
        selectAnnotation(annotation, animated: animated, completionHandler: nil)
    }

    func deselectAnnotation(_ annotation: MLNAnnotation?, animated: Bool) {
        guard let annotation, selected === annotation else { return }
        selected = nil
        view(for: annotation)?.isSelected = false
        webSend(["op": "popupClose"])
        delegate?.mapView(self, didDeselect: annotation)
    }

    private func showCallout(for annotation: MLNAnnotation) {
        guard delegate?.mapView(self, annotationCanShowCallout: annotation) == true,
              let title = annotation.title, !title.isEmpty,
              CLLocationCoordinate2DIsValid(annotation.coordinate) else {
            webSend(["op": "popupClose"])
            return
        }
        let entry = markers[ObjectIdentifier(annotation)]
        let height = entry.map { Double($0.size.height) / 2 - Double($0.offset.dy) } ?? 0
        webSend([
            "op": "popup",
            "lng": annotation.coordinate.longitude, "lat": annotation.coordinate.latitude,
            "title": title, "subtitle": annotation.subtitle ?? "",
            "oy": -(height + 4),
        ])
    }

    private func createMarker(for annotation: MLNAnnotation) {
        markerSequence += 1
        let entry = MarkerEntry(id: "m\(markerSequence)", annotation: annotation)
        if let view = delegate?.mapView(self, viewFor: annotation) {
            view.annotation = annotation
            view.webMapOwner = self
            entry.view = view
        }
        markers[ObjectIdentifier(annotation)] = entry
        renderMarker(entry)
    }

    private func renderMarker(_ entry: MarkerEntry) {
        let image: UIImage?
        if let view = entry.view {
            image = WebMapImages.snapshot(view)
            entry.size = view.bounds.size
            entry.offset = view.centerOffset
        } else {
            image = Self.defaultPin
            entry.size = Self.defaultPin.size
            entry.offset = CGVector(dx: 0, dy: -Self.defaultPin.size.height / 2)
        }
        if let image, let data = image.pngData() {
            var hasher = Hasher()
            hasher.combine(data)
            let key = "i" + String(UInt(bitPattern: hasher.finalize()), radix: 36)
            if markerImageData[key] == nil {
                if markerImageData.count > 600 { pruneMarkerImages() }
                markerImageData[key] = data.base64EncodedString()
            }
            entry.imageKey = key
        } else {
            entry.imageKey = ""
        }
        sendMarker(entry)
    }

    private func pruneMarkerImages() {
        let used = Set(markers.values.map(\.imageKey))
        markerImageData = markerImageData.filter { used.contains($0.key) }
        sentMarkerImages = sentMarkerImages.intersection(used)
    }

    private func sendMarker(_ entry: MarkerEntry) {
        if !entry.imageKey.isEmpty, !sentMarkerImages.contains(entry.imageKey),
           let base64 = markerImageData[entry.imageKey] {
            webSend(["op": "markerImage", "key": entry.imageKey, "b64": base64])
            if pageReady { sentMarkerImages.insert(entry.imageKey) }
        }
        let coordinate = entry.annotation.coordinate
        let valid = CLLocationCoordinate2DIsValid(coordinate)
        let z = annotationList.firstIndex(where: { $0 === entry.annotation }) ?? 0
        webSend([
            "op": "marker", "id": entry.id,
            "lng": valid ? coordinate.longitude : 0, "lat": valid ? coordinate.latitude : 0,
            "key": entry.imageKey,
            "w": Double(max(entry.size.width, 1)), "h": Double(max(entry.size.height, 1)),
            "ox": Double(entry.offset.dx), "oy": Double(entry.offset.dy),
            "z": z + (selected === entry.annotation ? 100_000 : 0),
            "hidden": !valid || (entry.view?.isHidden ?? false),
        ])
    }

    /// A point annotation's coordinate changed, or a shape annotation's points.
    func annotationDidMove(_ shape: MLNShape) {
        guard annotationList.contains(where: { $0 === shape }) else { return }
        if Self.isShapeAnnotation(shape) {
            scheduleShapes()
        } else if let entry = markers[ObjectIdentifier(shape)] {
            sendMarker(entry)
            if selected === shape { showCallout(for: shape) }
        }
    }

    /// An annotation view changed its frame, offset or content: its bitmap is redrawn once per
    /// run loop pass.
    func annotationViewDidChange(_ view: MLNAnnotationView) {
        pendingMarkerRefresh.insert(ObjectIdentifier(view))
        guard !markerRefreshScheduled else { return }
        markerRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.markerRefreshScheduled = false
            let pending = self.pendingMarkerRefresh
            self.pendingMarkerRefresh.removeAll()
            for entry in self.markers.values {
                guard let view = entry.view, pending.contains(ObjectIdentifier(view)) else { continue }
                self.renderMarker(entry)
            }
        }
    }

    private static let defaultPin: UIImage = {
        let size = CGSize(width: 30, height: 42)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let c = context.cgContext
            let path = UIBezierPath()
            let radius: CGFloat = 13
            let centre = CGPoint(x: size.width / 2, y: radius + 2)
            path.addArc(withCenter: centre, radius: radius, startAngle: .pi * 0.8,
                        endAngle: .pi * 0.2, clockwise: true)
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height - 1))
            path.close()
            c.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                        color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor(red: 0.85, green: 0.19, blue: 0.15, alpha: 1).setFill()
            path.fill()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(red: 0.45, green: 0.05, blue: 0.04, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: centre.x - 4.5, y: centre.y - 4.5, width: 9, height: 9)).fill()
        }
    }()

    private func scheduleShapes() {
        guard !shapesScheduled else { return }
        shapesScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.shapesScheduled = false
            self.sendShapes()
        }
    }

    private func sendShapes() {
        var features: [[String: Any]] = []
        for annotation in annotationList where Self.isShapeAnnotation(annotation) {
            guard let shape = annotation as? MLNShape, let geometry = shape.geoJSONGeometry() else { continue }
            var properties: [String: Any] = [
                "stroke": WebMapJSON.color(delegate?.mapView(self, strokeColorForShapeAnnotation: shape) ?? .black),
                "alpha": Double(delegate?.mapView(self, alphaForShapeAnnotation: shape) ?? 1),
            ]
            if let line = shape as? MLNPolyline {
                properties["width"] = Double(delegate?.mapView(self, lineWidthForPolylineAnnotation: line) ?? 3)
            }
            if let polygon = shape as? MLNPolygon {
                properties["fill"] = WebMapJSON.color(
                    delegate?.mapView(self, fillColorForPolygonAnnotation: polygon)
                        ?? UIColor.systemBlue.withAlphaComponent(0.2))
                properties["width"] = 1.0
            }
            features.append(["type": "Feature", "geometry": geometry, "properties": properties])
        }
        webSend(["op": "shapes", "data": ["type": "FeatureCollection", "features": features]])
    }

    // MARK: - User location

    func setUserTrackingMode(_ mode: MLNUserTrackingMode, animated: Bool,
                             completionHandler: (() -> Void)?) {
        let changed = mode != trackingMode
        trackingMode = mode
        if mode != .none && !showsUserLocation {
            showsUserLocation = true
        }
        updateLocationServices()
        if changed {
            delegate?.mapView(self, didChange: mode, animated: animated)
        }
        if mode != .none, let location = userLocation?.location {
            follow(location, animated: animated, entering: changed)
        }
        completionHandler?()
    }

    private func follow(_ location: CLLocation, animated: Bool, entering: Bool) {
        var bearing: Double?
        switch trackingMode {
        case .followWithHeading:
            if let heading = userLocation?.heading {
                bearing = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            }
        case .followWithCourse:
            if location.course >= 0 { bearing = location.course }
        default:
            break
        }
        let zoom: Double? = entering && mirrorZoom < 14 ? 15 : nil
        moveCamera(center: location.coordinate, zoom: zoom, bearing: bearing,
                   duration: animated ? Self.animationDuration : 0)
    }

    private func updateLocationServices() {
        let wanted = showsUserLocation || trackingMode != .none
        guard wanted || locationManagerStorage != nil else { return }
        let status = locationManager.authorizationStatus
        let authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        if wanted && authorized {
            userLocation?.isUpdating = true
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
        } else {
            userLocation?.isUpdating = false
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
        }
    }

    private func sendUserLocation() {
        guard showsUserLocation, let location = userLocation?.location else {
            webSend(["op": "user", "visible": false])
            return
        }
        var heading = -1.0
        if let reading = userLocation?.heading {
            heading = reading.trueHeading >= 0 ? reading.trueHeading : reading.magneticHeading
        } else if location.course >= 0 {
            heading = location.course
        }
        webSend([
            "op": "user", "visible": true,
            "lng": location.coordinate.longitude, "lat": location.coordinate.latitude,
            "acc": max(0, location.horizontalAccuracy), "heading": heading,
        ])
    }
}

extension MLNMapView: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationServices()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard showsUserLocation, let location = locations.last else { return }
        if userLocation == nil { userLocation = MLNUserLocation() }
        userLocation?.location = location
        sendUserLocation()
        delegate?.mapView(self, didUpdate: userLocation)
        if trackingMode != .none {
            follow(location, animated: true, entering: false)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard showsUserLocation else { return }
        userLocation?.heading = newHeading
        sendUserLocation()
        if trackingMode == .followWithHeading, let location = userLocation?.location {
            follow(location, animated: true, entering: false)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension MLNMapView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

extension MLNMapView: WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The page lost its WebGL state with the process. A fresh document gets the whole model.
        for request in requests.values { request.cancel() }
        requests.removeAll()
        queryCallbacks.removeAll()
        loadPage()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // The document is loaded once from the bundle; the page never navigates anywhere else.
        decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
    }
}
