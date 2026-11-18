package app.vela.core.platform

/**
 * Checks the detached signature on a remote bundle (SPEC "Platform seams"): ECDSA over P-256 with
 * SHA-256, which is what `openssl dgst -sha256 -sign <ec.key>` produces
 * (`scripts/sign-calibration.sh`). Android: `java.security`. iOS: `SecKeyVerifySignature` with
 * `ecdsaSignatureMessageX962SHA256`.
 */
interface SignatureVerifier {
    /**
     * True when [signatureBase64] (a DER-encoded ECDSA signature, standard base64, surrounding
     * whitespace ignored) is a valid signature of [content] under [publicKeyBase64] (an EC P-256
     * public key as X.509 SubjectPublicKeyInfo DER, standard base64). Any error, including bad
     * base64 or a malformed key, is false.
     */
    fun verify(content: ByteArray, signatureBase64: String, publicKeyBase64: String): Boolean
}
