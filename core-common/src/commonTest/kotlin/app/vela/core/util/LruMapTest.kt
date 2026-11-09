package app.vela.core.util

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The eviction order of an access-order `LinkedHashMap` with `removeEldestEntry` = `size > 3`. */
class LruMapTest {
    @Test fun aReadKeepsAnEntryAndTheLeastRecentGoes() {
        val m = LruMap<Int, String>(3)
        m[1] = "a"; m[2] = "b"; m[3] = "c"
        assertEquals("a", m[1])
        m[4] = "d"
        assertNull(m[2])
        assertEquals(3, m.size)
        m[3] = "C"
        m[5] = "e"
        assertNull(m[1])
        assertEquals("C", m[3])
        assertEquals("d", m[4])
        assertEquals("e", m[5])
        m.clear()
        assertEquals(0, m.size)
    }
}
