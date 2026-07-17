import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

// `shared/engine` — Kotlin Multiplatform port target for Pastura's `Engine/`
// Swift layer (Issue #501 / ADR-023). Landed as an empty scaffold in Stage 1
// (PR-2); Stage 2-pre put the first real logic in it (`ConditionEvaluator`).
//
// Deliberately minimal vs `shared/models`:
//   - No `kotlin-serialization` PLUGIN and no `snakeyaml-engine-kmp` — the engine
//     run-path declares no `@Serializable` types of its own and does not parse
//     YAML (that is Models' `YamlCodec`). The plugin is codegen for
//     `@Serializable`; `JSONResponseParser` only needs the RUNTIME library to
//     walk a `JsonElement`, so the library is a dependency and the plugin stays
//     out. Models' own dep is `implementation`, so it does not reach here
//     transitively — hence the explicit declaration below.
//
// `kotlinx-coroutines-core` is `implementation`, NOT `api`, and is deliberately
// NOT exported into the framework. This encodes ADR-023 Decision 2: structured
// concurrency stays INSIDE each language and the K/N boundary is callback-only —
// no `suspend` function, Flow, `Deferred`, or `Job` may appear in the exported
// Obj-C surface. Coroutines back the §5.2 mechanisms internally
// (`CompletableDeferred` relay, `suspendCancellableCoroutine.invokeOnCancellation`,
// `Job` cancellation) while `RunHandle` / `LLMBackend` / `StreamCallbacks` stay
// plain interfaces.
//
// ⚠️ A leak does NOT fail the link. Measured on this branch: adding
// `public val leaked: CompletableDeferred<Unit>` to a commonMain class still
// produced BUILD SUCCESSFUL — no error, no "not specified as API-dependencies"
// warning — while silently pulling 48 coroutine symbol lines into the generated
// header (`PSEKotlinx_coroutines_coreCompletableDeferred`, `...coreJob`,
// `PSEKotlinCoroutineContext`, and the leaked property itself). So "the build is
// green" is NOT evidence the boundary is clean. `verifyEngineFrameworkSurface`
// (below) is the positive check that actually witnesses Decision 2.
//
// ⚠️ Do NOT "fix" a surface-check failure by promoting this to `api` + `export(...)`.
// A failure means a coroutine type reached the public boundary — Decision 2 was
// violated — and the fix is the leaking declaration, not the dep scope.
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
            // `implementation`, never `api`/`export` — see the header comment.
            implementation(libs.kotlinx.coroutines.core)
            // Runtime only (no plugin): `JSONResponseParser` walks a JsonElement.
            // Also `implementation` — no serialization type is on the boundary.
            implementation(libs.kotlinx.serialization.json)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            // Redundant while commonMain uses `api` (which does put models on
            // the test compile classpath). Kept deliberately, mirroring
            // `shared/models`'s own commonTest: it makes the test compile
            // contract robust to future commonMain dep-scope changes.
            implementation(project(":shared:models"))
            // Supplies `runTest` — a separate artifact from -core, and the first
            // coroutine-test usage in this repo.
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}

