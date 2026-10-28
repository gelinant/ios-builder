package app.vela.ios.place

import kotlinx.serialization.Serializable

/**
 * The Wikidata facts the place sheet's "Learn more" section shows (W-1). Every field is optional
 * except the id: a missing statement is not displayed rather than filled with a guess.
 *
 * [wikivoyage] maps a language code to the title of that language's Wikivoyage article, as the
 * item's sitelinks name it. It is not shown; it selects the page the extract comes from.
 */
@Serializable
data class WikiFacts(
    val wikidataId: String,
    val label: String? = null,
    /** P1082, people. */
    val population: Long? = null,
    /** P1619, formatted from the statement time and its precision (`1889-03-31`, `1889`, ...). */
    val opened: String? = null,
    /** P856, the official website. */
    val website: String? = null,
    /** P625, the item's point. */
    val latitude: Double? = null,
    val longitude: Double? = null,
    /** The language the label was read in, after the interface-language fallback. */
    val language: String = "en",
    /** Wikivoyage sitelinks, language code to article title. */
    val wikivoyage: Map<String, String> = emptyMap(),
    /** When this payload was fetched, epoch milliseconds. */
    val fetchedAtMs: Long = 0L,
) {
    /** The sheet fields that are actually present; the id always counts. */
    val fieldCount: Int
        get() = listOf(population, opened, website, wikidataId).count { it != null }
}

/**
 * One Wikivoyage article as the app consumes it: a cleaned lead extract, its public page and, for
 * the map layer, the coordinates Wikidata gives the matching item.
 *
 * [images] is always empty in W-1: the lot shows no Wikimedia image, so the section links to the
 * source page instead. It exists so the tests can assert that cleanliness.
 */
@Serializable
data class WikiArticle(
    val title: String,
    val language: String,
    val extract: String = "",
    val url: String,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val images: List<String> = emptyList(),
    val fetchedAtMs: Long = 0L,
)

/**
 * What the place sheet holds after one load: Wikidata facts and, when a Wikivoyage page exists for
 * the item, its extract. Null fields mean "not provided by the source", never "no such place".
 */
@Serializable
data class WikiKnowledge(
    val facts: WikiFacts? = null,
    val article: WikiArticle? = null,
    val fetchedAtMs: Long = 0L,
) {
    val fieldCount: Int get() = facts?.fieldCount ?: 0

    /** False in W-1 by construction; the test pins the absence of any image URL. */
    val hasImages: Boolean get() = !(article?.images.isNullOrEmpty())
}

/** One 24-hour cache row for the map layer, before the viewport filter. */
@Serializable
internal data class WikiLayerCache(
    val items: List<WikiArticle> = emptyList(),
    val fetchedAtMs: Long = 0L,
)
