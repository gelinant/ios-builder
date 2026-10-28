package app.vela.core.data.transit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The plan reply's coercions are Android's org.json ones (libcore `JSON` and `JSONTokener`). */
class OrgJsonTest {

    private fun v(text: String): JsonElement = Json.parseToJsonElement(text)

    @Test fun stringsReadAsAndroidPrintsThem() {
        assertEquals("abc", OrgJson.string(v("\"abc\"")))
        assertEquals("null", OrgJson.string(v("null")))
        assertEquals("5", OrgJson.string(v("5")))
        assertEquals("100.0", OrgJson.string(v("1e2")))
        assertEquals("38.5449", OrgJson.string(v("3.85449E1")))
        assertEquals("true", OrgJson.string(v("true")))
        assertEquals("12345678901", OrgJson.string(v("12345678901")))
    }

    @Test fun numbersCoerceAsAndroidDoes() {
        assertEquals(12L, OrgJson.long(v("\"12.9\"")))
        assertEquals(-3L, OrgJson.long(v("-3.7")))
        assertNull(OrgJson.long(v("\"x\"")))
        assertNull(OrgJson.long(v("true")))
        assertNull(OrgJson.long(v("null")))
        assertEquals(3, OrgJson.int(v("3.9")))
        assertEquals(6, OrgJson.int(v("\"6.9\"")))
        assertEquals(1.5, OrgJson.double(v("\"1.5\"")))
        assertEquals(7.0, OrgJson.double(v("7")))
        assertNull(OrgJson.double(v("{}")))
    }

    @Test fun booleansCoerceAsAndroidDoes() {
        assertEquals(true, OrgJson.boolean(v("true")))
        assertEquals(true, OrgJson.boolean(v("\"TRUE\"")))
        assertEquals(false, OrgJson.boolean(v("\"false\"")))
        assertNull(OrgJson.boolean(v("1")))
        assertNull(OrgJson.boolean(v("\"yes\"")))
    }
}