// ── ADR-023 Decision 2 surface guard ────────────────────────────────────────
//
// Asserts no coroutine type reached the exported Obj-C surface. This is the ONLY
// mechanism that witnesses the callback-only boundary: a leak links green (see
// the header comment), so without this check "no `suspend` crosses K/N" would be
// an unverified claim rather than a tested contract.
//
// Reads the macosArm64 debug framework header — the cheapest single link that
// carries the full surface, and the same target the Stage-2-gate Swift consumer
// binary-targets (host decision B′, #1135).
//
// TWO offender patterns, because they catch different leaks — measured on this
// branch, both against deliberately-leaking probes:
//
//   1. `coroutin` — a coroutine TYPE on the surface. A `public val` of
//      CompletableDeferred pulled in 48 symbol lines
//      (`PSEKotlinx_coroutines_coreCompletableDeferred`, `...coreJob`,
//      `PSEKotlinCoroutineContext`). Flow / Deferred / Job all carry the token.
//   2. `completionHandler:` — a `suspend fun` on the surface. K/N exports one as a
//      plain completion-handler-taking Obj-C method and pulls in NO
//      kotlinx_coroutines symbol at all, so pattern 1 misses it entirely. A
//      `public suspend fun` probe linked green AND passed a pattern-1-only guard —
//      while Decision 2 names `suspend` FIRST. Measured false-positive risk: the
//      clean header contains zero `completionHandler` occurrences.
//
// Comment-stripping is load-bearing, not defensive: K/N copies Kotlin KDoc into
// the generated header, and this module's boundary docs legitimately *discuss*
// `CompletableDeferred` and `suspendCancellableCoroutine`. A naive grep scores 10
// hits on a perfectly clean header. Only CODE lines are evidence.
//
// The state machine is calibrated to K/N's emitted shape (KDoc as leading
// `/** … */` blocks), NOT to general Obj-C: a block comment opened mid-line is not
// recognised. Fine here; do not reuse it as a general stripper.
val verifyEngineFrameworkSurface by tasks.registering {
    group = "verification"
    description = "Fails if a coroutine type leaked into the exported PasturaSharedEngine surface."
    dependsOn("linkDebugFrameworkMacosArm64")

    val headerFile = layout.buildDirectory.file(
        "bin/macosArm64/debugFramework/PasturaSharedEngine.framework/Headers/PasturaSharedEngine.h",
    )
    inputs.file(headerFile)
    // No output artifact — re-run whenever the header changes (inputs.file drives
    // up-to-date checking; the header is regenerated by the link task).
    outputs.upToDateWhen { false }

    doLast {
        val header = headerFile.get().asFile
        // Defense in depth only — `inputs.file(headerFile)` above already fails the
        // task if the header is missing, and `outputs.upToDateWhen { false }` is
        // what actually prevents a vacuous pass. Do not relax either believing this
        // branch covers them.
        if (!header.isFile) {
            throw GradleException(
                "Framework header not found at ${header.path}. " +
                    "linkDebugFrameworkMacosArm64 did not produce the expected layout.",
            )
        }

        var inBlockComment = false
        val offenders = mutableListOf<String>()
        header.readLines().forEachIndexed { index, raw ->
            val line = raw.trim()
            when {
                inBlockComment -> if (line.contains("*/")) inBlockComment = false
                line.startsWith("/*") -> if (!line.contains("*/")) inBlockComment = true
                line.startsWith("*") || line.startsWith("//") -> Unit
                line.contains("coroutin", ignoreCase = true) ->
                    offenders += "  ${index + 1}: [coroutine type] $line"
                line.contains("completionHandler:") ->
                    offenders += "  ${index + 1}: [exported suspend fun] $line"
            }
        }

        if (offenders.isNotEmpty()) {
            throw GradleException(
                buildString {
                    appendLine("ADR-023 Decision 2 violated: coroutine types reached the exported")
                    appendLine("PasturaSharedEngine surface. The K/N boundary must be callback-only —")
                    appendLine("no suspend fn, Flow, Deferred, or Job may cross.")
                    appendLine()
                    appendLine("Fix the leaking declaration; do NOT promote kotlinx-coroutines to")
                    appendLine("`api` + `export(...)` to silence this.")
                    appendLine()
                    appendLine("Offending header lines (${offenders.size}):")
                    offenders.take(10).forEach { appendLine(it) }
                    if (offenders.size > 10) appendLine("  … ${offenders.size - 10} more")
                },
            )
        }
        logger.lifecycle("ADR-023 Decision 2: exported surface is coroutine-free.")
    }
}

// Wired to the macosArm64 debug LINK, not just to XCFramework assembly.
//
// Assembly-only wiring left a real hole: per `.github/workflows/ci.yml`, CI runs
// `assemblePasturaSharedEngineDebugXCFramework` ONLY when a PR touches build
// config. So a PR adding `public val handle: CompletableDeferred<Unit>` to
// `RunHandle` — pure Kotlin, no build-file touch — would be green at PR time and
// caught up to 24h later by the nightly. That is exactly the shape of PR this
// module will now receive, since this PR is the one introducing the boundary types.
//
// Attaching to the link means any lane that produces a surface checks it, and adds
// one macosArm64 debug link (~15s warm) to a lane that already compiles K/N.
tasks.named("linkDebugFrameworkMacosArm64") {
    finalizedBy(verifyEngineFrameworkSurface)
}
tasks.matching {
    it.name.startsWith("assemblePasturaSharedEngine") && it.name.endsWith("XCFramework")
}.configureEach {
    finalizedBy(verifyEngineFrameworkSurface)
}
