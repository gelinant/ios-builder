package app.vela.ios.voice

import app.vela.core.voice.PiperCatalog

/**
 * Pure rules for picking the iOS spoken-guidance engine. The filesystem and sherpa-onnx live in
 * Swift; this object decides from plain values so JVM tests cover the fallback cases (no voice,
 * partial download, corrupt model, voice of another language) without a simulator.
 *
 * A Piper voice speaks one language. Its catalog id starts with `<lang>_<REGION>`, so the language
 * prefix must match the language the navigation text is generated in. When it does not, guidance
 * stays on AVSpeechSynthesizer instead of reading one language through another language's model.
 */
object IosVoiceSelection {
    const val NEURAL = "neural"
    const val SYSTEM = "system"

    /** Catalog ids in display order, so Swift needs no assumptions about Kotlin collection bridging. */
    fun catalogIds(): List<String> = PiperCatalog.ALL.map { it.id }

    fun recommendedId(language: String): String = PiperCatalog.defaultFor(languageOf(language)).id

    fun downloadUrl(id: String): String = PiperCatalog.downloadUrl(id)

    fun displayName(id: String): String = PiperCatalog.byId(id)?.displayName ?: id

    fun sizeMb(id: String): Int = PiperCatalog.byId(id)?.sizeMb ?: 0

    /** The language part of a Piper id (`en_US-hfc_female-medium` -> `en`) or of a locale tag. */
    fun languageOf(tagOrId: String): String =
        tagOrId.replace('_', '-').substringBefore('-').lowercase()

    /** A download is complete only when all three parts of a sherpa Piper directory exist. A
     *  half-extracted or corrupt directory is never offered. [entries] holds paths relative to the
     *  voice directory, with `/` separators. */
    fun isComplete(id: String, entries: Set<String>): Boolean =
        "$id.onnx" in entries && "tokens.txt" in entries &&
            entries.any { it == "espeak-ng-data" || it.startsWith("espeak-ng-data/") }

    /** The voice to load: the selection when it is installed and speaks [language], else the first
     *  installed voice of that language, else null. Never returns an id that is not installed. */
    fun effectiveVoiceId(installed: List<String>, selected: String?, language: String): String? {
        val lang = languageOf(language)
        val usable = installed.asSequence()
            .filter { languageOf(it) == lang }
            .sorted()
            .toList()
        selected?.let { if (it in usable) return it }
        return usable.firstOrNull()
    }

    /** Why [effectiveVoiceId] returned null, for the Settings row and the debug line. */
    fun fallbackReason(installed: List<String>, selected: String?, language: String): String? {
        if (effectiveVoiceId(installed, selected, language) != null) return null
        if (selected != null && selected in installed && languageOf(selected) != languageOf(language)) {
            return "voice-language"
        }
        if (installed.isNotEmpty()) return "language-missing"
        return "no-voice"
    }

    /** `neural` only when a complete installed voice matches the guidance language. */
    fun engine(installed: List<String>, selected: String?, language: String): String =
        if (effectiveVoiceId(installed, selected, language) != null) NEURAL else SYSTEM
}
