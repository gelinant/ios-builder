package app.vela.core.config

import app.vela.core.VelaConfig
import app.vela.core.data.google.ChromeHints
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.SignatureVerifier
import app.vela.core.platform.call
import app.vela.core.platform.joinPath
import app.vela.core.util.ioDispatcher
import kotlin.concurrent.Volatile
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

/**
 * Holds the active [Calibration] and refreshes it from the public repo.
 *
 * On construction it loads a cached copy (if signature-valid and newer than the
 * bundled [DEFAULT]), else uses [DEFAULT], so the app always starts with a
 * working config, offline. [refresh] (called once at startup) pulls
 * `calibration.json` + its detached `calibration.json.sig` over HTTPS and adopts
 * the remote only if:
 *   1. the **signature verifies** against [PINNED_PUBLIC_KEY] (so only the holder
 *      of the private key, kept out of the repo, can push config/notices/code),
 *   2. every endpoint host is on the allowlist (a tampered file can't redirect
 *      requests off Google), and
 *   3. the version is newer.
 * The newest config thus reaches every user within a launch or two, with no APK
 * update, which is the whole point. Because the bundle is signed, it can safely
 * carry not just pb/endpoint/path config but user-facing [Notice]s and a sandboxed
 * JavaScript transform bundle ([Calibration.transformsJs]).
 *
 * Platform access goes through [CoreGraph] (files, HTTP) and [signatures]. Room for a second
 * signed source (the iOS overlay `calibration-ios.json`, signed with the fork's key, PORTAGE_IOS
 * D11): it would be a second fetch loop like the one in [refresh], with its own URLs, cache file
 * names and pinned key passed to [verifySignature], parsed as a partial bundle and laid over the
 * result of [parseBundle] before [active] is set. Nothing here assumes a single key.
 */
