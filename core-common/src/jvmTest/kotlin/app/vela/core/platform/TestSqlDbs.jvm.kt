package app.vela.core.platform

actual fun newTestDir(): String =
    java.nio.file.Files.createTempDirectory("vela-sql").toFile().apply { deleteOnExit() }.path

actual fun newTestSqlDbs(dir: String): SqlDbs = BundledSqlDbs(dir)

actual fun testSqlDbsWithDirHook(dir: String, ensureDir: (String) -> Unit): SqlDbs = BundledSqlDbs(dir, ensureDir)
