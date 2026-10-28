package app.vela.core.util

/** The content of one gzip member, as `GZIPInputStream(...).readBytes()`. Throws on a stream that
 *  is not gzip or is cut short. */
expect fun gunzip(data: ByteArray): ByteArray
