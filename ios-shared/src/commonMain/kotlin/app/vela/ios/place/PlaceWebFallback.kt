package app.vela.ios.place

import app.vela.core.platform.Cancellable

/**
 * The hidden Google page the place sheet falls back to for its reviews (docs/ios/
 * spike-webview-ios.md, W-2): implemented in Swift over one WKWebView (`HiddenWebView`), called and
 * answered on the main thread.
 */
interface PlaceWebFallback {
    /** Loads [request]'s page, runs its script, and reports to [sink] until [WebReviewsSink.onResult]
     *  (exactly once, also after a cancel or a dead page). */
    fun reviews(request: WebReviewsRequest, sink: WebReviewsSink): Cancellable
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

/** What the page reports, as the strings its bridge passes. */
interface WebReviewsSink {
    fun onProgress(count: Int)

    /** The accumulated reviews so far, the JSON `ReviewsWebParser` reads. */
    fun onPartial(payload: String)

    /** The star breakdown, `[5-star, ..., 1-star]` as JSON. */
    fun onHistogram(json: String)

    /** The final list, or null when the page gave nothing (timeout, cancel, dead page). */
    fun onResult(payload: String?)
}
