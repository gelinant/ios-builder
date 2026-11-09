package app.vela.core.util

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/** A map whose reads and writes take one lock, for `ConcurrentHashMap`'s use as a shared tally. */
class LockedMap<K, V : Any> {
    private val lock = SynchronizedObject()
    private val map = HashMap<K, V>()

    operator fun get(key: K): V? = synchronized(lock) { map[key] }
    operator fun set(key: K, value: V) { synchronized(lock) { map[key] = value } }

    /** A copy of the entries now. */
    fun snapshot(): Map<K, V> = synchronized(lock) { HashMap(map) }
}

/** A list whose appends and copies take one lock, for `Collections.synchronizedList`. */
class LockedList<T> {
    private val lock = SynchronizedObject()
    private val list = ArrayList<T>()

    operator fun plusAssign(item: T) { synchronized(lock) { list.add(item) } }

    val size: Int get() = synchronized(lock) { list.size }

    /** A copy of the items now. */
    fun toList(): List<T> = synchronized(lock) { ArrayList(list) }
}
