package app.vela.ios.saved

import java.io.ByteArrayOutputStream
import java.util.zip.Inflater

/** [Inflater] with `nowrap`: a ZIP method-8 member is raw DEFLATE, with no zlib header. */
actual fun inflateRaw(data: ByteArray, sizeHint: Int): ByteArray {
    val inflater = Inflater(true)
    try {
        inflater.setInput(data)
        val out = ByteArrayOutputStream(if (sizeHint in 1..SavedKmz.MAX_KML_BYTES) sizeHint else 64 * 1024)
        val buffer = ByteArray(64 * 1024)
        while (!inflater.finished()) {
            val read = inflater.inflate(buffer)
            if (read == 0) {
                if (inflater.needsInput() || inflater.needsDictionary()) throw IllegalStateException("deflate stream cut short")
                continue
            }
            out.write(buffer, 0, read)
            if (out.size() > SavedKmz.MAX_KML_BYTES) throw IllegalStateException("KML too large")
        }
        return out.toByteArray()
    } finally {
        inflater.end()
    }
}
