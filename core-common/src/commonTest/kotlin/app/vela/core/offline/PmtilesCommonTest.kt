package app.vela.core.offline

import app.vela.core.platform.fileLength
import app.vela.core.platform.gunzip
import app.vela.core.platform.gzip
import app.vela.core.platform.joinPath
import app.vela.core.platform.newTestDir
import app.vela.core.platform.openRandomFile
import app.vela.core.platform.sha256
import app.vela.core.platform.toHex
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The PMTiles code on the platform file, gzip and hash functions, so it also runs on iOS. */
class PmtilesCommonTest {
    private fun layerTile(vararg layers: String): ByteArray {
        val out = ArrayList<Byte>()
        for (name in layers) {
            val n = name.encodeToByteArray()
            val layer = byteArrayOf(0x0A, n.size.toByte()) + n
            out += 0x1A.toByte(); out += layer.size.toByte(); out += layer.toList()
        }
        return out.toByteArray()
    }

    /** A clustered v3 archive at z12: header, gzipped root directory, metadata, gzipped tiles. */
    private fun archive(tiles: List<Pair<Pair<Int, Int>, ByteArray>>): String {
        val blobs = tiles.map { gzip(it.second) }
        var at = 0L
        val entries = tiles.mapIndexed { i, (c, _) ->
            PmtilesReader.Entry(PmtilesReader.tileId(12, c.first, c.second), at, blobs[i].size.toLong(), 1).also { at += blobs[i].size }
        }.sortedBy { it.id }
        val dir = PmtilesCompact.writeDirectory(entries, 2)!!
        val meta = gzip("{}".encodeToByteArray())
        val head = ByteArray(127)
        "PMTiles".encodeToByteArray().copyInto(head)
        head[7] = 3
        fun le64(o: Int, v: Long) { for (i in 0 until 8) head[o + i] = ((v shr (8 * i)) and 0xFF).toByte() }
        le64(8, 127L); le64(16, dir.size.toLong())
        le64(24, 127L + dir.size); le64(32, meta.size.toLong())
        le64(40, 0); le64(56, 127L + dir.size + meta.size); le64(64, at)
        head[96] = 1; head[97] = 2; head[98] = 2; head[100] = 0; head[101] = 12
        val path = joinPath(newTestDir(), "a.pmtiles")
        openRandomFile(path, write = true).use { f ->
            f.write(head); f.write(dir); f.write(meta)
            blobs.forEach { f.write(it) }
            f.sync()
        }
        return path
    }

    @Test fun gzipRoundTripsAndHashesMatchTheStandard() {
        val text = "Vela offline ".repeat(5000).encodeToByteArray()
        assertContentEquals(text, gunzip(gzip(text)))
        assertContentEquals(ByteArray(0), gunzip(gzip(ByteArray(0))))
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", sha256(ByteArray(0)).toHex())
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", sha256("abc".encodeToByteArray()).toHex())
        val million = ByteArray(1_000_000) { 'a'.code.toByte() }
        assertEquals("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", sha256(million).toHex())
    }

    @Test fun aRandomFileReadsWritesAndTruncates() {
        val path = joinPath(newTestDir(), "r.bin")
        openRandomFile(path, write = true).use { f ->
            f.write(byteArrayOf(1, 2, 3, 4, 5))
            assertEquals(5L, f.filePointer())
            f.seek(1)
            assertEquals(2, f.read())
            val two = ByteArray(2).also { f.readFully(it) }
            assertContentEquals(byteArrayOf(3, 4), two)
            f.setLength(3)
            assertEquals(3L, f.length())
            f.seek(3)
            assertEquals(-1, f.read())
        }
        assertEquals(3L, fileLength(path))
        assertEquals(0L, fileLength(joinPath(newTestDir(), "none")))
    }

    @Test fun anArchiveIsReadTileByTile() {
        val roads = layerTile("water", PmtilesReader.ROAD_LAYER)
        val bare = layerTile("water")
        val path = archive(listOf((654 to 1582) to roads, (655 to 1582) to bare))
        val h = assertNotNull(PmtilesReader.header(path))
        assertEquals(12, h.maxZoom)
        assertEquals(true, PmtilesReader.hasTile(path, 12, 654, 1582))
        assertEquals(false, PmtilesReader.hasTile(path, 12, 656, 1582))
        assertNull(PmtilesReader.hasTile(path, 13, 1, 1))
        assertEquals(true, PmtilesReader.hasRoads(path, 12, 654, 1582))
        assertEquals(false, PmtilesReader.hasRoads(path, 12, 655, 1582))
        assertContentEquals(bare, PmtilesReader.tileBytes(path, 12, 655, 1582))
        val got = PmtilesReader.Archive.file(path, fileLength(path), 0L).use { it.tiles(12, listOf(654 to 1582, 655 to 1582, 1 to 1)) }
        assertEquals(setOf(654 to 1582, 655 to 1582), got.keys)
        assertContentEquals(roads, got[654 to 1582])
        assertEquals(2, PmtilesReader.entries(path)?.size)
    }

    @Test fun compactingKeepsTheFingerprint() {
        val path = archive(listOf((1 to 2) to layerTile("a"), (3 to 4) to layerTile("b")))
        val before = assertNotNull(PmtilesPatch.fingerprint(path))
        val out = PmtilesCompact.compact(path)
        assertTrue(out is PmtilesCompact.Outcome.Done || out is PmtilesCompact.Outcome.Refused, "$out")
        assertEquals(before, PmtilesPatch.fingerprint(path))
        assertNull(PmtilesPatch.read(path))
    }
}
