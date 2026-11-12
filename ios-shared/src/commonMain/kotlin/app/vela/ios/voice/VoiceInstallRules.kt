package app.vela.ios.voice

/** One voice row's controls, for the settings section and the library sheet. */
data class VoiceRowStatus(
    val installed: Boolean,
    val inUse: Boolean,
    val downloading: Boolean,
    val installing: Boolean,
    val progressPercent: Int,
    val canUse: Boolean,
    val canDownload: Boolean,
    val canRemove: Boolean,
)

/**
 * The download and removal rules shared by both voice screens. Only one voice downloads at a
 * time; an installed voice is never offered again; a voice being extracted cannot be removed;
 * removing the selected voice clears the selection instead of leaving a dead id behind.
 *
 * The installed set itself comes from the filesystem, so an interrupted download is never
 * installed. These functions only decide what the buttons may do.
 */
object VoiceInstallRules {
    fun row(
        installed: Boolean,
        inUse: Boolean,
        downloadingId: String?,
        id: String,
        installing: Boolean,
        progress: Double,
    ): VoiceRowStatus {
        val downloading = downloadingId == id
        val clamped = progress.coerceIn(0.0, 1.0)
        return VoiceRowStatus(
            installed = installed,
            inUse = inUse,
            downloading = downloading,
            installing = downloading && installing,
            progressPercent = if (downloading) (clamped * 100).toInt() else 0,
            canUse = installed && !inUse,
            canDownload = !installed && downloadingId == null,
            canRemove = installed && !downloading,
        )
    }

    /** A tap on Download is ignored while another voice downloads or this one is installed. */
    fun canStartDownload(installed: Boolean, downloadingId: String?): Boolean =
        !installed && downloadingId == null

    /** Removing the selected id clears the pick; another id leaves it untouched. */
    fun selectionAfterRemove(removedId: String, selectedId: String?): String? =
        if (selectedId == removedId) null else selectedId

    /** A finished install becomes the pick, as Android selects a voice the user just fetched. */
    fun selectionAfterInstall(installedId: String): String = installedId
}
