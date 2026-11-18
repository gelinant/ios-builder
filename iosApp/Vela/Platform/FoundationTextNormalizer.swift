import Foundation
import VelaCore

/// The `TextNormalizer` seam over Foundation's Unicode mappings.
final class FoundationTextNormalizer: NSObject, TextNormalizer {
    func normalize(text: String, form: NormalForm) -> String {
        if form == .nfd {
            return text.decomposedStringWithCanonicalMapping
        } else if form == .nfkc {
            return text.precomposedStringWithCompatibilityMapping
        } else if form == .nfkd {
            return text.decomposedStringWithCompatibilityMapping
        }
        return text.precomposedStringWithCanonicalMapping
    }
}
