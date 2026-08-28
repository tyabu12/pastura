package com.pastura.engine

import com.pastura.models.PhaseType

/**
 * The linter-owned single source of truth for per-phase `{token}` placeholder
 * availability (ADR-024 D4).
 *
 * Resolves #920's open model-shape question in favor of a **[PhaseType] key
 * plus one narrow qualifier** (`chooseRoundRobin`) rather than a full
 * per-phase descriptor type: the only known intra-phase supply split is
 * `choose` round-robin vs individual (round-robin additionally injects
 * `{opponent_name}` and the whisper channel). Every other phase's supplied set
 * is fully determined by its [PhaseType].
 *
 * Two orthogonal facets, derived by reading the handler code:
 *
 * - [supplied] — the tokens a phase type **writes into the expansion
 *   namespace** (injected for its own LLM prompt, or written to
 *   `state.variables` for downstream phases). A token in this set is
 *   guaranteed *present* when the phase expands — it may still resolve to the
 *   empty string if its producer hasn't run (that's the producer relation
 *   below). A token *absent* here leaks its literal braces to the LLM (rules
 *   R10/R12).
 * - [producers] — for a producer-gated token, the phase type(s) that must
 *   have run **earlier in the phase list** for the token to resolve to a
 *   non-empty value (rule R11). Tokens with no producer (`scoreboard`,
 *   `conversation_log`, `candidates`, …) are always resolvable in a phase
 *   that supplies them and return `null` here.
 *
 * The lint rules (R10-R12) and #920's phase-aware `PhaseEditorSheet` hint
 * both read this map — the ADR's absorption of #920(B) is exactly "retarget
 * the editor hint to read the linter-owned map". This type is pure data +
 * lookups; it applies no logic to a `Scenario` (the rules do that).
 *
 * Important: the *union* of [supplied] over all phase types equals
 * `PromptPlaceholders.engineSupplied` **plus** [tokensBeyondEngineSupplied] —
 * a handful of genuinely handler-injected tokens that `engineSupplied` (a
 * curated coverage-guard subset, #890) never registered. The equality is
 * asserted in tests so a new handler-supplied placeholder must update this
 * map.
 *
 * Visibility: `internal`, not `public` — [ScenarioSemanticLinter] is now its
 * Kotlin consumer (D2c onward), and it stays `internal` because nothing
 * outside `shared/engine` needs to reach it, keeping the K/N export surface
 * unchanged. The Swift file
 * (`Pastura/Pastura/Engine/PlaceholderAvailability.swift`) is the source of
 * truth: a [PhaseType] or token change is a three-file hand edit — the Swift
 * original, this file, and its commonTest sibling.
 *
 * Kotlin port of `Pastura/Pastura/Engine/PlaceholderAvailability.swift`.
 * Ported for the ADR-023 Stage 3 Engine migration.
 */
internal object PlaceholderAvailability {

    // MARK: - Supplied tokens per phase type

