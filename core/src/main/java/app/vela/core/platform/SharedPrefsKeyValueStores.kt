package app.vela.core.platform

import android.content.Context
import android.content.SharedPreferences

/** [KeyValueStores] over `SharedPreferences`: [open] is `getSharedPreferences(name, MODE_PRIVATE)`. */
class SharedPrefsKeyValueStores(private val context: Context) : KeyValueStores {
    override fun open(name: String): KeyValueStore =
        SharedPrefsKeyValueStore(context.getSharedPreferences(name, Context.MODE_PRIVATE))
}

/** [KeyValueStore] over one `SharedPreferences` file. */
class SharedPrefsKeyValueStore(private val prefs: SharedPreferences) : KeyValueStore {
    override fun contains(key: String): Boolean = prefs.contains(key)
    override fun getString(key: String, default: String?): String? = prefs.getString(key, default)
    override fun getLong(key: String, default: Long): Long = prefs.getLong(key, default)
    override fun getInt(key: String, default: Int): Int = prefs.getInt(key, default)
    override fun getBoolean(key: String, default: Boolean): Boolean = prefs.getBoolean(key, default)
    override fun getFloat(key: String, default: Float): Float = prefs.getFloat(key, default)
    override fun keys(): Set<String> = prefs.all.keys.toSet()
    override fun edit(): KeyValueEditor = Editor(prefs.edit())

    private class Editor(private val e: SharedPreferences.Editor) : KeyValueEditor {
        override fun putString(key: String, value: String?): KeyValueEditor = also { e.putString(key, value) }
        override fun putLong(key: String, value: Long): KeyValueEditor = also { e.putLong(key, value) }
        override fun putInt(key: String, value: Int): KeyValueEditor = also { e.putInt(key, value) }
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor = also { e.putBoolean(key, value) }
        override fun putFloat(key: String, value: Float): KeyValueEditor = also { e.putFloat(key, value) }
        override fun remove(key: String): KeyValueEditor = also { e.remove(key) }
        override fun clear(): KeyValueEditor = also { e.clear() }
        override fun apply() = e.apply()
        override fun commit(): Boolean = e.commit()
    }
}
