package app.vela.core.platform

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JvmSignatureVerifierTest {

    // The EC P-256 public key pinned in CalibrationStore (the private half lives in
    // ~/.vela-signing, never the repo). SIG was produced by:
    //   printf 'vela-bundle-test' | openssl dgst -sha256 -sign vela-calibration.key | base64
    private val pubKey =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEuz8/zxOJFhVqKco74fkmzrLlyPra4/pTEUm7lmue/Kig0T497fcs+hjhZkaSqVZAwloNrr0+0ILi7yATmU+d3g=="
    private val content = "vela-bundle-test".toByteArray(Charsets.UTF_8)
    private val sig =
        "MEUCICNp3ywAv9ociTILtnAj+ji1C5OOktZVZlUPcfFu/VNmAiEAj28opQKS5UM126c1r1WoLbcTxXfSduo8ZT0KuYTU8ok="

    @Test fun acceptsAValidOpensslSignature() {
        assertTrue(JvmSignatureVerifier.verify(content, sig, pubKey))
    }

    @Test fun rejectsTamperedContent() {
        assertFalse(JvmSignatureVerifier.verify("vela-bundle-TEST".toByteArray(), sig, pubKey))
    }

    @Test fun rejectsAGarbageSignature() {
        assertFalse(JvmSignatureVerifier.verify(content, "bm90LWEtc2ln", pubKey))
        assertFalse(JvmSignatureVerifier.verify(content, "", pubKey))
    }

    @Test fun rejectsWrongKey() {
        // A different (valid-format) P-256 SPKI key must not verify this signature.
        val otherKey =
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEzqNE/dKDceX4Gqh632nAku8CWFePZNOkY0GcBbHbX7ClA0bwXc5LowB6KlPVggtWzfLlC1oTAb8VMcBDhdsftA=="
        assertFalse(JvmSignatureVerifier.verify(content, sig, otherKey))
    }
}
