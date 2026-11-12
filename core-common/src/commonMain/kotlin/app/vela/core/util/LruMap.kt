package app.vela.core.util

/**
 * A map that keeps the [maxSize] most recently used entries, as a `java.util.LinkedHashMap` in
 * access order whose `removeEldestEntry` is `size > maxSize`: a read or a write makes an entry the
 * most recent, and a write past [maxSize] drops the least recent. Not thread-safe; callers lock.
 */
class LruMap<K, V : Any>(private val maxSize: Int) {
    private val map = LinkedHashMap<K, V>()

    val size: Int get() = map.size

    operator fun get(key: K): V? {
        val v = map.remove(key) ?: return null
        map[key] = v
        return v
    }

    operator fun set(key: K, value: V) {
        map.remove(key)
        map[key] = value
        if (map.size > maxSize) map.remove(map.keys.first())
    }

    fun clear() = map.clear()
}
