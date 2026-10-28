package app.vela.ios.net

/**
 * The error the Swift `VelaHttp` hands back when no response came: a transport failure, the
 * deadline, or a cancel. [reason] is `timeout`, `cancelled` or `network`.
 */
class IosHttpException(message: String, val reason: String) : Exception(message) {
    val isTimeout: Boolean get() = reason == TIMEOUT
    val isCancelled: Boolean get() = reason == CANCELLED

    companion object {
        const val TIMEOUT = "timeout"
        const val CANCELLED = "cancelled"
        const val NETWORK = "network"
    }
}
