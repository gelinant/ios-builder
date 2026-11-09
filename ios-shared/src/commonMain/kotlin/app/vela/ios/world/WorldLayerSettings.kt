package app.vela.ios.world

import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores

/**
 * A key source that is not UserDefaults. The iOS implementation is `KeychainSecrets`, which only
 * answers presence here and receives the value through [put]. The shared code never reads a key
 * back, never formats one and never writes one to the flag store.
 */
interface WorldSecretStore {
    fun has(secretId: String): Boolean
    fun put(secretId: String, value: String): Boolean
    fun remove(secretId: String)
}

/**
 * The world layers' switches and timestamps, under stable keys in their own settings store. It
 * makes no request and starts no task: a layer's own lot writes its switch, records a timestamp
 * after a fetch [markUpdated], and reads [state] to decide whether its data may still draw.
 *
 * Keys are never written here. [setKey] only forwards to [WorldSecretStore]; [keyPresent] only
 * returns a boolean, so the sheet can say whether a key exists without holding its value.
 */
class WorldLayerSettings(
    stores: KeyValueStores,
    private val secrets: WorldSecretStore,
) {
    private val flags: KeyValueStore = stores.open(STORE)

    /** A layer starts off; the default is never on. */
    fun isEnabled(id: String): Boolean = flags.getBoolean(flagKey(id), false)

    fun setEnabled(id: String, on: Boolean) {
        if (WorldLayerCatalog.find(id) == null) return
        flags.edit().putBoolean(flagKey(id), on).apply()
    }

    /** Epoch milliseconds of the last accepted data, 0 when the layer has none yet. */
    fun lastUpdatedMs(id: String): Long = flags.getLong(updatedKey(id), 0L)

    /** Records a fetch result. Kept apart from the key: no secret ever reaches [flags]. */
    fun markUpdated(id: String, atMs: Long) {
        if (WorldLayerCatalog.find(id) == null || atMs <= 0L) return
        flags.edit().putLong(updatedKey(id), atMs).apply()
    }

    /** True when the user has saved a key for this layer. The value itself stays in the Keychain. */
    fun keyPresent(id: String): Boolean {
        val spec = WorldLayerCatalog.find(id) ?: return false
        return secrets.has(secretId(spec.id))
    }

    /** Saves a key in the secret store. An empty value clears it; plaintext never goes to [flags]. */
    fun setKey(id: String, value: String) {
        if (WorldLayerCatalog.find(id) == null) return
        val trimmed = value.trim()
        if (trimmed.isEmpty()) secrets.remove(secretId(id)) else secrets.put(secretId(id), trimmed)
    }

    fun clearKey(id: String) {
        if (WorldLayerCatalog.find(id) == null) return
        secrets.remove(secretId(id))
    }

    /** The state of one layer at [nowMs]. [installed] comes from the Swift file that owns it. */
    fun state(id: String, installed: Boolean, nowMs: Long): WorldLayerState {
        val spec = WorldLayerCatalog.find(id)
            ?: return WorldLayerState(
                id = id,
                enabled = false,
                installed = false,
                needsKey = false,
                keyPresent = false,
                updatedAtMs = 0L,
                nowMs = nowMs,
                maxAgeSeconds = 0L,
            )
        return WorldLayerState(
            id = spec.id,
            enabled = isEnabled(spec.id),
            installed = installed,
            needsKey = spec.needsKey,
            keyPresent = keyPresent(spec.id),
            updatedAtMs = lastUpdatedMs(spec.id),
            nowMs = nowMs,
            maxAgeSeconds = spec.maxAgeSeconds,
        )
    }

    /** Every state in catalog order; Swift calls [state] per layer instead and keeps its own order. */
    fun snapshot(installedIds: Set<String>, nowMs: Long): List<WorldLayerState> =
        WorldLayerCatalog.ALL.map { state(it.id, it.id in installedIds, nowMs) }

    companion object {
        /** The settings suite opened by [WorldLayerSettings], separate from `vela_settings`. */
        const val STORE = "vela_world"

        /** Stable switch key: `world_layer_<id>_on`. */
        fun flagKey(id: String): String = "world_layer_${id}_on"

        /** Stable timestamp key: `world_layer_<id>_updated_at`. */
        fun updatedKey(id: String): String = "world_layer_${id}_updated_at"

        /** Keychain account name: `world_layer_<id>_key`. */
        fun secretId(id: String): String = "world_layer_${id}_key"
    }
}