class CalibrationStore(
    graph: CoreGraph,
    private val signatures: SignatureVerifier,
) {
    private val files = graph.files
    private val http = graph.http
    private val cacheFile = joinPath(files.filesDir, "calibration.json")
    private val sigFile = joinPath(files.filesDir, "calibration.json.sig")

    @Volatile
    private var active: Calibration = (loadCached() ?: Calibration.DEFAULT).also { latest = it; VelaLinks.overrides = it.links }

    @Volatile
    private var refreshed = false

    /** The config every scraper call reads. Never null; never blocks. */
    fun current(): Calibration = active

    suspend fun refresh() {
        if (refreshed) return
        refreshed = true
        withContext(ioDispatcher) {
            runCatching {
                // The file is asked for where the last bundle said it lives (a moved repository
                // announces its new place through the old one first); when that does not answer,
                // where this build was compiled to look; and when GitHub itself does not answer,
                // the copy on the website, which is what makes a closed account one signed push.
                val pushed = VelaLinks.calibration()
                val compiledUrl = VelaLinks.default(VelaLinks.CALIBRATION)
                val mirror = VelaLinks.calibrationMirror()
                val compiledMirror = VelaLinks.default(VelaLinks.CALIBRATION_MIRROR)
                val at = listOf(pushed, compiledUrl, mirror, compiledMirror).distinct()
                var body: String? = null
                var sig: String? = null
                for (url in at) {
                    // A host that does not resolve, refuses or times out moves on to the next
                    // address, as a non-2xx reply does; and so does a copy that answers with the
                    // wrong bytes (a site's catch-all page, a stale mirror). Reject anything we
                    // didn't sign: this is what makes pushing CODE safe.
                    val b = fetchQuiet(url) ?: continue
                    val s = fetchQuiet("$url.sig") ?: continue
                    if (!verifySignature(b.encodeToByteArray(), s)) continue
                    body = b; sig = s
                    break
                }
                if (body == null || sig == null) return@runCatching
                val remote = parseBundle(body) ?: return@runCatching
                if (remote.version > active.version && isAllowed(remote)) {
                    runCatching {
                        files.writeText(cacheFile, body)
                        files.writeText(sigFile, sig)
                    }
                    active = remote
                    latest = remote
                    VelaLinks.overrides = remote.links
                }
            }
        }
    }

    private suspend fun fetchQuiet(url: String): String? = runCatching { fetch(url) }.getOrNull()

    private suspend fun fetch(url: String): String? {
        // Vela's own repo: the honest, contactable identifier, not the scrape's browser UA.
        val resp = http.call(HttpRequest(url, headers = listOf(HttpHeader("User-Agent", VelaConfig.VELA_UA))))
        return if (resp.isSuccessful) resp.bodyText() else null
    }

    private fun loadCached(): Calibration? = runCatching {
        if (!files.exists(cacheFile) || !files.exists(sigFile)) return null
        val body = files.readText(cacheFile)
        // Re-verify the cache too: a cache written by an older (unsigned) build, or
        // tampered on disk, falls back to the bundled DEFAULT for one launch.
        if (!verifySignature(body.encodeToByteArray(), files.readText(sigFile))) return null
        parseBundle(body)?.takeIf { it.version >= Calibration.DEFAULT.version && isAllowed(it) }
    }.getOrNull()

    /** ECDSA-P256/SHA-256 verify against the detached [sigBase64] using [publicKey]. */
    private fun verifySignature(content: ByteArray, sigBase64: String, publicKey: String = PINNED_PUBLIC_KEY): Boolean =
        signatures.verify(content, sigBase64, publicKey)

    /** Security gate: every endpoint must point at an allow-listed host, so a
     *  compromised config can never exfiltrate requests to an attacker's server. */
    private fun isAllowed(c: Calibration): Boolean {
        val hosts = listOf(c.searchEndpoint, c.directionsEndpoint, c.reviewsEndpoint, c.photosEndpoint, c.sessionWarmUrl, c.suggestEndpoint)
            .map { urlHost(it) }
        return hosts.all { it != null && it in ALLOWED_HOSTS } && VelaLinks.acceptable(c.links)
    }

    companion object {
        private val BUNDLE_JSON = Json { ignoreUnknownKeys = true }

        /** Lenient JSON → Calibration: any missing field falls back to [DEFAULT], so
         *  a remote file can override just the one thing that drifted. */
        fun parseBundle(body: String): Calibration? = runCatching {
            val o = BUNDLE_JSON.parseToJsonElement(body).jsonObject
            fun str(k: String, fallback: String): String =
                (o[k] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() } ?: fallback
            val version = (o["version"] as? JsonPrimitive)?.content?.toIntOrNull() ?: return@runCatching null
            val d = Calibration.DEFAULT
        // SANITIZED, not merely defaulted: an unsendable value (a control character, an absurd
        // length) must fall back to the compiled UA rather than reach OkHttp, which throws at
        // request-build time inside a runCatching that swallows it: one stray newline in a
        // pushed bundle would otherwise kill every scrape with no crash and no log.
        val ua = ChromeHints.sanitize((o["userAgent"] as? JsonPrimitive)?.content) ?: d.userAgent
            // Field-index paths: each value is a JSON array of ints; merge the remote
            // ones over the bundled defaults so a file can override just one path.
            val remotePaths = (o["paths"] as? JsonObject)?.mapNotNull { (k, v) ->
                val list = (v as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content?.toIntOrNull() }
                if (!list.isNullOrEmpty()) k to list else null
            }?.toMap().orEmpty()
            val remoteDirPaths = (o["directionsPaths"] as? JsonObject)?.mapNotNull { (k, v) ->
                val list = (v as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content?.toIntOrNull() }
                if (!list.isNullOrEmpty()) k to list else null
            }?.toMap().orEmpty()
            val remoteSuggestPaths = (o["suggestPaths"] as? JsonObject)?.mapNotNull { (k, v) ->
                val list = (v as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content?.toIntOrNull() }
                if (!list.isNullOrEmpty()) k to list else null
            }?.toMap().orEmpty()
            // Plain string maps (review words / selectors): blank values skipped, empty map = absent.
            fun strMap(k: String): Map<String, String>? =
                (o[k] as? JsonObject)?.mapNotNull { (key, v) ->
                    (v as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() }?.let { key to it }
                }?.toMap()?.takeIf { it.isNotEmpty() }
            val notices = (o["notices"] as? JsonArray)?.mapNotNull { el ->
                val n = el as? JsonObject ?: return@mapNotNull null
                fun s(k: String): String? = (n[k] as? JsonPrimitive)?.content
                val id = s("id") ?: return@mapNotNull null
                val title = s("title") ?: return@mapNotNull null
                Notice(
                    id = id,
                    level = s("level") ?: Notice.LEVEL_INFO,
                    title = title,
                    body = s("body") ?: "",
                    url = s("url"),
                )
            }.orEmpty()
            val transformsJs = (o["transformsJs"] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() }
            // Word-table overrides, lenient like tuning: bad entries are skipped, an empty result
            // reads as absent (null = compiled tables) so a malformed block can't blank a language.
            // These fields existed in Calibration from day one but were never parsed here - every
            // remote bundle silently dropped them (found chasing the Hebrew openNow bug, 2026-07-19).
            fun wordMap(k: String): Map<String, List<String>>? =
                (o[k] as? JsonObject)?.mapNotNull { (lang, v) ->
                    val words = (v as? JsonArray)
                        ?.mapNotNull { w -> (w as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() } }
                    if (!words.isNullOrEmpty()) lang to words else null
                }?.toMap()?.takeIf { it.isNotEmpty() }
            fun wordList(k: String): List<String>? =
                (o[k] as? JsonArray)
                    ?.mapNotNull { w -> (w as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() } }
                    ?.takeIf { it.isNotEmpty() }
            val stopBoardIndices = (o["stopBoardIndices"] as? JsonObject)?.mapNotNull { (k, v) ->
                (v as? JsonPrimitive)?.content?.toIntOrNull()?.let { k to it }
            }?.toMap()?.takeIf { it.isNotEmpty() }
            Calibration(
                version = version,
                searchEndpoint = str("searchEndpoint", d.searchEndpoint),
                searchPb = str("searchPb", d.searchPb),
                directionsEndpoint = str("directionsEndpoint", d.directionsEndpoint),
                directionsPb = str("directionsPb", d.directionsPb),
                reviewsEndpoint = str("reviewsEndpoint", d.reviewsEndpoint),
                reviewsPb = str("reviewsPb", d.reviewsPb),
                sessionWarmUrl = str("sessionWarmUrl", d.sessionWarmUrl),
                userAgent = ua,
                // DERIVED from the UA's major whenever it can be read, so the pair can never disagree
                // (Chrome computes the whole header from the major; see ChromeHints.secChUaFor).
                // The pushed field only matters for a UA that names no Chrome major.
                secChUa = ChromeHints.chromeMajor(ua)?.toIntOrNull()?.let { ChromeHints.secChUaFor(it) }
                    ?: ChromeHints.sanitize((o["secChUa"] as? JsonPrimitive)?.content)
                    ?: d.secChUa,
                chromeFullVersion = ChromeHints.sanitize((o["chromeFullVersion"] as? JsonPrimitive)?.content) ?: d.chromeFullVersion,
                photosEndpoint = str("photosEndpoint", d.photosEndpoint),
                photosProto = str("photosProto", d.photosProto),
                rpcContext = (o["rpcContext"] as? JsonPrimitive)?.content?.let { ChromeHints.sanitize(it) ?: "" } ?: d.rpcContext,
                reviewFeedProto = str("reviewFeedProto", d.reviewFeedProto),
                streetViewSearchBody = str("streetViewSearchBody", d.streetViewSearchBody),
                paths = Calibration.DEFAULT_PATHS + remotePaths,
                notices = notices,
                transformsJs = transformsJs,
                defaultVoiceSpeaker = (o["defaultVoiceSpeaker"] as? JsonPrimitive)?.content?.toIntOrNull() ?: d.defaultVoiceSpeaker,
                defaultVoiceSpeed = (o["defaultVoiceSpeed"] as? JsonPrimitive)?.content?.toFloatOrNull() ?: d.defaultVoiceSpeed,
                defaultVoiceId = (o["defaultVoiceId"] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() } ?: d.defaultVoiceId,
                defaultMapPalette = (o["defaultMapPalette"] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() } ?: d.defaultMapPalette,
                defaultPlacesSource = (o["defaultPlacesSource"] as? JsonPrimitive)?.content?.takeIf { it == "open" || it == "both" || it == "google" } ?: d.defaultPlacesSource,
                classicRoutePicker = (o["classicRoutePicker"] as? JsonPrimitive)?.content?.toBooleanStrictOrNull() ?: d.classicRoutePicker,
                // Numbers only, leniently: a non-numeric value is skipped rather than failing the
                // bundle, so one bad dial can never take down the whole calibration.
                tuning = (o["tuning"] as? JsonObject)?.mapNotNull { (k, v) ->
                    (v as? JsonPrimitive)?.content?.toDoubleOrNull()?.let { k to it }
                }?.toMap() ?: d.tuning,
                statusClosedWords = wordMap("statusClosedWords"),
                statusOpenWords = wordMap("statusOpenWords"),
                transitCategoryWords = wordList("transitCategoryWords"),
                transitExcludeWords = wordList("transitExcludeWords"),
                stopBoardIndices = stopBoardIndices,
                directionsPaths = Calibration.DEFAULT_DIRECTIONS_PATHS + remoteDirPaths,
                suggestEndpoint = str("suggestEndpoint", d.suggestEndpoint),
                suggestPb = str("suggestPb", d.suggestPb),
                suggestPaths = Calibration.DEFAULT_SUGGEST_PATHS + remoteSuggestPaths,
                reviewWords = strMap("reviewWords"),
                reviewSelectors = strMap("reviewSelectors"),
                links = strMap("links") ?: emptyMap(),
            )
        }.getOrNull()

        /** The last applied bundle, readable WITHOUT an injected store - the view layer's
         *  tuning dials (zoom defaults, overlay threshold) live too deep in composables to
         *  plumb the store into. Set at init (cached bundle or compiled default) and on every
         *  accepted refresh; always signature-verified content or [Calibration.DEFAULT]. */
        @Volatile
        var latest: Calibration = Calibration.DEFAULT
            private set

        private val ALLOWED_HOSTS = setOf("www.google.com", "google.com")

        private const val URI_ILLEGAL = "\"<>\\^`{|}[]"
        private const val USERINFO_CHARS = "-_.!~*'();:&=+$,%"

        /**
         * The server host of [url], as `java.net.URI(url).host` gives it for anything [ALLOWED_HOSTS]
         * could match, or null: a string `URI` refuses (a space, a control character, a bad `%`
         * escape, a second `#`, a bracket), no `scheme://`, a registry-style authority (two `@`, a
         * bad port, a label outside letters, digits and inner hyphens). Case is kept, as `URI`
         * keeps it. Brackets (IPv6 literals) are refused outright; none is on the allowlist.
         * `CalibrationHostTest` (jvmTest) compares it with `URI` over a corpus.
         */
        internal fun urlHost(url: String): String? {
            for ((i, c) in url.withIndex()) {
                if (c.code <= 0x20 || c.code == 0x7F || (c.code in 0x80..0x9F) || c in URI_ILLEGAL) return null
                if (c.isWhitespace() || c.isISOControl()) return null
                if (c == '%' && (i + 2 >= url.length || !url[i + 1].isHex() || !url[i + 2].isHex())) return null
            }
            if (url.count { it == '#' } > 1) return null
            // `URI` reads a scheme-relative `//host/path` as having a host too.
            val afterSlashes = if (url.startsWith("//")) {
                2
            } else {
                val schemeEnd = url.indexOf("://")
                if (schemeEnd <= 0) return null
                val scheme = url.substring(0, schemeEnd)
                if (!scheme[0].isAsciiLetter() || !scheme.all { it.isAsciiLetter() || it.isAsciiDigit() || it in "+-." }) return null
                schemeEnd + 3
            }
            val authority = url.substring(afterSlashes).takeWhile { it != '/' && it != '?' && it != '#' }
            val at = authority.indexOf('@')
            if (at >= 0 && !authority.substring(0, at).all { it.isAsciiLetter() || it.isAsciiDigit() || it in USERINFO_CHARS }) return null
            val hostPort = authority.substring(at + 1)
            val colon = hostPort.indexOf(':')
            val host = if (colon >= 0) hostPort.substring(0, colon) else hostPort
            if (colon >= 0 && !hostPort.substring(colon + 1).all { it.isAsciiDigit() }) return null
            if (host.isEmpty()) return null
            val labels = host.removeSuffix(".").split('.')
            val okLabel = { l: String ->
                l.isNotEmpty() && l.all { it.isAsciiLetter() || it.isAsciiDigit() || it == '-' } &&
                    l.first() != '-' && l.last() != '-'
            }
            if (!labels.all(okLabel)) return null
            // URI reads a dotted name whose last label starts with a digit as an IPv4 address and
            // refuses it unless it is one; neither form is on the allowlist.
            if (!labels.last()[0].isAsciiLetter()) return null
            return host
        }

        private fun Char.isHex() = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
        private fun Char.isAsciiLetter() = this in 'a'..'z' || this in 'A'..'Z'
        private fun Char.isAsciiDigit() = this in '0'..'9'

        // EC P-256 public key (SPKI, base64); the private half lives only in
        // ~/.vela-signing/vela-calibration.key, never in the repo. Embedding the
        // PUBLIC key is safe; it just lets the app reject bundles we didn't sign.
        const val PINNED_PUBLIC_KEY =
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEuz8/zxOJFhVqKco74fkmzrLlyPra4/pTEUm7lmue/Kig0T497fcs+hjhZkaSqVZAwloNrr0+0ILi7yATmU+d3g=="
    }
}
