import CoreLocation
import MapLibre
import UIKit

/// One drawn stretch of the active navigation route. `level` is -1 for the traveled part, 0 for
/// free flow and Google's own 1..3 congestion grades for the road ahead.
struct NavRoutePiece {
    let level: Int
    let coordinates: [CLLocationCoordinate2D]
}

/// The next maneuver's arrow and the one after it. `kind` is the shared `ManeuverType` name, so
/// the glyph comes from the same `StepsSheet.symbol` the banner uses.
struct NavRouteArrow {
    let role: String
    let kind: String
    let coordinate: CLLocationCoordinate2D
    let rotation: Double
}

/// One lane glyph of the approach, left lane first, pointing along the approach bearing.
struct NavRouteLane {
    let indications: [String]
    let valid: Bool
    let coordinate: CLLocationCoordinate2D
    let rotation: Double
}

/// Everything the navigation map paints. An empty value clears the whole group, so leaving the
/// drive cannot leave a stale line behind.
struct NavRouteDraw {
    var pieces: [NavRoutePiece] = []
    var arrows: [NavRouteArrow] = []
    var lanes: [NavRouteLane] = []

    static let empty = NavRouteDraw()
}

/// The routes on the map: alternates faded under the selected one, its live traffic stretches on
/// top, and the trip's two ends and intermediate stops (SPEC 4.8, the preview's colors on the light map). Above the roads
/// and bridges, under the labels.
///
/// The navigation group lives here too: the traveled and congestion pieces, the road-ahead arrows
/// and the lane row. Its casing and line sit in the same band as the preview line, so the painted
/// road marks the style inserts there still draw over them; the arrows and lanes go above that
/// band when they are first needed, under the labels.
final class RouteLayers {
    static let altLayer = "vela-route-alt"

    static let navCasingLayer = "vela-nav-casing"
    static let navTraveledLayer = "vela-nav-traveled"
    static let navArrowLayer = "vela-nav-arrow"
    static let navLaneLayer = "vela-nav-lane"
    /// The short-lived step preview highlight. It is a decoration over the route, so a tap
    /// passes through to the line under it.
    static let stepFocusLayer = "vela-step-focus"

    /// The nav group's symbol layers are decoration, not routes: MAP-TAP leaves their taps to
    /// the line under them, while every line layer stays a route target.
    static let navigationSymbolIdentifiers: Set<String> = [navArrowLayer, navLaneLayer]

    /// Every style layer identifier this class can add. MAP-TAP reads it for its audit.
    static let layerIdentifiers = [
        altLayer, "vela-route-alt-edge", "vela-route-casing", "vela-route-selected",
        "vela-route-traffic-1", "vela-route-traffic-2", "vela-route-traffic-3",
        "vela-route-ends",
        navCasingLayer, navTraveledLayer, "vela-nav-free", "vela-nav-slow", "vela-nav-heavy",
        "vela-nav-severe", navArrowLayer, navLaneLayer, stepFocusLayer,
    ]

    private static let altSource = "vela-route-alt"
    private static let selectedSource = "vela-route-selected"
    private static let trafficSource = "vela-route-traffic"
    private static let endsSource = "vela-route-ends"
    private static let navPieceSource = "vela-nav-piece"
    private static let navArrowSource = "vela-nav-arrow"
    private static let navLaneSource = "vela-nav-lane"
    private static let stepFocusSource = "vela-step-focus"

    private var lines: [RouteLine] = []
    private var selected = -1
    private var ends: (CLLocationCoordinate2D, CLLocationCoordinate2D)?
    private var stops: [CLLocationCoordinate2D] = []
    private var navigation = NavRouteDraw.empty
    private var stepFocus: [CLLocationCoordinate2D] = []
    private var navSymbolsInserted = false
    private var navStyle: ObjectIdentifier?

