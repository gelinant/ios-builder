import CoreGraphics
import Foundation
import UIKit

/// A style-spec JSON value carried inside an `NSExpression` constant. Style properties read back
/// from a loaded style come back in this box, so a value saved and restored is the exact JSON.
final class MLNJSONBox: NSObject {
    let json: Any

    init(_ json: Any) {
        self.json = json
    }
}

/// A style-spec filter read back from a loaded style. It can be combined with ordinary predicates
/// in an `NSCompoundPredicate`; the converter writes its JSON unchanged.
final class MLNJSONPredicate: NSPredicate {
    let json: Any

    init(json: Any) {
        self.json = json
        super.init()
    }

    required init?(coder: NSCoder) {
        json = true
        super.init(coder: coder)
    }

    override func evaluate(with object: Any?) -> Bool {
        false
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        self
    }

    override var predicateFormat: String {
        "MLNJSONPredicate"
    }
}

extension NSExpression {
    /// A raw style-spec expression, MapLibre Native's `NSExpression(mglJSONObject:)`.
    static func mglJSON(_ object: Any) -> NSExpression {
        NSExpression(forConstantValue: MLNJSONBox(object))
    }

    /// The style-spec JSON of this expression.
    var mglJSONObject: Any {
        WebMapJSON.expression(self, topLevel: true)
    }
}

/// `NSExpression` and `NSPredicate` to MapLibre style-spec JSON. Covers what the app builds:
/// constants (numbers, strings, colors, vectors, arrays), key paths, conditionals, arithmetic
/// functions, comparisons, `IN` and compound predicates.
enum WebMapJSON {
    static func expression(_ expression: NSExpression?, topLevel: Bool) -> Any {
        guard let expression else { return NSNull() }
        switch expression.expressionType {
        case .constantValue:
            return value(expression.constantValue, topLevel: topLevel)
        case .keyPath:
            return keyPath(expression.keyPath)
        case .variable:
            return variable(expression.variable)
        case .conditional:
            return [
                "case",
                filter(expression.predicate),
                self.expression(expression.true, topLevel: false),
                self.expression(expression.false, topLevel: false),
            ]
        case .function:
            return function(expression)
        case .aggregate:
            let members = (expression.collection as? [Any] ?? []).map { member -> Any in
                if let nested = member as? NSExpression {
                    return self.expression(nested, topLevel: true)
                }
                return value(member, topLevel: true)
            }
            return topLevel ? members : ["literal", members]
        default:
            return NSNull()
        }
    }

    private static func keyPath(_ path: String) -> Any {
        switch path {
        case "$zoomLevel", "zoomLevel": return ["zoom"]
        case "$featureIdentifier": return ["id"]
        case "$geometryType": return ["geometry-type"]
        case "$featureAttributes": return ["properties"]
        default: return ["get", path]
        }
    }

    private static func variable(_ name: String) -> Any {
        switch name {
        case "zoomLevel": return ["zoom"]
        case "featureIdentifier": return ["id"]
        case "geometryType": return ["geometry-type"]
        case "featureAttributes": return ["properties"]
        case "lineProgress": return ["line-progress"]
        case "heatmapDensity": return ["heatmap-density"]
        default: return ["var", name]
        }
    }

    private static func function(_ expression: NSExpression) -> Any {
        let arguments = (expression.arguments ?? []).map { self.expression($0, topLevel: false) }
        switch expression.function {
        case "multiply:by:": return ["*"] + arguments
        case "add:to:": return ["+"] + arguments
        case "from:subtract:": return ["-"] + arguments
        case "divide:by:": return ["/"] + arguments
        case "modulus:by:": return ["%"] + arguments
        case "abs:": return ["abs"] + arguments
        case "sqrt:": return ["sqrt"] + arguments
        case "raise:toPower:": return ["^"] + arguments
        case "ceiling:": return ["ceil"] + arguments
        case "floor:": return ["floor"] + arguments
        case "uppercase:": return ["upcase"] + arguments
        case "lowercase:": return ["downcase"] + arguments
        case "mgl_join:": return ["concat"] + arguments
        case "max:": return ["max"] + arguments
        case "min:": return ["min"] + arguments
        default: return arguments.first ?? NSNull()
        }
    }

