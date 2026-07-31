package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationError
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import kotlinx.coroutines.test.runTest
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `ConditionalIntegrationTests`, collapsed into one class
 * per the commonTest convention.
 *
 * `conditional` is the only handler that nests, so it is the sole consumer of three
 * [PhaseContext] mechanisms and the sole enforcement point of the branch policy on
 * this side (Kotlin has no `ScenarioValidator`). The cases below pin, in ADR-023
 * §12 terms, the mechanisms a green-but-wrong port would silently lose.
 *
 * ## §12 condition-4 perturbation record
 *
 * Each mechanism was broken in isolation and the named **dedicated claimant**
 * confirmed to redden. Every mutation's anchor was asserted to match **exactly
 * once** before applying — a `replace` that silently no-ops leaves the original
 * behaviour and reads as verified. The unmutated baseline was re-confirmed at 0 red
 * in the same run, so every count below is signal rather than pre-existing noise.
 * Counts are measured, not derived — re-measure rather than reason if you change a
 * fixture. Measured 2026-07-31, #1342.
 *
 * | Mechanism broken | Mutation | Dedicated claimant | Incidental |
 * |---|---|---|---|
 * | Verdict drives the branch | `if (evaluation.value)` → `if (true)` | [takesTheElseBranchWhenTheConditionFails] | 1 — [anAbsentBranchIsASilentNoOp] then runs a branch |
 * | …other polarity | same → `if (false)` | [takesTheThenBranchWhenTheConditionHolds] | 12 — nearly every fixture puts its sub-phases in `then` |
 * | Warning forwarding | warnings loop deleted | [forwardsEvaluatorWarningsAsWarningPrefixedSummaries] | 1 — [emitsWarningsBeforeTheVerdict] finds no warning |
 * | The `⚠️ ` prefix | `"⚠️ $warning"` → `"$warning"` | [forwardsEvaluatorWarningsAsWarningPrefixedSummaries] | 1 — same |
 * | Warnings precede the verdict | the two emits swapped | [emitsWarningsBeforeTheVerdict] | none |
 * | Verdict emit | `ConditionalEvaluated` emit deleted | [emitsConditionalEvaluatedCarryingTheExpressionAndVerdict] | 2 — one counts events, one needs the index |
 * | Absent branch is a no-op | `else …elsePhases.orEmpty()` falls back to `thenPhases` | [anAbsentBranchIsASilentNoOp] | none |
 * | `phasePath` nesting | `context.phasePath + innerIndex` → `listOf(innerIndex)` | [nestsSubPhasePathsUnderTheOuterPath] | 5 — every other path assertion |
 * | State into the next sub-phase | `execute(subContext, current)` → `…, state)` | [threadsStateThroughSuccessiveSubPhasesAndReturnsTheAccumulation] | none |
 * | State out of `runBranch` | `return current` → `return state` | same | none |
 * | Pairing on throw | the catch arm's emit deleted | [pairsPhaseCompletedWhenASubHandlerThrows] | 1 — [pairsPhaseCompletedForANonSimulationExceptionThrowToo], same arm |
 * | Catch **breadth** | `Throwable` → `SimulationException` | [pairsPhaseCompletedForANonSimulationExceptionThrowToo] | none |
 * | Parent `turnGate` threading | `context.turnGate` → `TurnFailureGate()` | [sharesTheParentTurnGateAcrossSubPhases] | 1 — [pairsPhaseCompletedWhenASubHandlerThrows] needs the breaker to throw |
 * | Loop-head `pauseCheck` call | call deleted | [callsPauseCheckOncePerSubPhaseWithTheNestedPath], [cancellationFromPauseCheckStopsBeforeTheNextSubPhaseStarts] | none |
 * | `detector` threading | field dropped from the sub-context | [threadsTheDetectorIntoSubPhaseContexts] | none |
 * | `logger` threading | field dropped | [threadsTheLoggerIntoSubPhaseContexts] | none |
 * | Allow-set completeness | `EVENT_INJECT` entry removed | [allowsExactlyTheNineBranchPermittedPhaseTypes] | 1 — [threadsStateThroughSuccessiveSubPhasesAndReturnsTheAccumulation] uses it |
 * | …other polarity | `NARRATE` entry **added** | [allowsExactlyTheNineBranchPermittedPhaseTypes], [rejectsEveryPhaseTypeDisallowedInsideABranch] | 1 — [aRejectedSubPhaseEmitsNoPhaseStarted] keys on NARRATE |
 * | Resolve-before-emit ordering | guard block moved after the `phaseStarted` emit | [aRejectedSubPhaseEmitsNoPhaseStarted] | none |
 * | Malformed condition rejected | `evaluate` wrapped in `runCatching` → false | [aMalformedConditionThrowsRatherThanEvaluatingFalse] | 1 — [anAbsentConditionThrowsJustLikeAnEmptyOne] |
 * | The `?: ""` null default | → `?: "1 == 1"` | [anAbsentConditionThrowsJustLikeAnEmptyOne] | none |
 * | Sub-context `pauseCheck` threading | `context.pauseCheck` → `{ }` | *(none — expected green)* | none |
 *
 * Six things this table encodes that are easy to get wrong:
 *
 * 1. **The last row is the point, not a gap.** No registered sub-handler consumes
 *    `pauseCheck`, so no mutation of that field can redden anything. It is declared
 *    expected-green rather than listed as covered — and it was re-measured against
 *    the final suite, not assumed from the earlier one.
 * 2. **Both gates are measured in both polarities.** Removing an allow-set entry
 *    only proves an allowed type can be dropped; **adding** a rejected one is what
 *    proves the branch policy is still enforced. Same for the branch selector.
 * 3. **The two pairing rows look redundant and are not.** Deleting the catch's emit
 *    reddens both pairing tests; *narrowing* the catch reddens only the
 *    non-`SimulationException` one, because a `SimulationException` still pairs
 *    under the narrow catch. That single-test red is the entire evidence for the
 *    catch-breadth decision.
 * 4. **Resolve-before-emit needs its own row.** Moving the guard after the emit
 *    leaves [rejectsEveryPhaseTypeDisallowedInsideABranch] green — the throw still
 *    happens — so the rejection axis cannot stand in for the ordering axis.
 * 5. **One row exists because a mutation came back green.** The first pass mutated
 *    the `?: ""` default while the only condition test passed a non-null `""`, so
 *    the elvis never fired and the mutation never reached a test. Read as a finding
 *    about the fixtures rather than as a redundant guard, it surfaced that the
 *    `null` path had no coverage at all; [anAbsentConditionThrowsJustLikeAnEmptyOne]
 *    was added for it, and only then did the row redden.
 * 6. **Rows 3 and 4 are not separable.** Both produce the same red set, so
 *    [forwardsEvaluatorWarningsAsWarningPrefixedSummaries] proves "a ⚠️-prefixed
 *    summary is emitted" and cannot tell a missing emit from a missing prefix. Both
 *    are real breakages and both are caught, but that is one claim, not two.
 *
 * **Coverage of the table itself**: 22 mutations, 21 reddening; all 20 tests are a
 * dedicated claimant for at least one row.
 *
 * **The counts this record leans on are machine-checked, not maintained in prose** —
 * the "9 of 14" allow-set and the enum's case count are asserted in
 * [allowsExactlyTheNineBranchPermittedPhaseTypes], and
 * `TurnFailureGate.consecutiveSkipLimit`, which the parent-gate row's arithmetic
 * depends on, is asserted in [sharesTheParentTurnGateAcrossSubPhases]. Change
 * either and a test fails before this table can go stale.
 *
 * Ported for the ADR-023 KMP Engine migration (#501, #1342).
 */
class ConditionalHandlerTests {

    private val handler = ConditionalHandler()

    /**
     * The conditional sits at index 2, so [PhaseContext.phasePath] is `[2]`.
     *
     * Non-trivial on purpose. With an outer `[0]` a port that rebuilt the nested
     * path as `listOf(innerIndex)` instead of `context.phasePath + innerIndex`
     * would emit exactly the same paths, and every path assertion below would pass
     * against the broken port.
     */
    private val outerPath = listOf(2)

    private fun scenario(
        condition: String? = "1 == 1",
        then: List<Phase>? = null,
        otherwise: List<Phase>? = null,
        agents: List<String> = listOf("Alice", "Bob"),
        extraData: Map<String, AnyCodableValue> = emptyMap(),
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = "en",
        simulationLanguage = null,
        agentCount = agents.size,
        rounds = 2,
        logWindow = null,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(type = PhaseType.SUMMARIZE, template = "outer-0"),
            Phase(type = PhaseType.SUMMARIZE, template = "outer-1"),
            Phase(
                type = PhaseType.CONDITIONAL,
                condition = condition,
                thenPhases = then,
                elsePhases = otherwise,
            ),
        ),
        extraData = extraData,
    )

    private fun context(
        s: Scenario,
        backend: LLMBackend = ScriptedLLMBackend(emptyList()),
        events: MutableList<SimulationEvent> = mutableListOf(),
        gate: TurnFailureGate = TurnFailureGate(),
        pauseCheck: suspend (List<Int>) -> Unit = { },
        detector: LanguageDetector? = null,
        logger: EngineLogger = NoopEngineLogger(),
    ) = PhaseContext(
        scenario = s,
        phase = s.phases[2],
        backend = backend,
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = pauseCheck,
        phasePath = outerPath,
        turnGate = gate,
        detector = detector,
        logger = logger,
    )

    private fun summarize(text: String) = Phase(type = PhaseType.SUMMARIZE, template = text)

    private fun speakAll() = Phase(
        type = PhaseType.SPEAK_ALL,
        prompt = "Speak.",
        outputSchema = mapOf("statement" to "string"),
    )

    private fun eventInject(variable: String, source: String) = Phase(
        type = PhaseType.EVENT_INJECT,
        source = source,
        eventVariable = variable,
        probability = 1.0,
    )

    private fun failingCall() =
        ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "boom"))

    private fun speaks(statement: String) =
        ScriptedLLMBackend.Script.completing("""{"statement": "$statement"}""")

    private fun started(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.PhaseStarted>()

    private fun completed(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.PhaseCompleted>()

    private fun summaries(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.Summary>()

    private class SpyLanguageDetector(private val canned: String?) : LanguageDetector {
        val recorded = mutableListOf<String>()
        override fun detect(text: String): String? {
            recorded.add(text)
            return canned
        }
    }

    private class SpyEngineLogger : EngineLogger {
        val messages = mutableListOf<String>()
        override fun log(
            level: EngineLogLevel,
            category: String,
            message: String,
            privacy: EngineLogPrivacy,
        ) {
            messages.add(message)
        }
    }

    // MARK: - Condition evaluation and branch selection

    @Test
    fun takesTheThenBranchWhenTheConditionHolds() = runTest {
        val s = scenario(
            condition = "1 == 1",
            then = listOf(summarize("THEN")),
            otherwise = listOf(summarize("ELSE")),
        )
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, events = events), SimulationState.initial(s))

        assertEquals(listOf("THEN"), summaries(events).map { it.text })
    }

    @Test
    fun takesTheElseBranchWhenTheConditionFails() = runTest {
        val s = scenario(
            condition = "1 == 2",
            then = listOf(summarize("THEN")),
            otherwise = listOf(summarize("ELSE")),
        )
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, events = events), SimulationState.initial(s))

        assertEquals(listOf("ELSE"), summaries(events).map { it.text })
    }

    @Test
    fun emitsConditionalEvaluatedCarryingTheExpressionAndVerdict() = runTest {
        val s = scenario(condition = "1 == 2", then = listOf(summarize("T")))
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, events = events), SimulationState.initial(s))

        val evaluated = events.filterIsInstance<SimulationEvent.ConditionalEvaluated>().single()
        assertEquals("1 == 2", evaluated.condition)
        assertEquals(false, evaluated.result)
    }

    @Test
    fun forwardsEvaluatorWarningsAsWarningPrefixedSummaries() = runTest {
        // `vote_winner` is runtime-absent before any vote runs, so the evaluator
        // returns false plus a warning. The ⚠️ prefix is asserted, not just the
        // presence of a Summary: it is a plain interpolation rather than a
        // `pickLanguage` literal, so the prompt-literal parity gate cannot see it.
        val s = scenario(condition = "vote_winner == \"Alice\"", then = listOf(summarize("T")))
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, events = events), SimulationState.initial(s))

        val texts = summaries(events).map { it.text }
        assertTrue(texts.any { it.startsWith("⚠️ ") }, "expected a ⚠️-prefixed summary, got $texts")
    }

    @Test
    fun emitsWarningsBeforeTheVerdict() = runTest {
        // Ordering is the contract: a consumer reading the stream must see WHY a
        // runtime-absent operand forced `false` before it sees the `false`.
        val s = scenario(condition = "vote_winner == \"Alice\"", then = listOf(summarize("T")))
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, events = events), SimulationState.initial(s))

        val warningIndex = events.indexOfFirst {
            it is SimulationEvent.Summary && it.text.startsWith("⚠️ ")
        }
        val verdictIndex = events.indexOfFirst { it is SimulationEvent.ConditionalEvaluated }
        assertTrue(warningIndex >= 0, "no warning emitted at all: $events")
        assertTrue(warningIndex < verdictIndex, "warning must precede the verdict: $events")
    }

    @Test
    fun aMalformedConditionThrowsRatherThanEvaluatingFalse() = runTest {
        // Reachable on this side, unlike Swift, where `ScenarioValidator` rejects the
        // expression at load and shadows this path entirely.
        val s = scenario(condition = "", then = listOf(summarize("T")))

        val error = assertFailsWith<SimulationException> {
            handler.execute(context(s), SimulationState.initial(s))
        }
        assertIs<SimulationError.ScenarioValidationFailed>(error.error)
    }

    @Test
    fun anAbsentConditionThrowsJustLikeAnEmptyOne() = runTest {
        // `Phase.condition` is nullable, and `?: ""` is what routes null into the
        // evaluator's rejection. The empty-string case above does NOT cover this:
        // "" is non-null, so the elvis never fires there. Found by perturbation —
        // mutating the default to a truthy expression left the whole suite green,
        // which was a finding about the fixtures rather than a redundant guard.
        val s = scenario(condition = null, then = listOf(summarize("T")))

        val error = assertFailsWith<SimulationException> {
            handler.execute(context(s), SimulationState.initial(s))
        }
        assertIs<SimulationError.ScenarioValidationFailed>(error.error)
    }

    // MARK: - Sub-phase dispatch, paths, and state

    @Test
    fun anAbsentBranchIsASilentNoOp() = runTest {
        val s = scenario(condition = "1 == 2", then = listOf(summarize("T"))) // no else
        val before = SimulationState.initial(s)
        val events = mutableListOf<SimulationEvent>()

        val after = handler.execute(context(s, events = events), before)

        assertEquals(before, after, "an absent branch must not touch state")
        assertTrue(started(events).isEmpty(), "no sub-phase started: $events")
        assertTrue(completed(events).isEmpty(), "no sub-phase completed: $events")
        assertEquals(1, events.size, "only the verdict should be emitted, got $events")
    }

    @Test
    fun nestsSubPhasePathsUnderTheOuterPath() = runTest {
        val s = scenario(then = listOf(summarize("a"), summarize("b")))
        val events = mutableListOf<SimulationEvent>()

        handler.execute(context(s, events = events), SimulationState.initial(s))

        assertEquals(listOf(listOf(2, 0), listOf(2, 1)), started(events).map { it.phasePath })
        assertEquals(listOf(listOf(2, 0), listOf(2, 1)), completed(events).map { it.phasePath })
    }

    @Test
    fun threadsStateThroughSuccessiveSubPhasesAndReturnsTheAccumulation() = runTest {
        // event_inject writes `variables["ev"]`; the summarize that follows expands
        // `{ev}` from the SAME map. Unknown placeholders are left literal, so a port
        // that handed each sub-phase the entry state would emit "saw {ev}".
        val s = scenario(
            then = listOf(eventInject("ev", "pool"), summarize("saw {ev}")),
            extraData = mapOf("pool" to AnyCodableValue.ArrayValue(listOf("STORM"))),
        )
        val events = mutableListOf<SimulationEvent>()

        val after = handler.execute(context(s, events = events), SimulationState.initial(s))

        assertEquals("saw STORM", summaries(events).map { it.text }.last())
        assertEquals("STORM", after.variables["ev"], "execute must return the accumulation")
    }

    // MARK: - Lifecycle pairing

    @Test
    fun pairsPhaseCompletedWhenASubHandlerThrows() = runTest {
        val s = scenario(then = listOf(speakAll(), speakAll()))
        val backend = ScriptedLLMBackend(List(6) { failingCall() })
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<SimulationException> {
            handler.execute(context(s, backend, events), SimulationState.initial(s))
        }

        assertEquals(listOf(listOf(2, 0), listOf(2, 1)), started(events).map { it.phasePath })
        assertEquals(
            listOf(listOf(2, 0), listOf(2, 1)),
            completed(events).map { it.phasePath },
            "the throwing sub-phase must still be paired by the catch arm",
        )
    }

    @Test
    fun pairsPhaseCompletedForANonSimulationExceptionThrowToo() = runTest {
        // Script exhaustion throws IllegalStateException. Used here NOT as failure
        // injection — `kmp-interop.md` Pattern 4 rightly bans that — but as the
        // cheapest arbitrary non-SimulationException Throwable, because the mechanism
        // under test is the catch's BREADTH. Narrow the catch to SimulationException
        // and this escapes between the phaseStarted emit and the pairing, leaving a
        // dangling phaseStarted([2, 0]) that Swift never produces.
        val s = scenario(then = listOf(speakAll()))
        val events = mutableListOf<SimulationEvent>()

        val thrown = assertFailsWith<IllegalStateException> {
            handler.execute(
                context(s, ScriptedLLMBackend(emptyList()), events),
                SimulationState.initial(s),
            )
        }

        // The type alone is too loose to carry the claim: on JVM
        // `kotlinx.coroutines.CancellationException` IS an `IllegalStateException`
        // subclass, so this would also pass on a cancellation that never reached the
        // catch at all. Read WHICH throwable fired, per kmp-interop.md Pattern 4.
        assertTrue(
            thrown.message?.contains("ScriptedLLMBackend exhausted") == true,
            "expected script exhaustion, got: ${thrown.message}",
        )
        assertEquals(listOf(listOf(2, 0)), started(events).map { it.phasePath })
        assertEquals(listOf(listOf(2, 0)), completed(events).map { it.phasePath })
    }

    @Test
    fun aRejectedSubPhaseEmitsNoPhaseStarted() = runTest {
        // The handler is resolved BEFORE phaseStarted is emitted. Move the resolve
        // after the emit and this reddens with a dangling phaseStarted([2, 1]),
        // while every rejection test below stays green — the throw still happens.
        val s = scenario(then = listOf(summarize("ok"), Phase(type = PhaseType.NARRATE)))
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<SimulationException> {
            handler.execute(context(s, events = events), SimulationState.initial(s))
        }

        assertEquals(listOf(listOf(2, 0)), started(events).map { it.phasePath })
        assertEquals(listOf(listOf(2, 0)), completed(events).map { it.phasePath })
    }

    // MARK: - Context threading into sub-phases

    @Test
    fun sharesTheParentTurnGateAcrossSubPhases() = runTest {
        // consecutiveSkipLimit is 3. Two skips land in sub-phase 0 (Alice, Bob) and
        // the third in sub-phase 1, which trips the breaker.
        //
        // Split across TWO sub-phases deliberately: all three inside one sub-phase
        // would trip even with a fresh per-sub-context gate, so the test would pass
        // by construction against exactly the bug it exists to catch.
        val s = scenario(then = listOf(speakAll(), speakAll()))
        val backend = ScriptedLLMBackend(List(6) { failingCall() })
        val events = mutableListOf<SimulationEvent>()

        val error = assertFailsWith<SimulationException> {
            handler.execute(context(s, backend, events), SimulationState.initial(s))
        }

        assertEquals(3, TurnFailureGate.consecutiveSkipLimit, "the arithmetic above assumes 3")
        assertIs<SimulationError.TurnFailureLimitReached>(error.error)
        assertEquals(
            2,
            events.filterIsInstance<SimulationEvent.TurnSkipped>().size,
            "the tripping failure emits no TurnSkipped",
        )
    }

    @Test
    fun callsPauseCheckOncePerSubPhaseWithTheNestedPath() = runTest {
        val seen = mutableListOf<List<Int>>()
        val s = scenario(then = listOf(summarize("a"), summarize("b")))

        handler.execute(context(s, pauseCheck = { seen += it }), SimulationState.initial(s))

        assertEquals(listOf(listOf(2, 0), listOf(2, 1)), seen)
    }

    @Test
    fun cancellationFromPauseCheckStopsBeforeTheNextSubPhaseStarts() = runTest {
        // This is the whole cancellation story on this side. The handler carries no
        // ensureActive() of its own: pauseCheck raising CancellationException IS the
        // documented contract, and this test is what holds the handler to using it.
        var calls = 0
        val s = scenario(then = listOf(summarize("a"), summarize("b")))
        val events = mutableListOf<SimulationEvent>()

        assertFailsWith<CancellationException> {
            handler.execute(
                context(
                    s,
                    events = events,
                    pauseCheck = {
                        calls += 1
                        if (calls == 2) throw CancellationException("cancelled while paused")
                    },
                ),
                SimulationState.initial(s),
            )
        }

        assertEquals(listOf(listOf(2, 0)), started(events).map { it.phasePath })
        assertEquals(listOf(listOf(2, 0)), completed(events).map { it.phasePath })
    }

    @Test
    fun threadsTheDetectorIntoSubPhaseContexts() = runTest {
        // `detector` is DEFAULTED on PhaseContext, so dropping it from the sub-context
        // compiles clean and leaves every other test green. The adherence check runs
        // only once the joined output clears LLMCaller's minimum detection length —
        // 12 scalars, quoted here as prose because that constant is `private` and
        // cannot be referenced (unlike MAX_RETRIES below, which is). Hence the
        // deliberately long statement.
        val spy = SpyLanguageDetector(canned = "en")
        val s = scenario(then = listOf(speakAll()), agents = listOf("Alice"))
        val backend = ScriptedLLMBackend(
            List(LLMCaller.MAX_RETRIES + 1) { speaks("A sufficiently long English sentence.") },
        )

        handler.execute(context(s, backend, detector = spy), SimulationState.initial(s))

        assertTrue(
            spy.recorded.isNotEmpty(),
            "the adherence check never ran — detector was not threaded into the sub-context",
        )
    }

    @Test
    fun threadsTheLoggerIntoSubPhaseContexts() = runTest {
        // Same defaulted-field hazard as the detector. A parse failure on the first
        // attempt guarantees LLMCaller logs, then the retry succeeds.
        val spy = SpyEngineLogger()
        val s = scenario(then = listOf(speakAll()), agents = listOf("Alice"))
        // Over-scripted by one. The flow consumes exactly two calls today, but an
        // exactly-fitting script list makes any future extra call redden on the
        // harness's exhaustion error BEFORE `spy.messages` is asserted, which would
        // misattribute the failure to the logger seam.
        val backend = ScriptedLLMBackend(
            listOf(
                ScriptedLLMBackend.Script.completing("not json at all"),
                speaks("Recovered on retry."),
                speaks("Spare, so the assertion below stays the detector."),
            ),
        )

        handler.execute(context(s, backend, logger = spy), SimulationState.initial(s))

        assertTrue(
            spy.messages.any { it.contains("JSON parse failed") },
            "logger was not threaded into the sub-context; recorded: ${spy.messages}",
        )
    }

    // MARK: - Depth-1 and the branch policy

    @Test
    fun rejectsEveryPhaseTypeDisallowedInsideABranch() = runTest {
        val disallowed = listOf(
            PhaseType.CONDITIONAL,
            PhaseType.REFLECT,
            PhaseType.WHISPER,
            PhaseType.RELATIONSHIP_UPDATE,
            PhaseType.NARRATE,
        )
        for (type in disallowed) {
            val s = scenario(then = listOf(Phase(type = type)))
            val error = assertFailsWith<SimulationException>("$type must be rejected") {
                handler.execute(context(s), SimulationState.initial(s))
            }
            val message = assertIs<SimulationError.ScenarioValidationFailed>(error.error).message
            assertTrue(message.contains("depth-1"), "expected the depth-1 message, got: $message")
        }
    }

    @Test
    fun allowsExactlyTheNineBranchPermittedPhaseTypes() = runTest {
        // Derived by probing every PhaseType, not hand-listed: a hand list cannot
        // disagree with itself, so dropping an entry from `subHandlers` would just
        // move that type into the expected-rejected set and stay green.
        //
        // Classification is on the depth-1 message alone — an allowed handler may
        // still throw for its own reasons under this bare fixture, and that is not a
        // rejection.
        val allowed = mutableSetOf<PhaseType>()
        for (type in PhaseType.entries) {
            val s = scenario(
                then = listOf(Phase(type = type)),
                agents = listOf("Alice"),
                extraData = mapOf("pool" to AnyCodableValue.ArrayValue(listOf("E"))),
            )
            // Scripts are supplied generously rather than exactly: the allowed
            // handlers have different call counts and some throw for their own
            // reasons under this bare fixture. That is fine — an exhaustion
            // IllegalStateException is not a SimulationException, so it classifies
            // as "allowed", which is the correct verdict for a registered handler.
            val thrown = runCatching {
                handler.execute(
                    context(s, ScriptedLLMBackend(List(8) { speaks("Something said here.") })),
                    SimulationState.initial(s),
                )
            }.exceptionOrNull()
            val rejected = thrown is SimulationException &&
                (thrown.error as? SimulationError.ScenarioValidationFailed)
                    ?.message?.contains("depth-1") == true
            if (!rejected) allowed += type
        }

        assertEquals(14, PhaseType.entries.size, "the 9-of-14 claim is executable, not prose")
        assertEquals(
            setOf(
                PhaseType.SPEAK_ALL,
                PhaseType.SPEAK_EACH,
                PhaseType.VOTE,
                PhaseType.CHOOSE,
                PhaseType.SCORE_CALC,
                PhaseType.ASSIGN,
                PhaseType.ELIMINATE,
                PhaseType.SUMMARIZE,
                PhaseType.EVENT_INJECT,
            ),
            allowed,
        )
    }
}
