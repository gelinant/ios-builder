package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.distanceTo
import java.util.zip.GZIPInputStream
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * A real "coffee" reply for the San Francisco fixture point, recorded on the macOS runner
 * (scripts/ios/ci-ipa.sh, run v2-search-ios-20261024-225803-24241) with the iOS identity.
 */
class RecordedSearchReplyTest {
    private val reply: String = GZIPInputStream(javaClass.getResourceAsStream("/search-coffee-sf.txt.gz")!!)
        .readBytes().decodeToString()

    @Test fun theRecordedReplyParsesIntoCoffeePlaces() = runTest {
        val http = FakeHttp { r -> if ("/search?" in r.url) ok(reply) else ok("") }
        val sf = LatLng(37.7749, -122.4194)
        val result = IosSources.over(http).search("coffee", sf, 12_000.0)
        assertTrue(result.places.size >= 15, "only ${result.places.size} places")
        assertTrue(result.places.count { it.address != null } >= 15)
        assertTrue(result.places.count { it.rating != null } >= 10)
        assertTrue(result.places.all { it.location.distanceTo(sf) < 30_000.0 })
        println("recorded reply: ${result.places.size} places, ${result.places.count { it.reviewCount != null }} with a review count")
    }
}
