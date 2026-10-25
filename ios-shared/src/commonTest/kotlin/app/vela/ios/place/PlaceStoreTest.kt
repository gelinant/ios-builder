package app.vela.ios.place

import app.vela.core.config.Calibration
import app.vela.core.data.MapDataSource
import app.vela.core.data.google.parse.PhotoPage
import app.vela.core.data.google.parse.ReviewFeed
import app.vela.core.model.DayBusyness
import app.vela.core.model.HourBusyness
import app.vela.core.model.LatLng
import app.vela.core.model.Photo
import app.vela.core.model.Place
import app.vela.core.model.PlaceDetails
import app.vela.core.model.PopularTimes
import app.vela.core.model.Review
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import app.vela.core.platform.Cancellable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val FID = "0x8085299fd6f41a23:0x10d37b4cae550f0"

/** Davis Food Co-op as the search list gives it: rated, counted, one hours line. */
private fun coop(fid: String? = FID) = Place(
    id = "coop", name = "Davis Food Co-op", location = LatLng(38.5449, -121.7405), category = "Grocery store",
    address = "620 G St, Davis, CA 95616", rating = 4.6, reviewCount = 1094, hours = listOf("Open"), featureId = fid,
)

private fun review(n: Int) = Review(author = "Reviewer $n", authorPhoto = null, rating = 5 - n % 5, relativeTime = "a week ago", text = "Text $n")

private val popular = PopularTimes(listOf(DayBusyness(1, listOf(HourBusyness(9, 40), HourBusyness(10, 70)))))

/** Answers each place call from its function and counts the calls. */
private class PlaceSource : MapDataSource {
    var details: (Int) -> PlaceDetails? = { null }
    var photos: (Int, String) -> PhotoPage? = { _, _ -> null }
    var feed: (Int, String) -> ReviewFeed? = { _, _ -> null }
    var detailsCalls = 0
    var photoCalls = 0
    var feedCalls = 0
    val feedLangs = mutableListOf<String?>()

    override suspend fun placeDetails(place: Place): PlaceDetails? = details(++detailsCalls)
    override suspend fun placePhotoPage(featureId: String, pageToken: String): PhotoPage? = photos(++photoCalls, pageToken)
    override suspend fun reviewFeed(featureId: String, hl: String?, pageToken: String): ReviewFeed? {
        feedLangs += hl
        return feed(++feedCalls, pageToken)
    }

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult = error("unused")
    override suspend fun placeDetails(id: String): Place = error("unused")
    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = error("unused")
}

/** The hidden page: keeps each request's sink for the test to answer. */
private class FakeWeb : PlaceWebFallback {
    val requests = mutableListOf<WebReviewsRequest>()
    val sinks = mutableListOf<WebReviewsSink>()
    var cancels = 0

    override fun reviews(request: WebReviewsRequest, sink: WebReviewsSink): Cancellable {
        requests += request
        sinks += sink
        return Cancellable { cancels++ }
    }
}

private fun json(vararg n: Int) = n.joinToString(",", "[", "]") { "{\"rid\":\"r$it\",\"r\":4,\"a\":\"Page reviewer $it\",\"d\":\"a month ago\",\"t\":\"Page text $it\"}" }

