package app.vela.ios.offline

/**
 * Debug UI fixtures only. The synthetic offline bodies ship in the app bundle under an
 * `offline-fixture-` prefix (`offline-fixture-pack-v1.zip`), while their manifests carry the plain
 * names (`pack-v1.zip`) that a real mirror would publish. [OfflineStore] passes every plan URL
 * through [rewrite] while fixture catalogs are loaded, so a piece, a delta patch, the world archive
 * or the glyph pack cannot reach a transfer with a name the bundled fixtures do not have. The
 * mapping is idempotent: a URL that already carries the prefix is left alone, which keeps a
 * restored plan safe to run again.
 */
internal object OfflineFixtureUrls {
    const val HOST = "offline.fixture.invalid"
    private const val PREFIX = "offline-fixture-"
    private const val BASE = "https://$HOST/"

    fun rewrite(url: String): String {
        if (!url.startsWith(BASE)) return url
        val name = url.substringAfterLast('/')
        if (name.isEmpty() || name.startsWith(PREFIX)) return url
        return BASE + PREFIX + name
    }
}
