package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.data.SuggestResult
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private class SuggestSource : MapDataSource {
    data class Call(val query: String, val near: LatLng?, val span: Double?)

    val calls = mutableListOf<Call>()
    val answers = mutableListOf<CompletableDeferred<SuggestResult>>()
    var searchCalls = 0

    override suspend fun suggest(query: String, near: LatLng?, spanMeters: Double?, lang: String?): SuggestResult {
        calls += Call(query, near, spanMeters)
        val answer = CompletableDeferred<SuggestResult>()
        answers += answer
        return answer.await()
    }

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult {
        searchCalls++
        return SearchResult(query, listOf(Place(id = "result", name = query, location = near ?: LatLng(37.78, -122.41))))
    }

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = error("unused")
}

@OptIn(ExperimentalCoroutinesApi::class)
class SuggestStoreTest {
    @Test fun typingPauseCoalescesEdits() = runTest {
        val source = SuggestSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("c")
        store.setQuery("co")
        store.setQuery("coff")
        advanceTimeBy(SearchStore.SUGGEST_DEBOUNCE_MS - 1)
        runCurrent()
        assertTrue(source.calls.isEmpty())
        advanceTimeBy(1)
        runCurrent()
        assertEquals(listOf("coff"), source.calls.map { it.query })
    }

    @Test fun suggestionsUseTheViewportAndKeepBothRowKinds() = runTest {
        val source = SuggestSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(37.70, -122.50, 37.80, -122.40, 13.0)
        store.setQuery("coff")
        advanceTimeBy(SearchStore.SUGGEST_DEBOUNCE_MS)
        runCurrent()
        assertEquals(37.75, source.calls.single().near!!.lat, 1e-9)
        assertEquals(11_119.0, source.calls.single().span!!, 20.0)
        source.answers.single().complete(
            SuggestResult(
                listOf(Place(id = "p", name = "Coffee place", location = LatLng(37.75, -122.45))),
                listOf("coffee near me"),
            ),
        )
        runCurrent()
        assertEquals(listOf("Coffee place"), store.state.value.suggestions.map { it.name })
        assertEquals(listOf("coffee near me"), store.state.value.querySuggestions)
    }

    @Test fun aLateAnswerCannotReopenSuggestionsAfterSelection() = runTest {
        val source = SuggestSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("coff")
        advanceTimeBy(SearchStore.SUGGEST_DEBOUNCE_MS)
        runCurrent()
        store.dismissSuggestions()
        source.answers.single().complete(SuggestResult(listOf(Place(id = "p", name = "Stale", location = LatLng(37.7, -122.4))), emptyList()))
        advanceTimeBy(1_000)
        runCurrent()
        assertTrue(store.state.value.suggestions.isEmpty())
        assertEquals(1, source.calls.size)
    }

    @Test fun submitCancelsAutocomplete() = runTest {
        val source = SuggestSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("coff")
        store.submit()
        advanceTimeBy(1_000)
        runCurrent()
        assertTrue(source.calls.isEmpty())
        assertEquals(1, source.searchCalls)
        assertTrue(store.state.value.suggestions.isEmpty())
    }

    @Test fun categorySearchDoesNotStartAutocomplete() = runTest {
        val source = SuggestSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.search("Coffee")
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals("Coffee", store.state.value.query)
        assertEquals(1, source.searchCalls)
        assertTrue(source.calls.isEmpty())
    }

    @Test fun setQueryBeforeStartDoesNoNetworkWork() = runTest {
        val source = SuggestSource()
        val store = SearchStore(source, backgroundScope)
        store.setQuery("coff")
        advanceTimeBy(1_000)
        runCurrent()
        assertTrue(source.calls.isEmpty())
    }
}
