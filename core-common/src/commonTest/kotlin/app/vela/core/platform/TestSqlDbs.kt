package app.vela.core.platform

/** A fresh empty folder on disk for one test. */
expect fun newTestDir(): String

/** The SqlDbs the platform tests run: `BundledSqlDbs` over [dir], on the JVM and on iOS. */
expect fun newTestSqlDbs(dir: String = newTestDir()): SqlDbs
