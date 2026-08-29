import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// `shared/models` — Kotlin Multiplatform port of Pastura's `Models/` Swift
// layer (Issue #220 — KMP Models Layer Validation Spike).
//
// W1 establishes the module skeleton:
//   - iOS targets (arm64 device + simulator-arm64 + x64), consumed by the iOS
//     app through `shared/engine`'s `PasturaSharedEngine` umbrella — this
//     module builds no framework of its own (see the targets below).
//   - JVM target for simulator-free Models tests on `./gradlew jvmTest`
//     (per the parallel motivation in the issue body).

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

    // iOS targets. NO framework binaries and NO umbrella of this module's own:
    // ADR-023 §6 Stage-5 ruling (b) dropped the models-only `PasturaShared`
    // XCFramework rather than retargeting it, which disarms the §9.7
    // two-umbrella landmine mechanically (there is no second umbrella left to
    // co-link). These targets stay because `shared/engine` needs their klibs:
    // its `export(project(":shared:models"))` links every models symbol into
    // `PasturaSharedEngine`, so Models still ships to Swift — through the one
    // engine umbrella, on the same three iOS triples.
    iosArm64()
    iosSimulatorArm64()
    iosX64()

    // macOS host target (#501 Stage 2-gate). Registered here — one stage ahead
    // of the ADR-023 §6 Stage-4 parity harness that names `macosArm64` as its
    // Kotlin/Native rung — because the Stage-2-gate Swift spike consumer is a
    // detached macOS SwiftPM package (host decision B′, #1135). Registering the
    // TARGET does not move the Stage-4 parity harness itself; that lands on
    // schedule.
    //
    // Like the iOS targets above, this one declares no framework binary: since
    // ADR-023 §6 Stage-5 ruling (b) this module has no umbrella of its own and
    // ships to Swift only inside `PasturaSharedEngine`, which re-exports it.
    // Nothing consumes a macOS models-only framework, and building one would
    // buy nothing until some Swift consumer wants Models alone. `macosArm64Test`
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
    // Inject the LIVE string catalog for `MessageCatalogCoverageTests` — the only
    // check that a Models-layer message's `Rendering.format` is still a live,
    // translated catalog key. On Apple targets `localizedFormat` falls back to the
    // key itself when the lookup misses, so drift loses the ja translation silently.
    // Absolute path, same reason as `pastura.presetsDir` above.
    systemProperty(
        "pastura.xcstringsPath",
        rootProject.layout.projectDirectory
            .file("Pastura/Pastura/Resources/Localizable.xcstrings")
            .asFile.absolutePath,
    )
}
