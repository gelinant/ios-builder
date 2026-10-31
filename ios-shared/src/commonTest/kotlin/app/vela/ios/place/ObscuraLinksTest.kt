package app.vela.ios.place

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The link-only rules of AO-1 and AO-2: fixed hosts, bounded six-decimal points, no free text. */
class ObscuraLinksTest {
    @Test fun nearbyUrlUsesTheSitesOwnSearchShape() {
        assertEquals(
            "https://www.atlasobscura.com/search?q=&location=&nearby=true&lat=48.856600&lng=2.352200",
            ObscuraLinks.nearbyUrl(48.8566, 2.3522),
        )
    }

    @Test fun nearbyUrlKeepsTheHostAndThePathFixed() {
        val url = ObscuraLinks.nearbyUrl(51.5074, -0.1278)!!
        assertTrue(url.startsWith("https://www.atlasobscura.com/search?"))
        assertEquals(ObscuraLinks.HOST, "www.atlasobscura.com")
        assertFalse(url.contains("/foods/"))
    }

    @Test fun nearbyUrlPadsNegativeAndSmallCoordinatesToSixDecimals() {
        assertEquals(
            "https://www.atlasobscura.com/search?q=&location=&nearby=true&lat=-0.000400&lng=0.008000",
            ObscuraLinks.nearbyUrl(-0.0004, 0.008),
        )
    }

    @Test fun nearbyUrlBoundsTheCoordinateInsteadOfTrustingIt() {
        val high = ObscuraLinks.nearbyUrl(200.0, 500.0)!!
        assertTrue(high.endsWith("lat=90.000000&lng=180.000000"), high)
        val low = ObscuraLinks.nearbyUrl(-200.0, -500.0)!!
        assertTrue(low.endsWith("lat=-90.000000&lng=-180.000000"), low)
    }

    @Test fun nearbyUrlRefusesAPointThatIsNotFinite() {
        assertNull(ObscuraLinks.nearbyUrl(Double.NaN, 2.3522))
        assertNull(ObscuraLinks.nearbyUrl(48.8566, Double.POSITIVE_INFINITY))
    }

    @Test fun nearbyUrlCarriesNoPlaceTextAndNothingUnescaped() {
        val url = ObscuraLinks.nearbyUrl(48.8566, 2.3522)!!
        val query = url.substringAfter('?').split('&')
        assertEquals(listOf("q=", "location=", "nearby=true"), query.take(3))
        assertTrue(query.drop(3).all { it.matches(Regex("(lat|lng)=-?\\d+\\.\\d{6}")) })
        assertFalse(url.contains("%"))
        assertFalse(url.contains("+"))
    }

    @Test fun gastroUrlIsTheFixedPlaceIndexWithoutAnyCoordinate() {
        val url = ObscuraLinks.gastroUrl("Cafe")!!
        assertEquals("https://www.atlasobscura.com/gastro/places", url)
        assertFalse(url.contains("lat="))
        assertFalse(url.contains("lng="))
        assertFalse(url.contains("/foods/"))
    }

    @Test fun gastroUrlOnlyExistsForFoodAndDrinkCategories() {
        assertTrue(ObscuraLinks.isFood("Cafe"))
        assertTrue(ObscuraLinks.isFood("Seafood restaurant"))
        assertTrue(ObscuraLinks.isFood("Wine bar"))
        assertTrue(ObscuraLinks.isFood("Bakery"))
        assertFalse(ObscuraLinks.isFood("Gas station"))
        assertFalse(ObscuraLinks.isFood("Capital city"))
        assertFalse(ObscuraLinks.isFood("Museum"))
        assertFalse(ObscuraLinks.isFood(null))
        assertFalse(ObscuraLinks.isFood(""))
        assertNull(ObscuraLinks.gastroUrl("Gas station"))
        assertNull(ObscuraLinks.gastroUrl(null))
    }
}
