package com.pastura.engine

import com.pastura.models.SimulationEvent
import kotlin.math.floor
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The Kotlin mirror of the harness's `EventLineMapper`
 * (`tools/harness/Sources/PasturaHarnessKit/EventLineMapper.swift`).
 *
 * ADR-023 Stage 4 compares the two engines through this projection rather than
 * through a `SimulationEvent` encoding — see #501's 2026-08-06 comment for why
 * (`SimulationEvent` is `Equatable`, not `Codable`, and ADR-023 §12 rejected
 * adding the conformance for a callback-boundary type).
 *
 * ## Why this lives in `commonTest`, not `commonMain`
 *
 * The Swift original is a **tool**, under `tools/harness/`, not app Engine
 * code — ADR-023 §4 scopes the port at `Pastura/Pastura/Engine/`. Putting the
 * mirror in `commonMain` would export it on the `PasturaSharedEngine`
 * XCFramework surface with no consumer on either side.
 *
 * ## The `when` is exhaustive with no `else`, deliberately
 *
 * The compile-time canary the Swift original also carries: a `SimulationEvent`
 * addition reaching only one engine's transcript is exactly the drift the
 * parity suite exists to catch, and a case falling into an `else` would present
 * as "no divergence".
 *
 * ## What has to match, and what does not
 *
 * `TranscriptComparator` parses each line and flattens it to dotted paths, so
 * **key order is irrelevant to the comparison** — it is fixed here for
 * `LedgerEntry.Structural`, which pins a whole line as text, and for readable
 * diffs. What *is* load-bearing is the **key names** and the **rendered scalar
 * content**, because `TranscriptComparator.render` reads `JsonPrimitive.content`
 * verbatim. The Swift side's exact bytes are pinned by
 * `RunLogTests.fullyPopulatedLinePinsTheWireShape`; this file is written
 * against that measurement, not against the fixtures' observed lines.
 */
internal object EventLineMapper {

