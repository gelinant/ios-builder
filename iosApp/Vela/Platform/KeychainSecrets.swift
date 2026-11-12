import Foundation
import Security
import VelaCore

/// The only place a world-layer key is stored on iOS. Values go to the Keychain under one
/// service, one account per layer; the shared `WorldLayerSettings` only asks whether an account
/// exists and never reads the value back. Nothing here logs a key.
///
/// `WorldSecretStore` is the Kotlin interface the sheet's model calls. `has`, `put` and `remove`
/// are the whole surface, so a future layer cannot reach the plaintext through the host.
final class KeychainSecrets: NSObject, WorldSecretStore {
    static let shared = KeychainSecrets()

    /// Bumped only with a migration; the account is the stable `world_layer_<id>_key`.
    private let service = "app.vela.ios.world"

    private override init() {
        super.init()
    }

    private func query(_ secretId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretId,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Presence only: no data is returned, so the key never enters Swift memory here.
    func has(secretId: String) -> Bool {
        var request = query(secretId)
        request[kSecReturnData as String] = false
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(request as CFDictionary, nil) == errSecSuccess
    }

    /// Replaces the value for one account. An empty value is a removal, never an empty secret.
    @discardableResult
    func put(secretId: String, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(secretId: secretId)
            return false
        }
        remove(secretId: secretId)
        var request = query(secretId)
        request[kSecValueData as String] = Data(trimmed.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }

    func remove(secretId: String) {
        SecItemDelete(query(secretId) as CFDictionary)
    }
}
