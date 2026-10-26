package app.vela.ios.settings

import app.vela.core.data.ClockFormat
import app.vela.core.data.NoGoogle
import app.vela.core.i18n.NavStringsRegistry
import app.vela.core.platform.KeyValueStores
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The settings facet's serializable state. Empty language and "system" modes follow the device. */
data class SettingsState(
    val languageTag: String = "",
    val units: String = "system",
    val clockMode: String = "system",
    val imperial: Boolean = false,
    val use24h: Boolean = false,
)

/**
 * Language, units and clock settings, persisted through the same KeyValueStores as Android.
 * Construction is inert. [start] applies NoGoogle, NavStrings and ClockFormat before any request.
 * The offline facet owns the Google switch after startup; this class only reads its preference for
 * the early flag, so there is one writer and one piece of UI state for that switch.
 */
class SettingsStore(
    stores: KeyValueStores,
    private val deviceUse24h: Boolean,
    private val deviceImperial: Boolean,
    private val systemTag: () -> String = { "en" },
    private val languageOverride: String? = null,
) {
    private val settings = stores.open("vela_settings")
    private val unitSettings = stores.open("vela_units")

    private val _state = MutableStateFlow(SettingsState())
    val state: StateFlow<SettingsState> = _state.asStateFlow()

    val imperial: Boolean get() = state.value.imperial
    val use24h: Boolean get() = state.value.use24h

    private var started = false

    fun start() {
        if (started) return
        started = true
        NoGoogle.enabled = settings.getBoolean(GOOGLE_DISABLED_KEY, false)
        val language = normalizeLanguage(languageOverride)
            ?: normalizeLanguage(settings.getString(LANGUAGE_KEY, ""))
            ?: ""
        val units = normalizeMode(unitSettings.getString(UNITS_MODE_KEY, "system"), UNIT_MODES)
        val clock = normalizeMode(settings.getString(CLOCK_KEY, "system"), CLOCK_MODES)
        _state.value = SettingsState(
            languageTag = language,
            units = units,
            clockMode = clock,
            imperial = imperialFor(units),
            use24h = use24hFor(clock),
        )
        ClockFormat.use24h = state.value.use24h
        applyNavLanguage()
    }

    fun setLanguage(tag: String) {
        val normalized = normalizeLanguage(tag) ?: ""
        settings.edit().putString(LANGUAGE_KEY, normalized).apply()
        _state.value = state.value.copy(languageTag = normalized)
        applyNavLanguage()
    }

    fun setUnits(mode: String) {
        val normalized = normalizeMode(mode, UNIT_MODES)
        val imperial = imperialFor(normalized)
        unitSettings.edit()
            .putString(UNITS_MODE_KEY, normalized)
            .putBoolean(IMPERIAL_KEY, imperial)
            .apply()
        _state.value = state.value.copy(units = normalized, imperial = imperial)
    }

    fun setClockMode(mode: String) {
        val normalized = normalizeMode(mode, CLOCK_MODES)
        val use24h = use24hFor(normalized)
        settings.edit().putString(CLOCK_KEY, normalized).apply()
        ClockFormat.use24h = use24h
        _state.value = state.value.copy(clockMode = normalized, use24h = use24h)
    }

    private fun imperialFor(mode: String) = when (mode) {
        "imperial" -> true
        "metric" -> false
        else -> deviceImperial
    }

    private fun use24hFor(mode: String) = when (mode) {
        "24" -> true
        "12" -> false
        else -> deviceUse24h
    }

    private fun applyNavLanguage() {
        val tag = state.value.languageTag.ifBlank { systemTag() }
        val parts = tag.replace('_', '-').split('-').filter { it.isNotEmpty() }
        val language = parts.firstOrNull()?.lowercase() ?: "en"
        val script = parts.drop(1).firstOrNull { it.length == 4 }?.replaceFirstChar { it.titlecase() } ?: ""
        val region = parts.drop(1).firstOrNull { it.length == 2 || it.length == 3 }?.uppercase() ?: ""
        NavStringsRegistry.setLanguage(language, region, script)
    }

    companion object {
        const val GOOGLE_DISABLED_KEY = "ios_google_disabled"
        private const val LANGUAGE_KEY = "app_language"
        private const val CLOCK_KEY = "clock_mode"
        private const val UNITS_MODE_KEY = "mode"
        private const val IMPERIAL_KEY = "imperial"

        private val UNIT_MODES = setOf("system", "metric", "imperial")
        private val CLOCK_MODES = setOf("system", "12", "24")
        private val SUPPORTED = setOf(
            "en", "en-GB", "ar", "de", "es", "et", "fr", "he", "hu", "it", "ja", "kmr",
            "nl", "pl", "pt", "pt-BR", "ro", "ru", "sl", "sv", "tr", "uk", "zh", "zh-TW",
        )

        private fun normalizeMode(value: String?, modes: Set<String>): String =
            value?.takeIf { it in modes } ?: "system"

        /** Canonical Android preference codes, also used by the Swift language picker. */
        fun normalizeLanguage(tag: String?): String? {
            if (tag == null) return null
            val parts = tag.trim().replace('_', '-').split('-').filter { it.isNotEmpty() }
            if (parts.isEmpty()) return ""
            val language = when (parts[0].lowercase()) {
                "iw" -> "he"
                "in" -> "id"
                "ji" -> "yi"
                else -> parts[0].lowercase()
            }
            val region = parts.drop(1).firstOrNull { it.length == 2 || it.length == 3 }?.uppercase() ?: ""
            val script = parts.drop(1).firstOrNull { it.length == 4 }?.lowercase() ?: ""
            val canonical = when (language) {
                "pt" -> if (region == "BR") "pt-BR" else "pt"
                "zh" -> if (script == "hant" || region in setOf("TW", "HK", "MO")) "zh-TW" else "zh"
                "en" -> if (region == "GB") "en-GB" else "en"
                else -> language
            }
            return canonical.takeIf { it in SUPPORTED }
        }
    }
}
