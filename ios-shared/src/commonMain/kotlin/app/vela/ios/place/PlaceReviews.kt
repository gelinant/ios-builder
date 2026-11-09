package app.vela.ios.place

import app.vela.core.model.Review
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Review helpers shared by the place store and its JVM tests. The histogram comes from Google's
 * page (`tr[aria-label]` rows, `[5-star ... 1-star]`), and a page merge must never repeat a review
 * already on screen: Android de-duplicates on author + text, which is also the key the translation
 * flag travels on.
 */
object PlaceReviews {

    /** The separator of [reviewKey]: a character no author or review body carries. */
    const val KEY_SEPARATOR: Char = '\u0000'

    /** A parsed `[5-star ... 1-star]` histogram, or null when the payload is not one. */
    fun parseHistogram(json: String): List<Int>? {
        val counts = json.trim().removePrefix("[").removeSuffix("]")
            .split(',').map { it.trim().toIntOrNull() }
        if (counts.size != 5 || counts.any { it == null || it < 0 }) return null
        val values = counts.map { it!! }
        return values.takeIf { it.sum() > 0 }
    }

    /** [existing] followed by the reviews of [page] that are not already there, in order. */
    fun mergeReviewPages(existing: List<Review>, page: List<Review>): List<Review> {
        val out = LinkedHashMap<String, Review>()
        for (review in existing) {
            val key = reviewKey(review)
            if (key !in out) out[key] = review
        }
        for (review in page) {
            val key = reviewKey(review)
            if (key !in out) out[key] = review
        }
        return out.values.toList()
    }

    /** The identity Android's review merge uses: the author and the review body. */
    fun reviewKey(review: Review): String = reviewKey(review.author, review.text)

    fun reviewKey(author: String, text: String?): String =
        author.trim() + KEY_SEPARATOR + (text ?: "")

    /**
     * The keys of the reviews Google marked as translated in this scraped page payload. The scraper
     * sets `tr` when a card carries Google's own translation notice; the body it sends is then the
     * translated text. A payload without the flag yields nothing, so no label is invented.
     */
    fun translatedReviewKeys(payload: String): List<String> = runCatching {
        Json.parseToJsonElement(payload).jsonArray.mapNotNull { element ->
            val entry = element.jsonObject
            val translated = (entry["tr"]?.jsonPrimitive?.intOrNull ?: 0) != 0
            if (!translated) return@mapNotNull null
            val author = entry["a"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
            if (author.isEmpty()) return@mapNotNull null
            reviewKey(author, entry["t"]?.jsonPrimitive?.contentOrNull)
        }.distinct()
    }.getOrDefault(emptyList())
}
