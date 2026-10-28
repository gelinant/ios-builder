package app.vela.ios.settings

import kotlin.concurrent.Volatile

/**
 * The process-wide place content policy, the iOS counterpart of Android's `ShowReviews`,
 * `LoadPhotos`, `HideAdult`, `HideExternalLinks`, `DetailsRetry` and `FullPlaceLoad` holders.
 *
 * [SettingsStore] writes every field from the persisted settings before the first request, so a
 * place load always sees the same values the settings screen shows. The values are plain
 * `@Volatile` flags because the place store runs on the main thread and the settings screen may
 * write from the same thread while a request is being prepared.
 *
 * `placeContent` is either [FULL] (details, reviews and photos from Google) or [TILES] (the map
 * tiles and the place row from search only, with no place page request).
 */
object ContentPolicy {
    const val FULL = "full"
    const val TILES = "tiles"

    const val QUALITY_HIGH = "high"
    const val QUALITY_STANDARD = "standard"
    const val QUALITY_LOW = "low"

    const val CACHE_MB_MIN = 50
    const val CACHE_MB_MAX = 400

    @Volatile var placeContent: String = FULL
    @Volatile var showReviews: Boolean = true
    @Volatile var reviewsOnTap: Boolean = false
    @Volatile var loadPhotos: Boolean = true
    @Volatile var photosOnTap: Boolean = false
    @Volatile var photosWifiOnly: Boolean = false
    @Volatile var photoQuality: String = QUALITY_STANDARD
    @Volatile var photoCacheMb: Int = 200
    @Volatile var fullPlaceLoad: Boolean = false
    @Volatile var detailsRetry: Boolean = true
    @Volatile var hideAdult: Boolean = false
    @Volatile var hideExternalLinks: Boolean = false
    @Volatile var redactPlacesInExports: Boolean = false

    fun apply(
        placeContent: String,
        showReviews: Boolean,
        reviewsOnTap: Boolean,
        loadPhotos: Boolean,
        photosOnTap: Boolean,
        photosWifiOnly: Boolean,
        photoQuality: String,
        photoCacheMb: Int,
        fullPlaceLoad: Boolean,
        detailsRetry: Boolean,
        hideAdult: Boolean,
        hideExternalLinks: Boolean,
        redactPlacesInExports: Boolean = false,
    ) {
        this.placeContent = if (placeContent == TILES) TILES else FULL
        this.showReviews = showReviews
        this.reviewsOnTap = reviewsOnTap
        this.loadPhotos = loadPhotos
        this.photosOnTap = photosOnTap
        this.photosWifiOnly = photosWifiOnly
        this.photoQuality = when (photoQuality) {
            QUALITY_HIGH, QUALITY_LOW -> photoQuality
            else -> QUALITY_STANDARD
        }
        this.photoCacheMb = photoCacheMb.coerceIn(CACHE_MB_MIN, CACHE_MB_MAX)
        this.fullPlaceLoad = fullPlaceLoad
        this.detailsRetry = detailsRetry
        this.hideAdult = hideAdult
        this.hideExternalLinks = hideExternalLinks
        this.redactPlacesInExports = redactPlacesInExports
    }

    /** The full place page is off: the sheet keeps the search row and asks Google nothing. */
    val tilesOnly: Boolean get() = placeContent == TILES

    /** Resets the process holders, for tests and a clean Debug launch. */
    fun reset() {
        apply(
            placeContent = FULL, showReviews = true, reviewsOnTap = false, loadPhotos = true,
            photosOnTap = false, photosWifiOnly = false, photoQuality = QUALITY_STANDARD,
            photoCacheMb = 200, fullPlaceLoad = false, detailsRetry = true, hideAdult = false,
            hideExternalLinks = false, redactPlacesInExports = false,
        )
    }
}
