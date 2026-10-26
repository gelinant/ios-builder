package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private fun mergedPlace(
    id: String,
    name: String,
    lat: Double = 38.5580,
    lng: Double = -121.7600,
    featureId: String? = null,
    category: String? = null,
    address: String? = null,
) = Place(id = id, name = name, location = LatLng(lat, lng), featureId = featureId, category = category, address = address)

class SearchMergeTest {
    @Test fun stableIdsAndFeatureIdsCollapseAcrossSources() {
        val byId = SearchMerge.merge(
            online = listOf(mergedPlace("same", "Google name", lat = 38.5580)),
            local = listOf(mergedPlace("same", "Offline name", lat = 38.5700)),
            query = null, near = null, photon = emptyList(),
        )
        assertEquals(1, byId.size)
        assertEquals("Google name", byId.single().name)

        val byFeature = SearchMerge.merge(
            online = listOf(mergedPlace("google:1", "Google", featureId = "0x1:0x2")),
            local = listOf(mergedPlace("osm:1", "Offline", featureId = "0x1:0x2")),
            query = null, near = null, photon = emptyList(),
        )
        assertEquals(1, byFeature.size)
        assertEquals("google:1", byFeature.single().id)
    }

    @Test fun normalizedNameAndLocationCollapseButDistinctPlacesRemain() {
        val online = mergedPlace("google:1", "Cafe Roma")
        val twin = mergedPlace("osm:1", " cafe-roma ", lat = 38.5582, address = "231 E St")
        val other = mergedPlace("osm:2", "CAFE ROMA", lat = 38.5600)
        val result = SearchMerge.merge(listOf(online), listOf(twin, other), null, null, emptyList())
        assertEquals(listOf("google:1", "osm:2"), result.map { it.id })
        assertEquals("231 E St", result.first().address)
        assertEquals(SearchMerge.nameLocKey(online), SearchMerge.nameLocKey(mergedPlace("x", "CAFE-ROMA")))
        assertEquals("0x1:0x2", SearchMerge.placeKey(mergedPlace("x", "X", featureId = "0x1:0x2")))
    }

    @Test fun onlineIdentityWinsAndOfflineAddressSurvives() {
        val online = mergedPlace("google:1", "Covell Market", featureId = "0x1:0x2")
        val local = mergedPlace(
            "osm:9", "covell market", lat = 38.5581, category = "Supermarket",
            address = "1451 West Covell Boulevard, Davis, CA 95616",
        )
        val result = SearchMerge.merge(listOf(online), listOf(local), null, null, emptyList()).single()
        assertEquals("google:1", result.id)
        assertEquals("0x1:0x2", result.featureId)
        assertEquals("Supermarket", result.category)
        assertEquals(local.address, result.address)
    }

    @Test fun typedAddressHitsLeadByStreetScoreThenDistanceWithoutReorderingOtherRows() {
        val near = LatLng(38.5580, -121.7600)
        val query = "1451 W Covell Blvd"
        val exact = mergedPlace(
            "google:exact", "1451 W Covell Blvd", lat = 38.5600, address = "Davis, CA",
        )
        val east = mergedPlace(
            "photon:east", "1451 East Covell Boulevard", lat = 38.5581, address = "Davis, CA",
        )
        val firstRest = mergedPlace("google:a", "Covell Market", lat = 38.5582)
        val secondRest = mergedPlace("google:b", "Another place", lat = 38.5583)
        val result = SearchMerge.merge(
            online = listOf(firstRest, exact, secondRest), local = emptyList(),
            query = query, near = near, photon = listOf(east),
        )
        assertEquals(listOf("google:exact", "photon:east", "google:a", "google:b"), result.map { it.id })
    }

    @Test fun localExactAddressLeadsWhenNetworkMissesIt() {
        val query = "1451 W Covell Blvd"
        val localAddress = mergedPlace(
            "addr:1451", "1451 West Covell Boulevard", category = "Address",
            address = "1451 West Covell Boulevard, Davis",
        )
        val online = mergedPlace("google:1", "Covell Market")
        val result = SearchMerge.merge(listOf(online), listOf(localAddress), query, null, emptyList())
        assertEquals(listOf("addr:1451", "google:1"), result.map { it.id })
    }

    @Test fun coveredLocalAddressStillFillsTheOnlineRowsMissingAddress() {
        val query = "1451 W Covell Blvd"
        val online = mergedPlace("google:1", "1451 W Covell Blvd", address = null)
        val local = mergedPlace(
            "addr:1451", "1451 West Covell Boulevard", lat = 38.5581, category = "Address",
            address = "1451 West Covell Boulevard, Davis, CA 95616",
        )
        val result = SearchMerge.merge(listOf(online), listOf(local), query, null, emptyList())
        assertEquals(listOf("google:1"), result.map { it.id })
        assertEquals(local.address, result.single().address)
    }

    @Test fun approximateAddressDisappearsWhenAnyNetworkRowCarriesTheRealAddress() {
        val query = "1475 W Covell Blvd"
        val estimate = mergedPlace(
            "addr~1475", "1475 West Covell Boulevard", lat = 38.5590, category = "Address",
            address = "1475 West Covell Boulevard, Davis",
        )
        val real = mergedPlace(
            "google:real", "Covell Market", lat = 38.5700,
            address = "1475 West Covell Boulevard, Davis, CA 95616",
        )
        val result = SearchMerge.merge(listOf(real), listOf(estimate), query, null, emptyList())
        assertEquals(listOf("google:real"), result.map { it.id })
        assertFalse(result.any { it.id.startsWith("addr~") })
    }

    @Test fun photonGoogleAndOfflineCopiesProduceOneRow() {
        val query = "1451 W Covell Blvd"
        val google = mergedPlace(
            "google:1", "1451 W Covell Blvd", featureId = "0x1:0x2", address = null,
        )
        val photon = mergedPlace(
            "photon:1", "1451 W Covell Blvd", lat = 38.5581,
            address = "1451 W Covell Blvd, Davis, CA",
        )
        val offline = mergedPlace(
            "addr:1451", "1451 W Covell Blvd", lat = 38.5581, category = "Address",
            address = "1451 W Covell Blvd, Davis, CA 95616",
        )
        val result = SearchMerge.merge(listOf(google), listOf(offline), query, null, listOf(photon))
        assertEquals(1, result.size)
        assertTrue(result.single().id.startsWith("google:") || result.single().id.startsWith("photon:"))
        assertFalse(result.single().address.isNullOrBlank())
    }
}