    /**
     * Every engine-supplied `{token}` the given phase type writes into the
     * expansion namespace — see the object doc for the "present but possibly
     * empty" vs "absent -> literal leak" distinction.
     *
     * @param phaseType The phase whose supplied set is requested.
     * @param chooseRoundRobin Only meaningful for [PhaseType.CHOOSE]. `true`
     *   selects the round-robin branch (`ChooseHandler.callAgent`, which adds
     *   `{opponent_name}` and injects the whisper channel); `false` selects
     *   the individual branch (no `{opponent_name}`, and — matching the
     *   handler's asymmetry — no `{my_whispers}`). Ignored for every other
     *   phase type.
     * @return The supplied token set (may be empty for pure code phases that
     *   neither expand a template nor write a consumer-facing variable).
     */
    fun supplied(phaseType: PhaseType, chooseRoundRobin: Boolean): Set<String> =
        when (phaseType) {
            PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH, PhaseType.REFLECT ->
                // SpeakAll/SpeakEach/Reflect handlers all call inject{Assigned,Notes,Whispers,Relationships,Mood}.
                baseInjected.union(perPersonaInjected).union(whisperSelfInjected)

            PhaseType.VOTE ->
                // VoteHandler additionally builds {candidates} and writes {vote_results} to state.
                baseInjected.union(perPersonaInjected).union(whisperSelfInjected)
                    .union(setOf("candidates", "vote_results"))

            PhaseType.CHOOSE ->
                if (chooseRoundRobin) {
                    // ChooseHandler.callAgent adds {opponent_name} and injects the whisper channel.
                    baseInjected.union(perPersonaInjected).union(whisperSelfInjected)
                        .union(setOf("opponent_name"))
                } else {
                    // executeIndividual omits injectWhispers (a real handler asymmetry) -> no
                    // {my_whispers}, and never pairs so no {opponent_name}. It DOES call
                    // injectMood, so {my_mood} rides in via perPersonaInjected.
                    baseInjected.union(perPersonaInjected)
                }

            PhaseType.WHISPER ->
                // WhisperHandler adds the in-phase {whisper_partner}/{whisper_exchange} tokens.
                baseInjected.union(perPersonaInjected).union(whisperSelfInjected)
                    .union(setOf("whisper_partner", "whisper_exchange"))

            PhaseType.SUMMARIZE ->
                // SummarizeHandler never calls the inject* helpers, so no per-persona
                // tokens. The {agent1}-family + score tokens exist only in its pairing
                // branch (state.pairings non-empty + template contains "{agent1}").
                baseInjected.union(pairingInjected)

            PhaseType.ASSIGN ->
                // AssignHandler writes assigned_<name> (surfaced as {assigned}/{assigned_word}),
                // {assigned_topic} (all mode) and {wolf_name} (random_one mode).
                assignProduced

            PhaseType.EVENT_INJECT ->
                // EventInjectHandler writes the default event variable {current_event}
                // (a custom `as:` name is scenario-specific and resolved by the rule layer).
                setOf("current_event")

            PhaseType.RELATIONSHIP_UPDATE ->
                // RelationshipUpdateHandler writes relationships_<name>, surfaced downstream
                // as {relationships} via PromptBuilder.injectRelationships.
                setOf("relationships")

            PhaseType.NARRATE ->
                // NarrateHandler never calls the inject* helpers (it is not a
                // participant handler) -- it only explicitly injects
                // {conversation_log}/{scoreboard} into its own template expansion, and
                // {current_round} is already present in state.variables (written
                // per-round by SimulationRunner regardless of handler). No per-persona
                // or pairing tokens.
                baseInjected

            PhaseType.SCORE_CALC, PhaseType.ELIMINATE, PhaseType.CONDITIONAL ->
                // Pure control / scoring code phases: no template expansion, no
                // consumer-facing variable written.
                emptySet()
        }

    // MARK: - Producer relation

    /**
     * The phase type(s) that must have run earlier for [token] to resolve to
     * a non-empty value, or `null` when [token] is not producer-gated
     * (always resolvable in any phase that supplies it).
     *
     * Note: pairing tokens (`{agent1}`-family) are producer-gated on a
     * *round-robin* [PhaseType.CHOOSE] (they read `state.pairings`), which
     * this phase-type-granular map cannot express precisely — that relation
     * is R9's lane, checked with the `chooseRoundRobin` qualifier in the
     * rule layer, so they are deliberately absent here. Likewise a custom
     * `event_inject` `as:` name is resolved from the scenario's phases, not
     * this static map (which covers only the default `current_event`).
     */
    fun producers(token: String): Set<PhaseType>? = producerMap[token]

    // MARK: - Token groups (handler-derived)

    /**
     * Tokens every LLM handler writes unconditionally: `{scoreboard}` /
     * `{conversation_log}` (built per call) and `{current_round}` (written
     * to `state.variables` by `SimulationRunner` each round).
     */
    val baseInjected: Set<String> = setOf(
        "scoreboard", "conversation_log", "current_round"
    )

    /**
     * Per-persona tokens injected by `inject{Assigned,Notes,Relationships,Mood}`
     * in **every** LLM handler (including `choose` individual). Always
     * written — so present even when the producer hasn't run — but absent
     * from `summarize`/code phases, which never call the inject* helpers
     * (rule R12).
     */
    val perPersonaInjected: Set<String> = setOf(
        "assigned", "assigned_word", "my_notes", "relationships", "my_mood"
    )

    /**
     * The whisper-channel token injected by `injectWhispers` — every LLM
     * handler **except** `choose` individual (`executeIndividual` omits the
     * call).
     */
    val whisperSelfInjected: Set<String> = setOf("my_whispers")

