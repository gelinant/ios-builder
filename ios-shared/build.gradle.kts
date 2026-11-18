import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The Kotlin side of the iOS app (SPEC 2.1): the iOS graph and, later, the presentation stores
// SwiftUI observes. It links into VelaCore.framework, which exports :core-common so Swift sees its
// classes directly. The jvm target only runs the shared logic's tests on Linux.
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.skie)
}

kotlin {
    jvm {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
    listOf(iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "VelaCore"
            // Static: linked into the app binary, nothing to embed or sign.
            isStatic = true
            export(dependencies.project(":core-common"))
            binaryOption("bundleId", "app.vela.core")
        }
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":core-common"))
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.atomicfu)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}
