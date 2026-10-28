package app.vela.core.platform

import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class AndroidPlatformFilesTest {
    private val root = Files.createTempDirectory("vela-files").toFile()
    private val files = AndroidPlatformFiles(root.resolve("files"), root.resolve("cache"), root.resolve("nobackup"))

    @After fun tearDown() { root.deleteRecursively() }

    @Test fun writesReadsListsAndDeletes() {
        val dir = joinPath(files.filesDir, "piper", "voice")
        assertFalse(files.exists(dir))
        assertNull(files.list(dir))
        assertTrue(files.mkdirs(dir))
        assertTrue(files.mkdirs(dir))
        assertTrue(files.isDirectory(dir))

        val a = joinPath(dir, "a.bin")
        files.writeBytes(a, byteArrayOf(1, 2, 3))
        assertArrayEquals(byteArrayOf(1, 2, 3), files.readBytes(a))
        assertEquals(3L, files.size(a))
        assertTrue(files.lastModifiedMillis(a) > 0)

        val b = joinPath(dir, "b.json")
        files.writeTextAtomic(b, "{\"v\":1}")
        files.writeTextAtomic(b, "{\"v\":2}")
        assertEquals("{\"v\":2}", files.readText(b))
        assertFalse(files.exists("$b.tmp"))

        files.mkdirs(joinPath(dir, "sub"))
        files.writeText(joinPath(dir, "sub", "c.txt"), "héllo")
        assertEquals(listOf("a.bin", "b.json", "sub"), files.list(dir)!!.map { it.name }.sorted())
        assertEquals(joinPath(dir, "a.bin"), files.list(dir)!!.single { it.name == "a.bin" }.path)
        assertEquals(0L, files.list(dir)!!.single { it.name == "sub" }.size)
        assertEquals(3L + 7L + "héllo".encodeToByteArray().size, files.treeSize(dir))

        assertTrue(files.rename(a, joinPath(dir, "a2.bin")))
        assertFalse(files.exists(a))
        assertEquals(0L, files.size(a))
        assertEquals(0L, files.lastModifiedMillis(a))

        assertFalse(files.delete(joinPath(dir, "sub")))
        assertTrue(files.deleteRecursively(joinPath(files.filesDir, "piper")))
        assertFalse(files.exists(dir))
    }

    @Test fun foldersAreTheGivenOnes() {
        assertEquals(root.resolve("files").path, files.filesDir)
        assertEquals(root.resolve("cache").path, files.cacheDir)
        assertEquals(root.resolve("nobackup").path, files.noBackupDir)
    }

    @Test fun normalizerAndLocaleMatchTheJvm() {
        assertEquals("e\u0301", JvmTextNormalizer.normalize("é", NormalForm.NFD))
        assertEquals("é", JvmTextNormalizer.normalize("e\u0301", NormalForm.NFC))
        assertEquals("fi", JvmTextNormalizer.normalize("\uFB01", NormalForm.NFKD))
        assertEquals(java.util.Locale.getDefault().language, AndroidPlatformLocale.defaultLanguage())
        assertEquals(java.util.Locale.getDefault().toLanguageTag(), AndroidPlatformLocale.defaultTag())
    }
}