    /**
     * Projects [event] to one JSON line, or `null` for the two kinds that carry
     * no transcript surface.
     *
     * [t] and [attempt] exist to mirror the Swift signature; the parity fixtures
     * pin both to 0, which is why every golden line reads `"t":0,"attempt":0`.
     */
    internal fun map(event: SimulationEvent, t: Double = 0.0, attempt: Int = 0): String? {
        val payload: Map<String, JsonElement> = when (event) {
            // Redundant with the final `AgentOutput` and orders of magnitude
            // larger; the Swift original skips it for the same reason. Both
            // engines emit it, with payloads that differ by construction —
            // Swift runs a partial-output extractor over each chunk, Kotlin
            // forwards raw text — so it could not be compared even if kept.
            is SimulationEvent.AgentOutputStream -> return null
            // Internal resume-persistence snapshot (a whole SimulationState),
            // not part of the transcript surface.
            is SimulationEvent.RoundCheckpoint -> return null

            is SimulationEvent.RoundStarted -> fields(
                "event" to JsonPrimitive("round_started"),
                "round" to JsonPrimitive(event.round),
                "total_rounds" to JsonPrimitive(event.totalRounds),
            )
            is SimulationEvent.RoundCompleted -> fields(
                "event" to JsonPrimitive("round_completed"),
                "round" to JsonPrimitive(event.round),
                "scores" to ints(event.scores),
            )
            is SimulationEvent.PhaseStarted -> fields(
                "event" to JsonPrimitive("phase_started"),
                "phase_type" to JsonPrimitive(event.phaseType.serialName()),
                "phase_path" to path(event.phasePath),
            )
            is SimulationEvent.PhaseCompleted -> fields(
                "event" to JsonPrimitive("phase_completed"),
                "phase_type" to JsonPrimitive(event.phaseType.serialName()),
                "phase_path" to path(event.phasePath),
            )
            // No `raw_text` arm: Kotlin's `TurnOutput` carries no `rawText`, an
            // omission its own class KDoc records as deliberate. The Swift
            // emitter strips its own in `ParityFixtureEmitter.normalize` so the
            // two sides compare like for like — see that function for what the
            // stripping costs.
            is SimulationEvent.AgentOutput -> fields(
                "event" to JsonPrimitive("agent_output"),
                "agent" to JsonPrimitive(event.agent),
                "phase_type" to JsonPrimitive(event.phaseType.serialName()),
                "fields" to strings(event.output.fields),
            )
            is SimulationEvent.ScoreUpdate -> fields(
                "event" to JsonPrimitive("score_update"),
                "scores" to ints(event.scores),
            )
            is SimulationEvent.Elimination -> fields(
                "event" to JsonPrimitive("elimination"),
                "agent" to JsonPrimitive(event.agent),
                "vote_count" to JsonPrimitive(event.voteCount),
            )
            is SimulationEvent.Assignment -> fields(
                "event" to JsonPrimitive("assignment"),
                "agent" to JsonPrimitive(event.agent),
                "value" to JsonPrimitive(event.value),
            )
            is SimulationEvent.SharedAssignment -> fields(
                "event" to JsonPrimitive("shared_assignment"),
                "value" to JsonPrimitive(event.value),
            )
            is SimulationEvent.Summary -> fields(
                "event" to JsonPrimitive("summary"),
                "value" to JsonPrimitive(event.text),
            )
            is SimulationEvent.Narration -> fields(
                "event" to JsonPrimitive("narration"),
                "value" to JsonPrimitive(event.text),
            )
            is SimulationEvent.RelationshipUpdate -> fields(
                "event" to JsonPrimitive("relationship_update"),
                "relationships" to nested(event.relationships),
            )
            is SimulationEvent.VoteResults -> fields(
                "event" to JsonPrimitive("vote_results"),
                "votes" to strings(event.votes),
                "tallies" to ints(event.tallies),
            )
            is SimulationEvent.PairingResult -> fields(
                "event" to JsonPrimitive("pairing_result"),
                "agent" to JsonPrimitive(event.agent1),
                "agent2" to JsonPrimitive(event.agent2),
                "action1" to JsonPrimitive(event.action1),
                "action2" to JsonPrimitive(event.action2),
            )
            is SimulationEvent.ConditionalEvaluated -> fields(
                "event" to JsonPrimitive("conditional_evaluated"),
                "condition" to JsonPrimitive(event.condition),
                "result" to JsonPrimitive(event.result),
            )
            // Optional on both sides (`case eventInjected(event: String?)`), so
            // a Kotlin null omits the key exactly as Swift's `nil` does. No
            // fixture runs an `event_inject` phase, so this arm is unexercised
            // end to end.
            is SimulationEvent.EventInjected -> fields(
                "event" to JsonPrimitive("event_injected"),
                "value" to event.event?.let { JsonPrimitive(it) },
            )
            is SimulationEvent.SimulationCompleted -> fields(
                "event" to JsonPrimitive("simulation_completed"),
            )
            is SimulationEvent.SimulationPaused -> fields(
                "event" to JsonPrimitive("simulation_paused"),
                "round" to JsonPrimitive(event.round),
                "phase_path" to path(event.phasePath),
            )
            // ⚠️ KNOWN TO DISAGREE WITH SWIFT, AND UNEXERCISED — but DETERMINISTIC,
            // which `toString()` was not: `SimulationError`'s singletons are
            // plain `object`s, so `toString()` falls through to `Any.toString()`
            // and yields `…SimulationError$Cancelled@7ceb3185`, whose identity
            // hash changes every run. No fixture reaches an error path today, so
            // nothing was red; the first one that does would have made the
            // golden drift against itself.
            //
            // `simpleName` still will not match Swift, which projects via
            // `String(describing: error)` and yields the lowercase case
            // (`cancelled` vs `Cancelled`); and a payload-carrying case loses
            // its payload here where Swift keeps it. Whoever first drives an
            // error path — S4's cancellation tail is the likely trigger — must
            // close that with a ledger entry or a shared spelling.
            is SimulationEvent.ErrorEvent -> fields(
                "event" to JsonPrimitive("error"),
                "error" to JsonPrimitive(event.error::class.simpleName ?: "unknown"),
            )
            is SimulationEvent.InferenceStarted -> fields(
                "event" to JsonPrimitive("inference_started"),
                "agent" to JsonPrimitive(event.agent),
            )
            is SimulationEvent.InferenceCompleted -> fields(
                "event" to JsonPrimitive("inference_completed"),
                "agent" to JsonPrimitive(event.agent),
                "duration_seconds" to number(event.durationSeconds),
                "token_count" to event.tokenCount?.let { JsonPrimitive(it) },
            )
            is SimulationEvent.LanguageMismatch -> fields(
                "event" to JsonPrimitive("language_mismatch"),
                "agent" to JsonPrimitive(event.agent),
                "detected" to event.detected?.let { JsonPrimitive(it) },
                "expected" to JsonPrimitive(event.expected),
            )
            is SimulationEvent.TurnSkipped -> fields(
                "event" to JsonPrimitive("turn_skipped"),
                "agent" to JsonPrimitive(event.agent),
                "phase_type" to JsonPrimitive(event.phaseType.serialName()),
                "value" to JsonPrimitive(event.cause),
            )
            is SimulationEvent.ActionRejected -> fields(
                "event" to JsonPrimitive("action_rejected"),
                "agent" to JsonPrimitive(event.agent),
                "phase_type" to JsonPrimitive(event.phaseType.serialName()),
                "value" to JsonPrimitive(event.raw),
            )
        }

        return sorted(
            payload + fields(
                "type" to JsonPrimitive("event"),
                "t" to number(t),
                "attempt" to JsonPrimitive(attempt),
            ),
        ).toString()
    }

