import Foundation
import VelaCore

/// One browsable Piper voice, mirrored from the shared Android catalog (`PiperCatalog` in
/// `:core-common`). The id is the single source of truth: it is the sherpa asset id, the on-disk
/// directory name and the `<id>.onnx` stem.
struct VoiceEntry: Identifiable, Hashable {
    let id: String

    var name: String { IosVoiceSelection.shared.displayName(id: id) }
    var sizeMb: Int { Int(IosVoiceSelection.shared.sizeMb(id: id)) }
    var language: String { IosVoiceSelection.shared.languageOf(tagOrId: id) }
    var downloadUrl: String { IosVoiceSelection.shared.downloadUrl(id: id) }
}

enum VoiceCatalog {
    /// Same order and ids as Android. Never duplicated by hand.
    static let all: [VoiceEntry] =
        IosVoiceSelection.shared.catalogIds().map { VoiceEntry(id: $0) }

    static func entry(_ id: String) -> VoiceEntry? {
        all.first { $0.id == id }
    }

    static func recommended(language: String) -> VoiceEntry? {
        entry(IosVoiceSelection.shared.recommendedId(language: language))
    }

    static func voices(language: String) -> [VoiceEntry] {
        all.filter { $0.language == IosVoiceSelection.shared.languageOf(tagOrId: language) }
    }

    static func languageLabel(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}
