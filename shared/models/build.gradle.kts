import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

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

    // Umbrella XCFramework export (D6 in #220). The three iOS targets each
    // produce a framework binary named `PasturaShared`; the aggregate
    // `XCFramework("PasturaShared")` task bundles them into
    // `PasturaShared.xcframework`. Task name:
    // `assemblePasturaSharedXCFramework` (also: `assemble<Debug|Release>PasturaSharedXCFramework`).
    // Swift consumption (`import PasturaShared`) lands in W3 (H8); W1 only
    // validates that the toolchain produces a valid XCFramework directory.
    val xcf = XCFramework("PasturaShared")
    iosArm64 {
        binaries.framework {
            baseName = "PasturaShared"
            xcf.add(this)
        }
    }
    iosSimulatorArm64 {
        binaries.framework {
            baseName = "PasturaShared"
            xcf.add(this)
        }
    }
    iosX64 {
        binaries.framework {
            baseName = "PasturaShared"
            xcf.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.serialization.json)
            // YAML 1.2 parser. Backs `YamlCodec` actuals in
            // jvmMain/iosMain via snakeyaml-engine-kmp's KMP API
            // (W2 PR-A item 9 — Day-1 D3 in #220).
            implementation(libs.snakeyaml.engine.kmp)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            // commonMain uses `implementation` (not `api`), so the
            // kotlinx-serialization-json dep does NOT transitively expose to
            // test sourceSets through Gradle's compile classpath. Adding it
            // explicitly here makes the test compile contract robust to
            // future commonMain dep scope changes.
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.snakeyaml.engine.kmp)
        }
    }
}
