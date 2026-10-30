package app.vela.ios.voice

import app.vela.core.search.VoiceCommandExamples
import app.vela.core.voice.AsrCatalog

/**
 * Which downloaded engine should run, as the pure rules Android's `AsrEngine.forRecognition`
 * applies: the user's pick when it is installed and speaks the language, else an installed Whisper
 * (the multilingual default), else the pick as a last resort. The installed set comes from the
 * filesystem in Swift, never from a stored list, so a partial download cannot be selected.
 *
 * Ids travel as strings because Swift reads this through [IosAsrCatalog] instead of the Kotlin enum.
 */
object AsrSelection {
    /** The user's pick when installed, else the first installed engine. */
    fun activeId(installed: List<String>, selected: String?): String? {
        val pick = AsrCatalog.byId(selected)
        if (pick != null && pick.id in installed) return pick.id
        return installed.firstOrNull { AsrCatalog.byId(it) != null }
    }

    /** The engine id to load for [lang], or null when no engine is installed. */
    fun forRecognition(installed: List<String>, selected: String?, lang: String): String? {
        val pick = AsrCatalog.byId(activeId(installed, selected)) ?: return null
        if (pick.supportsLanguage(lang)) return pick.id
        val whisper = AsrCatalog.entries.firstOrNull { it.id in installed && it.modelType == "whisper" }
        return (whisper ?: pick).id
    }
}

/**
 * A flat, string-based view of [AsrCatalog] for the Swift layer, the same shape as
 * `IosVoiceSelection`: Swift never touches a Kotlin enum, so the catalog can grow without a Swift
 * compile break, and the ids, sizes and URLs stay those of the Android release.
 */
object IosAsrCatalog {
    /** Catalog order, which is also the picker order. */
    fun ids(): List<String> = AsrCatalog.entries.map { it.id }

    fun displayName(id: String): String = AsrCatalog.byId(id)?.displayName ?: id
    fun modelType(id: String): String = AsrCatalog.byId(id)?.modelType ?: ""
    fun sizeMb(id: String): Int = AsrCatalog.byId(id)?.sizeMb ?: 0
    fun downloadUrl(id: String): String = AsrCatalog.byId(id)?.url ?: ""
    fun sha256(id: String): String = AsrCatalog.byId(id)?.sha256 ?: ""
    fun bytes(id: String): Long = AsrCatalog.byId(id)?.bytes ?: 0L

    /** Every file the installed check requires (the model, its tokens and Silero VAD). */
    fun files(id: String): List<String> = AsrCatalog.byId(id)?.files ?: emptyList()

    /** The Whisper file prefix (`tiny`), empty for another model family. */
    fun whisperPrefix(id: String): String = AsrCatalog.byId(id)?.whisperPrefix ?: ""

    /** The engine the voice-search offer downloads for [lang] (Whisper tiny for English). */
    fun defaultId(lang: String): String = AsrCatalog.defaultFor(lang).id
}

/**
 * The example commands shown while listening, from the shared `VoiceCommandExamples` table (the
 * same list Android shows, and the one `QueryIntentExamplesTest` proves the parser understands).
 */
object IosVoiceExamples {
    fun phrases(lang: String): List<String> =
        VoiceCommandExamples.forLanguage(lang).map { it.phrase }.take(5)
}