    /** Drops null-valued pairs, mirroring Swift `Codable`'s `nil` omission. */
    private fun fields(vararg pairs: Pair<String, JsonElement?>): Map<String, JsonElement> =
        pairs.mapNotNull { (key, value) -> value?.let { key to it } }.toMap()

    /**
     * Sorts keys at every depth, matching `JSONEncoder`'s `.sortedKeys`.
     *
     * `entries.sortedBy{}.associate{}` rather than `toSortedMap`, which is
     * JVM-only and would compile on every per-target build while failing
     * `compileCommonMainKotlinMetadata` (`.claude/rules/kmp-interop.md`
     * Pattern 4). `associate` returns a `LinkedHashMap`, so insertion order —
     * and therefore the sort — survives into [JsonObject.toString].
     *
     * The two sides' collation can in principle disagree on non-ASCII keys
     * (Kotlin compares UTF-16 code units), a cousin of the ledgered
     * `SCOREBOARD_ORDERING` class. That would not affect the *path-based* field
     * comparison, but it would change a
     * [DivergenceLedger.LedgerEntry.Structural] entry's pinned bytes. It does
     * not arise in the current fixtures: every agent name is BMP (katakana or
     * ASCII), where the two orderings coincide.
     */
    private fun sorted(map: Map<String, JsonElement>): JsonObject =
        JsonObject(map.entries.sortedBy { it.key }.associate { it.key to it.value })

    /**
     * Renders a `Double` the way `JSONEncoder` does: an integral value drops
     * its `.0`, a fractional one keeps its decimals.
     *
     * Load-bearing, not cosmetic. `TranscriptComparator.render` compares
     * `JsonPrimitive.content` as text, so a bare `JsonPrimitive(0.0)` would
     * read `"0.0"` against Swift's `"0"` and put an uncovered diff on **every**
     * line — `t` is non-optional on all of them.
     *
     * Unrelated to the ADR-023 divergence-6 ruling, which is about
     * `JSONResponseParser` normalizing parsed model values inside `fields`.
     * That one is engine behaviour and is pinned as a ledger entry; this one is
     * the transcript encoder. Do not resolve either by pointing at the other.
     *
     * `toLong` is safe over this domain — `t` and `durationSeconds` are second
     * counts — and is not claimed beyond it. The fractional branch is
     * **unreachable on the fixture path** (the emitter passes `t: 0` and
     * normalizes `durationSeconds` to `0`) and measured only at
     * exactly-representable values (`1.5`, `2.25`): a future non-zero `t` would
     * expose Swift's `1e-05` against Kotlin's `1.0E-5`, so do not read the green
     * suite as evidence that branch agrees.
     */
    private fun number(value: Double): JsonPrimitive =
        if (value.isFinite() && floor(value) == value) {
            JsonPrimitive(value.toLong())
        } else {
            JsonPrimitive(value)
        }

    private fun path(values: List<Int>): JsonArray =
        JsonArray(values.map { JsonPrimitive(it) })

    private fun strings(map: Map<String, String>): JsonObject =
        sorted(map.mapValues { JsonPrimitive(it.value) })

    private fun ints(map: Map<String, Int>): JsonObject =
        sorted(map.mapValues { JsonPrimitive(it.value) })

    private fun nested(map: Map<String, Map<String, Int>>): JsonObject =
        sorted(map.mapValues { ints(it.value) })
}
