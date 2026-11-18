package app.vela.core.net

/**
 * Request tag (2026-09-23): send this Google request with the WebView's Google session, not the
 * app's. The app's session is new every launch and Google gives new sessions a limited view (5
 * reviews, and popular times missing on busy places like a big-box store); the WebView's has aged.
 *
 * Common code asks for it with `RequestTags.agedSession`, after checking the `agedSession` dial.
 * Android turns that into this OkHttp request tag (`OkHttpVelaHttp`), which the Cronet transport
 * honors; without Cronet the request keeps the app's session. iOS reads the flag itself.
 */
object AgedSession
