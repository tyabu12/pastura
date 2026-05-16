// Root build file. No plugins applied here; subprojects apply their own
// via `alias(libs.plugins.X)` against the version catalog in
// `gradle/libs.versions.toml`. Per Gradle 9 best practice (T4 in #220).

plugins {
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
