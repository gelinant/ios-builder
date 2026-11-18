package app.vela.ios.place

import app.vela.core.platform.Cancellable

/**
 * The hidden Google pages behind the complete place sheet: reviews, the full categorized gallery,
 * and the details reply that can carry popular times. Swift implements these over `HiddenWebView`,
 * with calls and answers on the main thread (docs/ios/spike-webview-ios.md, W-2).
 */
interface PlaceWebFallback {
    /** Loads [request]'s page, runs its script, and reports to [sink] until [WebReviewsSink.onResult]
     *  (exactly once, also after a cancel or a dead page). */
    fun reviews(request: WebReviewsRequest, sink: WebReviewsSink): Cancellable

    /** Walks the gallery and its category tabs. The sink receives the scraper's raw bridge values. */
    fun photos(request: WebPhotosRequest, sink: WebPhotosSink): Cancellable

    /** Warms Google, then fetches [request]'s focused search from the page's own origin. */
    fun details(request: WebDetailsRequest, sink: WebDetailsSink): Cancellable
}

/** One reviews scrape: the place's page and the script to inject for a request id. */
class WebReviewsRequest(
    val featureId: String,
    val url: String,
    private val build: (String) -> String,
) {
    /** The scraper for [requestId], with the bridge still written `VelaBridge`. */
    fun script(requestId: String): String = build(requestId)
}

/** What the review page reports, as the strings its bridge passes. */
interface WebReviewsSink {
    fun onProgress(count: Int)

    /** The accumulated reviews so far, the JSON `ReviewsWebParser` reads. */
    fun onPartial(payload: String)

    /** The star breakdown, `[5-star, ..., 1-star]` as JSON. */
    fun onHistogram(json: String)

    /** The final list, or null when the page gave nothing (timeout, cancel, dead page). */
    fun onResult(payload: String?)
}

/** One gallery walk. Swift builds the page script because Android has not moved it to core-common. */
class WebPhotosRequest(
    val featureId: String,
    val url: String,
    val cap: Int,
)

/** Raw values from the gallery bridge. Kotlin parses and merges them with the RPC's dates. */
interface WebPhotosSink {
    /** Newline-separated `category<TAB>url` entries, accumulated across gallery tabs. */
    fun onPartial(payload: String)

    /** JSON `[[url, postedText], ...]` mined from the page's initialization state. */
    fun onDates(json: String)

    /** The star breakdown, `[5-star, ..., 1-star]` as JSON. */
    fun onHistogram(json: String)

    /** The final gallery, or null on timeout, cancellation, or a dead page. */
    fun onResult(payload: String?)
}

/** The warmed same-origin details request. Its focused query includes the place's address. */
class WebDetailsRequest(
    val featureId: String,
    val url: String,
    val warmUrl: String,
)

interface WebDetailsSink {
    /** The raw search reply, or null on timeout, cancellation, or a dead page. */
    fun onResult(payload: String?)
}
