package app.vela.ios.platform

import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import platform.Foundation.NSNumber
import platform.Foundation.NSUserDefaults

/**
 * [KeyValueStores] over `UserDefaults` (PORTAGE_IOS.md D5): one suite per store name, under the
 * app's bundle id (`app.vela.ios.vela_saved`, ...). Written in Kotlin rather than Swift because
 * the seam's contract throws on a read with the wrong type, which a Swift class cannot do through
 * a Kotlin interface without `@Throws`.
 *
 * Each value is stored with its type, so a read as another type fails as Android's
 * `ClassCastException` does. `apply` writes into `UserDefaults` at once (it persists in the
 * background by itself); `commit` also asks it to synchronize.
 */
class UserDefaultsKeyValueStores(private val prefix: String = "app.vela.ios.") : KeyValueStores {
    private val lock = SynchronizedObject()
    private val stores = HashMap<String, UserDefaultsKeyValueStore>()

    override fun open(name: String): KeyValueStore = synchronized(lock) {
        stores.getOrPut(name) { UserDefaultsKeyValueStore(NSUserDefaults(suiteName = prefix + name)) }
    }
}

class UserDefaultsKeyValueStore(private val defaults: NSUserDefaults) : KeyValueStore {
    private val lock = SynchronizedObject()

    override fun contains(key: String): Boolean = synchronized(lock) { defaults.objectForKey(TYPE + key) != null }

    override fun getString(key: String, default: String?): String? = read(key, S, default) { defaults.stringForKey(key) }
    override fun getLong(key: String, default: Long): Long = read(key, L, default) { (defaults.objectForKey(key) as? NSNumber)?.longLongValue }
    override fun getInt(key: String, default: Int): Int = read(key, I, default) { (defaults.objectForKey(key) as? NSNumber)?.intValue }
    override fun getBoolean(key: String, default: Boolean): Boolean = read(key, B, default) { (defaults.objectForKey(key) as? NSNumber)?.boolValue }
    override fun getFloat(key: String, default: Float): Float = read(key, F, default) { (defaults.objectForKey(key) as? NSNumber)?.floatValue }

    override fun keys(): Set<String> = synchronized(lock) { storedKeys() }

    private fun storedKeys(): Set<String> =
        defaults.dictionaryRepresentation().keys.mapNotNull { (it as? String)?.takeIf { k -> k.startsWith(TYPE) }?.removePrefix(TYPE) }.toSet()

    override fun edit(): KeyValueEditor = Editor()

    private fun <T> read(key: String, type: String, default: T, get: () -> T?): T = synchronized(lock) {
        val stored = defaults.stringForKey(TYPE + key) ?: return@synchronized default
        if (stored != type) throw ClassCastException("$key holds a $stored, read as a $type")
        get() ?: default
    }

    private inner class Editor : KeyValueEditor {
        private var clearAll = false
        private val changes = ArrayList<Pair<String, Pair<String, Any>?>>()

        override fun putString(key: String, value: String?): KeyValueEditor = put(key, value?.let { S to it })
        override fun putLong(key: String, value: Long): KeyValueEditor = put(key, L to value)
        override fun putInt(key: String, value: Int): KeyValueEditor = put(key, I to value)
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor = put(key, B to value)
        override fun putFloat(key: String, value: Float): KeyValueEditor = put(key, F to value)
        override fun remove(key: String): KeyValueEditor = put(key, null)
        override fun clear(): KeyValueEditor = also { clearAll = true }

        private fun put(key: String, value: Pair<String, Any>?): KeyValueEditor = also { changes += key to value }

        override fun apply() {
            write()
            // A user can kill the app immediately after an action. Android's apply() is allowed to
            // finish in the background, but on iOS the pending write would then be lost.
            defaults.synchronize()
        }

        override fun commit(): Boolean {
            write()
            return defaults.synchronize()
        }

        private fun write() = synchronized(lock) {
            if (clearAll) {
                for (k in storedKeys()) {
                    defaults.removeObjectForKey(k)
                    defaults.removeObjectForKey(TYPE + k)
                }
            }
            for ((key, change) in changes) {
                if (change == null) {
                    defaults.removeObjectForKey(key)
                    defaults.removeObjectForKey(TYPE + key)
                    continue
                }
                val (type, value) = change
                when (value) {
                    is String -> defaults.setObject(value, key)
                    is Long -> defaults.setObject(NSNumber(longLong = value), key)
                    is Int -> defaults.setInteger(value.toLong(), key)
                    is Boolean -> defaults.setBool(value, key)
                    is Float -> defaults.setFloat(value, key)
                }
                defaults.setObject(type, TYPE + key)
            }
        }
    }

    private companion object {
        /** The type of each value lives next to it under this prefix. */
        const val TYPE = "__type__."
        const val S = "String"
        const val L = "Long"
        const val I = "Int"
        const val B = "Boolean"
        const val F = "Float"
    }
}
