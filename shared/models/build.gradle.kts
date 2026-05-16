import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// `shared/models` — Kotlin Multiplatform port of Pastura's `Models/` Swift
// layer (Issue #220 — KMP Models Layer Validation Spike).
//
// W1 establishes the module skeleton:
//   - iOS targets (arm64 device + simulator-arm64 + x64) for XCFramework
//     consumption by the iOS app (W3+ scope; W1 only validates the toolchain).
//   - JVM target for simulator-free Models tests on `./gradlew jvmTest`
//     (per the parallel motivation in the issue body).
//
// XCFramework export config is added in W1 Item 3.
// Pilot types (Persona, Pairing) and roundtrip tests land in W1 Item 4.

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvm {
        // T2: pin compile bytecode target to JVM 17. Runtime classpath uses
        // the local JDK (or `actions/setup-java` JDK 17 in CI — see
        // `.github/workflows/ci.yml`). Java toolchain auto-provisioning via
        // Foojay was tried but Foojay 0.10.0 references `JvmVendorSpec.IBM_SEMERU`
        // which Gradle 9.5.1 has removed; deferred to W2 when a Gradle-9.x
        // compatible Foojay release lands. Bytecode-only pin is enough for W1.
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    iosArm64()
    iosSimulatorArm64()
    iosX64()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.serialization.json)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
