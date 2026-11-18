package app.vela.ios.search

import app.vela.core.model.Place
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

/**
 * The results filters and sort, in Android's terms (MapScreen's results header): Open now, a
 * rating floor, a price ceiling, wheelchair accessibility, and relevance/rating/distance order.
 *
 * The first four thin the results the source already returned, exactly as Android does. Open now
 * is the exception: on top of that local filter, turning it on also re-runs the same Google search
 * with the localized "open now" phrase, because late at night most fetched places are closed and
 * filtering them would leave almost nothing (see [SearchQueryParameters]).
 */
data class SearchFilters(
    val openNow: Boolean = false,
    val minRating: Double = 0.0,
    /** 0 = off, else the highest price level to keep (1 = $ .. 4 = $$$$). */
    val priceMax: Int = 0,
    val accessibleOnly: Boolean = false,
    /** One of [SORT_RELEVANCE], [SORT_RATING], [SORT_DISTANCE]. */
    val sort: Int = SORT_RELEVANCE,
) {
    /** Whether a local filter is on. Sort never changes membership. */
    val filtersAnything: Boolean
        get() = openNow || minRating > 0.0 || priceMax > 0 || accessibleOnly

    /** The part of these filters a source can honour; the rest is dropped, not guessed. */
    fun supportedBy(support: SearchFilterSupport): SearchFilters = SearchFilters(
        openNow = openNow && support.openNow,
        minRating = if (support.minRating) minRating else 0.0,
        priceMax = if (support.price) priceMax else 0,
        accessibleOnly = accessibleOnly && support.accessible,
        sort = when {
            sort == SORT_RATING && !support.sortRating -> SORT_RELEVANCE
            sort == SORT_DISTANCE && !support.sortDistance -> SORT_RELEVANCE
            else -> sort
        },
    )

    companion object {
        const val SORT_RELEVANCE = 0
        const val SORT_RATING = 1
        const val SORT_DISTANCE = 2
    }
}

/** Which controls a source can answer. Swift draws only these and explains the rest. */
data class SearchFilterSupport(
    val openNow: Boolean,
    val minRating: Boolean,
    val price: Boolean,
    val accessible: Boolean,
    val sortRating: Boolean,
    val sortDistance: Boolean,
) {
    /** Relevance is the source's own order, so it always works. */
    val sortRelevance: Boolean get() = true

    /** Whether any filter (not sort) can be honoured here. */
    val anyFilter: Boolean get() = openNow || minRating || price || accessible
}

object SearchFilterSupportMatrix {
    /**
     * Google's keyless search reply carries the live open status, the rating, the price level and
     * the one accessibility attribute, so every control works.
     */
    val google = SearchFilterSupport(
        openNow = true, minRating = true, price = true, accessible = true,
        sortRating = true, sortDistance = true,
    )

    /**
     * Photon (OpenStreetMap) and downloaded region packs carry no rating, no price level, no live
     * status and no accessibility attribute. Applying those filters would empty the list, which
     * reads as "nothing is open" rather than "this source cannot tell", so iOS hides them.
     * Distance survives where the row carries a distance from the search bias; relevance is
     * Photon's own ranking.
     */
    val noGoogle = SearchFilterSupport(
        openNow = false, minRating = false, price = false, accessible = false,
        sortRating = false, sortDistance = true,
    )

    fun of(noGoogleEnabled: Boolean): SearchFilterSupport = if (noGoogleEnabled) noGoogle else google
}

/**
 * Applies the filters and the sort. Android's order and null handling, one for one: a missing
 * rating fails a rating floor and sorts last, a missing price level fails a price ceiling (it is
 * unknown, so it may exceed the ceiling), and a missing distance sorts last.
 */
object SearchFiltering {
    fun apply(places: List<Place>, filters: SearchFilters, now: LocalDateTime): List<Place> =
        apply(places, filters) { now }

    /**
     * The store's form: the clock is only read when Open now is on, so a plain search never pays
     * for a time-zone lookup.
     */
    fun apply(places: List<Place>, filters: SearchFilters, now: () -> LocalDateTime): List<Place> {
        var list = places
        if (filters.openNow) {
            val at = now()
            list = list.filter { isOpenNow(it, at) == true }
        }
        if (filters.minRating > 0.0) list = list.filter { (it.rating ?: 0.0) >= filters.minRating }
        if (filters.priceMax > 0) list = list.filter { (it.priceLevel ?: Int.MAX_VALUE) <= filters.priceMax }
        if (filters.accessibleOnly) list = list.filter { it.wheelchairAccessible }
        return when (filters.sort) {
            SearchFilters.SORT_RATING -> list.sortedByDescending { it.rating ?: -1.0 }
            SearchFilters.SORT_DISTANCE -> list.sortedBy { it.distanceMeters ?: Double.MAX_VALUE }
            else -> list
        }
    }

    /**
     * Google's live status first. When the reply omitted it, the weekly hours answer, as Android's
     * `MapScreen` does; a place with neither stays out, since it cannot be confirmed open.
     */
    fun isOpenNow(place: Place, now: LocalDateTime): Boolean? =
        place.openNow ?: PlaceHours.openAt(place.hours, now)
}

/** The clock and phrase the store needs, kept together so tests can pin both. */
internal fun currentLocalTime(): LocalDateTime =
    kotlin.time.Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())

/**
 * What iOS adds to Google's request for the filters. Android sends no filter token in `pb`: its
 * results header filters the reply locally, and its Open now chip instead re-runs the SAME
 * `/search?tbm=map&q=...&pb=...` with the localized "open now" phrase appended to the query. iOS
 * does exactly that, through the same [app.vela.core.data.MapDataSource.search] path, so the
 * endpoint, the `pb` template and the URL encoding stay identical to Android's.
 */
object SearchQueryParameters {
    /** The `q=` value: the user's words, plus the English or localized phrase for Open now. */
    fun googleQuery(base: String, filters: SearchFilters, openNowPhrase: String): String =
        if (!filters.openNow || openNowPhrase.isBlank()) base else "$base $openNowPhrase"

    /** The same value as it goes into the URL (Android's `String.enc()`, `+` for a space). */
    fun encodedGoogleQuery(base: String, filters: SearchFilters, openNowPhrase: String): String =
        app.vela.core.util.UrlCodec.encode(googleQuery(base, filters, openNowPhrase))
}