    static func value(_ value: Any?, topLevel: Bool) -> Any {
        guard let value else { return NSNull() }
        switch value {
        case let box as MLNJSONBox:
            return box.json
        case let expression as NSExpression:
            return self.expression(expression, topLevel: topLevel)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            let double = number.doubleValue
            return double.isFinite ? number : 0
        case let text as String:
            return text
        case let color as UIColor:
            return self.color(color)
        case let nsValue as NSValue:
            let type = String(cString: nsValue.objCType)
            if type.contains("CGVector") {
                let vector = nsValue.cgVectorValue
                let pair: [Any] = [Double(vector.dx), Double(vector.dy)]
                return topLevel ? pair : ["literal", pair]
            }
            if type.contains("CGPoint") {
                let point = nsValue.cgPointValue
                let pair: [Any] = [Double(point.x), Double(point.y)]
                return topLevel ? pair : ["literal", pair]
            }
            if type.contains("UIEdgeInsets") {
                let insets = nsValue.uiEdgeInsetsValue
                let list: [Any] = [Double(insets.top), Double(insets.right),
                                   Double(insets.bottom), Double(insets.left)]
                return topLevel ? list : ["literal", list]
            }
            return NSNull()
        case let array as [Any]:
            let members = array.map { self.value($0, topLevel: true) }
            return topLevel ? members : ["literal", members]
        case let dictionary as [String: Any]:
            var out: [String: Any] = [:]
            for (key, member) in dictionary { out[key] = self.value(member, topLevel: true) }
            return topLevel ? out : ["literal", out]
        case is NSNull:
            return NSNull()
        default:
            return String(describing: value)
        }
    }

    /// CSS `rgba()`, which every style-spec color property accepts. Dynamic colors resolve with
    /// the current trait collection, as MapLibre Native did when the value was set.
    static func color(_ color: UIColor) -> String {
        let resolved = color.resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            if resolved.getWhite(&white, alpha: &alpha) {
                red = white
                green = white
                blue = white
            }
        }
        func channel(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        let a = Double(max(0, min(1, alpha)))
        return "rgba(\(channel(red)),\(channel(green)),\(channel(blue)),\(String(format: "%.3f", a)))"
    }

    // MARK: - Predicates

    static func filter(_ predicate: NSPredicate?) -> Any {
        guard let predicate else { return true }
        if let json = predicate as? MLNJSONPredicate {
            return json.json
        }
        if let compound = predicate as? NSCompoundPredicate {
            let members = (compound.subpredicates as? [NSPredicate] ?? []).map(filter)
            switch compound.compoundPredicateType {
            case .and: return ["all"] + members
            case .or: return ["any"] + members
            case .not: return ["!", members.first ?? true]
            @unknown default: return true
            }
        }
        if let comparison = predicate as? NSComparisonPredicate {
            return self.comparison(comparison)
        }
        switch predicate.predicateFormat {
        case "TRUEPREDICATE": return true
        case "FALSEPREDICATE": return false
        default: return true
        }
    }

    private static func comparison(_ predicate: NSComparisonPredicate) -> Any {
        let left = expression(predicate.leftExpression, topLevel: false)
        let right = expression(predicate.rightExpression, topLevel: false)
        switch predicate.predicateOperatorType {
        case .equalTo: return ["==", left, right]
        case .notEqualTo: return ["!=", left, right]
        case .lessThan: return ["<", left, right]
        case .lessThanOrEqualTo: return ["<=", left, right]
        case .greaterThan: return [">", left, right]
        case .greaterThanOrEqualTo: return [">=", left, right]
        case .in:
            return ["in", left, right]
        case .contains:
            return ["in", right, left]
        case .between:
            if let bounds = right as? [Any], bounds.count == 2,
               let pair = bounds[1] as? [Any], pair.count == 2 {
                return ["all", [">=", left, pair[0]], ["<=", left, pair[1]]]
            }
            return true
        default:
            return true
        }
    }
}