@OptIn(ExperimentalCoroutinesApi::class)
class PlaceStoreTest {
    private fun TestScope.store(source: PlaceSource, tuning: Map<String, Double> = emptyMap()) = PlaceStore(
        source = { source },
        // Not backgroundScope: advanceUntilIdle leaves background work alone, and the loads wait.
        scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler)),
        calibration = { Calibration.DEFAULT.copy(tuning = Calibration.DEFAULT.tuning + tuning) },
        now = { testScheduler.currentTime },
        reviewsHl = { "fr" },
    )

    @Test fun constructionDoesNothingAndSelectWaitsForStart() = runTest {
        val source = PlaceSource()
        val store = store(source)
        store.select(coop())
        advanceUntilIdle()
        assertNull(store.state.value.selected)
        assertEquals(0, source.detailsCalls + source.photoCalls + source.feedCalls)
    }

    @Test fun aPickLoadsDetailsAndPhotosAndArmsTheReviews() = runTest {
        val source = PlaceSource().apply {
            details = { PlaceDetails(popularTimes = popular, reviewCount = 1094, hours = List(7) { "Day $it" }, phone = "(530) 758-2667", website = "https://davisfood.coop/") }
            photos = { _, _ -> PhotoPage(List(50) { Photo("https://lh5.googleusercontent.com/p/$it=w400", postedText = "2 months ago") }, "next") }
            feed = { _, _ -> ReviewFeed(List(10) { review(it) }, end = false, nextToken = "more") }
        }
        val store = store(source).apply { start() }
        store.select(coop())
        runCurrent()
        val st = store.state.value
        assertEquals("(530) 758-2667", st.selected?.phone)
        assertEquals(7, st.selected?.hours?.size)
        assertEquals(popular, st.selected?.popularTimes)
        assertEquals("620 G St, Davis, CA 95616", st.selected?.address)
        assertFalse(st.loadingDetails)
        assertEquals(50, st.selected?.photoUrls?.size)
        assertEquals("next", st.photosNextToken)
        assertFalse(st.photosLoading)
        assertFalse(store.standing.limited.value)
        // Reviews wait for their section to be on screen.
        assertTrue(st.reviewsLoading)
        assertEquals(0, source.feedCalls)
        store.ensureReviews()
        runCurrent()
        assertEquals(10, store.state.value.reviews.size)
        assertEquals(ReviewsSource.FEED, store.state.value.reviewsSource)
        assertEquals("more", store.state.value.reviewsNextToken)
        assertEquals(listOf<String?>("fr"), source.feedLangs)
        store.ensureReviews()
        runCurrent()
        assertEquals(1, source.feedCalls)
    }

    @Test fun aStrippedFirstAnswerIsAskedAgain() = runTest {
        val source = PlaceSource().apply {
            details = { n -> if (n == 1) PlaceDetails(rating = 4.6) else PlaceDetails(popularTimes = popular, reviewCount = 1094) }
            photos = { n, _ -> if (n == 1) PhotoPage(emptyList(), null) else PhotoPage(List(10) { Photo("https://lh5.googleusercontent.com/p/$it") }, "next") }
        }
        val store = store(source).apply { start() }
        store.select(coop())
        runCurrent()
        assertTrue(store.state.value.loadingDetails)
        assertTrue(store.state.value.photosLoading)
        advanceUntilIdle()
        assertEquals(2, source.detailsCalls)
        assertEquals(2, source.photoCalls)
        assertEquals(popular, store.state.value.selected?.popularTimes)
        assertEquals(10, store.state.value.selected?.photoUrls?.size)
        // Ten photos with more waiting: Google's limited view.
        assertTrue(store.standing.limited.value)
    }

    @Test fun anEmptyFeedFallsBackToThePageAndStreamsIt() = runTest {
        val source = PlaceSource().apply { feed = { _, _ -> ReviewFeed(emptyList(), end = true) } }
        val web = FakeWeb()
        val store = store(source).apply { start(); this.web = web }
        store.select(coop())
        store.ensureReviews()
        // Past the two retry waits, well short of the page's 45 s.
        advanceTimeBy(10_000)
        runCurrent()
        assertEquals(3, source.feedCalls)
        assertEquals(1, web.requests.size)
        val request = web.requests[0]
        assertEquals("https://www.google.com/maps?cid=75778018372833520&hl=fr&gl=us", request.url)
        val script = request.script("42")
        assertTrue("var ID=\"42\"" in script)
        assertTrue("var CAP=10;" in script)
        val sink = web.sinks[0]
        sink.onProgress(2)
        sink.onPartial(json(1, 2))
        sink.onHistogram("[700,200,50,20,10]")
        assertEquals(2, store.state.value.reviewsFound)
        assertEquals(listOf("Page reviewer 1", "Page reviewer 2"), store.state.value.reviews.map { it.author })
        assertEquals(listOf(700, 200, 50, 20, 10), store.state.value.selected?.ratingHistogram)
        assertTrue(store.state.value.reviewsLoading)
        sink.onResult(json(1, 2, 3, 4, 5))
        advanceUntilIdle()
        assertEquals(5, store.state.value.reviews.size)
        assertFalse(store.state.value.reviewsLoading)
        assertEquals(ReviewsSource.PAGE, store.state.value.reviewsSource)
    }

    @Test fun aDeadPageKeepsWhatItStreamed() = runTest {
        val source = PlaceSource()
        val web = FakeWeb()
        val store = store(source, mapOf("iosNativeReviewFeed" to 0.0)).apply { start(); this.web = web }
        store.select(coop())
        store.ensureReviews()
        runCurrent()
        assertEquals(0, source.feedCalls)
        web.sinks[0].onPartial(json(1, 2, 3, 4))
        web.sinks[0].onResult(null)
        advanceUntilIdle()
        assertEquals(4, store.state.value.reviews.size)
        assertEquals(1, web.requests.size)
    }

    @Test fun aSliverIsScrapedAgain() = runTest {
        val web = FakeWeb()
        val store = store(PlaceSource(), mapOf("nativeReviewFeed" to 0.0)).apply { start(); this.web = web }
        store.select(coop())
        store.ensureReviews()
        runCurrent()
        web.sinks[0].onResult(json(1))
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(2, web.requests.size)
        web.sinks[1].onResult(json(1, 2, 3, 4, 5, 6))
        advanceUntilIdle()
        assertEquals(6, store.state.value.reviews.size)
    }

    @Test fun anAnswerForAPlaceNoLongerOpenIsDropped() = runTest {
        val web = FakeWeb()
        val store = store(PlaceSource(), mapOf("nativeReviewFeed" to 0.0)).apply { start(); this.web = web }
        store.select(coop())
        store.ensureReviews()
        runCurrent()
        val other = coop("0x1:0x2").copy(id = "other", name = "Other")
        store.select(other)
        runCurrent()
        assertEquals(1, web.cancels)
        web.sinks[0].onPartial(json(1, 2))
        assertTrue(store.state.value.reviews.isEmpty())
        assertEquals("Other", store.state.value.selected?.name)
        store.close()
        assertNull(store.state.value.selected)
    }

    @Test fun aReopenedPlaceReadsTheCache() = runTest {
        val source = PlaceSource().apply {
            details = { PlaceDetails(popularTimes = popular, reviewCount = 1094) }
            photos = { _, _ -> PhotoPage(List(50) { Photo("https://lh5.googleusercontent.com/p/$it") }, null) }
            feed = { _, _ -> ReviewFeed(List(5) { review(it) }, end = true) }
        }
        val store = store(source).apply { start() }
        repeat(2) {
            store.select(coop())
            store.ensureReviews()
            advanceUntilIdle()
        }
        assertEquals(1, source.detailsCalls)
        assertEquals(1, source.photoCalls)
        assertEquals(1, source.feedCalls)
        assertEquals(ReviewsSource.CACHE, store.state.value.reviewsSource)
        // Five reviews and the end of the feed for a place with 1094: the limited view.
        assertTrue(store.state.value.reviewsLimited)
    }

    @Test fun moreReviewsAndMorePhotosAppendTheNextPage() = runTest {
        val source = PlaceSource().apply {
            photos = { _, token -> if (token.isEmpty()) PhotoPage(listOf(Photo("https://a/1")), "p2") else PhotoPage(listOf(Photo("https://a/1"), Photo("https://a/2")), null) }
            feed = { _, token -> if (token.isEmpty()) ReviewFeed(listOf(review(1)), end = false, nextToken = "t2") else ReviewFeed(listOf(review(1), review(2)), end = true) }
        }
        val store = store(source).apply { start() }
        store.select(coop())
        store.ensureReviews()
        advanceUntilIdle()
        store.loadMoreReviews()
        store.loadMorePhotos()
        advanceUntilIdle()
        assertEquals(listOf("Reviewer 1", "Reviewer 2"), store.state.value.reviews.map { it.author })
        assertNull(store.state.value.reviewsNextToken)
        assertEquals(listOf("https://a/1", "https://a/2"), store.state.value.selected?.photoUrls)
        assertNull(store.state.value.photosNextToken)
    }

    @Test fun aBareAddressAsksForNoReviews() = runTest {
        val source = PlaceSource()
        val store = store(source).apply { start() }
        store.select(Place(id = "a", name = "620 G St", location = LatLng(38.5449, -121.7405), featureId = FID))
        store.ensureReviews()
        advanceUntilIdle()
        assertFalse(store.state.value.reviewsLoading)
        assertEquals(0, source.feedCalls)
    }

    @Test fun cidAndPageLanguage() {
        assertEquals("75778018372833520", PlaceStore.cidOf(FID))
        assertNull(PlaceStore.cidOf("ChIJ"))
        assertEquals("en", PlaceStore.reviewsHl("ko", "ko-KR"))
        assertEquals("iw", PlaceStore.reviewsHl("he", "he-IL"))
        assertEquals("zh-TW", PlaceStore.reviewsHl("zh", "zh-Hant-TW"))
        assertEquals("zh-CN", PlaceStore.reviewsHl("zh", "zh-Hans-CN"))
        assertEquals("fr", PlaceStore.reviewsHl("fr", "fr-FR"))
    }
}
