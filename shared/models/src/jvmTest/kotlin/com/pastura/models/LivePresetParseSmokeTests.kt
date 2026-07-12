package com.pastura.models

import kotlinx.serialization.json.JsonObject
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Drift-immune parser-health smoke over the LIVE preset YAML — #501 Stage 1.
 *
 * Complements [YamlFidelityEquivalenceTests], which is intentionally frozen at
 * `f73bc48` (its Swift baseline cannot be regenerated in Stage 1 — see that
 * class's doc). This smoke instead reads the CURRENT
 * `Pastura/Pastura/Resources/Presets/` YAML files via the `pastura.presetsDir`
 * system property injected by the `jvmTest` task (see
 * `shared/models/build.gradle.kts`) and asserts only that
 * `snakeyaml-engine-kmp` can PARSE each one into a top-level map.
 *
 * **Why this is drift-immune**: it checks parse-ABILITY, not content-equality
 * against a frozen baseline, so a preset *edit* never turns it red. It goes red
 * only when a preset uses YAML that the Kotlin parser genuinely cannot handle —
 * a true-positive the Kotlin Models layer must know about before Stage 2+ runs
 * the Engine on that content. Full CURRENT-preset cross-language re-validation
 * (against a regenerated Swift baseline) returns at Stage 2/5 with the harness.
 */
class LivePresetParseSmokeTests {

    private val codec: YamlCodec = YamlCodec.default()

    @Test
    fun everyLivePresetParsesToATopLevelMap() {
        val dir = System.getProperty("pastura.presetsDir")
            ?: error(
                "Missing `pastura.presetsDir` system property — the jvmTest task " +
                    "must inject it (see shared/models/build.gradle.kts).",
            )
        val presetDir = File(dir)
        assertTrue(presetDir.isDirectory, "presetsDir is not a directory: ${presetDir.path}")

        val yamls = presetDir.listFiles { f -> f.isFile && f.name.endsWith(".yaml") }
            ?.sortedBy { it.name }
            .orEmpty()
        // Guard against a silently-empty dir / mis-injected property passing vacuously.
        assertTrue(
            yamls.size >= 4,
            "Expected at least the 4 base presets under ${presetDir.path}, found ${yamls.size}",
        )

        for (file in yamls) {
            val tree = try {
                codec.decode(file.readText(Charsets.UTF_8))
            } catch (e: Throwable) {
                fail("snakeyaml-engine-kmp failed to parse live preset ${file.name}: ${e.message}")
            }
            assertTrue(
                tree is JsonObject,
                "Live preset ${file.name} did not parse to a top-level map (got ${tree::class.simpleName})",
            )
        }
    }
}
