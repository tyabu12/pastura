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
    // `PasturaShared.xcframework`. Task names (verified against
    // `./gradlew :shared:models:tasks --all`, #1135): both-config
    // `assemblePasturaSharedXCFramework`, single-config
    // `assemblePasturaShared<Debug|Release>XCFramework` — the config infix goes
    // AFTER the umbrella name, not before it. (This comment previously claimed
    // `assemble<Debug|Release>PasturaSharedXCFramework`, which does not exist:
    // Gradle rejects it as an ambiguous abbreviation of the per-platform
    // `assemble<Config><Platform>FatFrameworkFor…` tasks.)
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

    // macOS host target (#501 Stage 2-gate). Registered here — one stage ahead
    // of the ADR-023 §6 Stage-4 parity harness that names `macosArm64` as its
    // Kotlin/Native rung — because the Stage-2-gate Swift spike consumer is a
    // detached macOS SwiftPM package (host decision B′, #1135). Registering the
    // TARGET does not move the Stage-4 parity harness itself; that lands on
    // schedule.
    //
    // Deliberately NOT added to the `PasturaShared` umbrella above: nothing
    // consumes a macOS `PasturaShared`. The spike links the engine module's
    // `PasturaSharedEngine` umbrella, which re-exports this module. Adding a
    // macOS slice here would cost a fourth link target in the nightly and buy
    // nothing until some Swift consumer wants Models alone. `macosArm64Test`
    // still runs the shared `commonTest` suite on the K/N host runtime — the
    // point of the target at this stage.
    macosArm64()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.serialization.json)
            // YAML 1.2 parser. Backs `SnakeYamlEngineCodec` in commonMain —
            // no expect/actual needed because snakeyaml-engine-kmp's `Load`
            // API is exposed across all KMP targets
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

// Inject the LIVE bundled-preset directory for `LivePresetParseSmokeTests`
// (jvmTest) — the drift-immune parser-health smoke that asserts snakeyaml-engine-kmp
// can parse every CURRENT preset (#501 Stage 1). The absolute path keeps the read
// independent of Gradle's test working directory (differs local vs CI).
// NOTE: the cross-language fidelity harness (`YamlFidelityEquivalenceTests`) does
// NOT use this — Stage 1 froze it to `jvmTest/resources/frozen-presets/` copies of
// `f73bc48`, since its Swift-Yams baseline can't be regenerated without the
// (stripped) Swift Roundtrip harness. See that class's doc for the rationale.
tasks.named<Test>("jvmTest") {
    systemProperty(
        "pastura.presetsDir",
        rootProject.layout.projectDirectory
            .dir("Pastura/Pastura/Resources/Presets")
            .asFile.absolutePath,
    )
}