    /** Pairing tokens `SummarizeHandler` writes in its per-pairing branch. */
    val pairingInjected: Set<String> = setOf(
        "agent1", "action1", "agent2", "action2", "score1", "score2"
    )

    /** Tokens `AssignHandler` makes resolvable downstream. */
    val assignProduced: Set<String> = setOf(
        "assigned", "assigned_word", "assigned_topic", "wolf_name"
    )

    /**
     * Handler-injected tokens genuinely supplied by the engine but **not**
     * registered in `PromptPlaceholders.engineSupplied` (a curated
     * coverage-guard subset scoped to placeholders bundled presets actually
     * reference, #890). Named here so the union-equality maintenance test
     * can state the delta explicitly instead of hiding it.
     */
    val tokensBeyondEngineSupplied: Set<String> = setOf(
        "my_notes", // reflect's channel -- promote to engineSupplied when a bundled preset first references {my_notes}
        "my_mood", // mood inertia (#913) -- promote to engineSupplied when a bundled preset first references {my_mood}
        "whisper_partner", "whisper_exchange",
        "agent1", "action1", "agent2", "action2", "score1", "score2"
    )

    /**
     * Producer-gated token -> producing phase type(s). Cross-checked against
     * [supplied] in tests: every producer's output token is also in that
     * producer's supplied set.
     *
     * Declared BEFORE [crossPhaseStateReadable] because a Kotlin `object`
     * initialises its properties strictly in declaration order, unlike
     * Swift's lazy `static let` (the Swift file has them the other way
     * round). The reverse order is a compile error here, not a runtime
     * surprise — measured in the commonTest sibling's condition-4 record.
     */
    val producerMap: Map<String, Set<PhaseType>> = mapOf(
        "assigned" to setOf(PhaseType.ASSIGN),
        "assigned_word" to setOf(PhaseType.ASSIGN),
        "assigned_topic" to setOf(PhaseType.ASSIGN),
        "wolf_name" to setOf(PhaseType.ASSIGN),
        "my_notes" to setOf(PhaseType.REFLECT),
        "my_whispers" to setOf(PhaseType.WHISPER),
        "relationships" to setOf(PhaseType.RELATIONSHIP_UPDATE),
        "vote_results" to setOf(PhaseType.VOTE),
        "current_event" to setOf(PhaseType.EVENT_INJECT),
        // Over-approximation (#913): unlike every other entry -- each with a single
        // semantically-exact producer -- mood can be declared in ANY LLM phase's
        // output schema, and this phase-type-granular map cannot see per-scenario
        // schema opt-in. Listing all six keeps R11's producer-gating honest (mood
        // only resolves after some LLM phase ran) at the cost of lint precision; the
        // miss->"" posture of `injectMood` makes that imprecision benign.
        "my_mood" to setOf(
            PhaseType.SPEAK_ALL, PhaseType.SPEAK_EACH, PhaseType.VOTE,
            PhaseType.CHOOSE, PhaseType.REFLECT, PhaseType.WHISPER
        )
    )

    /**
     * Tokens a producer phase writes into `state.variables` and that ANY
     * later LLM phase's prompt can read via generic `{token}` expansion —
     * the cross-phase-readable complement of the per-persona `inject*`
     * tokens (whose availability is phase-type-specific and already
     * modeled by [supplied]). Derived as the producer-gated tokens minus
     * the per-persona / whisper injected forms so it stays in lockstep with
     * [producerMap]: `{assigned_topic, wolf_name, vote_results, current_event}`.
     *
     * The editor's phase-aware prompt hint (#920 B) unions this into every
     * LLM phase's supplied set, so an author still discovers
     * `{assigned_topic}` / `{current_event}` — usable when an upstream
     * `assign` / `event_inject` ran, and permitted by the R10/R11 linter's
     * global known-token set. Whether a producer actually runs earlier
     * stays R11's lane, not the hint's. A custom `event_inject` `as:` name
     * is scenario-specific and intentionally absent (the editor sheet has
     * no scenario context; only the default is listed).
     *
     * Must follow [producerMap] in declaration order: a Kotlin `object`
     * initialises its properties strictly top-to-bottom, and the compiler
     * rejects an initialiser that reads a later-declared property.
     */
    val crossPhaseStateReadable: Set<String> =
        producerMap.keys
            .minus(perPersonaInjected)
            .minus(whisperSelfInjected)
}
