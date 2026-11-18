package app.vela.core.data

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo

/**
 * Matching and ranking for offline search, shared by the place packs ([OfflinePoiStore], OSM) and
 * the downloaded places archives the map draws (Overture, AllThePlaces, OSM), so a result from
 * either source is judged the same way.
 */
object OfflineRank {
    /** A category query (the map's chips, "restaurants", "gas") keeps to results this close to the
     *  search point: with no place pack for the area, "Restaurants" used to list a downloaded state
     *  on the far side of the country. A name search is never cut. */
    const val CATEGORY_MAX_M = 100_000.0

    /** Two rows this close with the same name are one place seen by two sources. */
    private const val SAME_PLACE_M = 120.0

    fun isCategoryQuery(query: String): Boolean = OfflinePoiStore.categoryKeywords(query.trim()).isNotEmpty()

    // The accented Latin letters fold spells plainly: Latin-1, Latin Extended-A and B (European
    // languages, Turkish) and the Vietnamese vowels. glob builds its classes from the same ranges.
    private val ACCENTED_LATIN = Regex("[\u00C0-\u024F\u1EA0-\u1EF9]")
    private val MARKS_ON_LATIN = Regex("([A-Za-z\u00C0-\u024F])\\p{Mn}+")

    /** A name or query with what people do not type folded away: accents on Latin letters ("cafe"
     *  is "Café", "zurich" is "Zürich"), apostrophes and periods dropped, hyphens as spaces,
     *  lowercase. Only Latin is folded: the pack query can match a folded letter only through
     *  [glob]'s classes, which are Latin, and decomposing other scripts takes the voicing marks
     *  off kana, splits Hangul and drops Thai, Devanagari and Arabic vowel signs, which no name
     *  in a pack would then match. */
    fun fold(s: String): String =
        MARKS_ON_LATIN.replace(
            ACCENTED_LATIN.replace(s) { LATIN_NFD[it.value[0]] ?: it.value },
            "$1",
        ).lowercase()
            .replace("ß", "ss").replace("æ", "ae").replace("œ", "oe").replace("ø", "o").replace("ł", "l").replace("đ", "d").replace("ı", "i")
            .replace("'", "").replace("\u2019", "").replace(".", "").replace('-', ' ')

    /** The canonical decomposition (NFD) of every letter [ACCENTED_LATIN] matches that has one, from
     *  the Unicode tables: Latin decompositions are frozen by Unicode's stability policy, and
     *  `OfflineRankJvmParityTest` checks each one against `java.text.Normalizer`, which this used
     *  to call. Entries are the letter then its decomposition, separated by spaces. */
    internal val LATIN_NFD: Map<Char, String> by lazy {
        LATIN_NFD_TABLE.split(' ').associate { it[0] to it.substring(1) }
    }

