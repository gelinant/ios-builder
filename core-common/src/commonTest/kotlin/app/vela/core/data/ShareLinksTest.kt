package app.vela.core.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/** SHR-PLACE: outgoing links and text, with Google and with NoGoogle. */
class ShareLinksTest {

    @Test fun googlePlaceLinkUsesTheListingCidOrANameAndPoint() {
        assertEquals(
            "https://www.google.com/maps?cid=18446744073709551615",
            ShareLinks.googlePlaceUrl("Davis Food Co-op", 38.5449, -121.7405, "0x0:0xffffffffffffffff"),
        )
        assertEquals(
            "https://www.google.com/maps/search/?api=1&query=Davis%20Food%20Co-op%2038.5449%2C-121.7405",
            ShareLinks.googlePlaceUrl("Davis Food Co-op", 38.5449, -121.7405, null),
        )
        // The canonical link is never a shortener, so the short-link setting never changes it.
        assertFalse(ShortLinks.isShortener(ShareLinks.googlePlaceUrl("A", 1.0, 2.0, null)))
    }

    @Test fun placeTextCarriesNameAddressAndTheAndroidPinWithoutALink() {
        assertEquals(
            "Davis Food Co-op\n620 W 18th St, Davis, CA",
            ShareLinks.placeText(
                "Davis Food Co-op", "620 W 18th St, Davis, CA", 38.5449, -121.7405, hasLink = true),
        )
        assertEquals(
            "Davis Food Co-op\ngeo:38.5449,-121.7405?q=38.5449,-121.7405(Davis%20Food%20Co-op)",
            ShareLinks.placeText(
                "Davis Food Co-op", null, 38.5449, -121.7405, hasLink = false),
        )
        // An address that begins with the name is shared as the address alone, without a repeat.
        assertEquals(
            "Davis Food Co-op, 620 W 18th St, Davis, CA",
            ShareLinks.placeText(
                "Davis Food Co-op", "Davis Food Co-op, 620 W 18th St, Davis, CA", 0.0, 0.0,
                hasLink = true),
        )
    }

    @Test fun googlePlaceShareCarriesTheNameAddressAndCanonicalLink() {
        val share = ShareLinks.placeShare(
            "Davis Food Co-op", "620 W 18th St, Davis, CA", 38.5449, -121.7405,
            featureId = "0x0:0xffffffffffffffff", sourceId = "0x0:0xffffffffffffffff", google = true,
        )
        assertEquals("Davis Food Co-op", share.subject)
        assertEquals("Davis Food Co-op\n620 W 18th St, Davis, CA", share.text)
        assertEquals("https://www.google.com/maps?cid=18446744073709551615", share.link)
    }

    @Test fun noGoogleSharesTheOpenStreetMapObjectOrAPhotonSearch() {
        assertEquals(
            "https://www.openstreetmap.org/node/123",
            ShareLinks.openPlaceUrl("osm:n123", "Temple Coffee", null),
        )
        assertEquals(
            "https://www.openstreetmap.org/way/456",
            ShareLinks.openPlaceUrl("overture:osm:way/456", "Temple Coffee", null),
        )
        assertNull(ShareLinks.osmUrl("0x808f:0x1"))
        assertNull(ShareLinks.osmUrl("photon:12,34"))
        assertEquals(
            "https://photon.komoot.io/?q=Temple%20Coffee%201234%20K%20St",
            ShareLinks.openPlaceUrl("0x808f:0x1", "Temple Coffee", "1234 K St"),
        )
        val osm = ShareLinks.placeShare(
            "Temple Coffee", "1234 K St", 38.5449, -121.7405,
            featureId = null, sourceId = "osm:n123", google = false,
        )
        assertEquals("Temple Coffee\n1234 K St", osm.text)
        val link = osm.link!!
        assertEquals("https://www.openstreetmap.org/node/123", link)
        assertFalse(link.contains("google"), link)
    }

    @Test fun noGooglePlaceWithoutAnOpenObjectFallsBackToTheGeoPin() {
        val share = ShareLinks.placeShare(
            "Davis Food Co-op", "620 W 18th St, Davis, CA", 38.5449, -121.7405,
            featureId = "0x0:0x1", sourceId = "photon:38.5,-121.7", google = false,
        )
        assertEquals("https://photon.komoot.io/?q=Davis%20Food%20Co-op%20620%20W%2018th%20St%2C%20Davis%2C%20CA",
            share.link)
        assertFalse(share.text.contains("geo:"), share.text)
        assertFalse(share.text.contains("google"), share.text)

        // Nothing open can be named at all: Android's keyless pin is the share.
        val pin = ShareLinks.placeShare(
            "", null, 38.5449, -121.7405,
            featureId = null, sourceId = null, google = false,
        )
        assertNull(pin.link)
        assertEquals("38.5449\ngeo:38.5449,-121.7405?q=38.5449,-121.7405", pin.text)
    }

    @Test fun googleDirectionsLinkKeepsOriginStopsAndMode() {
        assertEquals(
            "https://www.google.com/maps/dir/?api=1&destination=Davis%20Food%20Co-op"
                + "&travelmode=driving&origin=Sacramento&waypoints=Temple%20Coffee%7CPeet%27s",
            ShareLinks.googleDirectionsUrl(
                "Sacramento", "Davis Food Co-op", listOf("Temple Coffee", "Peet's"), "DRIVE"),
        )
        // The device's position is what an absent Google origin already means.
        assertEquals(
            "https://www.google.com/maps/dir/?api=1&destination=Davis%20Food%20Co-op&travelmode=walking",
            ShareLinks.googleDirectionsUrl(
                "your location", "Davis Food Co-op", emptyList(), "WALK"),
        )
        assertNull(ShareLinks.googleDirectionsUrl("Sacramento", "  ", emptyList(), "DRIVE"))
    }

    @Test fun routeTextHasOriginStopsModeAndOnlyTheRealEta() {
        assertEquals(
            "Directions from Sacramento to Davis Food Co-op\n"
                + "Stops: Temple Coffee, Peet's\n"
                + "Mode: Driving\n"
                + "ETA: 24 min",
            ShareLinks.routeText(
                "Sacramento", "Davis Food Co-op", listOf("Temple Coffee", "Peet's"), "DRIVE", "24 min"),
        )
        assertEquals(
            "Directions from your location to Davis Food Co-op\nMode: Walking",
            ShareLinks.routeText("your location", "Davis Food Co-op", emptyList(), "WALK", null),
        )
        // A route whose duration is unknown passes no ETA and gets no invented one.
        assertFalse(ShareLinks.routeText("A", "B", emptyList(), "TRANSIT", null).contains("ETA"))
    }

    @Test fun noGoogleRouteShareHasNoFabricatedLink() {
        val share = ShareLinks.routeShare(
            "Sacramento", "Davis Food Co-op", listOf("Temple Coffee"), "DRIVE", "24 min",
            google = false,
        )
        assertEquals("Route to Davis Food Co-op", share.subject)
        assertNull(share.link)
        assertFalse(share.text.contains("google"), share.text)
        assertFalse(share.text.contains("goo.gl"), share.text)
        assertFalse(share.text.contains("https://"), share.text)

        val google = ShareLinks.routeShare(
            "Sacramento", "Davis Food Co-op", emptyList(), "DRIVE", "24 min", google = true,
        )
        assertEquals(
            "https://www.google.com/maps/dir/?api=1&destination=Davis%20Food%20Co-op"
                + "&travelmode=driving&origin=Sacramento",
            google.link,
        )
    }
}
