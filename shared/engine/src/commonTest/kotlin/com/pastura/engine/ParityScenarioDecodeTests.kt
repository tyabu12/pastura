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

    /**
     * The roster is generated (`parity-emit --write`), so an empty one is a
     * plausible failure — and every loop in this file would then pass while
     * measuring nothing. Stated here rather than inherited, since this file is
     * the slice's declared first gate.
     */
    @Test
    fun theGoldenRosterIsNotEmpty() {
        assertTrue(
            ParityGolden.all.isNotEmpty(),
            "the golden roster is empty — every fixture loop in this file would pass vacuously",
        )
    }

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
                scenario.personas.size,
                scenario.agentCount,
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
     * accepting exactly the drift the gate is for. Injected at the top level
     * (reaching [Scenario]) and inside the phase list (reaching `Phase`), where
     * a Swift-side field addition would most plausibly land —
     * `ignoreUnknownKeys` is one setting applying at every depth, so the second
     * case is corroboration rather than a distinct mechanism.
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
     * also what a malformed document raises. So the message must both name the
     * key and read as a strict-mode rejection, and the pre-check separates both
     * from an injection that silently did nothing.
     *
     * **The phrase conjunct is defensive, not demonstrated.** kotlinx's message
     * shape varies by error class, and some variants quote the offending input
     * — which would carry the key and let a key-only check pass a *parse*
     * failure. The one broken-document case probed here (a structural break
     * before the key) does not: it raises `Unexpected JSON token at offset 1 …
     * at path: $` with no input dump, so the key conjunct alone would already
     * have reddened it. A break *after* the key is unreachable — strict mode
     * rejects the key before the parser gets there.
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
        val message = failure.message.orEmpty()
        assertTrue(
            message.contains(INJECTED_KEY) && message.contains(UNKNOWN_KEY_PHRASE),
            "the $where control failed for the wrong reason — the message must name " +
                "$INJECTED_KEY AND read as a strict-mode rejection (\"$UNKNOWN_KEY_PHRASE\"); " +
                "a broken document would satisfy the first alone: $message",
        )
    }

    private companion object {
        /**
         * Deliberately not a near-miss of any real field: a name that collided
         * with one would be *accepted*, and the control would report the
         * decoder as lenient when it is strict.
         */
        const val INJECTED_KEY = "__notAKnownKey__"

        /**
         * kotlinx's strict-mode wording, matched alongside [INJECTED_KEY] —
         * see [assertRejectsInjectedKey] for how far that conjunct is
         * demonstrated.
         */
        const val UNKNOWN_KEY_PHRASE = "Encountered an unknown key"
    }
}