    private const val LATIN_NFD_TABLE =
        "\u00C0\u0041\u0300 \u00C1\u0041\u0301 \u00C2\u0041\u0302 \u00C3\u0041\u0303 " +
        "\u00C4\u0041\u0308 \u00C5\u0041\u030A \u00C7\u0043\u0327 \u00C8\u0045\u0300 " +
        "\u00C9\u0045\u0301 \u00CA\u0045\u0302 \u00CB\u0045\u0308 \u00CC\u0049\u0300 " +
        "\u00CD\u0049\u0301 \u00CE\u0049\u0302 \u00CF\u0049\u0308 \u00D1\u004E\u0303 " +
        "\u00D2\u004F\u0300 \u00D3\u004F\u0301 \u00D4\u004F\u0302 \u00D5\u004F\u0303 " +
        "\u00D6\u004F\u0308 \u00D9\u0055\u0300 \u00DA\u0055\u0301 \u00DB\u0055\u0302 " +
        "\u00DC\u0055\u0308 \u00DD\u0059\u0301 \u00E0\u0061\u0300 \u00E1\u0061\u0301 " +
        "\u00E2\u0061\u0302 \u00E3\u0061\u0303 \u00E4\u0061\u0308 \u00E5\u0061\u030A " +
        "\u00E7\u0063\u0327 \u00E8\u0065\u0300 \u00E9\u0065\u0301 \u00EA\u0065\u0302 " +
        "\u00EB\u0065\u0308 \u00EC\u0069\u0300 \u00ED\u0069\u0301 \u00EE\u0069\u0302 " +
        "\u00EF\u0069\u0308 \u00F1\u006E\u0303 \u00F2\u006F\u0300 \u00F3\u006F\u0301 " +
        "\u00F4\u006F\u0302 \u00F5\u006F\u0303 \u00F6\u006F\u0308 \u00F9\u0075\u0300 " +
        "\u00FA\u0075\u0301 \u00FB\u0075\u0302 \u00FC\u0075\u0308 \u00FD\u0079\u0301 " +
        "\u00FF\u0079\u0308 \u0100\u0041\u0304 \u0101\u0061\u0304 \u0102\u0041\u0306 " +
        "\u0103\u0061\u0306 \u0104\u0041\u0328 \u0105\u0061\u0328 \u0106\u0043\u0301 " +
        "\u0107\u0063\u0301 \u0108\u0043\u0302 \u0109\u0063\u0302 \u010A\u0043\u0307 " +
        "\u010B\u0063\u0307 \u010C\u0043\u030C \u010D\u0063\u030C \u010E\u0044\u030C " +
        "\u010F\u0064\u030C \u0112\u0045\u0304 \u0113\u0065\u0304 \u0114\u0045\u0306 " +
        "\u0115\u0065\u0306 \u0116\u0045\u0307 \u0117\u0065\u0307 \u0118\u0045\u0328 " +
        "\u0119\u0065\u0328 \u011A\u0045\u030C \u011B\u0065\u030C \u011C\u0047\u0302 " +
        "\u011D\u0067\u0302 \u011E\u0047\u0306 \u011F\u0067\u0306 \u0120\u0047\u0307 " +
        "\u0121\u0067\u0307 \u0122\u0047\u0327 \u0123\u0067\u0327 \u0124\u0048\u0302 " +
        "\u0125\u0068\u0302 \u0128\u0049\u0303 \u0129\u0069\u0303 \u012A\u0049\u0304 " +
        "\u012B\u0069\u0304 \u012C\u0049\u0306 \u012D\u0069\u0306 \u012E\u0049\u0328 " +
        "\u012F\u0069\u0328 \u0130\u0049\u0307 \u0134\u004A\u0302 \u0135\u006A\u0302 " +
        "\u0136\u004B\u0327 \u0137\u006B\u0327 \u0139\u004C\u0301 \u013A\u006C\u0301 " +
        "\u013B\u004C\u0327 \u013C\u006C\u0327 \u013D\u004C\u030C \u013E\u006C\u030C " +
        "\u0143\u004E\u0301 \u0144\u006E\u0301 \u0145\u004E\u0327 \u0146\u006E\u0327 " +
        "\u0147\u004E\u030C \u0148\u006E\u030C \u014C\u004F\u0304 \u014D\u006F\u0304 " +
        "\u014E\u004F\u0306 \u014F\u006F\u0306 \u0150\u004F\u030B \u0151\u006F\u030B " +
        "\u0154\u0052\u0301 \u0155\u0072\u0301 \u0156\u0052\u0327 \u0157\u0072\u0327 " +
        "\u0158\u0052\u030C \u0159\u0072\u030C \u015A\u0053\u0301 \u015B\u0073\u0301 " +
        "\u015C\u0053\u0302 \u015D\u0073\u0302 \u015E\u0053\u0327 \u015F\u0073\u0327 " +
        "\u0160\u0053\u030C \u0161\u0073\u030C \u0162\u0054\u0327 \u0163\u0074\u0327 " +
        "\u0164\u0054\u030C \u0165\u0074\u030C \u0168\u0055\u0303 \u0169\u0075\u0303 " +
        "\u016A\u0055\u0304 \u016B\u0075\u0304 \u016C\u0055\u0306 \u016D\u0075\u0306 " +
        "\u016E\u0055\u030A \u016F\u0075\u030A \u0170\u0055\u030B \u0171\u0075\u030B " +
        "\u0172\u0055\u0328 \u0173\u0075\u0328 \u0174\u0057\u0302 \u0175\u0077\u0302 " +
        "\u0176\u0059\u0302 \u0177\u0079\u0302 \u0178\u0059\u0308 \u0179\u005A\u0301 " +
        "\u017A\u007A\u0301 \u017B\u005A\u0307 \u017C\u007A\u0307 \u017D\u005A\u030C " +
        "\u017E\u007A\u030C \u01A0\u004F\u031B \u01A1\u006F\u031B \u01AF\u0055\u031B " +
        "\u01B0\u0075\u031B \u01CD\u0041\u030C \u01CE\u0061\u030C \u01CF\u0049\u030C " +
        "\u01D0\u0069\u030C \u01D1\u004F\u030C \u01D2\u006F\u030C \u01D3\u0055\u030C " +
        "\u01D4\u0075\u030C \u01D5\u0055\u0308\u0304 \u01D6\u0075\u0308\u0304 " +
        "\u01D7\u0055\u0308\u0301 \u01D8\u0075\u0308\u0301 \u01D9\u0055\u0308\u030C " +
        "\u01DA\u0075\u0308\u030C \u01DB\u0055\u0308\u0300 \u01DC\u0075\u0308\u0300 " +
        "\u01DE\u0041\u0308\u0304 \u01DF\u0061\u0308\u0304 \u01E0\u0041\u0307\u0304 " +
        "\u01E1\u0061\u0307\u0304 \u01E2\u00C6\u0304 \u01E3\u00E6\u0304 \u01E6\u0047\u030C " +
        "\u01E7\u0067\u030C \u01E8\u004B\u030C \u01E9\u006B\u030C \u01EA\u004F\u0328 " +
        "\u01EB\u006F\u0328 \u01EC\u004F\u0328\u0304 \u01ED\u006F\u0328\u0304 \u01EE\u01B7\u030C " +
        "\u01EF\u0292\u030C \u01F0\u006A\u030C \u01F4\u0047\u0301 \u01F5\u0067\u0301 " +
        "\u01F8\u004E\u0300 \u01F9\u006E\u0300 \u01FA\u0041\u030A\u0301 \u01FB\u0061\u030A\u0301 " +
        "\u01FC\u00C6\u0301 \u01FD\u00E6\u0301 \u01FE\u00D8\u0301 \u01FF\u00F8\u0301 " +
        "\u0200\u0041\u030F \u0201\u0061\u030F \u0202\u0041\u0311 \u0203\u0061\u0311 " +
        "\u0204\u0045\u030F \u0205\u0065\u030F \u0206\u0045\u0311 \u0207\u0065\u0311 " +
        "\u0208\u0049\u030F \u0209\u0069\u030F \u020A\u0049\u0311 \u020B\u0069\u0311 " +
        "\u020C\u004F\u030F \u020D\u006F\u030F \u020E\u004F\u0311 \u020F\u006F\u0311 " +
        "\u0210\u0052\u030F \u0211\u0072\u030F \u0212\u0052\u0311 \u0213\u0072\u0311 " +
        "\u0214\u0055\u030F \u0215\u0075\u030F \u0216\u0055\u0311 \u0217\u0075\u0311 " +
        "\u0218\u0053\u0326 \u0219\u0073\u0326 \u021A\u0054\u0326 \u021B\u0074\u0326 " +
        "\u021E\u0048\u030C \u021F\u0068\u030C \u0226\u0041\u0307 \u0227\u0061\u0307 " +
        "\u0228\u0045\u0327 \u0229\u0065\u0327 \u022A\u004F\u0308\u0304 \u022B\u006F\u0308\u0304 " +
        "\u022C\u004F\u0303\u0304 \u022D\u006F\u0303\u0304 \u022E\u004F\u0307 \u022F\u006F\u0307 " +
        "\u0230\u004F\u0307\u0304 \u0231\u006F\u0307\u0304 \u0232\u0059\u0304 \u0233\u0079\u0304 " +
        "\u1EA0\u0041\u0323 \u1EA1\u0061\u0323 \u1EA2\u0041\u0309 \u1EA3\u0061\u0309 " +
        "\u1EA4\u0041\u0302\u0301 \u1EA5\u0061\u0302\u0301 \u1EA6\u0041\u0302\u0300 " +
        "\u1EA7\u0061\u0302\u0300 \u1EA8\u0041\u0302\u0309 \u1EA9\u0061\u0302\u0309 " +
        "\u1EAA\u0041\u0302\u0303 \u1EAB\u0061\u0302\u0303 \u1EAC\u0041\u0323\u0302 " +
        "\u1EAD\u0061\u0323\u0302 \u1EAE\u0041\u0306\u0301 \u1EAF\u0061\u0306\u0301 " +
        "\u1EB0\u0041\u0306\u0300 \u1EB1\u0061\u0306\u0300 \u1EB2\u0041\u0306\u0309 " +
        "\u1EB3\u0061\u0306\u0309 \u1EB4\u0041\u0306\u0303 \u1EB5\u0061\u0306\u0303 " +
        "\u1EB6\u0041\u0323\u0306 \u1EB7\u0061\u0323\u0306 \u1EB8\u0045\u0323 \u1EB9\u0065\u0323 " +
        "\u1EBA\u0045\u0309 \u1EBB\u0065\u0309 \u1EBC\u0045\u0303 \u1EBD\u0065\u0303 " +
        "\u1EBE\u0045\u0302\u0301 \u1EBF\u0065\u0302\u0301 \u1EC0\u0045\u0302\u0300 " +
        "\u1EC1\u0065\u0302\u0300 \u1EC2\u0045\u0302\u0309 \u1EC3\u0065\u0302\u0309 " +
        "\u1EC4\u0045\u0302\u0303 \u1EC5\u0065\u0302\u0303 \u1EC6\u0045\u0323\u0302 " +
        "\u1EC7\u0065\u0323\u0302 \u1EC8\u0049\u0309 \u1EC9\u0069\u0309 \u1ECA\u0049\u0323 " +
        "\u1ECB\u0069\u0323 \u1ECC\u004F\u0323 \u1ECD\u006F\u0323 \u1ECE\u004F\u0309 " +
        "\u1ECF\u006F\u0309 \u1ED0\u004F\u0302\u0301 \u1ED1\u006F\u0302\u0301 " +
        "\u1ED2\u004F\u0302\u0300 \u1ED3\u006F\u0302\u0300 \u1ED4\u004F\u0302\u0309 " +
        "\u1ED5\u006F\u0302\u0309 \u1ED6\u004F\u0302\u0303 \u1ED7\u006F\u0302\u0303 " +
        "\u1ED8\u004F\u0323\u0302 \u1ED9\u006F\u0323\u0302 \u1EDA\u004F\u031B\u0301 " +
        "\u1EDB\u006F\u031B\u0301 \u1EDC\u004F\u031B\u0300 \u1EDD\u006F\u031B\u0300 " +
        "\u1EDE\u004F\u031B\u0309 \u1EDF\u006F\u031B\u0309 \u1EE0\u004F\u031B\u0303 " +
        "\u1EE1\u006F\u031B\u0303 \u1EE2\u004F\u031B\u0323 \u1EE3\u006F\u031B\u0323 " +
        "\u1EE4\u0055\u0323 \u1EE5\u0075\u0323 \u1EE6\u0055\u0309 \u1EE7\u0075\u0309 " +
        "\u1EE8\u0055\u031B\u0301 \u1EE9\u0075\u031B\u0301 \u1EEA\u0055\u031B\u0300 " +
        "\u1EEB\u0075\u031B\u0300 \u1EEC\u0055\u031B\u0309 \u1EED\u0075\u031B\u0309 " +
        "\u1EEE\u0055\u031B\u0303 \u1EEF\u0075\u031B\u0303 \u1EF0\u0055\u031B\u0323 " +
        "\u1EF1\u0075\u031B\u0323 \u1EF2\u0059\u0300 \u1EF3\u0079\u0300 \u1EF4\u0059\u0323 " +
        "\u1EF5\u0079\u0323 \u1EF6\u0059\u0309 \u1EF7\u0079\u0309 \u1EF8\u0059\u0303 " +
        "\u1EF9\u0079\u0303"

