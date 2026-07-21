package com.pastura.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * Stage 3 (tag-form adapter) tests for [Canonicalizer] — Issue #220 W2 PR-B
 * Stage 3.
 *
 * Verifies single-direction normalization of Kotlin polymorphic
 * discriminator shape (`{"type":"<name>",<payload>}`) into Swift's
 * auto-synthesized `Codable` outer-wrap shape
 * (`{"<caseName>":{<payload>}}`). The Swift form is canonical because the
 * existing on-disk `payloadJSON` SQLite rows (per `models-and-data.md`
 * § Data layer) are written by Swift's `JSONEncoder` and therefore use
 * the outer-wrap form already.
 *
 * Stage 3 is opt-in: an empty discriminator set means the canonicalizer
 * runs Stages 1+2 only and the tree's `"type"` keys are left intact
 * (necessary for non-polymorphic types like `Phase`, whose `type` field
 * carries a `PhaseType` value like `"choose"` — a field value, not a
 * discriminator).
 */
class CanonicalizerStage3Tests {

    private val codePhaseDiscriminators: Set<String> = setOf(
        "elimination",
        "scoreUpdate",
        "summary",
        "narration",
        "voteResults",
        "pairingResult",
        "assignment",
        "sharedAssignment",
        "eventInjected",
    )

    // -------- opt-in semantics --------

    @Test
    fun emptyDiscriminatorSetSkipsStage3() {
        val input = buildJsonObject {
            put("type", JsonPrimitive("elimination"))
            put("agent", JsonPrimitive("ada"))
            put("voteCount", JsonPrimitive(3))
        }
        val output = Canonicalizer.canonicalize(input) as JsonObject
        // Stage 1 still runs (keys sorted) but the type key is preserved.
        assertEquals(listOf("agent", "type", "voteCount"), output.keys.toList())
        assertEquals(JsonPrimitive("elimination"), output["type"])
    }

