package app.vela.core.data

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo
import app.vela.core.platform.SqlDb
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.queryLong
import app.vela.core.util.Fmt
import app.vela.core.util.toRadians

/**
 * A tiny on-device place index (SQLite) populated from OpenStreetMap/[OverpassPois]
 * when a map region is downloaded — the keyless, no-backend source behind **offline
 * search**. Used as a fallback when Google search can't be reached (offline).
 */
class OfflinePoiStore(sql: SqlDbs) {
    private val db: SqlDb = sql.open(
        "vela_offline_pois.db", 2,
        onCreate = ::create,
        onUpgrade = { db, _, _ -> db.execute("DROP TABLE IF EXISTS poi"); create(db) },
    )

    private fun create(db: SqlDb) {
        db.execute(
            "CREATE TABLE poi(id TEXT PRIMARY KEY, name TEXT, lat REAL, lng REAL, category TEXT, " +
                "address TEXT, phone TEXT, website TEXT, hours TEXT)",
        )
        db.execute("CREATE INDEX idx_poi_name ON poi(name COLLATE NOCASE)")
    }

    /** Upsert a batch of POIs (deduped by id). Keeps the detail tags (address/phone/
     *  website/hours) the OSM source carries, so an offline place sheet isn't bare. */
    fun add(pois: List<Place>) {
        if (pois.isEmpty()) return
        db.transaction {
            for (p in pois) {
                db.execute(
                    "INSERT OR REPLACE INTO poi(id,name,lat,lng,category,address,phone,website,hours) VALUES (?,?,?,?,?,?,?,?,?)",
                    listOf(
                        p.id, p.name, p.location.lat, p.location.lng, p.category, p.address, p.phone, p.website,
                        p.hours.joinToString("\n").ifBlank { null },
                    ),
                )
            }
        }
    }

    fun count(): Int = db.queryLong("SELECT COUNT(*) FROM poi").toInt()

    /** Every POI within [radiusM] of [loc], nearest first: the businesses AT a typed address. A
     *  pack POI often has no `addr:*` of its own (most US chains do not in OSM), so an address
     *  search could find the house point but never the shop standing on it (user 2026-09-19). */
    fun near(loc: LatLng, radiusM: Double, limit: Int = 6): List<Place> {
        val dLat = radiusM / 111_000.0
        val dLng = dLat / kotlin.math.cos(loc.lat.toRadians()).coerceAtLeast(0.2)
        val args = listOf((loc.lat - dLat).toString(), (loc.lat + dLat).toString(), (loc.lng - dLng).toString(), (loc.lng + dLng).toString())
        val sql = "SELECT id,name,lat,lng,category,address,phone,website,hours FROM poi WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?"
        val rows = ArrayList<Place>()
        fun query(db: SqlDb) {
            runCatching {
                db.query(sql, args) { c ->
                    run {
                        val at = LatLng(c.getDouble(2), c.getDouble(3))
                        val d = loc.distanceTo(at)
                        if (d > radiusM) return@run
                        rows.add(Place(
                            id = c.getString(0)!!, name = c.getString(1)!!, location = at, category = c.getString(4),
                            address = c.getString(5), phone = c.getString(6), website = c.getString(7),
                            hours = app.vela.core.util.OsmHours.lines(c.getString(8)), // packs keep OSM's raw tag
                            distanceMeters = d,
                        ))
                    }
                }
            }
        }
        query(db)
        OfflinePacks.dbs.forEach(::query)
        return rows.distinctBy { it.id }.sortedBy { it.distanceMeters }.take(limit)
    }