    /** For each plain letter, every accented letter that [fold] turns into it, both cases: the
     *  Latin-1 and Latin Extended-A/B blocks (European languages, Turkish) and the Vietnamese
     *  vowels. The rest of Latin Extended Additional is left out: every letter in a class is
     *  compared at every position of every name, and those forms are not in place names. */
    private val ACCENTED: Map<Char, String> by lazy {
        val out = HashMap<Char, StringBuilder>()
        for (cp in (0x00C0..0x024F) + (0x1EA0..0x1EF9)) {
            val c = cp.toChar()
            val f = fold(c.toString())
            if (f.length == 1 && f[0] in 'a'..'z') out.getOrPut(f[0]) { StringBuilder() }.append(c)
        }
        out.mapValues { it.value.toString() }
    }

    /** The longest folded text that gets accent classes in [glob]. Past it the letters match by
     *  case only, which keeps the pattern far under SQLite's 50,000-byte limit. */
    private const val GLOB_ACCENT_CHARS = 48

    /**
     * A SQLite GLOB pattern that finds [folded] (text already through [fold]) anywhere in a name,
     * whatever its case or accents: each letter becomes a class of its forms, so "cafe" is
     * `*[cCçÇ...][aAáÁ...][fF][eEéÉ...]*`. The packs store names as OpenStreetMap wrote them and
     * SQLite cannot fold accents itself (its LIKE only ignores case for ASCII), so the folding
     * is done in the pattern. GLOB reads UTF-8 one character at a time, classes included.
     */
    fun glob(folded: String): String = glob(folded, eszett = false)