    func set(_ lines: [RouteLine], selected: Int, on style: MLNStyle?) {
        self.lines = lines
        self.selected = selected
        let active = lines.first(where: { $0.index == selected }) ?? lines.first
        if let first = active?.coordinates.first, let last = active?.coordinates.last {
            ends = (first, last)
        } else {
            ends = nil
        }
        stops = active?.stops ?? []
        if let style { apply(to: style) }
    }

    /// The navigation render: pieces colored by level, the road-ahead arrows and the lane row.
    /// Passing nil clears every nav source; the preview layers are untouched.
    func setNavigation(_ draw: NavRouteDraw?, on style: MLNStyle?) {
        navigation = draw ?? .empty
        guard let style else { return }
        ensureLayers(in: style)
        updateNavigation(style)
    }

    /// The short-lived highlight on the stretch leading to a tapped step. An empty list clears
    /// it; the layer stays in the style but draws nothing.
    func setStepFocus(_ coordinates: [CLLocationCoordinate2D], on style: MLNStyle?) {
        stepFocus = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard let style else { return }
        ensureLayers(in: style)
        updateStepFocus(style)
    }

    /// Re-adds the layers after a style load.
    func apply(to style: MLNStyle) {
        ensureLayers(in: style)
        updatePreview(style)
        updateNavigation(style)
        updateStepFocus(style)
    }

    private func updatePreview(_ style: MLNStyle) {
        let alt: [MLNShape & MLNFeature] = lines.filter { $0.index != selected && $0.coordinates.count >= 2 }.map { line -> (MLNShape & MLNFeature) in
            var coords = line.coordinates
            let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            f.attributes = ["index": line.index]
            return f
        }
        (style.source(withIdentifier: Self.altSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: alt)

        var picked: [MLNShape & MLNFeature] = []
        var traffic: [MLNShape & MLNFeature] = []
        if let line = lines.first(where: { $0.index == selected }), line.coordinates.count >= 2 {
            var coords = line.coordinates
            picked.append(MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count)))
            for t in line.traffic where t.coordinates.count >= 2 {
                var tc = t.coordinates
                let f = MLNPolylineFeature(coordinates: &tc, count: UInt(tc.count))
                f.attributes = ["level": t.level]
                traffic.append(f)
            }
        }
        (style.source(withIdentifier: Self.selectedSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: picked)
        (style.source(withIdentifier: Self.trafficSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: traffic)

        var points: [MLNShape & MLNFeature] = []
        if let ends {
            let start = MLNPointFeature()
            start.coordinate = ends.0
            start.attributes = ["end": 0]
            let stop = MLNPointFeature()
            stop.coordinate = ends.1
            stop.attributes = ["end": 1]
            points = [start, stop]
        }
        for coordinate in stops {
            let point = MLNPointFeature()
            point.coordinate = coordinate
            point.attributes = ["end": 2]
            points.append(point)
        }
        (style.source(withIdentifier: Self.endsSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: points)
    }

    /// The nav group's three sources. Every piece carries `index` 0, so a tap that lands on one
    /// still reaches the existing route-selection handler, exactly like the preview line.
    private func updateNavigation(_ style: MLNStyle) {
        var pieces: [MLNShape & MLNFeature] = []
        for piece in navigation.pieces where piece.coordinates.count >= 2 {
            var coords = piece.coordinates
            let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            f.attributes = ["level": piece.level, "index": 0]
            pieces.append(f)
        }
        (style.source(withIdentifier: Self.navPieceSource) as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: pieces)

        var arrows: [MLNShape & MLNFeature] = []
        for arrow in navigation.arrows {
            let f = MLNPointFeature()
            f.coordinate = arrow.coordinate
            f.attributes = [
                "icon": Self.arrowImageName(arrow.kind),
                "role": arrow.role,
                "rot": arrow.rotation,
                "index": 0,
            ]
            arrows.append(f)
        }
        (style.source(withIdentifier: Self.navArrowSource) as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: arrows)

        var lanes: [MLNShape & MLNFeature] = []
        for lane in navigation.lanes {
            let f = MLNPointFeature()
            f.coordinate = lane.coordinate
            f.attributes = [
                "icon": Self.laneImageName(lane.indications, valid: lane.valid),
                "rot": lane.rotation,
                "valid": lane.valid ? 1 : 0,
                "index": 0,
            ]
            lanes.append(f)
        }
        (style.source(withIdentifier: Self.navLaneSource) as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: lanes)
        // A style load recreates the layers below the painted road; the first arrows put their
        // layers above that band, once, so the glyphs are not hidden under lane dashes.
        raiseSymbols(in: style)
    }

    /// The step preview's one line. It is rebuilt in place, never appended, so a second tap
    /// replaces the first stretch instead of stacking them.
    private func updateStepFocus(_ style: MLNStyle) {
        var shapes: [MLNShape & MLNFeature] = []
        if stepFocus.count >= 2 {
            var coords = stepFocus
            shapes.append(MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count)))
        }
        (style.source(withIdentifier: Self.stepFocusSource) as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: shapes)
    }

