package app.vela.web

import android.content.Context
import android.net.Uri
import android.webkit.JavascriptInterface
import android.webkit.WebView
import app.vela.core.data.google.parse.ReviewsWebParser
import app.vela.core.model.Review
import dagger.hilt.android.qualifiers.ApplicationContext
import java.math.BigInteger
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Fetches a place's reviews through a hidden [WebView] - the keyless reviews source after Google
 * **deleted** the old `listentitiesreviews` endpoint (now HTTP 404) and moved reviews behind a
 * `batchexecute` RPC (`rpcids=T4jwAf`) whose request proto resisted capture.
 *
 * Rather than replay that RPC, we let Google's own JS render the reviews (loading the place's
 * canonical `?cid=` page, anonymous/no-login, desktop UA - same tactic as [WebPhotoFetcher] and
 * `WebDirectionsFetcher`) and read them back out of the DOM: per review the star rating, author,
 * relative date, text **and the reviewer's uploaded photos** (the old endpoint only ever served
 * avatars - this is also how per-review photos finally arrive). The page builds a JSON array over a
 * JS bridge; [ReviewsWebParser] (in `:core`) turns it into [Review]s.
 *
 * Strictly best-effort + lazy: any failure/timeout returns empty and the place sheet just shows no
 * reviews. Serialized by the base session since the single WebView navigates per place.
 */