    /** [glob] with each "ss" read as one "ß", so "strasse" finds "Hauptstraße"; null when the
     *  text has no "ss". A pattern cannot say "ss or ß", and folding ß in the pack's names in
     *  SQL costs every search about a fifth more, so this second pattern is only run when it
     *  can matter. The other letters [fold] spells as two (æ, œ) are typed as themselves by the
     *  people who search for them, and are not given one. */
    fun globEszett(folded: String): String? = if ("ss" in folded) glob(folded, eszett = true) else null

    private fun glob(folded: String, eszett: Boolean): String {
        val sb = StringBuilder("*")
        var skip = false
        folded.forEachIndexed { i, c ->
            if (skip) { skip = false; return@forEachIndexed }
            if (eszett && c == 's' && folded.getOrNull(i + 1) == 's') { sb.append("[ßẞ]"); skip = true; return@forEachIndexed }
            when {
                c == '*' || c == '?' || c == '[' -> sb.append('[').append(c).append(']')
                c == ']' -> sb.append("[]]")
                c in 'a'..'z' -> {
                    sb.append('[').append(c).append(c.uppercaseChar())
                    if (i < GLOB_ACCENT_CHARS) sb.append(ACCENTED[c].orEmpty())
                    sb.append(']')
                }
                c.uppercaseChar() != c -> sb.append('[').append(c).append(c.uppercaseChar()).append(']')
                else -> sb.append(c)
            }
        }
        return sb.append('*').toString()
    }