    private func ensureLayers(in style: MLNStyle) {
        let key = ObjectIdentifier(style)
        if navStyle != key {
            navStyle = key
            navSymbolsInserted = false
        }
        guard style.source(withIdentifier: Self.altSource) == nil else {
            Self.registerImages(in: style)
            return
        }
        let alt = MLNShapeSource(identifier: Self.altSource, shape: nil, options: nil)
        let sel = MLNShapeSource(identifier: Self.selectedSource, shape: nil, options: nil)
        let traffic = MLNShapeSource(identifier: Self.trafficSource, shape: nil, options: nil)
        let endsSource = MLNShapeSource(identifier: Self.endsSource, shape: nil, options: nil)
        let navPieces = MLNShapeSource(identifier: Self.navPieceSource, shape: nil, options: nil)
        let navArrows = MLNShapeSource(identifier: Self.navArrowSource, shape: nil, options: nil)
        let navLanes = MLNShapeSource(identifier: Self.navLaneSource, shape: nil, options: nil)
        let stepFocusSource = MLNShapeSource(identifier: Self.stepFocusSource, shape: nil, options: nil)
        [alt, sel, traffic, endsSource, navPieces, navArrows, navLanes, stepFocusSource]
            .forEach { style.addSource($0) }
        Self.registerImages(in: style)

        let altLine = line("vela-route-alt", alt, color: UIColor(rgb: 0x7FA9F0), width: 6.3)
        let altEdge = line("vela-route-alt-edge", alt, color: UIColor(rgb: 0x3566C4), width: 1.6)
        altEdge.lineGapWidth = NSExpression(forConstantValue: 6.3)
        let casing = line("vela-route-casing", sel, color: UIColor(rgb: 0x1A57C2), width: 9)
        let main = line("vela-route-selected", sel, color: UIColor(rgb: 0x2F7BF0), width: 6.5)
        var layers: [MLNStyleLayer] = [altLine, altEdge, casing, main]
        let levels: [(String, String, UInt32)] = [
            ("vela-route-traffic-1", "level == 1", 0xF2A33A),
            ("vela-route-traffic-2", "level == 2", 0xE5483B),
            ("vela-route-traffic-3", "level >= 3", 0x9E1C1C),
        ]
        for (id, predicate, rgb) in levels {
            let t = line(id, traffic, color: UIColor(rgb: rgb), width: 6.5)
            t.predicate = NSPredicate(format: predicate)
            layers.append(t)
        }
        let navCasing = line(Self.navCasingLayer, navPieces, color: UIColor(rgb: 0x14509E), width: 10)
        let navTraveled = line(Self.navTraveledLayer, navPieces, color: UIColor(rgb: 0x9AA0A6), width: 7)
        navTraveled.predicate = NSPredicate(format: "level == -1")
        let navFree = line("vela-nav-free", navPieces, color: UIColor(rgb: 0x2F7BF0), width: 7)
        navFree.predicate = NSPredicate(format: "level == 0")
        let navSlow = line("vela-nav-slow", navPieces, color: UIColor(rgb: 0xF2A33A), width: 7)
        navSlow.predicate = NSPredicate(format: "level == 1")
        let navHeavy = line("vela-nav-heavy", navPieces, color: UIColor(rgb: 0xE5483B), width: 7)
        navHeavy.predicate = NSPredicate(format: "level == 2")
        let navSevere = line("vela-nav-severe", navPieces, color: UIColor(rgb: 0x9E1C1C), width: 7)
        navSevere.predicate = NSPredicate(format: "level >= 3")
        layers.append(contentsOf: [navCasing, navTraveled, navFree, navSlow, navHeavy, navSevere])

        let arrow = MLNSymbolStyleLayer(identifier: Self.navArrowLayer, source: navArrows)
        arrow.iconImageName = NSExpression(forKeyPath: "icon")
        arrow.iconScale = NSExpression(
            forConditional: NSPredicate(format: "role == 'next'"),
            trueExpression: NSExpression(forConstantValue: 0.9),
            falseExpression: NSExpression(forConstantValue: 0.62))
        arrow.iconRotation = NSExpression(forKeyPath: "rot")
        arrow.iconRotationAlignment = NSExpression(forConstantValue: "map")
        arrow.iconPitchAlignment = NSExpression(forConstantValue: "map")
        arrow.iconAllowsOverlap = NSExpression(forConstantValue: true)
        arrow.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        layers.append(arrow)

        let lane = MLNSymbolStyleLayer(identifier: Self.navLaneLayer, source: navLanes)
        lane.iconImageName = NSExpression(forKeyPath: "icon")
        lane.iconScale = NSExpression(forConstantValue: 0.62)
        lane.iconRotation = NSExpression(forKeyPath: "rot")
        lane.iconRotationAlignment = NSExpression(forConstantValue: "map")
        lane.iconPitchAlignment = NSExpression(forConstantValue: "map")
        lane.iconAllowsOverlap = NSExpression(forConstantValue: true)
        lane.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        layers.append(lane)

        let endsLayer = MLNCircleStyleLayer(identifier: "vela-route-ends", source: endsSource)
        endsLayer.circleRadius = NSExpression(forConstantValue: 7)
        endsLayer.circleColor = NSExpression(
            forConditional: NSPredicate(format: "end == 2"),
            trueExpression: NSExpression(forConstantValue: UIColor(rgb: 0xF2A33A)),
            falseExpression: NSExpression(
                forConditional: NSPredicate(format: "end == 1"),
                trueExpression: NSExpression(forConstantValue: UIColor(rgb: 0xD93025)),
                falseExpression: NSExpression(forConstantValue: UIColor.white)))
        endsLayer.circleStrokeColor = NSExpression(
            forConditional: NSPredicate(format: "end != 0"),
            trueExpression: NSExpression(forConstantValue: UIColor.white),
            falseExpression: NSExpression(forConstantValue: UIColor(rgb: 0x1A57C2)))
        endsLayer.circleStrokeWidth = NSExpression(forConstantValue: 3)
        layers.append(endsLayer)

        let focus = line(Self.stepFocusLayer, stepFocusSource, color: UIColor(rgb: 0xFFB300), width: 11)
        focus.lineOpacity = NSExpression(forConstantValue: 0.92)
        layers.append(focus)

        if let below = labelLayer(in: style) {
            for layer in layers { style.insertLayer(layer, below: below) }
        } else {
            for layer in layers { style.addLayer(layer) }
        }
    }

