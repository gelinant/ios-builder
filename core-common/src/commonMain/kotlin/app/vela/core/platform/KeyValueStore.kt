package app.vela.core.platform

/**
 * Named key-value files (SPEC "Platform seams"). Android: `SharedPreferences`, one file per name
 * (`getSharedPreferences(name, MODE_PRIVATE)`), so an existing install reads its old data. iOS: a
 * `UserDefaults` suite per name.
 */
interface KeyValueStores {
    /** The store called [name] (`vela_saved`, `vela_settings`, ...). The same name gives the same
     *  data within a process. */
    fun open(name: String): KeyValueStore
}

/**
 * One named store. Reads see every edit applied before them in this process, including an
 * [KeyValueEditor.apply] whose disk write has not finished.
 *
 * Reading a key as a type other than the one it was written with is an error: Android throws
 * `ClassCastException`. Callers keep one type per key.
 */
interface KeyValueStore {
    fun contains(key: String): Boolean
    fun getString(key: String, default: String?): String?
    fun getLong(key: String, default: Long): Long
    fun getInt(key: String, default: Int): Int
    fun getBoolean(key: String, default: Boolean): Boolean
    fun getFloat(key: String, default: Float): Float

    /** Every key present now. */
    fun keys(): Set<String>

    /** A batch of changes. Nothing is visible until [KeyValueEditor.apply] or
     *  [KeyValueEditor.commit]. */
    fun edit(): KeyValueEditor
}

/**
 * Changes to one [KeyValueStore], applied together. Each call returns the editor for chaining, as
 * `SharedPreferences.Editor` does. [clear] runs first at apply time, whatever its place in the
 * chain; the other changes run in call order.
 */
interface KeyValueEditor {
    /** A null [value] removes the key. */
    fun putString(key: String, value: String?): KeyValueEditor
    fun putLong(key: String, value: Long): KeyValueEditor
    fun putInt(key: String, value: Int): KeyValueEditor
    fun putBoolean(key: String, value: Boolean): KeyValueEditor
    fun putFloat(key: String, value: Float): KeyValueEditor
    fun remove(key: String): KeyValueEditor
    fun clear(): KeyValueEditor

    /** Makes the changes visible at once and writes them to disk in the background. A process
     *  kill right after can lose them. */
    fun apply()

    /** Makes the changes visible and writes them to disk before returning. Blocks: never on the
     *  main thread. Returns false when the write failed. */
    fun commit(): Boolean
}
