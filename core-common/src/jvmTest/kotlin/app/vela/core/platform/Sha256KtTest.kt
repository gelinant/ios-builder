package app.vela.core.platform

import java.security.MessageDigest
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertContentEquals

/** The Kotlin SHA-256 iOS runs, against the JDK's. */
class Sha256KtTest {
    @Test fun matchesMessageDigestAtEveryBlockBoundary() {
        val r = Random(7)
        for (n in (0..200) + listOf(1000, 4095, 4096, 65_537)) {
            val bytes = r.nextBytes(n)
            val k = Sha256Kt()
            // Fed in uneven pieces, as the fingerprint feeds it.
            var i = 0
            while (i < n) { val m = minOf(n - i, 1 + r.nextInt(70)); k.update(bytes.copyOfRange(i, i + m)); i += m }
            assertContentEquals(MessageDigest.getInstance("SHA-256").digest(bytes), k.digest(), "length $n")
        }
    }
}