    /** Name/category match, nearest first. Robust to a few things a plain LIKE misses:
     *  - Category words ("gas", "coffee", "food", the map's chips) are expanded to the OSM tag values
     *    we actually store — a gas station is category "Fuel" (from `amenity=fuel`), not "gas".
     *  - Multi-word queries ("mexican restaurant", "coffee shop") match the whole phrase OR any single
     *    word, so "mexican restaurant" finds "Ixtapa Mexican Restaurant" and the restaurant category,
     *    instead of returning nothing because no name contains the exact phrase.
     */
    /** [extra]: rows from another source (the downloaded places archives), ranked together with
     *  the packs' own; on a same-name twin within a block the earlier row, an [extra] one, wins. */
    fun search(query: String, near: LatLng?, limit: Int = 30, extra: List<Place> = emptyList()): List<Place> {
        val term = query.trim()
        // name/category LIKE targets: the whole query, plus each word ≥3 chars (multi-word only).
        // A query that IS a known category ("gas station") is not split: its words matched other
        // categories ("station" brought every charging station to the top, issue #657).
        val nameCat = LinkedHashSet<String>().apply { add(term) }
        val words = OfflineRank.queryWords(term)
        nameCat.addAll(words)
        // category-tag targets: keywords for the whole query and for each word.
        val cats = LinkedHashSet<String>().apply { addAll(categoryKeywords(term)); words.forEach { addAll(categoryKeywords(it)) } }

        val clauses = ArrayList<String>()
        val args = ArrayList<String>()
        // Names are compared with apostrophes and periods dropped and hyphens as spaces, on both
        // sides, so "mcdonalds" finds "McDonald's" and "7 eleven" finds "7-Eleven" (issue #657).
        // Accents are folded too, so "cafe" finds "Café": see nameMatch.
        for (t in nameCat) {
            val (sql, a) = nameMatch(OfflineRank.fold(t))
            clauses.add(sql); args.addAll(a)
            clauses.add("category LIKE ?"); args.add("%$t%")
        }
        for (c in cats) { clauses.add("category LIKE ?"); args.add("%$c%") }
        // Whole-query address match, so typing a downloaded POI's street address finds it offline (the
        // general typed-address geocoder is OfflineAddressStore).
        clauses.add("address LIKE ?"); args.add("%$term%")
        // Whole-query NAME matches must survive the LIMIT, not just win the post-sort: a state pack has
        // thousands of category hits ("cafe"), and taking the first 400 in table order dropped an exact
        // name match that lived past them (found while verifying delta updates). The ORDER BY puts
        // phrase-in-name rows first, THEN the cap applies. Its args are the last bound.
        val (phraseInName, phraseArgs) = nameMatch(OfflineRank.fold(term))
        args.addAll(phraseArgs)
        // Then NEAREST first, so the 400 kept are the 400 closest: without it the cut took rows in
        // table order (OSM id order, effectively random across a state) and "restaurants" listed
        // places a hundred miles off while closer ones never made the cut. A flat-earth distance
        // is enough to order them; the pack has no spatial index, so this is the same full scan.
        val nearest = near?.let { n ->
            val k = kotlin.math.cos(n.lat.toRadians())
            val lat = Fmt.fixed(n.lat, 6)
            val lng = Fmt.fixed(n.lng, 6)
            ", ((lat - $lat) * (lat - $lat) + (lng - $lng) * (lng - $lng) * ${Fmt.fixed(k * k, 6)})"
        }.orEmpty()
        val sql = "SELECT id,name,lat,lng,category,address,phone,website,hours FROM poi " +
            "WHERE ${clauses.joinToString(" OR ")} ORDER BY $phraseInName DESC$nearest LIMIT 400"
        val rows = ArrayList<Place>()
        fun query(db: SqlDb) {
            runCatching {
                db.query(sql, args) { c ->
                    run {
                        val loc = LatLng(c.getDouble(2), c.getDouble(3))
                        rows.add(
                            Place(
                                id = c.getString(0)!!,
                                name = c.getString(1)!!,
                                location = loc,
                                category = c.getString(4),
                                address = c.getString(5),
                                phone = c.getString(6),
                                website = c.getString(7),
                                hours = app.vela.core.util.OsmHours.lines(c.getString(8)), // packs keep OSM's raw tag
                                distanceMeters = near?.distanceTo(loc),
                            ),
                        )
                    }
                }
            }
        }
        // The viewport-download index, then every installed region pack (a state's whole POI set) —
        // same schema, same SQL. Dedupe by id (a POI can be in both once its area was also saved).
        query(db)
        OfflinePacks.dbs.forEach(::query)
        return OfflineRank.rank(query, near, extra + rows, limit)
    }