@Singleton
class WebReviewsFetcher @Inject constructor(
    @ApplicationContext context: Context,
    private val diag: app.vela.core.diag.DiagLog,
    private val calibration: app.vela.core.config.CalibrationStore,
) : HiddenWebView(context, "reviews") {
    private val progress = ConcurrentHashMap<String, (Int) -> Unit>()
    private val partial = ConcurrentHashMap<String, (List<Review>) -> Unit>()
    private val caps = java.util.concurrent.ConcurrentHashMap<String, Int>()
    private val hists = ConcurrentHashMap<String, (List<Int>) -> Unit>()
    // Request ids whose scraper is already in the page: the settle timer and the load cap race
    // to inject it, and only the first may.
    private val injected = java.util.Collections.synchronizedSet(HashSet<String>())

    override fun bridge(): Any = ReviewBridge()

    private inner class ReviewBridge {
        @JavascriptInterface
        fun onResult(id: String, payload: String) = deliver(id, payload)

        // Live "N reviews found so far" ticks from the scraper (the scrape runs ~10-40 s on busy
        // pages; the UI shows this so the wait reads as progress, not a hang). Arrives on the
        // WebView's JavaBridge thread, so the callback must be thread-safe.
        @JavascriptInterface
        fun onProgress(id: String, n: Int) {
            progress[id]?.invoke(n)
        }

        // Scrape PROBE (diagnostics only): what the page looks like from inside the hidden
        // WebView every few seconds - tabs found, whether the reviews tab opened, cards on
        // screen, viewport size. This is how a "collecting reviews" that never lands gets
        // diagnosed from a Diagnostics export instead of a guess (issue #359).
        @JavascriptInterface
        fun onInfo(id: String, text: String) {
            android.util.Log.i("VelaReviews", text)
            diag.record("reviews", "probe", text)
        }

        // The accumulated reviews SO FAR, sent whenever the count grows: the sheet streams them
        // into the list under the progress bar instead of making the user stare at a bar for 30 s.
        // Same JavaBridge thread; parse failures are dropped (the final onResult is authoritative).
        // The star breakdown ([5-star..1-star] counts), read off the same page in passing.
        @JavascriptInterface
        fun onHistogram(id: String, json: String) {
            val cb = hists[id] ?: return
            runCatching { org.json.JSONArray(json).let { a -> List(a.length()) { a.getInt(it) } } }.getOrNull()
                ?.takeIf { it.size == 5 && it.sum() > 0 }?.let(cb)
        }

        @JavascriptInterface
        fun onPartial(id: String, payload: String) {
            val cb = partial[id] ?: return
            runCatching { ReviewsWebParser.parse(payload) }.getOrNull()?.let { if (it.isNotEmpty()) cb(it) }
        }
    }

    /** Reviews for [featureId] (`0x..:0x..`), newest/most-relevant first as Google renders them,
     *  each with its uploaded photos, or empty on any failure. [onProgress] streams the running
     *  count while the scrape is in flight; [onPartial] streams the accumulated reviews themselves
     *  (a growing prefix of the final result). Both are called off the main thread. */
    suspend fun fetch(
        featureId: String,
        onProgress: (Int) -> Unit = {},
        onPartial: (List<Review>) -> Unit = {},
        // How many to scrape before stopping: a place tap takes the first page (FIRST_REVIEWS in
        // MapViewModel), the full-load setting keeps the old 50. Each page past the first is
        // another feed request to Google.
        cap: Int = 50,
        onHistogram: (List<Int>) -> Unit = {},
    ): List<Review> {
        val cid = cidOf(featureId) ?: return emptyList()
        return session {
            var reqId = ""
            val raw = try {
                request(TOTAL_TIMEOUT_MS) { id ->
                    reqId = id
                    progress[id] = onProgress
                    partial[id] = onPartial
                    caps[id] = cap
                    hists[id] = onHistogram
                    // Blank the PREVIOUS place's DOM before navigating: a slow load could otherwise
                    // let the MAX_LOAD cap inject the scraper into the old page and return the
                    // previous place's reviews for THIS featureId (empty > wrong).
                    evaluate("try{document.documentElement.innerHTML=''}catch(e){}")
                    val hl = reviewsHl()
                    diag.record("reviews", "load hl=$hl app=${app.vela.ui.AppLocale.language.value.ifBlank { "system" }} region=${DiagRegion.of(context)}", "cid=$cid")
                    load("https://www.google.com/maps?cid=$cid&hl=$hl&gl=us", id)
                    // Proceed even if the SPA's onPageFinished is slow.
                    main.postDelayed({ inject(id) }, MAX_LOAD_MS)
                }
            } finally {
                progress.remove(reqId)
                partial.remove(reqId)
                caps.remove(reqId)
                hists.remove(reqId)
                injected.remove(reqId)
            }
            val parsed = if (raw.isNullOrEmpty()) emptyList() else runCatching { ReviewsWebParser.parse(raw) }.getOrDefault(emptyList())
            diag.record(
                "reviews",
                if (raw == null) "timed out after ${TOTAL_TIMEOUT_MS / 1000} s with nothing" else "${parsed.size} review(s) parsed",
                parsed.firstOrNull()?.text?.take(60)?.let { "first text: $it" },
            )
            parsed
        }
    }

    /** Only google.com pages: a stray click on an external link (the place's website or menu
     *  action) must not navigate the hidden WebView away. */
    override fun allowNavigation(url: Uri): Boolean {
        val host = url.host.orEmpty()
        return host == "google.com" || host.endsWith(".google.com")
    }

    override fun configure(view: WebView) {
        // Desktop-WIDTH layout, not just a desktop UA: without the wide viewport the page lays
        // out at the WebView's CSS width (1200 physical px is ~450 CSS px on a 2.75x phone), which
        // is Google's narrow layout where the Reviews tab shows five cards and a button, and the
        // scrape settled on those five (2026-09-13). With it the CSS viewport is the desktop 980
        // px and the tab holds the full paged list the browser shows.
        view.settings.useWideViewPort = true
        view.settings.loadWithOverviewMode = true
        // Give the hidden (never-attached) WebView a REAL offscreen viewport. Google's reviews list is
        // virtualized + lazy-loaded off the scroll viewport; a 0x0 headless WebView renders the chrome
        // (rating histogram, topic filters) but NEVER the review cards. A tall explicit layout makes the
        // scroll pane real so the list renders + pages. (The photo gallery's category grids need the
        // same treatment, see WebPhotoFetcher.)
        // The size is in CSS px x density: Google's page carries a width=device-width viewport
        // meta, which makes useWideViewPort a no-op, so the DESKTOP layout (the full paged review
        // list in the tab) only comes from a physically wide view. 1200 physical px on a 2.75x phone
        // was 436 CSS px, the narrow layout with five cards and a button, and the scrape settled
        // on those five (2026-09-13).
        val density = view.resources.displayMetrics.density.coerceAtLeast(1f)
        val wPx = (WV_WIDTH * density).toInt()
        val hPx = (WV_HEIGHT * density).toInt()
        view.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(wPx, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(hPx, android.view.View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, wPx, hPx)
        // A never-attached WebView reads as a BACKGROUND page to Chromium: JS timers throttle
        // toward 1 Hz and rAF-driven rendering slows, which is why the visible Google Maps
        // WebView pages reviews near-instantly while this scrape crawled. Resume the timers once
        // so the renderer runs at foreground cadence (the session resumes the view per fetch).
        view.onResume()
        view.resumeTimers()
    }

    override fun onPageFinished(view: WebView, url: String?, requestId: String) {
        // Diagnostics: which page Google actually served, and in what language (issue #359: a
        // reader whose reviews stay English while the app asks for zh-TW; the export says which
        // side to blame).
        view.evaluateJavascript(
            JsNames.of("location.host+location.pathname.split('/@')[0].slice(0,40)+' lang='+document.documentElement.lang+' nav='+navigator.language"),
        ) { v -> diag.record("reviews", "page loaded", v?.trim('"')) }
        main.postDelayed({ inject(requestId) }, SETTLE_MS)
    }

    /** Start the scrape for request [id] once: the page-finish settle and the load cap both call
     *  this, and a request that is gone (timed out, superseded) gets nothing injected. */
    private fun inject(id: String) {
        if (!isPending(id) || !injected.add(id)) return
        webView?.evaluateJavascript(JsNames.of(extractScript(id, caps[id] ?: 50)), null)
    }

    /** The Google "cid" = the LOW half of the `0xHIGH:0xLOW` feature id as an unsigned decimal, the
     *  canonical `maps.google.com?cid=` deep-link to a place. */
    private fun cidOf(featureId: String): String? {
        val low = featureId.substringAfter(":", "").removePrefix("0x").ifBlank { return null }
        return runCatching { BigInteger(low, 16).toString() }.getOrNull()
    }

    /** Self-polling DOM scraper: open the full reviews list, then scroll it a window at a time,
     *  ACCUMULATING each review card into a keyed set (Google virtualizes the panel - it recycles
     *  DOM nodes as you scroll, so any single snapshot holds only ~10 cards; the union across scroll
     *  positions is the full list). Bridges the accumulated JSON array back once the list is exhausted
     *  or the cap is hit. */
    /** The :core review-word patterns, quoted for embedding in the scraper's JavaScript. */
    // Words + selectors come from the signed calibration bundle when it carries them
    // (`reviewWords`, `reviewSelectors`), else the compiled values - so a rotated class name or a
    // language Google renames the tab in is a config edit (2026-09-13). The script itself is
    // shared with iOS (`ReviewScripts` in :core-common).
    private fun extractScript(id: String, cap: Int = 50): String {
        val cal = calibration.current()
        return app.vela.core.web.ReviewScripts.reviews(
            id = id,
            cap = cap,
            reviewPattern = cal.reviewWords?.get("review") ?: app.vela.core.data.ReviewWords.REVIEW_PATTERN,
            morePattern = cal.reviewWords?.get("more") ?: app.vela.core.data.ReviewWords.MORE_PATTERN,
            selectors = cal.reviewSelectors.orEmpty(),
        )
    }

    internal companion object {
        // Must outlast the script's own hard stop (130 ticks x 250 ms ~ 33 s + page load) - if Kotlin
        // times out first we return EMPTY, which is worse than few. Lazy + best-effort as ever.
        const val TOTAL_TIMEOUT_MS = 45_000L
        // Compiled selector defaults (the calibration bundle's `reviewSelectors` overrides per key).
        const val DEFAULT_CARD_SEL = app.vela.core.web.ReviewScripts.DEFAULT_CARD_SEL
        const val DEFAULT_ID_SEL = app.vela.core.web.ReviewScripts.DEFAULT_ID_SEL
        const val DEFAULT_MORE_TOGGLE_SEL = app.vela.core.web.ReviewScripts.DEFAULT_MORE_TOGGLE_SEL
        const val DEFAULT_AUTHOR_SEL = app.vela.core.web.ReviewScripts.DEFAULT_AUTHOR_SEL
        const val DEFAULT_TEXT_SEL = app.vela.core.web.ReviewScripts.DEFAULT_TEXT_SEL
        const val DEFAULT_DATE_SEL = app.vela.core.web.ReviewScripts.DEFAULT_DATE_SEL
        const val SETTLE_MS = 150L

        /** Languages whose review-page wording the scraper's word lists cover (see `reviewsHl`).
         *  Outside this set the page stays English: a language the scraper cannot navigate would
         *  return FEWER reviews than English does. */
        // NB "iw" as well as "he": java.util.Locale.getLanguage() returns the OBSOLETE ISO code
        // for Hebrew on Android (the app's own resource dir is values-iw), so a "he"-only set
        // sends every Hebrew reader back to the English page - the one locale whose review words
        // were added by hand. Indonesian ("in") and Yiddish ("ji") carry the same trap.
        val SUPPORTED_HL = setOf("en", "fr", "de", "es", "it", "pt", "nl", "ru", "pl", "sv", "uk", "hu", "ro", "zh", "ja", "he", "iw")

        /** The page language for the hidden reviews WebView: the app's language when the scraper's
         *  word lists cover it (issue #278: the page language decides WHICH reviews Google serves,
         *  so a Chinese reader on an English page got English reviews), English otherwise. Chinese
         *  keeps its script (zh-TW for Traditional regions). This is the half of #307 that was
         *  described but never wired (review 2026-09-06). */
        fun reviewsHl(): String {
            val loc = app.vela.ui.AppLocale.effective()
            val lang = loc.language.lowercase()
            if (lang !in SUPPORTED_HL) return "en"
            // Google's own parameter for Hebrew is the legacy code, which is also what the
            // locale reports - pass it through rather than "correcting" it.
            if (lang == "he") return "iw"
            if (lang == "zh") {
                val hant = loc.script.equals("Hant", ignoreCase = true) || loc.country.uppercase() in setOf("TW", "HK", "MO")
                return if (hant) "zh-TW" else "zh-CN"
            }
            return lang
        }
        const val MAX_LOAD_MS = 7_000L
        // Offscreen viewport for the headless WebView - tall so the virtualized review list renders a
        // healthy batch per scroll position.
        const val WV_WIDTH = 1200  // CSS px (scaled by density at layout): the desktop layout's width
        const val WV_HEIGHT = 1000 // CSS px: SHORTER than the feed, so the pane scrolls and Google pages the next cards in (a 2400 px pane held the first 8 with nothing to scroll, 2026-09-13)
    }
}