    /** The single words a multi-word query is also matched by (3+ letters). None for a query that
     *  is a known category: "gas station" must not match on "station". */
    fun queryWords(term: String): List<String> {
        if (isCategoryQuery(term)) return emptyList()
        return term.trim().split(Regex("\\s+")).filter { it.length >= 3 }.takeIf { it.size > 1 }.orEmpty()
    }

    /** The same test the pack SQL runs: the query (or, multi-word, any word of 3+ letters) in the
     *  name or category, a category keyword in the category, or the whole query in the address. */
    fun matches(query: String, name: String, category: String?, address: String?, brand: String? = null): Boolean {
        val term = query.trim().lowercase()
        if (term.isEmpty()) return false
        val n = fold(name)
        val c = category?.lowercase().orEmpty()
        val words = queryWords(term)
        val targets = listOf(term) + words
        val b = brand?.let(::fold)
        if (targets.any { n.contains(fold(it)) || c.contains(it) || b?.contains(fold(it)) == true }) return true
        val cats = OfflinePoiStore.categoryKeywords(term) + words.flatMap { OfflinePoiStore.categoryKeywords(it) }
        if (cats.any { c.contains(it) }) return true
        return address?.lowercase()?.contains(term) == true
    }

    /** Transit stops last (unless the query asks for transit), then the rows that answer more of
     *  the query, then names where the query starts a word, then the nearest. A category row
     *  answers its word too: "restaurants" is not a substring of the category "Restaurant", so
     *  before this every chip result tied and far name matches ("... Restaurants") could lead.
     *  The word-start step is deliberately coarse: "shell" puts Shell ahead of a nearer Seashell
     *  Cafe, but Walmart and Walmart Supercenter stay tied so the nearer one still leads. */
    fun rank(query: String, near: LatLng?, rows: List<Place>, limit: Int): List<Place> {
        val term = query.trim()
        val qWords = queryWords(term).ifEmpty { listOf(term) }.map { it.lowercase() }
        val transitQuery = OfflinePoiStore.TRANSIT_QUERY_WORDS.any { term.lowercase().contains(it) }
        val categoryQuery = isCategoryQuery(term)
        val foldedTerm = fold(term)
        val withDist = rows.map { p -> if (near != null) p.copy(distanceMeters = near.distanceTo(p.location)) else p }
            .filter { p -> !categoryQuery || near == null || (p.distanceMeters ?: 0.0) <= CATEGORY_MAX_M }
        val kept = ArrayList<Place>()
        val seenIds = HashSet<String>()
        for (p in withDist) {
            if (!seenIds.add(p.id)) continue
            val key = p.name.trim().lowercase()
            if (kept.any { it.name.trim().lowercase() == key && it.location.distanceTo(p.location) < SAME_PLACE_M }) continue
            kept.add(p)
        }
        return kept.sortedWith(
            compareBy<Place> { p -> if (!transitQuery && (p.category ?: "").lowercase() in OfflinePoiStore.TRANSIT_STOP_CATS) 1 else 0 }
                .thenByDescending { p ->
                    val hay = (p.name + " " + (p.category ?: "") + " " + (p.address ?: "")).lowercase()
                    val name = fold(p.name)
                    val cat = (p.category ?: "").lowercase()
                    qWords.count { w -> hay.contains(w) || name.contains(fold(w)) || OfflinePoiStore.categoryKeywords(w).any { cat.contains(it) } }
                }.thenBy { p -> if (categoryQuery || startsAWord(fold(p.name), foldedTerm)) 0 else 1 }
                .thenBy { it.distanceMeters ?: Double.MAX_VALUE },
        ).take(limit)
    }

    private fun startsAWord(name: String, q: String): Boolean = q.isNotEmpty() && (name.startsWith(q) || name.contains(" $q"))
}
