package app.vela.ios.offline

import app.vela.core.offline.PmtilesPatch
import app.vela.core.platform.fileLength
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * A real archive and a real patch from `scripts/pmtiles-test-fixture.py`. The apply is accepted
 * only when it reproduces the published fingerprint; a tampered archive is refused and rolled
 * back, never left half patched.
 */
class OfflinePatchTest {
    private fun resource(name: String): ByteArray =
        javaClass.getResourceAsStream("/$name")!!.use { it.readBytes() }

    private fun copy(name: String): String {
        val dir = Files.createTempDirectory("vela-patch").toFile()
        val path = dir.resolve(name).path
        dir.resolve(name).writeBytes(resource(name))
        return path
    }

    @Test fun aValidPatchReachesThePublishedFingerprint() {
        val archive = copy("patched.pmtiles")
        val patch = copy("chain.vpatch")
        val outcome = PmtilesPatch.apply(archive, patch)
        assertTrue(outcome is PmtilesPatch.Outcome.Applied, "$outcome")
        assertEquals("cf8f027c76eaec23e32b013fe3bb250b", PmtilesPatch.fingerprint(archive))
    }

    @Test fun aTamperedArchiveIsRefusedAndLeftExactlyAsItWas() {
        val archive = copy("patched.pmtiles")
        val patch = copy("chain.vpatch")
        val file = java.io.File(archive)
        val bytes = file.readBytes()
        // One tile byte changes, its directory entry does not: only the final fingerprint can
        // catch this, and the archive must come back byte for byte.
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 0xFF).toByte()
        file.writeBytes(bytes)
        val before = fileLength(archive)
        val outcome = PmtilesPatch.apply(archive, patch)
        assertTrue(outcome is PmtilesPatch.Outcome.Refused, "$outcome")
        assertEquals(before, fileLength(archive))
        assertTrue(file.readBytes().contentEquals(bytes))
    }
}
