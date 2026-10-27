pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // MapLibre ships on Maven Central; jitpack is kept for community
        // bits we may pull later (e.g. a PMTiles plugin, the nav-SDK fork).
        maven { url = uri("https://jitpack.io") }
    }
}

rootProject.name = "Vela"

// Two modules, deliberately. `:core` is the "extractor" — all Google interop,
// routing, location and voice live here with no UI dependency, the same way
// NewPipe keeps NewPipeExtractor as a standalone library. `:app` is the
// Compose UI shell on top. Split further (core:model / core:data / …)
// once the surface grows.
// `:core-common` is the Kotlin Multiplatform part of `:core` (jvm and iOS targets) that the iOS
// app shares; `:core` depends on it. `-Pvela.iosOnly=true` includes only the modules the iOS app
// builds, so a Mac with no Android SDK can compile and test them. `:ios-shared` (jvm and iOS
// targets, no Android plugin) links them into the VelaCore framework for the iOS app.
include(":core-common")
include(":ios-shared")
if (providers.gradleProperty("vela.iosOnly").orNull != "true") {
    include(":app")
    include(":baselineprofile")
    include(":core")
    // OsmAnd's router jar with its bundled protobuf moved to a private package, so Cronet's protobuf can
    // sit beside it (see osmand-shaded/build.gradle.kts).
    include(":osmand-shaded")
}
