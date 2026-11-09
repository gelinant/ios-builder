package app.vela.core.platform

/**
 * The platform implementations the shared core runs on, built once per process and passed to the
 * classes that need them (SPEC "Platform seams"). Android builds it through Hilt
 * (`di/PlatformModule`); iOS builds it by hand from its Swift classes.
 */
class CoreGraph(
    val log: Log,
    val clock: Clock,
    val keyValues: KeyValueStores,
    val files: PlatformFiles,
    val http: VelaHttp,
    val text: TextNormalizer,
    val locale: PlatformLocale,
)
