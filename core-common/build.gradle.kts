import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The platform-free part of the core, shared with the iOS app (SPEC 2.1). `:core` takes the jvm
// variant through `api`, so a class moved here keeps its package and every import still resolves.
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvm {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
    iosArm64()
    iosSimulatorArm64()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.kotlinx.datetime)
            implementation(libs.atomicfu)
        }
        // The bundled SQLite behind BundledSqlDbs: the iOS SqlDbs, and the JVM tests' (Android
        // has its own over the platform SQLite in :core, so the jvm main variant stays without it).
        val bundledSql = "src/bundledSql/kotlin"
        iosMain {
            kotlin.srcDir(bundledSql)
            dependencies { implementation(libs.androidx.sqlite.bundled) }
        }
        jvmTest {
            kotlin.srcDir(bundledSql)
            dependencies { implementation(libs.androidx.sqlite.bundled) }
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:${libs.versions.coroutines.get()}")
        }
    }
}