    /// Moves the two symbol layers above the painted road marks, once per style. They are
    /// decoration on top of the line, and lane dashes must not cut through their glyphs.
    private func raiseSymbols(in style: MLNStyle) {
        guard !navSymbolsInserted else { return }
        guard style.layer(withIdentifier: Self.navArrowLayer) != nil,
              let anchor = labelLayer(in: style),
              let paintTop = style.layers.last(where: { $0.identifier.hasPrefix("vela-paint") })
        else { return }
        navSymbolsInserted = true
        for layer in style.layers where layer.identifier == Self.navArrowLayer
            || layer.identifier == Self.navLaneLayer {
            style.removeLayer(layer)
        }
        for identifier in [Self.navArrowLayer, Self.navLaneLayer] {
            let source = style.source(withIdentifier: identifier == Self.navArrowLayer
                ? Self.navArrowSource : Self.navLaneSource)
            guard let source else { continue }
            let layer: MLNStyleLayer
            if identifier == Self.navArrowLayer {
                layer = makeArrowLayer(source: source)
            } else {
                layer = makeLaneLayer(source: source)
            }
            if style.layer(withIdentifier: paintTop.identifier) != nil {
                style.insertLayer(layer, above: paintTop)
            } else {
                style.insertLayer(layer, below: anchor)
            }
        }
    }

