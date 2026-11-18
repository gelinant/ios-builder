package app.vela.ios.place

import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * The two link-only Atlas Obscura addresses the iOS place sheet opens in its Safari sheet.
 *
 * No place text ever reaches either URL: the nearby query only carries the site's own fixed
 * parameters and two bounded numbers, and the Gastro URL is a constant. Nothing is read back,
 * stored, or fetched as an image, and the terms reserve the service to personal non-commercial
 * use, so these functions only describe where a user may browse (docs/ios/PLACE.md, AO-1, AO-2).
 */
object ObscuraLinks {
    const val HOST = "www.atlasobscura.com"

    private const val BASE = "https://$HOST"
    private const val GASTRO = "$BASE/gastro/places"

    /** Atlas Obscura's own nearby search, centred on the place. Null when the point is not finite. */
    fun nearbyUrl(lat: Double, lng: Double): String? {
        if (!lat.isFinite() || !lng.isFinite()) return null
        val boundedLat = lat.coerceIn(-90.0, 90.0)
        val boundedLng = lng.coerceIn(-180.0, 180.0)
        return "$BASE/search?q=&location=&nearby=true&lat=${fixed6(boundedLat)}&lng=${fixed6(boundedLng)}"
    }

    /**
     * Gastro Obscura's place index, which has no position filter, so no coordinate is sent. Null
     * unless [category] is food or drink: the row never appears for an unrelated place.
     */
    fun gastroUrl(category: String?): String? = if (isFood(category)) GASTRO else null

    /** Whether a Google category names food or drink, by whole words and without a locale guess. */
    fun isFood(category: String?): Boolean {
        val text = category?.lowercase() ?: return false
        return splitWords(text).any { it in FOOD_WORDS }
    }

    /** Six fixed decimals, so the same place always produces the same URL on both platforms. */
    private fun fixed6(value: Double): String {
        val scaled = (value * 1_000_000.0).roundToLong()
        val sign = if (scaled < 0) "-" else ""
        val magnitude = abs(scaled)
        val whole = magnitude / 1_000_000L
        val fraction = magnitude % 1_000_000L
        return sign + whole.toString() + "." + fraction.toString().padStart(6, '0')
    }

    private fun splitWords(text: String): List<String> {
        val words = mutableListOf<String>()
        val current = StringBuilder()
        for (char in text) {
            if (char.isLetterOrDigit()) {
                current.append(char)
            } else if (current.isNotEmpty()) {
                words.add(current.toString())
                current.clear()
            }
        }
        if (current.isNotEmpty()) words.add(current.toString())
        return words
    }

    private val FOOD_WORDS = setOf(
        "restaurant", "cafe", "café", "coffee", "bar", "pub", "bakery", "bistro", "bistrot",
        "brasserie", "diner", "deli", "food", "foods", "eatery", "pizzeria", "pizza", "sushi",
        "ramen", "noodle", "noodles", "taqueria", "cantina", "grill", "steakhouse", "brewery",
        "brewpub", "winery", "vineyard", "teahouse", "juice", "dessert", "icecream", "gelato",
        "creamery", "snack", "buffet", "canteen", "gastropub", "tapas", "trattoria", "osteria",
        "patisserie", "pâtisserie", "pastry", "donut", "bagel", "sandwich", "burger", "chicken",
        "seafood", "oyster", "bbq", "barbecue", "smoothie", "chocolatier", "grocery", "butcher",
        "cheese", "wine", "liquor", "cocktail", "crêperie", "creperie", "boulangerie",
    )
}
