package app.vela.core.platform

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * [SignatureVerifier] over `java.security`: ECDSA-P256 / SHA-256, exactly what
 * `openssl dgst -sha256 -sign <ec.key>` produces, so the dev-side signing step is a one-liner.
 * Pure JVM crypto (no Android types), so it's unit-testable.
 */
object JvmSignatureVerifier : SignatureVerifier {
    /** True iff [signatureBase64] is a valid signature of [content] under [publicKeyBase64]
     *  (an EC P-256 SPKI public key, base64). Any error → false (reject). */
    override fun verify(content: ByteArray, signatureBase64: String, publicKeyBase64: String): Boolean = runCatching {
        val pub = KeyFactory.getInstance("EC")
            .generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)))
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(pub)
            update(content)
            verify(Base64.getDecoder().decode(signatureBase64.trim()))
        }
    }.getOrDefault(false)
}
