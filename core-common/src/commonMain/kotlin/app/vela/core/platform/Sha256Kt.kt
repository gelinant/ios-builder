package app.vela.core.platform

/** SHA-256 (FIPS 180-4) in Kotlin, the iOS [sha256]. `jvmTest` checks it against `MessageDigest`. */
internal class Sha256Kt : Sha256 {
    private val h = IntArray(8)
    private val block = ByteArray(64)
    private var fill = 0
    private var total = 0L
    private val w = IntArray(64)

    init { reset() }

    private fun reset() {
        INIT.copyInto(h)
        fill = 0
        total = 0L
    }

    override fun update(bytes: ByteArray) {
        var i = 0
        total += bytes.size
        while (i < bytes.size) {
            val n = minOf(64 - fill, bytes.size - i)
            bytes.copyInto(block, fill, i, i + n)
            fill += n
            i += n
            if (fill == 64) { compress(); fill = 0 }
        }
    }

    override fun digest(): ByteArray {
        val bits = total * 8
        block[fill++] = 0x80.toByte()
        if (fill > 56) {
            block.fill(0, fill, 64)
            compress()
            fill = 0
        }
        block.fill(0, fill, 56)
        for (k in 0 until 8) block[56 + k] = (bits ushr (56 - 8 * k)).toByte()
        compress()
        val out = ByteArray(32)
        for (k in 0 until 8) for (b in 0 until 4) out[4 * k + b] = (h[k] ushr (24 - 8 * b)).toByte()
        reset()
        return out
    }

    private fun compress() {
        for (t in 0 until 16) {
            w[t] = ((block[4 * t].toInt() and 0xFF) shl 24) or ((block[4 * t + 1].toInt() and 0xFF) shl 16) or
                ((block[4 * t + 2].toInt() and 0xFF) shl 8) or (block[4 * t + 3].toInt() and 0xFF)
        }
        for (t in 16 until 64) {
            val s0 = w[t - 15].rotateRight(7) xor w[t - 15].rotateRight(18) xor (w[t - 15] ushr 3)
            val s1 = w[t - 2].rotateRight(17) xor w[t - 2].rotateRight(19) xor (w[t - 2] ushr 10)
            w[t] = w[t - 16] + s0 + w[t - 7] + s1
        }
        var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3]
        var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7]
        for (t in 0 until 64) {
            val t1 = hh + (e.rotateRight(6) xor e.rotateRight(11) xor e.rotateRight(25)) + ((e and f) xor (e.inv() and g)) + K[t] + w[t]
            val t2 = (a.rotateRight(2) xor a.rotateRight(13) xor a.rotateRight(22)) + ((a and b) xor (a and c) xor (b and c))
            hh = g; g = f; f = e; e = d + t1
            d = c; c = b; b = a; a = t1 + t2
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d
        h[4] += e; h[5] += f; h[6] += g; h[7] += hh
    }

    private companion object {
        val INIT = intArrayOf(
            0x6a09e667, -0x4498517b, 0x3c6ef372, -0x5ab00ac6, 0x510e527f, -0x64fa9774, 0x1f83d9ab, 0x5be0cd19,
        )
        val K = longArrayOf(
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ).map { it.toInt() }.toIntArray()
    }
}