    @Test
    fun nonDiscriminatorTypeFieldIsLeftAlone() {
        // `Phase` JSON has a `type` field carrying a PhaseType value like
        // "choose" — a field value, not a discriminator. It must NOT be
        // lifted into outer-wrap form even when Stage 3 is on for some
        // other (CodePhaseEventPayload) namespace. "choose" is absent from
        // codePhaseDiscriminators, which is exactly what keeps it safe.
        val input = buildJsonObject {
            put("type", JsonPrimitive("choose"))
            put("subRounds", JsonPrimitive(1))
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonObject
        // "choose" is not a CodePhaseEventPayload discriminator → no lift.
        assertEquals(setOf("subRounds", "type"), output.keys.toSet())
        assertEquals(JsonPrimitive("choose"), output["type"])
    }

    @Test
    fun discriminatorKeyMustBeJsonPrimitiveString() {
        // If `type` is an integer or object, treat as a regular field.
        val input = buildJsonObject {
            put("type", JsonPrimitive(42))
            put("agent", JsonPrimitive("ada"))
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonObject
        assertEquals(setOf("agent", "type"), output.keys.toSet())
        assertEquals(JsonPrimitive(42), output["type"])
    }

    // -------- single-case lift --------

    @Test
    fun eliminationLiftedToSwiftOuterWrap() {
        val input = buildJsonObject {
            put("type", JsonPrimitive("elimination"))
            put("agent", JsonPrimitive("ada"))
            put("voteCount", JsonPrimitive(3))
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonObject
        assertEquals(setOf("elimination"), output.keys)
        val payload = output["elimination"] as JsonObject
        assertEquals(JsonPrimitive("ada"), payload["agent"])
        assertEquals(JsonPrimitive(3), payload["voteCount"])
    }

    @Test
    fun liftedFormHasInnerKeysSortedByStage1() {
        val input = buildJsonObject {
            put("type", JsonPrimitive("pairingResult"))
            put("agent2", JsonPrimitive("bob"))
            put("action2", JsonPrimitive("cooperate"))
            put("agent1", JsonPrimitive("alice"))
            put("action1", JsonPrimitive("defect"))
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonObject
        val payload = output["pairingResult"] as JsonObject
        assertEquals(
            listOf("action1", "action2", "agent1", "agent2"),
            payload.keys.toList(),
        )
    }

    @Test
    fun eventInjectedWithExplicitNullPayloadPreservesEventKey() {
        // EventInjected's `event` is nullable in Swift; the miss case is
        // persisted as {"event":null}. Stage 1's null-omit at the inner
        // object would drop `event` — but Stage 3 runs BEFORE Stage 1,
        // and the inner-object pass also applies Stage 1, so `event: null`
        // becomes absent. This pins that behavior: the canonical form is
        // {"eventInjected":{}} for a null miss.
        val input = buildJsonObject {
            put("type", JsonPrimitive("eventInjected"))
            put("event", kotlinx.serialization.json.JsonNull)
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonObject
        assertEquals(setOf("eventInjected"), output.keys)
        val payload = output["eventInjected"] as JsonObject
        assertEquals(0, payload.size)
    }

    @Test
    fun eventInjectedWithPresentEventLifts() {
        val input = buildJsonObject {
            put("type", JsonPrimitive("eventInjected"))
            put("event", JsonPrimitive("twist"))
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonObject
        val payload = output["eventInjected"] as JsonObject
        assertEquals(JsonPrimitive("twist"), payload["event"])
    }

    // -------- nested + array --------

    @Test
    fun arrayOfPolymorphicObjectsAllLifted() {
        val input = buildJsonArray {
            add(buildJsonObject {
                put("type", JsonPrimitive("elimination"))
                put("agent", JsonPrimitive("ada"))
                put("voteCount", JsonPrimitive(1))
            })
            add(buildJsonObject {
                put("type", JsonPrimitive("assignment"))
                put("agent", JsonPrimitive("bob"))
                put("value", JsonPrimitive("wolf"))
            })
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonArray
        assertEquals(2, output.size)
        val first = output[0] as JsonObject
        val second = output[1] as JsonObject
        assertEquals(setOf("elimination"), first.keys)
        assertEquals(setOf("assignment"), second.keys)
    }

    @Test
    fun liftedFormSortsKeysInPayloadObjects() {
        // After Stage 3 lifts the outer discriminator, Stage 1 still walks
        // the payload — every JsonObject within the payload (here the two
        // Map<String, *> fields `votes` / `tallies`) gets its keys sorted.
        // Pastura's CodePhaseEventPayload payloads never carry a nested
        // discriminator-bearing object themselves, so true polymorphic
        // recursion is not exercised in production fixtures; the
        // canonicalizer's recursive `normalizeTagForm` would handle it
        // correctly if such a shape arose (see Stage 3 implementation
        // recursing into JsonObject children).
        val input = buildJsonObject {
            put("type", JsonPrimitive("voteResults"))
            put("votes", buildJsonObject { put("alice", JsonPrimitive("bob")) })
            put("tallies", buildJsonObject { put("bob", JsonPrimitive(1)) })
        }
        val output = Canonicalizer.canonicalize(input, codePhaseDiscriminators) as JsonObject
        assertEquals(setOf("voteResults"), output.keys)
        val payload = output["voteResults"] as JsonObject
        assertEquals(listOf("tallies", "votes"), payload.keys.toList())
    }

    // -------- end-to-end with kotlinx polymorphic emission --------

    @Test
    fun realKotlinxPolymorphicEmissionLifts() {
        // Encode the actual Kotlin CodePhaseEventPayload (PR-A) and verify
        // Canonicalizer lifts the kotlinx output into Swift outer-wrap.
        val payload: CodePhaseEventPayload = CodePhaseEventPayload.Elimination(
            agent = "ada",
            voteCount = 2,
        )
        val encoded = Json.encodeToString<CodePhaseEventPayload>(payload)
        val tree = Json.parseToJsonElement(encoded)

        val canonical = Canonicalizer.canonicalize(tree, codePhaseDiscriminators) as JsonObject
        assertEquals(setOf("elimination"), canonical.keys)
        val inner = canonical["elimination"] as JsonObject
        assertEquals(JsonPrimitive("ada"), inner["agent"])
        assertEquals(JsonPrimitive(2), inner["voteCount"])

        // Final JSON-text form — what the harness will byte-match against
        // Swift baseline output.
        val canonicalText = Json.encodeToString(JsonObject.serializer(), canonical)
        assertEquals("""{"elimination":{"agent":"ada","voteCount":2}}""", canonicalText)
    }

    @Test
    fun realKotlinxEventInjectedMissCaseLifts() {
        // Day-1 sanity per W2 PR-B Q6: confirm Kotlin emits the
        // miss case with an inner null, then Canonicalizer's Stage 1
        // drops the null, leaving {"eventInjected":{}}.
        val payload: CodePhaseEventPayload = CodePhaseEventPayload.EventInjected(event = null)
        val encoded = Json.encodeToString<CodePhaseEventPayload>(payload)
        val tree = Json.parseToJsonElement(encoded)

        // First sanity-check the kotlinx native output — it should NOT
        // contain a polymorphic outer wrap, just the discriminator + payload.
        // (We don't pin the exact text shape because kotlinx's emission of
        // `null` defaults may evolve; we pin the canonical output below.)
        val rawObj = tree as JsonObject
        assertEquals(JsonPrimitive("eventInjected"), rawObj["type"])

        val canonical = Canonicalizer.canonicalize(tree, codePhaseDiscriminators) as JsonObject
        val canonicalText = Json.encodeToString(JsonObject.serializer(), canonical)
        assertEquals("""{"eventInjected":{}}""", canonicalText)
    }

    // -------- enum raw-value validation --------

    @Test
    fun phaseTypeEnumProducesSnakeCaseRawValue() {
        // Pinned by PR-A's PhaseTypeTests; re-asserted here as the
        // canonical equivalence harness depends on Kotlin enums producing
        // the same raw-value strings Swift's `String`-raw-value enums
        // already emit.
        val encoded = Json.encodeToString(PhaseType.serializer(), PhaseType.SPEAK_ALL)
        assertEquals("\"speak_all\"", encoded)
    }

    @Test
    fun galleryCategoryEnumProducesSnakeCaseRawValue() {
        val encoded = Json.encodeToString(
            GalleryCategory.serializer(),
            GalleryCategory.SOCIAL_PSYCHOLOGY,
        )
        assertEquals("\"social_psychology\"", encoded)
    }

    @Test
    fun codePhaseDiscriminatorSetMatchesAllSealedCases() {
        // Drift guard: adding a new CodePhaseEventPayload case without updating
        // the harness discriminator set fires this test. The set is the
        // canonical source of truth — caller-side opt-in via the canonicalizer's
        // `polymorphicDiscriminatorValues` param.
        val expected = setOf(
            "elimination",
            "scoreUpdate",
            "summary",
            "narration",
            "voteResults",
            "pairingResult",
            "assignment",
            "sharedAssignment",
            "eventInjected",
        )
        assertEquals(expected, codePhaseDiscriminators)
        // One sample per sealed case. [assertCovered] is an exhaustive `when`
        // (no `else`), so a newly-added subclass fails to compile until handled
        // there — the substitute for the `sealedSubclasses` reflection
        // commonMain lacks. The sample discriminators (read from real encoded
        // JSON, so a swapped @SerialName reddens) must EQUAL the discriminator
        // set, which closes the silent-omission hole a bare hand-list left open.
        val samples: List<CodePhaseEventPayload> = listOf(
            CodePhaseEventPayload.Elimination("a", 1),
            CodePhaseEventPayload.ScoreUpdate(mapOf("a" to 1)),
            CodePhaseEventPayload.Summary("text"),
            CodePhaseEventPayload.Narration("live"),
            CodePhaseEventPayload.VoteResults(mapOf("a" to "b"), mapOf("b" to 1)),
            CodePhaseEventPayload.PairingResult("a", "x", "b", "y"),
            CodePhaseEventPayload.Assignment("a", "v"),
            CodePhaseEventPayload.SharedAssignment("topic"),
            CodePhaseEventPayload.EventInjected("ev"),
        )
        samples.forEach(::assertCovered)
        val sampleDiscriminators = samples.map { s ->
            val tree = Json.parseToJsonElement(Json.encodeToString<CodePhaseEventPayload>(s)) as JsonObject
            (tree["type"] as JsonPrimitive).content
        }.toSet()
        assertEquals(codePhaseDiscriminators, sampleDiscriminators)
    }

    private fun assertCovered(payload: CodePhaseEventPayload) {
        when (payload) {
            is CodePhaseEventPayload.Elimination -> Unit
            is CodePhaseEventPayload.ScoreUpdate -> Unit
            is CodePhaseEventPayload.Summary -> Unit
            is CodePhaseEventPayload.Narration -> Unit
            is CodePhaseEventPayload.VoteResults -> Unit
            is CodePhaseEventPayload.PairingResult -> Unit
            is CodePhaseEventPayload.Assignment -> Unit
            is CodePhaseEventPayload.SharedAssignment -> Unit
            is CodePhaseEventPayload.EventInjected -> Unit
        }
    }

    @Test
    fun codePhaseDiscriminatorsDoNotCollideWithPhaseTypeWire() {
        // Discharges the Canonicalizer.kt PR0-b re-check note: if a
        // CodePhaseEventPayload discriminator equaled a PhaseType wire value, the
        // Stage-3 lift (which fires on discriminator-value membership) would
        // mis-lift an embedded Phase's `type` field. PR0-b adds `narration` /
        // `sharedAssignment`; assert the intersection stays empty, deriving the
        // PhaseType wire set from the serializer rather than hardcoding it.
        // Derive the PhaseType wire set by encoding each entry (stable API) —
        // avoids the @ExperimentalSerializationApi descriptor-introspection path.
        val phaseTypeWire = PhaseType.entries
            .map { Json.encodeToString(PhaseType.serializer(), it).removeSurrounding("\"") }
            .toSet()
        assertEquals(
            emptySet(),
            codePhaseDiscriminators intersect phaseTypeWire,
            "CodePhaseEventPayload discriminators must not collide with PhaseType wire values",
        )
    }
}
