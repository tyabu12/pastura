import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// `shared/engine` — Kotlin Multiplatform port target for Pastura's `Engine/`
// Swift layer (Issue #501 / ADR-023). Landed here (Stage 1 PR-2) as an EMPTY
// scaffold: it registers the module and its target set so the Stage 2-pre
// `ConditionEvaluator` port has a compiling landing pad to drop into. No engine
// logic ports in this PR (Stage 1 = infrastructure only).
//
// Deliberately minimal vs `shared/models`:
//   - No `kotlin-serialization` plugin and no `snakeyaml-engine-kmp` — the
//     engine run-path does not declare its own `@Serializable` types or parse
//     YAML (that is Models' `YamlCodec`). Added in a later stage only if a
//     ported handler actually needs them.
//   - No framework/XCFramework export block — Swift consumption of the engine
//     module is Stage 5 (iOS consumption switch, ADR-023 §6). Stage 1 only
//     needs the module to compile (jvm + native klib).
//
// The `shared/models` dependency (Engine→Models, a CLAUDE.md hard rule) is
// pulled forward from Stage 2-pre so this PR validates the Gradle module graph
// + the models klib building as an upstream dependency. It is `implementation`
// (matching the models module's own dep-scope convention) — promote to `api`
// in Stage 2-pre only if `ConditionEvaluator`'s public API re-exports Models
// types to a consumer.

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

    // iOS target triple mirrors `shared/models` so the eventual XCFramework
    // (Stage 5) covers the same device + simulator + x64 set. No framework
    // binary is declared here yet — Stage 1 only compiles the native klib.
    iosArm64()
    iosSimulatorArm64()
    iosX64()

    // macOS host target (#501 Stage 2-gate) — mirrors `shared/models`. Pulled
    // forward of the ADR-023 §6 Stage-4 parity harness (which names `macosArm64`
    // as its Kotlin/Native rung) because the Stage-2-gate Swift spike consumer
    // is a detached macOS SwiftPM package (host decision B′, #1135). The target
    // registration moves; the Stage-4 harness does not.
    macosArm64()

    sourceSets {
        commonMain.dependencies {
            // Engine→Models layer edge. Inert at Stage 1 (no engine sources
            // reference Models yet); present so the module graph is validated
            // now rather than at the first ported symbol in Stage 2-pre.
            implementation(project(":shared:models"))
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            // `commonMain` uses `implementation` for the models edge, so it is
            // not transitively on the test compile classpath — add it explicitly
            // so Stage 2-pre's `ConditionEvaluator` tests can reference Models
            // types the moment they land (mirrors `shared/models`'s pattern).
            implementation(project(":shared:models"))
        }
    }
}
