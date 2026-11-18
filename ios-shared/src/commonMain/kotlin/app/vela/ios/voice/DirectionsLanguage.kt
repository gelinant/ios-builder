package app.vela.ios.voice

import app.vela.core.voice.PiperCatalog

/** The language parts `NavStringsRegistry.setLanguage` needs, kept as strings for Swift. */
data class NavLanguageParts(
    val language: String,
    val region: String,
    val script: String,
)

/**
 * The guidance language, which can differ from the menus as on Android (`directions_language`).
 * The rules are pure: an explicit choice wins, otherwise the app language, otherwise English,
 * because the shared navigation tables only exist for [supportedTags].
 *
 * Portuguese and Chinese are the two languages where the region or the script changes the table,
 * so the tag keeps them: `pt` is Portugal, `pt-br` Brazil, `zh` Simplified, `zh-tw` Traditional.
 */
object DirectionsLanguage {
    /** Android's key in `vela_settings`. */
    const val KEY = "directions_language"

    /** The empty choice follows the app language. */
    const val FOLLOW_APP = ""

    val supportedTags: List<String> = listOf(
        "en", "fr", "de", "es", "it", "pt", "pt-br", "nl", "ru",
        "pl", "sv", "uk", "hu", "ro", "zh", "zh-tw", "ja", "he",
    )

    private val labels = mapOf(
        "en" to "English",
        "fr" to "Français",
        "de" to "Deutsch",
        "es" to "Español",
        "it" to "Italiano",
        "pt" to "Português",
        "pt-br" to "Português (Brasil)",
        "nl" to "Nederlands",
        "ru" to "Русский",
        "pl" to "Polski",
        "sv" to "Svenska",
        "uk" to "Українська",
        "hu" to "Magyar",
        "ro" to "Română",
        "zh" to "中文",
        "zh-tw" to "繁體中文",
        "ja" to "日本語",
        "he" to "עברית",
    )

    /**
     * A preference or locale tag as one of the guidance keys: `en-GB` is English, `pt-BR` is
     * Brazilian Portuguese, `zh-Hant` is Traditional Chinese. An empty result means the tag cannot
     * name a navigation table, not that it is English.
     */
    fun normalize(tag: String?): String {
        val parts = tag
            ?.trim()
            ?.replace('_', '-')
            ?.split('-')
            ?.filter { it.isNotEmpty() }
            ?: return ""
        if (parts.isEmpty()) return ""
        val language = when (parts[0].lowercase()) {
            "iw" -> "he"
            else -> parts[0].lowercase()
        }
        val region = parts.drop(1).firstOrNull { it.length == 2 || it.length == 3 }?.uppercase() ?: ""
        val script = parts.drop(1).firstOrNull { it.length == 4 }?.lowercase() ?: ""
        return when (language) {
            "pt" -> if (region == "BR") "pt-br" else "pt"
            "zh" -> if (script == "hant" || region in setOf("TW", "HK", "MO")) "zh-tw" else "zh"
            else -> language
        }
    }

    /** The explicit choice when supported, otherwise the app language, otherwise English. */
    fun effectiveTag(configured: String?, appTag: String, systemTag: String): String {
        val explicit = normalize(configured)
        if (explicit in supportedTags) return explicit
        val app = normalize(if (appTag.isBlank()) systemTag else appTag)
        return if (app in supportedTags) app else "en"
    }

    /** True when a catalog voice can speak the guidance language (Japanese cannot). */
    fun hasNeuralVoice(tag: String): Boolean {
        val language = normalize(tag).substringBefore('-')
        return language.isNotEmpty() && PiperCatalog.hasVoiceFor(language)
    }

    /** The endonym shown in the picker, like the voice library's language headers. */
    fun label(tag: String): String {
        val normalized = normalize(tag)
        if (normalized.isEmpty()) return labels.getValue("en")
        return labels[normalized] ?: normalized.uppercase()
    }

    /** Picker order, for Swift. */
    fun tags(): List<String> = supportedTags

    /** The registry arguments for [tag]; an unsupported tag keeps the English table. */
    fun parts(tag: String): NavLanguageParts {
        val normalized = normalize(tag).takeIf { it in supportedTags } ?: "en"
        return when (normalized) {
            "pt-br" -> NavLanguageParts("pt", "BR", "")
            "zh-tw" -> NavLanguageParts("zh", "TW", "Hant")
            "pt" -> NavLanguageParts("pt", "", "")
            "zh" -> NavLanguageParts("zh", "", "")
            else -> NavLanguageParts(normalized, "", "")
        }
    }

    /** The app language for voice search, which follows the menus, not the guidance choice. */
    fun appLanguage(tag: String?): String = normalize(tag).substringBefore('-').ifEmpty { "en" }
}
