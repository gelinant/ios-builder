package app.vela.ios.search

/**
 * A typed street address and the whole-word test for a result that carries it.
 *
 * This is the iOS copy of Android's pure `core/util/AddressQuery.kt`. The Android file is not in
 * `core-common`, so moving it would widen this change into the Android source sets.
 */
internal object AddressQuery {
    private val LEAD = Regex("""^\s*(\d+[a-zA-Z]?)\s+(.+)$""")
    private val SPLIT = Regex("""[^\p{L}\p{N}]+""")
    private val DIRECTIONS = setOf("n", "s", "e", "w", "ne", "nw", "se", "sw", "north", "south", "east", "west")
    private val TYPES = setOf(
        "st", "street", "ave", "av", "avenue", "rd", "road", "dr", "drive", "ln", "lane", "blvd", "boulevard",
        "ct", "court", "pl", "place", "way", "cir", "circle", "ter", "terrace", "hwy", "highway", "pkwy", "parkway",
        "trl", "trail", "loop", "apt", "unit", "suite", "ste",
    )

    /** The house number and first distinguishing street word, or null for a non-address query. */
    fun parse(query: String): Pair<String, String>? {
        val m = LEAD.find(query) ?: return null
        val words = m.groupValues[2].lowercase().split(SPLIT).filter { it.isNotEmpty() }
        if (words.isEmpty()) return null
        val street = words.firstOrNull { it !in DIRECTIONS && it !in TYPES } ?: words.first()
        return m.groupValues[1].lowercase() to street
    }

    private val CANON = mapOf(
        "n" to "north", "s" to "south", "e" to "east", "w" to "west",
        "ne" to "northeast", "nw" to "northwest", "se" to "southeast", "sw" to "southwest",
        "st" to "street", "ave" to "avenue", "av" to "avenue", "rd" to "road", "dr" to "drive", "ln" to "lane",
        "blvd" to "boulevard", "ct" to "court", "pl" to "place", "cir" to "circle", "ter" to "terrace",
        "hwy" to "highway", "pkwy" to "parkway", "trl" to "trail",
    )
    private val CANON_DIRS = setOf("north", "south", "east", "west", "northeast", "northwest", "southeast", "southwest")
    private val CANON_TYPES = TYPES.map { CANON[it] ?: it }.toSet() - setOf("apt", "unit", "suite", "ste")

    private fun canon(text: String): List<String> =
        text.lowercase().split(SPLIT).filter { it.isNotEmpty() }.map { CANON[it] ?: it }

    /** Android's direction- and street-type-aware score for ordering matching address rows. */
    fun score(query: String, name: String?, address: String?): Int {
        val m = LEAD.find(query) ?: return 0
        val typed = canon(m.groupValues[2].substringBefore(','))
        val got = canon("${name.orEmpty()} ${address.orEmpty()}").toSet()
        var score = typed.count { it in got }
        val typedDirs = typed.filter { it in CANON_DIRS }.toSet()
        val typedTypes = typed.filter { it in CANON_TYPES }.toSet()
        if (typedDirs.isNotEmpty() && got.any { it in CANON_DIRS && it !in typedDirs }) score--
        if (typedTypes.isNotEmpty() && got.any { it in CANON_TYPES && it !in typedTypes }) score--
        return score
    }

    /** Both the house number and distinguishing street word must be whole words of the result. */
    fun matches(query: String, name: String?, address: String?): Boolean {
        val (number, street) = parse(query) ?: return false
        val words = ("${name.orEmpty()} ${address.orEmpty()}").lowercase().split(SPLIT)
        return number in words && street in words
    }
}
