package app.vela.offline

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.offline.PlacesArchiveSearch
import app.vela.core.offline.PmtilesCompact
import app.vela.core.offline.PmtilesPatch
import app.vela.core.offline.PmtilesReader
import app.vela.core.platform.AndroidLog
import java.io.File

// The PMTiles code in :core-common takes paths; these take the app's Files, and add the archive
// streamed over OkHttp.

fun PmtilesReader.header(file: File) = header(file.path)
fun PmtilesReader.hasTile(file: File, z: Int, x: Int, y: Int) = hasTile(file.path, z, x, y)
fun PmtilesReader.hasRoads(file: File, z: Int, x: Int, y: Int) = hasRoads(file.path, z, x, y)
fun PmtilesReader.tileBytes(file: File, z: Int, x: Int, y: Int) = tileBytes(file.path, z, x, y)
fun PmtilesReader.entries(file: File) = entries(file.path)

/** A local archive; its path, length and modification time key the directory cache. */
fun PmtilesReader.Archive.Companion.file(file: File): PmtilesReader.Archive =
    PmtilesReader.Archive.file(file.absolutePath, file.length(), file.lastModified())

/** An archive served over HTTP (the places archives on the release host): each read is one
 *  `Range` request, answered 206. */
fun PmtilesReader.Archive.Companion.http(client: okhttp3.OkHttpClient, url: String): PmtilesReader.Archive =
    PmtilesReader.Archive(url, PmtilesReader.RangeReader { offset, length ->
        runCatching {
            client.newCall(
                okhttp3.Request.Builder().url(url).header("Range", "bytes=$offset-${offset + length - 1}").build(),
            ).execute().use { r -> if (r.code == 206) r.body?.bytes()?.takeIf { it.size == length } else null }
        }.getOrNull()
    })

fun PmtilesCompact.compact(file: File) = compact(file.path)

fun PmtilesPatch.read(patch: File) = read(patch.path, AndroidLog)
fun PmtilesPatch.apply(archive: File, patch: File, verify: Boolean = true) = apply(archive.path, patch.path, verify, AndroidLog)
fun PmtilesPatch.fingerprint(file: File) = fingerprint(file.path)

fun PlacesArchiveSearch.search(files: List<File>, near: LatLng, query: String, want: Int = 60): List<Place> =
    search(files.map { it.path }, near, query, want) { PmtilesReader.Archive.file(File(it)) }
