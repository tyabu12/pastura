package com.pastura.engine

import com.pastura.models.Pairing
import com.pastura.models.PairingStrategy
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationEvent
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin sibling of Swift's `ChooseHandlerTests` (+ its `…+TurnDegradation` split),
 * collapsed into one class per the commonTest convention.
 *
 * `choose` is the most entangled LLM handler of Wave B: two modes, and a
 * round-robin output (`pairings`) that three already-ported consumers read. The
 * cases below pin, in ADR-023 §12 terms, the mechanisms a green-but-wrong port
 * would silently lose — the adjacency arithmetic, both drop gates, the `succeeded`
 * set, the canonicalization boundary (canonical in round-robin, raw in individual),
 * the `pairings`/`PairingResult` production, and `opponent_name`'s reach into the
 * prompt.
 *
 * Ported for the ADR-023 KMP Engine migration (#501, #1262).
 */
class ChooseHandlerTests {

    private val handler = ChooseHandler()

    private fun scenario(
        agents: List<String> = listOf("Alice", "Bob", "Charlie"),
        language: String = "en",
        simulationLanguage: String? = null,
        prompt: String? = "Choose!",
        options: List<String>? = listOf("cooperate", "betray"),
        pairing: PairingStrategy? = PairingStrategy.ROUND_ROBIN,
        outputSchema: Map<String, String> = mapOf("action" to "string"),
    ) = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = simulationLanguage,
        agentCount = agents.size,
        rounds = 2,
        logWindow = null,
        context = "A test.",
        personas = agents.map { Persona(name = it, description = "$it's persona.") },
        phases = listOf(
            Phase(
                type = PhaseType.CHOOSE,
                prompt = prompt,
                outputSchema = outputSchema,
                options = options,
                pairing = pairing,
            ),
        ),
    )

    private fun context(
        s: Scenario,
        backend: LLMBackend,
        events: MutableList<SimulationEvent> = mutableListOf(),
    ) = PhaseContext(
        scenario = s,
        phase = s.phases[0],
        backend = backend,
        suspensionRelay = SuspensionRelay(),
        emitter = { events += it },
        pauseCheck = { },
        phasePath = listOf(0),
        turnGate = TurnFailureGate(),
    )

    private fun chooses(action: String) =
        ScriptedLLMBackend.Script.completing("""{"action": "$action"}""")

    private fun failing() =
        ScriptedLLMBackend.Script(terminal = TerminalStatus.Failed(errorCode = "transient blip"))

    private fun initial(s: Scenario) = SimulationState.initial(s).copy(currentRound = 1)

    private fun pairingResults(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.PairingResult>()

    private fun rejections(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.ActionRejected>()

    private fun skips(events: List<SimulationEvent>) =
        events.filterIsInstance<SimulationEvent.TurnSkipped>()

    // MARK: - Round-robin adjacency (§12 axis 1)

    @Test
    fun roundRobinCreatesAdjacentPairsAndCallsTheBackendTwicePerPair() = runTest {
        // 3 agents -> 3 adjacent pairs (Alice,Bob) (Bob,Charlie) (Charlie,Alice),
        // 2 calls per pair = 6. The `(i+1) % count` wrap is what makes the pair
        // COUNT equal the agent count; a non-wrapping `zipWithNext` would yield 2
        // pairs / 4 calls and turn this red.
        val s = scenario()
        val backend = ScriptedLLMBackend(
            listOf(
                chooses("cooperate"), chooses("betray"),
                chooses("cooperate"), chooses("cooperate"),
                chooses("betray"), chooses("betray"),
            ),
        )
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals(6, backend.callCount)
        assertEquals(3, next.pairings.size)
        // The wrap pair (last, first) exists — the specific edge a non-wrapping
        // implementation drops.
        assertTrue(next.pairings.any { it.agent1 == "Charlie" && it.agent2 == "Alice" })
    }

    @Test
    fun roundRobinPairsAreOrderedByPersonaDeclarationOrder() = runTest {
        val s = scenario(agents = listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(
            listOf(chooses("cooperate"), chooses("betray"), chooses("betray"), chooses("cooperate")),
        )
        val next = handler.execute(context(s, backend), initial(s))

        val first = next.pairings[0]
        assertEquals("Alice", first.agent1)
        assertEquals("cooperate", first.action1)
        assertEquals("Bob", first.agent2)
        assertEquals("betray", first.action2)
    }

    // MARK: - pairings + PairingResult production (§12 axis 7)

    @Test
    fun greenPathWritesCanonicalPairingsAndEmitsOnePairingResultEach() = runTest {
        // The producer->consumer path. ChooseHandler is the engine's only APPENDER to
        // `pairings` (the run loop's reset and PairwisePayoffLogic's post-scoring
        // clear are the other two writers, both emptying) and the sole emitter of
        // PairingResult; all three downstream consumers hand-inject `pairings` in
        // their own tests, so dropping either here stays green everywhere else.
        //
        // Deliberately shares its script with `caseVariantActionScores…` below: the
        // CASE VARIANT ("Betray") makes this test ALSO fail if canonicalization is
        // reverted, so the production and canonicalization contracts are wired to one
        // green path rather than two independently-satisfiable ones. The sibling test
        // keeps the narrower, single-purpose framing of the Swift original.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(chooses("Betray"), chooses("cooperate"), chooses("cooperate"), chooses("betray")),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(2, next.pairings.size)
        assertEquals(2, pairingResults(events).size)

        // Canonical `betray`, NOT the raw `"Betray"` the model produced.
        val first = next.pairings[0]
        assertEquals("Alice", first.agent1)
        assertEquals("betray", first.action1)
        assertEquals("betray", pairingResults(events)[0].action1)
        // Nothing was rejected — a case variant must score, not drop.
        assertTrue(rejections(events).isEmpty())

        // Every stored action is drawn from the declared option set, so an exact-match
        // consumer can never miss. (A raw-input port fails this on "Betray".)
        val declared = setOf("cooperate", "betray")
        for (pairing in next.pairings) {
            assertTrue(declared.contains(pairing.action1), "non-canonical action1: ${pairing.action1}")
            assertTrue(declared.contains(pairing.action2), "non-canonical action2: ${pairing.action2}")
        }
    }

    @Test
    fun pairingsAppendRatherThanReplaceAcrossTwoPhaseRuns() = runTest {
        // Append, not replace: the run loop resets `pairings` per round and
        // PairwisePayoffLogic clears after scoring, so accumulation within a round is
        // the correct scope. A `pairings = listOf(...)` port keeps only the last pair
        // and turns this red (it would also silently drop pairs WITHIN one phase).
        val s = scenario(agents = listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(List(8) { chooses("cooperate") })
        val ctx = context(s, backend)

        val afterFirst = handler.execute(ctx, initial(s))
        assertEquals(2, afterFirst.pairings.size)
        val afterSecond = handler.execute(ctx, afterFirst)
        assertEquals(4, afterSecond.pairings.size)
    }

    // MARK: - Off-menu drop + ActionRejected (§12 axis 2)

    @Test
    fun dropsPairingAndEmitsActionRejectedOnGenuineOffMenuAction() = runTest {
        // ADR-021 § Amendment 2026-07-17 (#1151): an off-menu action no longer falls
        // back to `options[0]` (fabricating a cooperate) — the whole pairing is
        // dropped and ActionRejected carries the raw value.
        // 2 agents -> 2 pairs (Alice,Bob) (Bob,Alice) -> 4 calls.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(
                chooses("invalid_action"), // Alice, pair 1 — off-menu
                chooses("cooperate"), // Bob, pair 1
                chooses("cooperate"), // Bob, pair 2
                chooses("betray"), // Alice, pair 2
            ),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        // Pair 1 dropped; only pair 2 survives — no fabricated cooperate for Alice.
        assertEquals(1, next.pairings.size)
        assertEquals("Bob", next.pairings[0].agent1)
        assertEquals("betray", next.pairings[0].action2)

        // Exactly one rejection, for Alice, carrying the verbatim raw value.
        assertEquals(1, rejections(events).size)
        assertEquals("Alice", rejections(events).single().agent)
        assertEquals("invalid_action", rejections(events).single().raw)
        assertEquals(PhaseType.CHOOSE, rejections(events).single().phaseType)

        // The dropped pairing emits no PairingResult — only pair 2's.
        assertEquals(1, pairingResults(events).size)
        // An off-menu answer is NOT a skip: the call succeeded and AgentOutput fired.
        assertTrue(skips(events).isEmpty())
        assertEquals(4, events.filterIsInstance<SimulationEvent.AgentOutput>().size)
    }

    @Test
    fun emitsOneActionRejectedPerOffMenuMemberWhenBothAreOffMenu() = runTest {
        // Both members off-menu -> two rejections from ONE dropped pairing. A port
        // that `return`s after the first rejection (or emits a single pair-level
        // event) turns this red.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(chooses("nope"), chooses("nah"), chooses("cooperate"), chooses("betray")),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(listOf("Alice", "Bob"), rejections(events).map { it.agent })
        assertEquals(listOf("nope", "nah"), rejections(events).map { it.raw })
        assertEquals(1, next.pairings.size) // pair 2 still scores
    }

    // MARK: - Canonicalization (§12 axis 5)

    @Test
    fun caseVariantActionScoresAsCanonicalOptionRatherThanDropping() = runTest {
        // Regression for the normalization half of validateAction: `"Betray"` must
        // fold onto `betray` and SCORE. Removing the trim+lowercase fold drops the
        // pairing instead and turns this red.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(chooses("Betray"), chooses("cooperate"), chooses("cooperate"), chooses("betray")),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(2, next.pairings.size)
        assertEquals("betray", next.pairings[0].action1)
        assertTrue(rejections(events).isEmpty())
    }

    @Test
    fun whitespacePaddedActionAlsoFoldsOntoTheCanonicalOption() = runTest {
        // The trim half of the fold, disjoint from the case half above.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(chooses("  betray  "), chooses("cooperate"), chooses("cooperate"), chooses("betray")),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals("betray", next.pairings[0].action1)
        assertTrue(rejections(events).isEmpty())
    }

    @Test
    fun anOptionlessRoundRobinPassesTheRawActionThroughInsteadOfDroppingEveryPairing() = runTest {
        // `options.isEmpty() -> return action` is preserved from Swift: an
        // options-less round-robin has nothing to canonicalize against, and returning
        // null there would drop EVERY pairing. Reverting the guard turns this red
        // (0 pairings, 2 rejections). Note the deliberate asymmetry with
        // PromptBuilder.chooseOptionsRule, which gates on `options != null`.
        val s = scenario(agents = listOf("Alice", "Bob"), options = null)
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(chooses("Anything"), chooses("Whatever"), chooses("x"), chooses("y")),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(2, next.pairings.size)
        // Raw, un-canonicalized (there is no option set to canonicalize against).
        assertEquals("Anything", next.pairings[0].action1)
        assertTrue(rejections(events).isEmpty())
    }

    // MARK: - Turn degradation, round-robin (§12 axes 3 + 4)

    @Test
    fun roundRobinSkipDropsWholePairingAndSparesTheOtherPairingsOutput() = runTest {
        // 3 agents -> pairs (Alice,Bob) (Bob,Charlie) (Charlie,Alice); call order
        // Alice,Bob,Bob,Charlie,Charlie,Alice. Failing call #1 (Alice as member 1 of
        // pair 0) drops that pairing, and her LATER call (#6, in pair 2) succeeds, so
        // she still ends the phase with a valid lastOutputs.
        //
        // That last assertion does NOT exercise the `succeeded` guard, despite
        // looking like it: at call #1 `succeeded` is still empty, so the guard takes
        // its clearing branch anyway (a no-op on an empty map) and call #6 writes
        // unconditionally. Deleting the guard leaves this test green. The guard's
        // protective arm — success THEN skip — is pinned by the next test,
        // `aSkipAfterASuccessDoesNotEraseTheEarlierValidOutput`; this one covers the
        // skip-then-success direction and the pairing drop.
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(
                failing(), // #1 Alice   (pair0 member1)
                chooses("cooperate"), // #2 Bob     (pair0 member2)
                chooses("cooperate"), // #3 Bob     (pair1 member1)
                chooses("betray"), // #4 Charlie (pair1 member2)
                chooses("cooperate"), // #5 Charlie (pair2 member1)
                chooses("betray"), // #6 Alice   (pair2 member2)
            ),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        // Exactly one skipped turn, typed to CHOOSE.
        assertEquals(1, skips(events).size)
        assertEquals("Alice", skips(events).single().agent)
        assertEquals(PhaseType.CHOOSE, skips(events).single().phaseType)

        // The (Alice,Bob) pairing is dropped; the other two survive.
        assertEquals(2, next.pairings.size)
        assertFalse(next.pairings.any { it.agent1 == "Alice" && it.agent2 == "Bob" })
        assertEquals(2, pairingResults(events).size)

        // The successful partner (Bob, #2) kept his output...
        assertEquals("cooperate", next.lastOutputs["Bob"]?.action)
        // ...and Alice's later success (#6) is NOT erased by her earlier skip.
        assertEquals("betray", next.lastOutputs["Alice"]?.action)
    }

    @Test
    fun aSkipAfterASuccessDoesNotEraseTheEarlierValidOutput() = runTest {
        // The `succeeded` guard's OTHER arm — success-THEN-skip — which Swift's own
        // test file documents as unreachable under its position-based mock. The
        // scripted backend here can express it directly: 3 agents, call #6 (Alice's
        // SECOND appearance) fails after her #1 succeeded. An unconditional clear on
        // the skip path wipes `lastOutputs["Alice"]` and turns this red; the guard
        // keeps her round-1 choice, which EventReactivePayoffLogic legitimately reads.
        val s = scenario()
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(
                chooses("cooperate"), // #1 Alice   (pair0 member1) — succeeds
                chooses("betray"), // #2 Bob
                chooses("cooperate"), // #3 Bob
                chooses("betray"), // #4 Charlie
                chooses("cooperate"), // #5 Charlie
                failing(), // #6 Alice   (pair2 member2) — skips
            ),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(1, skips(events).size)
        assertEquals("Alice", skips(events).single().agent)
        // Her earlier successful choice survives the later skip.
        assertEquals("cooperate", next.lastOutputs["Alice"]?.action)
        // Pair 2 (Charlie,Alice) is dropped; pairs 0 and 1 stand.
        assertEquals(2, next.pairings.size)
        assertFalse(next.pairings.any { it.agent1 == "Charlie" && it.agent2 == "Alice" })
    }

    @Test
    fun aSkipOnAnAgentsOnlySuccessfulSlotClearsItsStaleLastOutputs() = runTest {
        // The negative control for the guard above: when the agent NEVER succeeds in
        // this phase, the stale prior-round output MUST be cleared (ADR-021 D2), so
        // a decision that never happened cannot leak downstream. A port that always
        // preserves `lastOutputs` on skip turns this red.
        // 2 agents -> pairs (Alice,Bob) (Bob,Alice); Alice is calls #1 and #4.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(failing(), chooses("cooperate"), chooses("cooperate"), failing()),
        )
        val before = initial(s).copy(
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("action" to "stale"))),
        )
        val next = handler.execute(context(s, backend, events), before)

        assertEquals(2, skips(events).size)
        assertNull(next.lastOutputs["Alice"])
        assertEquals("cooperate", next.lastOutputs["Bob"]?.action)
        assertTrue(next.pairings.isEmpty()) // both pairings dropped
    }

    // MARK: - opponent_name reaches the prompt (§12 axis 8)

    @Test
    fun opponentNameIsExpandedIntoEachRoundRobinTurnsPrompt() = runTest {
        // `opponent_name` is the choose-only prompt variable — what makes a
        // round-robin turn "with opponent context". Dropping it fails SILENTLY:
        // expandTemplate leaves an unknown placeholder unchanged, so the literal
        // would reach the model with no exception and no diagnostic. Both halves are
        // asserted: the opponent's name is present AND the literal is gone.
        val s = scenario(agents = listOf("Alice", "Bob"), prompt = "You face {opponent_name}.")
        val backend = ScriptedLLMBackend(
            listOf(chooses("cooperate"), chooses("betray"), chooses("betray"), chooses("cooperate")),
        )
        handler.execute(context(s, backend), initial(s))

        // Exact equality, not `contains`: it pins BOTH halves at once — the opponent's
        // name is substituted AND no unresolved `{opponent_name}` literal survives.
        // Call #1 is Alice facing Bob; #2 is Bob facing Alice (so this also catches a
        // port that sets the variable once instead of per turn).
        assertEquals("You face Bob.", backend.requests[0].user)
        assertEquals("You face Alice.", backend.requests[1].user)
    }

    @Test
    fun individualModeDoesNotResolveOpponentName() = runTest {
        // The disjoint control: individual mode has no opponent, so the variable is
        // deliberately unset and the placeholder survives verbatim. This pins the
        // asymmetry rather than letting a "helpful" port set it in both modes.
        val s = scenario(
            agents = listOf("Alice", "Bob"),
            prompt = "You face {opponent_name}.",
            pairing = null,
        )
        val backend = ScriptedLLMBackend(listOf(chooses("cooperate"), chooses("betray")))
        handler.execute(context(s, backend), initial(s))

        assertEquals("You face {opponent_name}.", backend.requests[0].user)
    }

    // MARK: - Round-robin agent-count boundaries (§12 axis 9)

    @Test
    fun twoActiveAgentsProduceTwoMirroredPairings() = runTest {
        // (i+1)%2 yields (A,B) AND (B,A) — two MIRRORED pairings, both scored by
        // PairwisePayoffLogic. This is Swift-faithful and load-bearing: a
        // "deduplicate the mirror" fix would halve every 2-agent prisoner's-dilemma
        // round's score. Pinned so it cannot be silently "fixed".
        //
        // The same arithmetic self-pairs at ONE active agent — (A,A), double-scoring
        // A — which is likewise Swift-faithful. It is reachable rather than
        // theoretical: the run loop's "fewer than 2 active" break fires at round
        // START, so an `eliminate` phase earlier in the same round can drop the
        // roster to 1 before this phase runs. Not asserted here (constructing it
        // needs a multi-phase run), but do not "fix" that arm either.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(chooses("cooperate"), chooses("betray"), chooses("betray"), chooses("cooperate")),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(2, next.pairings.size)
        assertEquals(listOf("Alice" to "Bob", "Bob" to "Alice"), next.pairings.map { it.agent1 to it.agent2 })
        assertEquals(4, backend.callCount)
        assertEquals(2, pairingResults(events).size)
    }

    @Test
    fun eliminatedAgentsAreExcludedFromPairing() = runTest {
        // Charlie eliminated -> the active roster is [Alice, Bob] -> 2 pairs, 4 calls.
        val s = scenario()
        val backend = ScriptedLLMBackend(
            listOf(chooses("cooperate"), chooses("betray"), chooses("betray"), chooses("cooperate")),
        )
        val state = initial(s).copy(eliminated = mapOf("Charlie" to true))
        val next = handler.execute(context(s, backend), state)

        assertEquals(4, backend.callCount)
        assertFalse(next.pairings.any { it.agent1 == "Charlie" || it.agent2 == "Charlie" })
    }

    // MARK: - Individual mode (§12 axis 6)

    @Test
    fun individualChoiceCallsEveryActiveAgentAndCreatesNoPairings() = runTest {
        val s = scenario(agents = listOf("Alice", "Bob"), pairing = null)
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(chooses("cooperate"), chooses("betray")))
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals(2, backend.callCount)
        assertTrue(next.pairings.isEmpty())
        assertTrue(pairingResults(events).isEmpty())
    }

    @Test
    fun individualModeWritesTheRawActionWithoutCanonicalizing() = runTest {
        // Deliberate divergence from round-robin: individual mode has no pairing to
        // drop, and its consumer (EventReactivePayoffLogic) normalizes on read — so
        // the RAW value is stored, inventing nothing. A port that canonicalizes here
        // "for consistency" turns this red, and an off-menu answer must likewise pass
        // through rather than being rejected.
        val s = scenario(agents = listOf("Alice", "Bob"), pairing = null)
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(chooses("Betray"), chooses("something_else")))
        val next = handler.execute(context(s, backend, events), initial(s))

        assertEquals("Betray", next.lastOutputs["Alice"]?.action)
        assertEquals("something_else", next.lastOutputs["Bob"]?.action)
        // No canonicalization means no rejection path in this mode.
        assertTrue(rejections(events).isEmpty())
    }

    @Test
    fun individualSkipWritesNothingAndClearsStaleLastOutputs() = runTest {
        // ADR-021 D2 for individual mode: Alice's call fails -> she writes nothing and
        // her stale lastOutputs is cleared; Bob and Charlie choose normally. The
        // mirror of the round-robin `succeeded` discipline — here the clear is
        // unconditional, because one call per agent means no sibling success exists.
        val s = scenario(pairing = null)
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(listOf(failing(), chooses("cooperate"), chooses("betray")))
        val before = initial(s).copy(
            lastOutputs = mapOf("Alice" to TurnOutput(fields = mapOf("action" to "stale"))),
        )
        val next = handler.execute(context(s, backend, events), before)

        assertEquals(
            listOf("Bob", "Charlie"),
            events.filterIsInstance<SimulationEvent.AgentOutput>().map { it.agent },
        )
        assertEquals(listOf("Alice"), skips(events).map { it.agent })
        assertNull(next.lastOutputs["Alice"])
        assertEquals("cooperate", next.lastOutputs["Bob"]?.action)
    }

    @Test
    fun individualModeSkipsEliminatedAgents() = runTest {
        val s = scenario(pairing = null)
        val backend = ScriptedLLMBackend(listOf(chooses("cooperate"), chooses("betray")))
        val state = initial(s).copy(eliminated = mapOf("Bob" to true))
        val next = handler.execute(context(s, backend), state)

        assertEquals(2, backend.callCount)
        // Identity, not just the count: a port that skipped the WRONG agent would
        // still make two calls. Bob is absent; the other two ran.
        assertEquals(setOf("Alice", "Charlie"), next.lastOutputs.keys)
    }

    // MARK: - Empty action is a SKIP, not an off-menu rejection

    @Test
    fun emptyActionIsAbsorbedAsSkipNotAsAnOffMenuRejection() = runTest {
        // The parser rejects a present-but-empty expected key ({"action":""} —
        // `hasAllExpectedKeys` requires non-empty content), so three empties exhaust
        // the retry budget -> RetriesExhausted -> the turn gate absorbs it as a SKIP
        // (ADR-021 D2). It is therefore gate 1 (pairing dropped, TurnSkipped, no
        // AgentOutput), NOT gate 2 — the two drop paths must not be conflated, since
        // only gate 2 emits ActionRejected. Asserted through the skip MECHANISM, not
        // through validateAction's return.
        // 2 agents; Alice's first call burns 3 scripts, then the run continues.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val events = mutableListOf<SimulationEvent>()
        val backend = ScriptedLLMBackend(
            listOf(
                chooses(""), chooses(""), chooses(""), // #1 Alice — 3 attempts, all rejected
                chooses("cooperate"), // Bob, pair 0 member 2
                chooses("betray"), // Bob, pair 1 member 1
                chooses("cooperate"), // Alice, pair 1 member 2
            ),
        )
        val next = handler.execute(context(s, backend, events), initial(s))

        // Skip mechanism fired, and it is a skip — not a rejection.
        assertEquals(1, skips(events).size)
        assertEquals("Alice", skips(events).single().agent)
        assertTrue(rejections(events).isEmpty())
        // Downstream drop: pair 0 is gone, pair 1 stands.
        assertEquals(1, next.pairings.size)
        assertEquals("Bob", next.pairings[0].agent1)
        // No AgentOutput for the skipped turn (3 calls produced nothing).
        assertEquals(3, events.filterIsInstance<SimulationEvent.AgentOutput>().size)
    }

    // MARK: - captureMood round-trip (single-copy fold, #913)

    @Test
    fun capturedMoodSurfacesInTheNextRoundsPrompt() = runTest {
        // Pins the success-path `state.copy` fold: captureMood must land in the
        // RETURNED state (folded alongside lastOutputs), else round N's mood never
        // reaches round N+1. A second copy off the original drops one of the two.
        val moodSchema = mapOf("action" to "string", "mood" to "string")
        val s = scenario(agents = listOf("Alice", "Bob"), outputSchema = moodSchema)
        val backend = ScriptedLLMBackend(
            List(8) { idx ->
                ScriptedLLMBackend.Script.completing(
                    """{"action": "cooperate", "mood": "mood$idx"}""",
                )
            },
        )
        val ctx = context(s, backend)

        val afterFirst = handler.execute(ctx, initial(s))
        assertEquals("mood3", afterFirst.variables["mood_Alice"]) // last write wins (call #4)

        handler.execute(ctx, afterFirst)
        assertTrue(backend.requests[4].system.contains("mood3"))
        assertTrue(backend.requests[4].system.contains("Your Current Mood"))
    }

    @Test
    fun individualModeAlsoCapturesMood() = runTest {
        // Mood is symmetric across both modes (unlike injectWhispers). A port that
        // wires captureMood only into the round-robin path turns this red.
        val moodSchema = mapOf("action" to "string", "mood" to "string")
        val s = scenario(agents = listOf("Alice"), outputSchema = moodSchema, pairing = null)
        val backend = ScriptedLLMBackend(
            listOf(ScriptedLLMBackend.Script.completing("""{"action": "cooperate", "mood": "焦り"}""")),
        )
        val next = handler.execute(context(s, backend), initial(s))

        assertEquals("焦り", next.variables["mood_Alice"])
    }

    // MARK: - simulationLanguage override (ADR-010 Step E)

    @Test
    fun chooseHonorsSimulationLanguageOverrideJaToEn() = runTest {
        // ja authoring, en simulation override, prompt:null forces the fallback. The
        // captured prompt must contain the English fallback, not the Japanese one.
        val s = scenario(
            agents = listOf("Alice", "Bob"),
            language = "ja",
            simulationLanguage = "en",
            prompt = null,
            pairing = null,
        )
        val backend = ScriptedLLMBackend(listOf(chooses("cooperate"), chooses("betray")))
        handler.execute(context(s, backend), initial(s))

        val prompt = backend.requests[0].user
        assertTrue(prompt.contains("Make a choice"))
        assertFalse(prompt.contains("選択してください"))
    }

    @Test
    fun chooseHonorsSimulationLanguageOverrideEnToJa() = runTest {
        // Reverse: en authoring, ja simulation override.
        val s = scenario(
            agents = listOf("Alice", "Bob"),
            language = "en",
            simulationLanguage = "ja",
            prompt = null,
            pairing = null,
        )
        val backend = ScriptedLLMBackend(listOf(chooses("cooperate"), chooses("betray")))
        handler.execute(context(s, backend), initial(s))

        val prompt = backend.requests[0].user
        assertTrue(prompt.contains("選択してください"))
        assertFalse(prompt.contains("Make a choice"))
    }

    // MARK: - Immutable-state contract

    @Test
    fun theInputStateIsNeverMutated() = runTest {
        val s = scenario(agents = listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(
            listOf(chooses("cooperate"), chooses("betray"), chooses("betray"), chooses("cooperate")),
        )
        val before = initial(s)
        val next = handler.execute(context(s, backend), before)

        assertTrue(before.pairings.isEmpty())
        assertTrue(before.lastOutputs.isEmpty())
        assertEquals(2, next.pairings.size)
    }

    @Test
    fun aPreexistingPairingFromEarlierInTheRoundIsPreserved() = runTest {
        // Guards the append against a `pairings = listOf(...)` port from a different
        // angle than the two-run test: an entry already in state must survive.
        val s = scenario(agents = listOf("Alice", "Bob"))
        val backend = ScriptedLLMBackend(
            listOf(chooses("cooperate"), chooses("betray"), chooses("betray"), chooses("cooperate")),
        )
        val seeded = initial(s).copy(
            pairings = listOf(Pairing(agent1 = "X", agent2 = "Y", action1 = "a", action2 = "b")),
        )
        val next = handler.execute(context(s, backend), seeded)

        assertEquals(3, next.pairings.size)
        assertEquals("X", next.pairings[0].agent1)
    }
}