    private func line(_ id: String, _ source: MLNSource, color: UIColor, width: Double) -> MLNLineStyleLayer {
        let l = MLNLineStyleLayer(identifier: id, source: source)
        l.lineColor = NSExpression(forConstantValue: color)
        l.lineWidth = NSExpression(forConstantValue: width)
        l.lineCap = NSExpression(forConstantValue: "round")
        l.lineJoin = NSExpression(forConstantValue: "round")
        return l
    }

    private func makeArrowLayer(source: MLNSource) -> MLNStyleLayer {
        let arrow = MLNSymbolStyleLayer(identifier: Self.navArrowLayer, source: source)
        arrow.iconImageName = NSExpression(forKeyPath: "icon")
        arrow.iconScale = NSExpression(
            forConditional: NSPredicate(format: "role == 'next'"),
            trueExpression: NSExpression(forConstantValue: 0.9),
            falseExpression: NSExpression(forConstantValue: 0.62))
        arrow.iconRotation = NSExpression(forKeyPath: "rot")
        arrow.iconRotationAlignment = NSExpression(forConstantValue: "map")
        arrow.iconPitchAlignment = NSExpression(forConstantValue: "map")
        arrow.iconAllowsOverlap = NSExpression(forConstantValue: true)
        arrow.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        return arrow
    }

    private func makeLaneLayer(source: MLNSource) -> MLNStyleLayer {
        let lane = MLNSymbolStyleLayer(identifier: Self.navLaneLayer, source: source)
        lane.iconImageName = NSExpression(forKeyPath: "icon")
        lane.iconScale = NSExpression(forConstantValue: 0.62)
        lane.iconRotation = NSExpression(forKeyPath: "rot")
        lane.iconRotationAlignment = NSExpression(forConstantValue: "map")
        lane.iconPitchAlignment = NSExpression(forConstantValue: "map")
        lane.iconAllowsOverlap = NSExpression(forConstantValue: true)
        lane.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        return lane
    }

    // MARK: - Glyphs

    /// The lane image for the lane's own first indication, bright or dim like the banner's cell.
    static func laneImageName(_ indications: [String], valid: Bool) -> String {
        let symbol = laneSymbol(indications.first ?? "")
        let key = laneKey(symbol)
        return "vela-nav-lane-\(key)-\(valid ? "valid" : "dim")"
    }

    private static func laneKey(_ symbol: String) -> String {
        switch symbol {
        case "arrow.turn.up.left": return "left"
        case "arrow.turn.up.right": return "right"
        case "arrow.up.left": return "sleft"
        case "arrow.up.right": return "sright"
        case "arrow.uturn.down": return "uturn"
        default: return "straight"
        }
    }

