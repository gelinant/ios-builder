package app.vela.core.platform

import platform.Foundation.NSFileManager
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID

@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
actual fun newTestDir(): String {
    val dir = joinPath(NSTemporaryDirectory(), "vela-sql-" + NSUUID().UUIDString)
    NSFileManager.defaultManager.createDirectoryAtPath(dir, withIntermediateDirectories = true, attributes = null, error = null)
    return dir
}

actual fun newTestSqlDbs(dir: String): SqlDbs = BundledSqlDbs(dir)

actual fun testSqlDbsWithDirHook(dir: String, ensureDir: (String) -> Unit): SqlDbs = BundledSqlDbs(dir, ensureDir)
