package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import kotlinx.datetime.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** SRCH-FILTER: the local filters, the sort, the hours fallback and the NoGoogle matrix. */
class SearchFiltersTest {
    private val noonTuesday = LocalDateTime(2026, 10, 27, 12, 0)

    private fun place(
        name: String,
        rating: Double? = null,
        priceLevel: Int? = null,
        accessible: Boolean = false,
        openNow: Boolean? = null,
        hours: List<String> = emptyList(),
        distanceMeters: Double? = null,
    ) = Place(
        id = name, name = name, location = LatLng(37.78, -122.41),
        rating = rating, priceLevel = priceLevel, wheelchairAccessible = accessible,
        openNow = openNow, hours = hours, distanceMeters = distanceMeters,
    )

    private val weekdayHours = listOf(
        "Monday: 8 AM–6 PM", "Tuesday: 8 AM–6 PM", "Wednesday: 8 AM–6 PM",
        "Thursday: 8 AM–6 PM", "Friday: 8 AM–6 PM", "Saturday: Closed", "Sunday: Closed",
    )

    @Test fun openNowKeepsLiveStatusAndFallsBackToWeeklyHours() {
        val liveOpen = place("live open", openNow = true)
        val liveClosed = place("live closed", openNow = false)
        val hoursOpen = place("hours open", hours = weekdayHours)
        val unknown = place("unknown")
        val out = SearchFiltering.apply(
            listOf(liveOpen, liveClosed, hoursOpen, unknown),
            SearchFilters(openNow = true), noonTuesday,
        )
        assertEquals(listOf("live open", "hours open"), out.map { it.name })
    }

    @Test fun openNowUnderstandsPastMidnightRanges() {
        val late = listOf(
            "Monday: 6 PM–2 AM", "Tuesday: 6 PM–2 AM", "Wednesday: 6 PM–2 AM",
            "Thursday: 6 PM–2 AM", "Friday: 6 PM–2 AM", "Saturday: 6 PM–2 AM", "Sunday: 6 PM–2 AM",
        )
        // 1 AM Tuesday still belongs to Monday's range.
        assertTrue(PlaceHours.openAt(late, LocalDateTime(2026, 10, 27, 1, 0)) == true)
        assertFalse(PlaceHours.openAt(late, LocalDateTime(2026, 10, 27, 12, 0)) == true)
        assertNull(PlaceHours.openAt(emptyList(), noonTuesday))
        assertNull(PlaceHours.openAt(listOf("Tuesday: by appointment"), noonTuesday))
    }

    @Test fun ratingPriceAndAccessibilityMatchAndroidNullHandling() {
        val places = listOf(
            place("cheap accessible", rating = 4.6, priceLevel = 1, accessible = true),
            place("pricey", rating = 4.2, priceLevel = 4),
            place("no rating", priceLevel = 2, accessible = true),
            place("no price", rating = 4.9),
        )
        assertEquals(
            listOf("cheap accessible", "pricey", "no price"),
            SearchFiltering.apply(places, SearchFilters(minRating = 4.0), noonTuesday).map { it.name },
        )
        assertEquals(
            listOf("cheap accessible", "no rating"),
            SearchFiltering.apply(places, SearchFilters(priceMax = 2), noonTuesday).map { it.name },
        )
        assertEquals(
            listOf("cheap accessible", "no rating"),
            SearchFiltering.apply(places, SearchFilters(accessibleOnly = true), noonTuesday).map { it.name },
        )
    }

    @Test fun sortKeepsRelevanceOrderAndPutsUnknownRatingsAndDistancesLast() {
        val places = listOf(
            place("a", rating = 4.1, distanceMeters = 900.0),
            place("b", rating = null, distanceMeters = 120.0),
            place("c", rating = 4.8, distanceMeters = null),
        )
        assertEquals(listOf("a", "b", "c"),
            SearchFiltering.apply(places, SearchFilters(), noonTuesday).map { it.name })
        assertEquals(listOf("c", "a", "b"),
            SearchFiltering.apply(places, SearchFilters(sort = SearchFilters.SORT_RATING), noonTuesday).map { it.name })
        assertEquals(listOf("b", "a", "c"),
            SearchFiltering.apply(places, SearchFilters(sort = SearchFilters.SORT_DISTANCE), noonTuesday).map { it.name })
    }

    @Test fun noGoogleHidesEveryFilterButDistanceAndRelevance() {
        val google = SearchFilterSupportMatrix.of(noGoogleEnabled = false)
        assertTrue(google.openNow && google.minRating && google.price && google.accessible)
        assertTrue(google.sortRating && google.sortDistance && google.sortRelevance)

        val photon = SearchFilterSupportMatrix.of(noGoogleEnabled = true)
        assertFalse(photon.openNow)
        assertFalse(photon.minRating)
        assertFalse(photon.price)
        assertFalse(photon.accessible)
        assertFalse(photon.sortRating)
        assertTrue(photon.sortDistance)
        assertTrue(photon.sortRelevance)
        assertFalse(photon.anyFilter)
    }

    @Test fun unsupportedFiltersAreDroppedInsteadOfEmptyingTheList() {
        val wanted = SearchFilters(
            openNow = true, minRating = 4.5, priceMax = 2, accessibleOnly = true,
            sort = SearchFilters.SORT_RATING,
        )
        val kept = wanted.supportedBy(SearchFilterSupportMatrix.of(noGoogleEnabled = true))
        assertEquals(SearchFilters(), kept)
        assertFalse(kept.filtersAnything)
        // Distance sort is the one sort Photon keeps.
        assertEquals(
            SearchFilters(sort = SearchFilters.SORT_DISTANCE),
            SearchFilters(sort = SearchFilters.SORT_DISTANCE).supportedBy(SearchFilterSupportMatrix.noGoogle),
        )
    }

    @Test fun openNowRewordsTheQueryWithTheAppLanguagePhrase() {
        assertEquals(
            "coffee open now",
            SearchQueryParameters.googleQuery("coffee", SearchFilters(openNow = true), "open now"),
        )
        assertEquals(
            "café jetzt geöffnet",
            SearchQueryParameters.googleQuery("café", SearchFilters(openNow = true), "jetzt geöffnet"),
        )
        assertEquals("coffee", SearchQueryParameters.googleQuery("coffee", SearchFilters(), "open now"))
        // Android's String.enc(): a space becomes '+', as in the q= parameter it sends.
        assertEquals(
            "caf%C3%A9+jetzt+ge%C3%B6ffnet",
            SearchQueryParameters.encodedGoogleQuery("café", SearchFilters(openNow = true), "jetzt geöffnet"),
        )
    }
}