    /// The banner's lane arrow names, repeated here because the card's mapping is private to it.
    static func laneSymbol(_ arrow: String) -> String {
        switch arrow {
        case "left", "sharp left": return "arrow.turn.up.left"
        case "right", "sharp right": return "arrow.turn.up.right"
        case "slight left", "merge to left": return "arrow.up.left"
        case "slight right", "merge to right": return "arrow.up.right"
        case "uturn": return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }

    /// One-time per style: the arrow and lane images an in-memory symbol layer names. They are
    /// drawn at launch, so no sprite download is needed and an offline style still shows them.
    static func registerImages(in style: MLNStyle) {
        for kind in arrowKinds where style.image(forName: arrowImageName(kind)) == nil {
            let symbol = StepsSheet.symbol(kind)
            style.setImage(
                glyph(symbol: symbol, fill: 0x2F7BF0, tint: .white, circle: true),
                forName: arrowImageName(kind))
        }
        for symbol in laneSymbols {
            let bright = "vela-nav-lane-\(laneKey(symbol))-valid"
            let dim = "vela-nav-lane-\(laneKey(symbol))-dim"
            if style.image(forName: bright) == nil {
                style.setImage(
                    glyph(symbol: symbol, fill: 0x2F7BF0, tint: .white, circle: false),
                    forName: bright)
            }
            if style.image(forName: dim) == nil {
                style.setImage(
                    glyph(symbol: symbol, fill: 0xE8EAED, tint: UIColor(rgb: 0x5F6368), circle: false),
                    forName: dim)
            }
        }
    }

    private static let laneSymbols = [
        "arrow.up", "arrow.up.left", "arrow.up.right", "arrow.turn.up.left",
        "arrow.turn.up.right", "arrow.uturn.down",
    ]

    private static let arrowKinds = [
        "DEPART", "ARRIVE", "CONTINUE", "STRAIGHT",
        "TURN_LEFT", "SHARP_LEFT", "TURN_RIGHT", "SHARP_RIGHT",
        "SLIGHT_LEFT", "KEEP_LEFT", "FORK_LEFT", "RAMP_LEFT",
        "SLIGHT_RIGHT", "KEEP_RIGHT", "FORK_RIGHT", "RAMP_RIGHT",
        "UTURN", "MERGE", "ROUNDABOUT", "EXIT_ROUNDABOUT",
    ]

    /// The banner's own `StepsSheet.symbol` name for a known kind, and the straight arrow for one
    /// this build does not know, so the map can never draw a different symbol than the card.
    static func arrowImageName(_ kind: String) -> String {
        "vela-nav-arrow-" + (arrowKinds.contains(kind) ? kind : "STRAIGHT")
    }

    private static func glyph(symbol: String, fill: UInt32, tint: UIColor, circle: Bool) -> UIImage {
        let size: CGFloat = 52
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let background = circle
                ? UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: size - 12, height: size - 12))
                : UIBezierPath(roundedRect: CGRect(x: 7, y: 7, width: size - 14, height: size - 14),
                               cornerRadius: 9)
            UIColor(rgb: fill).setFill()
            background.fill()
            let configuration = UIImage.SymbolConfiguration(
                pointSize: size * 0.5, weight: .bold)
            guard let symbolImage = UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(tint, renderingMode: .alwaysOriginal) else { return }
            let box = size * 0.62
            symbolImage.draw(in: CGRect(x: (size - box) / 2, y: (size - box) / 2,
                                        width: box, height: box))
        }
    }

    /// The first symbol layer after the last bridge layer (SPEC 4.8), else the first symbol layer.
    private func labelLayer(in style: MLNStyle) -> MLNStyleLayer? {
        let all = style.layers
        let lastBridge = all.lastIndex(where: { $0.identifier.hasPrefix("bridge") }) ?? -1
        return all[(lastBridge + 1)...].first(where: { $0 is MLNSymbolStyleLayer })
            ?? all.first(where: { $0 is MLNSymbolStyleLayer })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
