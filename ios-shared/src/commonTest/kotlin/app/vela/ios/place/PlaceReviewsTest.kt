package app.vela.ios.place

import app.vela.core.model.Review
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlaceReviewsTest {

    private fun review(author: String, text: String?, stars: Int = 4) = Review(
        author = author, authorPhoto = null, rating = stars, relativeTime = "a week ago", text = text)

    @Test fun `a five row histogram parses in star order`() {
        assertEquals(listOf(700, 200, 50, 20, 10), PlaceReviews.parseHistogram("[700,200,50,20,10]"))
        assertEquals(listOf(7, 2, 5, 0, 1), PlaceReviews.parseHistogram(" [7, 2, 5, 0, 1] "))
    }

    @Test fun `a malformed or empty histogram is refused`() {
        assertNull(PlaceReviews.parseHistogram("[1,2,3,4]"))
        assertNull(PlaceReviews.parseHistogram("[0,0,0,0,0]"))
        assertNull(PlaceReviews.parseHistogram("[1,2,-3,4,5]"))
        assertNull(PlaceReviews.parseHistogram("garbage"))
    }

    @Test fun `a page merge appends only reviews that are not on screen`() {
        val first = listOf(review("Ana", "One"), review("Ben", "Two"))
        val page = listOf(review("Ben", "Two"), review("Cleo", "Three"))
        val merged = PlaceReviews.mergeReviewPages(first, page)
        assertEquals(listOf("Ana", "Ben", "Cleo"), merged.map { it.author })
        assertEquals(3, merged.size)
    }

    @Test fun `a different body from the same author is a different review`() {
        val merged = PlaceReviews.mergeReviewPages(
            listOf(review("Ana", "Short")),
            listOf(review("Ana", "Another visit")))
        assertEquals(2, merged.size)
        assertEquals(listOf("Short", "Another visit"), merged.map { it.text })
    }

    @Test fun `a repeated review inside one page is counted once`() {
        val merged = PlaceReviews.mergeReviewPages(emptyList(), listOf(review("Ana", "One"), review("Ana", "One")))
        assertEquals(1, merged.size)
    }

    @Test fun `translation markers follow author and body`() {
        val payload = """[
            {"rid":"a","a":"Ana","t":"Texto traducido","tr":1},
            {"rid":"b","a":"Ben","t":"Not translated"},
            {"rid":"c","a":"Cleo","t":"Autre texte","tr":0}
        ]"""
        val keys = PlaceReviews.translatedReviewKeys(payload)
        assertEquals(listOf(PlaceReviews.reviewKey("Ana", "Texto traducido")), keys)
        assertTrue(PlaceReviews.reviewKey(review("Ana", "Texto traducido")) in keys)
    }

    @Test fun `a payload without the flag invents nothing`() {
        assertTrue(PlaceReviews.translatedReviewKeys("""[{"a":"Ana","t":"Plain"}]""").isEmpty())
        assertTrue(PlaceReviews.translatedReviewKeys("garbage").isEmpty())
    }
}
