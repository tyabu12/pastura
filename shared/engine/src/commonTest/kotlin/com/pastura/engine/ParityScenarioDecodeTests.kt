package com.pastura.engine

import com.pastura.models.Scenario
import com.pastura.models.ScenarioCodec
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

/**
 * The first gate of ADR-023 Stage-4 slice 1b: can the Kotlin side even read the
 * Swift-authored scenario the golden froze?
 *
 * [ParityGolden]'s `scenarioJson` is Swift `Codable`'s synthesized shape
 * (`agentCount`, `outputSchema`, `excludeSelf`, `thenPhases`, `elsePhases`, …).
 * If that does not decode into [Scenario], slice 1b is not an engine-parity
 * problem at all — it is a type-parity one, and every later item is built on
 * sand. So this runs before the mirror and before `EngineParityTests`.
 *
 * ## Why the assertion is a SEMANTIC round-trip, not a byte comparison
 *
 * Comparing [ScenarioCodec.encodeToString]'s output against `scenarioJson`
 * byte-for-byte **must** fail, for two reasons that say nothing about parity:
 *
 * - Swift emits with `.sortedKeys` (`ParityFixtureEmitter.encodeScenario`);
 *   kotlinx emits in property-declaration order.
 * - [ScenarioCodec] uses the default `Json`, whose `encodeDefaults` is `false`,
 *   so `extraData = emptyMap()` is omitted — while the golden carries
 *   `"extraData":{}`.
 *
 * A byte assertion here would therefore re-scope the whole slice on an encoder
 * artifact. What actually matters is that no field is lost or invented in the
 * crossing, which `decode -> encode -> decode` states directly.
 */
class ParityScenarioDecodeTests {

    /**
     * `ignoreUnknownKeys` is left at its `false` default **explicitly**.
     *
     * Strictness is the whole point: a key Swift emits that Kotlin's model does
     * not know is exactly the drift this gate exists to catch, and a lenient
     * decoder would swallow it and report green.
     * [strictDecodingRejectsAKeyKotlinDoesNotKnow] is the control proving this
     * is live rather than merely written down.
     */
    private val json = Json { ignoreUnknownKeys = false }

    private fun decode(source: String): Scenario =
        json.decodeFromString(Scenario.serializer(), source)

    @Test
    fun everyGoldenScenarioDecodesIntoTheKotlinModel() {
        for (fixture in ParityGolden.all) {
            // A throw here IS the failure — `SerializationException` names the
            // offending key or the missing field, which is more diagnostic than
            // anything a wrapping assertion could add.
            val scenario = decode(fixture.scenarioJson)

            // Guard against a decode that "succeeded" into defaults. Every
            // assertion below is a field the golden actually populates, so a
            // model whose properties silently defaulted cannot pass.
            assertTrue(
                scenario.id.isNotEmpty(),
                "${fixture.name}: decoded scenario has an empty id",
            )
            assertTrue(
                scenario.phases.isNotEmpty(),
                "${fixture.name}: decoded scenario has no phases",
            )
            assertTrue(
                scenario.rounds > 0,
                "${fixture.name}: decoded scenario has rounds=${scenario.rounds}",
            )
            assertEquals(
                scenario.agentCount,
                scenario.personas.size,
                "${fixture.name}: agentCount disagrees with the decoded persona count",
            )
        }
    }

    @Test
    fun decodingIsLosslessAcrossAReEncode() {
        for (fixture in ParityGolden.all) {
            val once = decode(fixture.scenarioJson)
            val twice = decode(ScenarioCodec.encodeToString(once))
            assertEquals(
                once,
                twice,
                "${fixture.name}: a field was lost or invented in decode -> encode -> decode",
            )
        }
    }

    /**
     * Negative control for [json]'s strictness.
     *
     * Without it the green result above is unfalsifiable: a decoder that ignored
     * unknown keys would pass every assertion in this file while silently
     * accepting exactly the drift the gate is for. The key is injected at the
     * top level (reaching [Scenario]) and again inside the phase list (reaching
     * `Phase`), because a nested descriptor is where a Swift-side field addition
     * would most plausibly land — `ignoreUnknownKeys` is one setting on the
     * `Json` instance and applies at every depth, so the second case is
     * corroboration rather than a distinct mechanism.
     */
    @Test
    fun strictDecodingRejectsAKeyKotlinDoesNotKnow() {
        val fixture = ParityGolden.all.first()

        assertRejectsInjectedKey(
            "top level",
            fixture.scenarioJson.replaceFirst("{", """{"$INJECTED_KEY":1,"""),
            fixture.scenarioJson,
        )
        assertRejectsInjectedKey(
            "inside a phase",
            fixture.scenarioJson.replaceFirst(""""phases":[{""", """"phases":[{"$INJECTED_KEY":1,"""),
            fixture.scenarioJson,
        )
    }

    /**
     * Asserts [mutated] is rejected **because of the injected key**.
     *
     * The exception type alone does not state that: `SerializationException` is
     * also what a malformed document raises, so a control whose injection
     * happened to break the JSON would redden for the wrong reason and read as
     * verified. Matching the key name in the message separates "the strict
     * decoder rejected an unknown field" from "the string stopped being JSON",
     * and the pre-check separates both from an injection that silently did
     * nothing.
     */
    private fun assertRejectsInjectedKey(where: String, mutated: String, original: String) {
        assertTrue(
            mutated != original,
            "the $where control did not mutate the source — it would pass vacuously",
        )
        val failure = assertFailsWith<SerializationException>(
            "an unknown key $where was accepted",
        ) {
            decode(mutated)
        }
        assertTrue(
            failure.message?.contains(INJECTED_KEY) == true,
            "the $where control failed for the wrong reason — the message does not name " +
                "$INJECTED_KEY, so this is a parse failure rather than strict-mode rejection: " +
                "${failure.message}",
        )
    }

    private companion object {
        /**
         * Deliberately not a near-miss of any real field: a name that collided
         * with one would be *accepted*, and the control would report the
         * decoder as lenient when it is strict.
         */
        const val INJECTED_KEY = "__notAKnownKey__"
    }
}
