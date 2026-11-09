package app.vela.ios.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AddressQueryTest {
    @Test fun parsesAHouseNumberAndDistinguishingStreetWord() {
        assertEquals("912" to "miller", AddressQuery.parse("912 Miller Dr"))
        assertEquals("1451" to "covell", AddressQuery.parse("1451 W Covell Blvd, Davis"))
        assertEquals("200" to "b", AddressQuery.parse("200 B St"))
        assertEquals("12" to "north", AddressQuery.parse("12 North St"))
        assertNull(AddressQuery.parse("coffee"))
        assertNull(AddressQuery.parse("5th street"))
    }

    @Test fun matchesOnlyTheWholeHouseNumberAndStreet() {
        assertTrue(AddressQuery.matches("912 Miller Dr", "912 Miller Dr", "Davis, CA 95616"))
        assertTrue(AddressQuery.matches("1451 W Covell Blvd", "Some Market", "1451 W Covell Blvd, Davis"))
        assertFalse(AddressQuery.matches("616 Anderson Rd", "Anderson Plaza Cafe", "1900 Anderson Rd, Davis, CA 95616"))
        assertFalse(AddressQuery.matches("12 Oak Ave", "Oak Dental", "1200 Oak Ave, Davis, CA 95616"))
        assertFalse(AddressQuery.matches("530 Oak Ave", "Corner Bakery", "530 Elm St, Davis"))
        assertFalse(AddressQuery.matches("459 Ralston Ave", "Ralston Hardware", "88 Main St, Springfield"))
    }

    @Test fun directionAndStreetTypeBreakDistanceTies() {
        val query = "1451 W Covell Blvd, Davis, CA"
        val exact = AddressQuery.score(query, "1451 W Covell Blvd", "Davis, CA")
        val east = AddressQuery.score(query, "1451 East Covell Boulevard", "Davis, CA")
        val place = AddressQuery.score(query, "1451 Covell Place", "Davis, CA")
        assertTrue(exact > east && exact > place)
        assertTrue(east > place)
    }
}