    companion object {
        // Map a search word (or the map's category chip) to the OSM tag values we store as `category`
        // (amenity/shop/leisure/…, space-separated + capitalized, e.g. "Fuel", "Fast food"). Matched
        // case-insensitively via LIKE. Keep the values in the OSM form, not the display word.
        private val CATEGORY_KEYWORDS: Map<String, List<String>> = mapOf(
            "gas" to listOf("fuel", "charging station"),
            "gas station" to listOf("fuel"),
            "fuel" to listOf("fuel"),
            "petrol" to listOf("fuel"),
            "petrol station" to listOf("fuel"),
            "charging" to listOf("charging station"),
            "ev charging" to listOf("charging station"),
            "coffee" to listOf("cafe", "coffee"),
            "cafe" to listOf("cafe"),
            "food" to listOf("restaurant", "fast food"),
            "restaurant" to listOf("restaurant", "fast food"),
            "restaurants" to listOf("restaurant", "fast food"),
            "fast food" to listOf("fast food"),
            "groceries" to listOf("supermarket", "convenience", "greengrocer", "grocery"),
            "grocery" to listOf("supermarket", "convenience", "grocery"), // "grocery": the places archives' "Grocery store"
            "supermarket" to listOf("supermarket"),
            "store" to listOf("supermarket", "convenience", "department store"),
            "pharmacy" to listOf("pharmacy", "chemist"),
            "drug store" to listOf("pharmacy", "chemist"),
            "hotel" to listOf("hotel", "motel", "guest house"),
            "hotels" to listOf("hotel", "motel", "guest house"),
            "motel" to listOf("motel"),
            "lodging" to listOf("hotel", "motel", "guest house", "hostel"),
            "parking" to listOf("parking"),
            "parking lot" to listOf("parking"),
            "atm" to listOf("atm", "bank"),
            "atms" to listOf("atm", "bank"),
            "bank" to listOf("bank", "atm"),
            "banks" to listOf("bank", "atm"),
            "hospital" to listOf("hospital"),
            "hospitals" to listOf("hospital"),
            "clinic" to listOf("clinic", "doctors"),
            "doctor" to listOf("doctors", "clinic"),
            "urgent care" to listOf("clinic", "hospital"),
            "bar" to listOf("bar", "pub", "biergarten"),
            "bars" to listOf("bar", "pub", "biergarten"),
            "pub" to listOf("pub", "bar"),
            "bakery" to listOf("bakery"),
            "park" to listOf("park"),
            "parks" to listOf("park"),
            "school" to listOf("school"),
            "gym" to listOf("fitness center", "fitness centre", "sports center", "sports centre"),
            "car wash" to listOf("car wash"),
            "post office" to listOf("post office"),
            "post offices" to listOf("post office"),
            // tourism=camp_site / caravan_site ("Camp site", "Caravan site" once formatted).
            "campground" to listOf("camp site", "caravan site"),
            "campgrounds" to listOf("camp site", "caravan site"),
            "camping" to listOf("camp site", "caravan site"),
            // The "Things to do" chip. Mostly tourism=* values plus a few amenity/leisure ones that
            // win the category slot first (amenity is read before tourism).
            "things to do" to listOf(
                "attraction", "museum", "viewpoint", "theme park", "zoo", "aquarium", "gallery",
                "theatre", "cinema", "arts center", "arts centre", "water park",
            ),
            "hardware" to listOf("hardware", "doityourself"),
        )

        /** Exact key first, then the word minus a trailing "s", so typed plurals ("cafes", "gyms")
         *  reach the singular entry. Irregular plurals need their own key ("groceries"). */
        /** Pack categories that are transit stops (public_transport=* and amenity=bus_station). */
        internal val TRANSIT_STOP_CATS = setOf("platform", "stop position", "stop area", "station", "bus station", "bus stop")
        internal val TRANSIT_QUERY_WORDS = listOf("bus", "stop", "station", "transit", "train", "tram", "platform", "metro", "light rail", "subway", "ferry")

        /** The pack's name column with the punctuation [OfflineRank.fold] drops. LIKE ignores
         *  case for plain letters; accents are [nameMatch]'s job. */
        private const val NAME_FOLDED = "replace(replace(replace(replace(name,'''',''),'\u2019',''),'.',''),'-',' ')"

        /** True for a name with any letter outside ASCII: it has more bytes than characters. */
        private const val NON_ASCII = "length(name) <> length(CAST(name AS BLOB))"

        /**
         * The SQL test, and its arguments, for [folded] (text through [OfflineRank.fold]) appearing
         * in a name whatever its accents. A plain name is matched by LIKE exactly as before. Only a
         * name with a letter outside ASCII goes on to the accent pattern ([OfflineRank.glob]), which
         * costs several times what LIKE does per row, and most names in most packs are plain.
         */
        internal fun nameMatch(folded: String): Pair<String, List<String>> {
            val eszett = OfflineRank.globEszett(folded)
            val accented = "$NAME_FOLDED GLOB ?" + if (eszett != null) " OR name GLOB ?" else ""
            return "($NAME_FOLDED LIKE ? OR ($NON_ASCII AND ($accented)))" to listOfNotNull("%$folded%", OfflineRank.glob(folded), eszett)
        }

        internal fun categoryKeywords(query: String): List<String> {
            val key = query.trim().lowercase()
            return CATEGORY_KEYWORDS[key]
                ?: key.takeIf { it.length > 3 && it.endsWith("s") }?.let { CATEGORY_KEYWORDS[it.dropLast(1)] }
                ?: emptyList()
        }
    }
}
