import Foundation
import Security
import VelaCore

/// The `SignatureVerifier` seam over the Security framework (SPEC "Platform seams"): ECDSA P-256
/// with SHA-256, the DER signature `openssl dgst -sha256 -sign` writes. `SecKeyCreateWithData`
/// takes the raw uncompressed point (0x04, X, Y), the last 65 bytes of the 91-byte X.509
/// SubjectPublicKeyInfo; the 26 bytes before it must be the P-256 header. Any error is false.
final class SecKeySignatureVerifier: NSObject, VelaCore.SignatureVerifier {
    /// SEQUENCE { SEQUENCE { id-ecPublicKey, prime256v1 }, BIT STRING header } of a P-256 SPKI.
    static let p256SpkiHeader = Data([
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ])

    /// The calibration signing key, `CalibrationStore.PINNED_PUBLIC_KEY`.
    static var pinnedCalibrationKey: String { CalibrationStore.companion.PINNED_PUBLIC_KEY }

    func verify(content: KotlinByteArray, signatureBase64: String, publicKeyBase64: String) -> Bool {
        Self.verify(IosBytes.shared.toData(bytes: content), signatureBase64: signatureBase64,
                    publicKeyBase64: publicKeyBase64)
    }

    static func verify(_ content: Data, signatureBase64: String, publicKeyBase64: String) -> Bool {
        guard let spki = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              spki.count == p256SpkiHeader.count + 65,
              spki.prefix(p256SpkiHeader.count) == p256SpkiHeader,
              let signature = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        let point = Data(spki.suffix(65))
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(point as CFData, attributes as CFDictionary, &error) else {
            return false
        }
        return SecKeyVerifySignature(key, .ecdsaSignatureMessageX962SHA256, content as CFData,
                                     signature as CFData, &error)
    }
}
