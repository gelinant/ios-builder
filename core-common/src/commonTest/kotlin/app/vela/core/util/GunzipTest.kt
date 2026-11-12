package app.vela.core.util

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFails

class GunzipTest {
    /** Python's `gzip.compress(b"Davis to Sacramento " * 40, mtime=0)`. */
    private val gz = byteArrayOf(
        31, -117, 8, 0, 0, 0, 0, 0, 2, -1, 115, 73, 44, -53, 44, 86, 40, -55, 87, 8, 78, 76, 46, 74, -52, 77, -51, 3, 50, 93,
        70, -59, 70, -59, 70, -59, -64, 98, 0, 39, -93, -73, 30, 32, 3, 0, 0,
    )

    @Test fun inflatesOneMember() {
        assertContentEquals("Davis to Sacramento ".repeat(40).encodeToByteArray(), gunzip(gz))
    }

    @Test fun aCutStreamThrows() {
        assertFails { gunzip(gz.copyOf(20)) }
    }

    @Test fun plainBytesThrow() {
        assertFails { gunzip("not gzip".encodeToByteArray()) }
    }
}
