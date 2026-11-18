package app.vela.ios.search

import app.vela.core.platform.KeyValueStores
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** One quick-search chip: a fixed English query, the Android catalog order and its label key. */
data class QuickChip(
    /** Stable key in the saved order and hidden set. The fuel chip's query changes by region,
     *  so its key is fixed instead. */
    val key: String,
    /** The English words sent to Google, whatever the interface language. */
    val query: String,
    val labelKey: String,
)

/**
 * Android's Quick search buttons catalog (`QuickCategories`), in the same default order. The
 * labels are the 24-language `cat_*` keys, so a chip reads the same wherever it appears.
 */
object QuickChips {
    /** The fuel chip asks for petrol in some regions but keeps this key, as Android does. */
    const val FUEL_KEY = "Gas station"

    /** The default order. A saved order names these keys, so a future build can add one. */
    val KEYS = listOf(
        "Restaurants",
        "Coffee",
        FUEL_KEY,
        "Groceries",
        "Things to do",
        "Hotels",
        "Bars",
        "EV charging station",
        "Parking",
        "Pharmacy",
        "ATMs",
        "Parks",
        "Hospitals",
        "Banks",
        "Post office",
        "Campgrounds",
    )

    /**
     * Every chip, most used first. [fuelQuery] is "Petrol station" where the region says petrol;
     * the key stays [FUEL_KEY] so the saved order survives a language change.
     */
    fun catalog(fuelQuery: String = "Gas station"): List<QuickChip> = listOf(
        QuickChip("Restaurants", "Restaurants", "cat_restaurants"),
        QuickChip("Coffee", "Coffee", "cat_coffee"),
        QuickChip(FUEL_KEY, fuelQuery, "cat_gas"),
        QuickChip("Groceries", "Groceries", "cat_groceries"),
        QuickChip("Things to do", "Things to do", "cat_things_to_do"),
        QuickChip("Hotels", "Hotels", "cat_hotels"),
        QuickChip("Bars", "Bars", "cat_bars"),
        QuickChip("EV charging station", "EV charging station", "cat_ev"),
        QuickChip("Parking", "Parking", "cat_parking"),
        QuickChip("Pharmacy", "Pharmacy", "cat_pharmacy"),
        QuickChip("ATMs", "ATMs", "cat_atms"),
        QuickChip("Parks", "Parks", "cat_parks"),
        QuickChip("Hospitals", "Hospitals", "cat_hospitals"),
        QuickChip("Banks", "Banks", "cat_banks"),
        QuickChip("Post office", "Post office", "cat_post_offices"),
        QuickChip("Campgrounds", "Campgrounds", "cat_campgrounds"),
    )

    /**
     * The keys [order] names first, in that order, then every other default in its default place.
     * An unknown saved key (a chip withdrawn) is skipped; the chip takes the end of the list when
     * it comes back. Port of `QuickChipOrder.arrange`.
     */
    fun arrange(defaults: List<String> = KEYS, order: List<String>): List<String> {
        val known = order.filter { it in defaults }.distinct()
        return known + defaults.filter { it !in known }
    }

    /** [keys] with [key] moved [delta] places, held at both ends. Unchanged when absent. */
    fun moved(keys: List<String>, key: String, delta: Int): List<String> {
        val from = keys.indexOf(key)
        if (from < 0) return keys
        val to = (from + delta).coerceIn(0, keys.size - 1)
        if (to == from) return keys
        return keys.toMutableList().apply { removeAt(from); add(to, key) }
    }
}

/** The saved order and hidden set. An empty order means the catalog's own order. */
data class QuickChipsState(
    val order: List<String> = emptyList(),
    val hidden: Set<String> = emptySet(),
) {
    /** True once the order or the hidden set differs from the default (Android's reset rule). */
    val customized: Boolean get() = order.isNotEmpty() || hidden.isNotEmpty()
}

/**
 * Android's `QuickChipsPref`, in the same `vela_settings` store under the same keys. Android
 * writes the hidden set as a `StringSet`; the shared key-value seam has strings only, so iOS
 * keeps the same keys and joins both values with the same bar separator. The order key keeps
 * Android's exact format.
 */
class QuickChipsStore(keyValues: KeyValueStores) {
    private val settings = keyValues.open("vela_settings")
    private val _state = MutableStateFlow(load())
    val state: StateFlow<QuickChipsState> = _state.asStateFlow()

    fun arranged(): List<String> = QuickChips.arrange(order = _state.value.order)

    /** Chips the map row shows: the arranged list less the switched-off ones. */
    fun visible(): List<String> = arranged().filter { it !in _state.value.hidden }

    fun setShown(key: String, shown: Boolean) {
        val hidden = _state.value.hidden
        val next = if (shown) hidden - key else hidden + key
        if (next == hidden) return
        settings.edit().putString(HIDDEN_KEY, encode(next)).apply()
        _state.value = _state.value.copy(hidden = next)
    }

    fun setOrder(keys: List<String>) {
        if (keys == _state.value.order) return
        settings.edit().putString(ORDER_KEY, keys.joinToString(SEPARATOR)).apply()
        _state.value = _state.value.copy(order = keys)
    }

    /** Moves [key] by [delta] rows in the shown order, as the editor's handle does. */
    fun move(key: String, delta: Int) {
        val keys = arranged()
        setOrder(QuickChips.moved(keys, key, delta))
    }

    fun reset() {
        settings.edit().remove(ORDER_KEY).remove(HIDDEN_KEY).apply()
        _state.value = QuickChipsState()
    }

    private fun load(): QuickChipsState = QuickChipsState(
        order = settings.getString(ORDER_KEY, null)
            ?.split(SEPARATOR)?.filter { it.isNotEmpty() } ?: emptyList(),
        hidden = settings.getString(HIDDEN_KEY, null)
            ?.split(SEPARATOR)?.filter { it.isNotEmpty() }?.toSet() ?: emptySet(),
    )

    private fun encode(keys: Set<String>): String = keys.joinToString(SEPARATOR)

    companion object {
        const val ORDER_KEY = "quick_chips_order"
        const val HIDDEN_KEY = "quick_chips_hidden"

        /** Android's separator: no chip key holds a bar. */
        const val SEPARATOR = "|"
    }
}
