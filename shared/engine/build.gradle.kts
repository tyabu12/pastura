import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

// `shared/engine` — Kotlin Multiplatform port target for Pastura's `Engine/`
// Swift layer (Issue #501 / ADR-023). Landed as an empty scaffold in Stage 1
// (PR-2); Stage 2-pre put the first real logic in it (`ConditionEvaluator`).
//
// Deliberately minimal vs `shared/models`:
//   - No `kotlin-serialization` plugin and no `snakeyaml-engine-kmp` — the
//     engine run-path does not declare its own `@Serializable` types or parse
//     YAML (that is Models' `YamlCodec`). Added in a later stage only if a
//     ported handler actually needs them.
//
// The `shared/models` dependency (Engine→Models, a CLAUDE.md hard rule) is
// `api`, not `implementation`. Two independent reasons, either sufficient:
//   1. `export(project(":shared:models"))` below requires it — the Kotlin
//      Gradle plugin fails the framework link with "Following dependencies
//      exported in the framework are not specified as API-dependencies".
//   2. It is semantically correct regardless of export: `ConditionEvaluator`'s
//      public API already re-exports Models types (`Scenario`, `SimulationError`,
//      `SimulationState`). This discharges the condition the Stage-1 version of
//      this comment pre-registered ("promote to `api` … only if the public API
//      re-exports Models types to a consumer") — one stage later than predicted.

plugins {
    alias(libs.plugins.kotlin.multiplatform)
}

kotlin {
    jvm {
        // Pin bytecode target to JVM 17, matching `shared/models` (T2 in #220):
        // JVM parity tests + the Stage 4 cross-language harness run on jvmTest.
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    // Umbrella XCFramework for Swift consumption of the engine module.
    //
    // Needed at Stage 2-gate, NOT Stage 5 as this file previously asserted: the
    // gate's acceptance criterion (ADR-023 §6) requires a Swift-side scripted
    // streaming `LLMBackend` actual driving a real `AsyncThrowingStream` through
    // the §5.2 adapter — "a Kotlin-side mock alone does NOT satisfy the gate" —
    // so Swift must link a real framework before the GO/NO-GO call, not after.
    //
    // `export(project(":shared:models"))` makes this a single umbrella: Models
    // types cross both §5 boundaries (`SimulationEvent`, `Scenario`), so the
    // Swift consumer must see them through this framework rather than linking a
    // second one.
    //
    // ⚠️ INVARIANT: `PasturaShared` (models-only) and `PasturaSharedEngine` must
    // never be linked into the same binary — this umbrella statically embeds
    // every models symbol, so the pair means duplicate symbols and two copies of
    // the K/N runtime. Safe today (nothing on `main` links either), but the
    // retained `feature/kmp-spike-models` branch embeds `PasturaShared` into the
    // app target, and ADR-023 §6 Stage 5 merges that wiring back — it must be
    // retargeted to this umbrella or dropped at merge-back. Recorded as a §9.7
    // landmine in ADR-023 §6.
    val xcf = XCFramework("PasturaSharedEngine")

    // iOS target triple mirrors `shared/models` so the umbrella covers the same
    // device + simulator + x64 set.
    iosArm64 {
        binaries.framework {
            baseName = "PasturaSharedEngine"
            export(project(":shared:models"))
            xcf.add(this)
        }
    }
    iosSimulatorArm64 {
        binaries.framework {
            baseName = "PasturaSharedEngine"
            export(project(":shared:models"))
            xcf.add(this)
        }
    }
    iosX64 {
        binaries.framework {
            baseName = "PasturaSharedEngine"
            export(project(":shared:models"))
            xcf.add(this)
        }
    }

    // macOS host target (#501 Stage 2-gate). Pulled forward of the ADR-023 §6
    // Stage-4 parity harness, which names `macosArm64` as its Kotlin/Native
    // rung: the Stage-2-gate Swift spike consumer is a detached macOS SwiftPM
    // package (host decision B′, #1135) and binary-targets this slice. Only the
    // TARGET registration moves — the Stage-4 parity harness lands on schedule.
    //
    // This is the one slice with a live Swift consumer, which is why the macOS
    // framework lives in THIS umbrella and `shared/models` deliberately keeps
    // macosArm64 out of its own `PasturaShared` (nothing consumes a macOS
    // models-only framework — see that file's comment).
    macosArm64 {
        binaries.framework {
            baseName = "PasturaSharedEngine"
            export(project(":shared:models"))
            xcf.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
            // Engine→Models layer edge. `api` — see the header comment for why.
            api(project(":shared:models"))
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            // Redundant while commonMain uses `api` (which does put models on
            // the test compile classpath). Kept deliberately, mirroring
            // `shared/models`'s own commonTest: it makes the test compile
            // contract robust to future commonMain dep-scope changes.
            implementation(project(":shared:models"))
        }
    }
}
