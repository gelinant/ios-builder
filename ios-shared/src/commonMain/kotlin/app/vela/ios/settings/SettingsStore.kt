package app.vela.ios.settings

import app.vela.core.data.CategoryFilter
import app.vela.core.data.ClockFormat
import app.vela.core.data.LowDataMode
import app.vela.core.data.LowRamMode
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
    val lowDataMode: Boolean = false,
    val lowRamMode: Boolean = false,
    val placeContent: String = ContentPolicy.FULL,
    val showReviews: Boolean = true,
    val reviewsOnTap: Boolean = false,
    val loadPhotos: Boolean = true,
    val photosOnTap: Boolean = false,
    val photosWifiOnly: Boolean = false,
    val photoQuality: String = ContentPolicy.QUALITY_STANDARD,
    val photoCacheMb: Int = 200,
    val fullPlaceLoad: Boolean = false,
    val detailsRetry: Boolean = true,
    val hideAdult: Boolean = false,
    val hideExternalLinks: Boolean = false,
    val redactPlacesInExports: Boolean = false,
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
            lowDataMode = settings.getBoolean(LOW_DATA_KEY, false),
            lowRamMode = settings.getBoolean(LOW_RAM_KEY, false),
            placeContent = normalizeMode(settings.getString(PLACE_CONTENT_KEY, ContentPolicy.FULL), PLACE_CONTENT_MODES, ContentPolicy.FULL),
            showReviews = settings.getBoolean(SHOW_REVIEWS_KEY, true),
            reviewsOnTap = settings.getBoolean(REVIEWS_ON_TAP_KEY, false),
            loadPhotos = settings.getBoolean(LOAD_PHOTOS_KEY, true),
            photosOnTap = settings.getBoolean(PHOTOS_ON_TAP_KEY, false),
            photosWifiOnly = settings.getBoolean(PHOTOS_WIFI_KEY, false),
            photoQuality = normalizeMode(settings.getString(PHOTO_QUALITY_KEY, ContentPolicy.QUALITY_STANDARD), PHOTO_QUALITY_MODES, ContentPolicy.QUALITY_STANDARD),
            photoCacheMb = settings.getInt(PHOTO_CACHE_MB_KEY, 200).coerceIn(ContentPolicy.CACHE_MB_MIN, ContentPolicy.CACHE_MB_MAX),
            fullPlaceLoad = settings.getBoolean(FULL_PLACE_LOAD_KEY, false),
            detailsRetry = settings.getBoolean(DETAILS_RETRY_KEY, true),
            hideAdult = settings.getBoolean(HIDE_ADULT_KEY, false),
            hideExternalLinks = settings.getBoolean(HIDE_EXTERNAL_LINKS_KEY, false),
            redactPlacesInExports = settings.getBoolean(REDACT_EXPORTS_KEY, false),
        )
        ClockFormat.use24h = state.value.use24h
        applyContent()
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

    /**
     * Data and content settings. Each setter writes the same key Android uses, updates the state
     * first so the next place load sees it, then pushes the process holders.
     */
    fun setLowDataMode(on: Boolean) {
        settings.edit().putBoolean(LOW_DATA_KEY, on).apply()
        _state.value = state.value.copy(lowDataMode = on)
        applyContent()
    }

    fun setLowRamMode(on: Boolean) {
        settings.edit().putBoolean(LOW_RAM_KEY, on).apply()
        _state.value = state.value.copy(lowRamMode = on)
        applyContent()
    }

    fun setPlaceContent(mode: String) {
        val normalized = normalizeMode(mode, PLACE_CONTENT_MODES, ContentPolicy.FULL)
        settings.edit().putString(PLACE_CONTENT_KEY, normalized).apply()
        _state.value = state.value.copy(placeContent = normalized)
        applyContent()
    }

    fun setShowReviews(on: Boolean) {
        settings.edit().putBoolean(SHOW_REVIEWS_KEY, on).apply()
        _state.value = state.value.copy(showReviews = on)
        applyContent()
    }

    fun setReviewsOnTap(on: Boolean) {
        settings.edit().putBoolean(REVIEWS_ON_TAP_KEY, on).apply()
        _state.value = state.value.copy(reviewsOnTap = on)
        applyContent()
    }

    fun setLoadPhotos(on: Boolean) {
        settings.edit().putBoolean(LOAD_PHOTOS_KEY, on).apply()
        _state.value = state.value.copy(loadPhotos = on)
        applyContent()
    }

    fun setPhotosOnTap(on: Boolean) {
        settings.edit().putBoolean(PHOTOS_ON_TAP_KEY, on).apply()
        _state.value = state.value.copy(photosOnTap = on)
        applyContent()
    }

    fun setPhotosWifiOnly(on: Boolean) {
        settings.edit().putBoolean(PHOTOS_WIFI_KEY, on).apply()
        _state.value = state.value.copy(photosWifiOnly = on)
        applyContent()
    }

    fun setPhotoQuality(quality: String) {
        val normalized = normalizeMode(quality, PHOTO_QUALITY_MODES, ContentPolicy.QUALITY_STANDARD)
        settings.edit().putString(PHOTO_QUALITY_KEY, normalized).apply()
        _state.value = state.value.copy(photoQuality = normalized)
        applyContent()
    }

    fun setPhotoCacheMb(mb: Int) {
        val normalized = mb.coerceIn(ContentPolicy.CACHE_MB_MIN, ContentPolicy.CACHE_MB_MAX)
        settings.edit().putInt(PHOTO_CACHE_MB_KEY, normalized).apply()
        _state.value = state.value.copy(photoCacheMb = normalized)
        applyContent()
    }

    fun setFullPlaceLoad(on: Boolean) {
        settings.edit().putBoolean(FULL_PLACE_LOAD_KEY, on).apply()
        _state.value = state.value.copy(fullPlaceLoad = on)
        applyContent()
    }

    fun setDetailsRetry(on: Boolean) {
        settings.edit().putBoolean(DETAILS_RETRY_KEY, on).apply()
        _state.value = state.value.copy(detailsRetry = on)
        applyContent()
    }

    fun setHideAdult(on: Boolean) {
        settings.edit().putBoolean(HIDE_ADULT_KEY, on).apply()
        _state.value = state.value.copy(hideAdult = on)
        applyContent()
    }

    fun setHideExternalLinks(on: Boolean) {
        settings.edit().putBoolean(HIDE_EXTERNAL_LINKS_KEY, on).apply()
        _state.value = state.value.copy(hideExternalLinks = on)
        applyContent()
    }

    fun setRedactPlacesInExports(on: Boolean) {
        settings.edit().putBoolean(REDACT_EXPORTS_KEY, on).apply()
        _state.value = state.value.copy(redactPlacesInExports = on)
        applyContent()
    }

    /** Pushes the content state into the `:core` and placeholder holders before any request. */
    private fun applyContent() {
        val s = state.value
        ContentPolicy.apply(
            placeContent = s.placeContent,
            showReviews = s.showReviews,
            reviewsOnTap = s.reviewsOnTap,
            loadPhotos = s.loadPhotos,
            photosOnTap = s.photosOnTap,
            photosWifiOnly = s.photosWifiOnly,
            photoQuality = s.photoQuality,
            photoCacheMb = s.photoCacheMb,
            fullPlaceLoad = s.fullPlaceLoad,
            detailsRetry = s.detailsRetry,
            hideAdult = s.hideAdult,
            hideExternalLinks = s.hideExternalLinks,
            redactPlacesInExports = s.redactPlacesInExports,
        )
        LowDataMode.enabled = s.lowDataMode
        LowRamMode.enabled = s.lowRamMode
        CategoryFilter.enabled = s.hideAdult
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

        /** Android's holder keys, so a backup or a test fixture moves between the platforms. */
        private const val LOW_DATA_KEY = "low_data_mode"
        private const val LOW_RAM_KEY = "low_ram_mode"
        private const val PLACE_CONTENT_KEY = "place_content"
        private const val SHOW_REVIEWS_KEY = "show_reviews"
        private const val REVIEWS_ON_TAP_KEY = "reviews_on_tap"
        private const val LOAD_PHOTOS_KEY = "load_photos"
        private const val PHOTOS_ON_TAP_KEY = "photos_on_tap"
        private const val FULL_PLACE_LOAD_KEY = "place_full_load"
        private const val DETAILS_RETRY_KEY = "details_retry"
        private const val HIDE_ADULT_KEY = "hide_adult"
        private const val HIDE_EXTERNAL_LINKS_KEY = "hide_external_links"
        private const val REDACT_EXPORTS_KEY = "diag_redact"

        /** iOS-only policy keys, also read by ImageLoader for the photo cache. */
        private const val PHOTOS_WIFI_KEY = "photos_wifi_only"
        private const val PHOTO_QUALITY_KEY = "photo_quality"
        private const val PHOTO_CACHE_MB_KEY = "photo_cache_mb"

        private val UNIT_MODES = setOf("system", "metric", "imperial")
        private val CLOCK_MODES = setOf("system", "12", "24")
        private val PLACE_CONTENT_MODES = setOf(ContentPolicy.FULL, ContentPolicy.TILES)
        private val PHOTO_QUALITY_MODES = setOf(
            ContentPolicy.QUALITY_HIGH, ContentPolicy.QUALITY_STANDARD, ContentPolicy.QUALITY_LOW,
        )
        private val SUPPORTED = setOf(
            "en", "en-GB", "ar", "de", "es", "et", "fr", "he", "hu", "it", "ja", "kmr",
            "nl", "pl", "pt", "pt-BR", "ro", "ru", "sl", "sv", "tr", "uk", "zh", "zh-TW",
        )

        private fun normalizeMode(value: String?, modes: Set<String>, fallback: String = "system"): String =
            value?.takeIf { it in modes } ?: fallback

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
