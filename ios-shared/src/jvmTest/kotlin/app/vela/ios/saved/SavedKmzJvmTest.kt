package app.vela.ios.saved

import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The KMZ container around a My Maps KML: a ZIP whose document is `doc.kml`. */
class SavedKmzJvmTest {
    private val kml = """<?xml version="1.0"?><kml><Document><name>Weekend</name>
        <Placemark><name>Davis Food Co-op</name><Point><coordinates>-121.7405,38.5449,0</coordinates></Point></Placemark>
        </Document></kml>"""

    private fun zip(stored: Boolean = false, name: String = "doc.kml"): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            zip.putNextEntry(ZipEntry("readme.txt").apply { if (stored) store(this, "hello") })
            if (stored) zip.write("hello".encodeToByteArray()) else zip.write("not the document".encodeToByteArray())
            zip.closeEntry()
            val entry = ZipEntry(name)
            val bytes = kml.encodeToByteArray()
            if (stored) {
                entry.method = ZipEntry.STORED
                entry.size = bytes.size.toLong()
                val crc = CRC32().apply { update(bytes) }
                entry.crc = crc.value
            }
            zip.putNextEntry(entry)
            zip.write(bytes)
            zip.closeEntry()
        }
        return out.toByteArray()
    }

    private fun store(entry: ZipEntry, text: String) {
        val bytes = text.encodeToByteArray()
        entry.method = ZipEntry.STORED
        entry.size = bytes.size.toLong()
        entry.crc = CRC32().apply { update(bytes) }.value
    }

    @Test fun readsTheDeflatedDocumentFromKmz() {
        assertEquals(kml, SavedKmz.kml(zip()))
    }

    @Test fun readsAStoredDocumentToo() {
        assertEquals(kml, SavedKmz.kml(zip(stored = true)))
    }

    @Test fun findsANamedDocumentWhenItIsNotDocKml() {
        assertEquals(kml, SavedKmz.kml(zip(name = "My map.kml")))
    }

    @Test fun refusesBytesThatAreNotAZipOrCarryNoKml() {
        assertNull(SavedKmz.kml("not a zip".encodeToByteArray()))
        assertNull(SavedKmz.kml(byteArrayOf(0x50, 0x4B, 3, 4)))
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            zip.putNextEntry(ZipEntry("icon.png"))
            zip.write(byteArrayOf(1, 2, 3))
            zip.closeEntry()
        }
        assertNull(SavedKmz.kml(out.toByteArray()))
    }
}
