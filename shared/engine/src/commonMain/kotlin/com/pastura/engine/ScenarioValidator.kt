package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScenarioConventions
import com.pastura.models.ScenarioValidationMessage
import com.pastura.models.SimulationError

/**
 * Validates a [Scenario] against execution limits before running.
 *
 * Enforces agent count (2–10), round count (≤30), estimated inference count
 * (warn >50, error >100), and phase-field semantics (e.g. assign-phase
 * target/source compatibility) to prevent runaway or misconfigured simulations.
 *
 * Kotlin port of `Pastura/Pastura/Engine/ScenarioValidator.swift` plus its two
 * sibling extensions `ScenarioValidator+EventInject.swift` and
 * `ScenarioValidator+OutputFieldNames.swift` (ADR-023 §4, the "Load + validate"
 * row). The Swift originals split across three files only to stay under
 * SwiftLint's file/type length caps and to dodge a default-MainActor isolation
 * trap on sibling extensions; Kotlin has neither constraint, so the whole gate
 * lives here.
 *
 * ## Scope: the RUN gate only
 *
 * `validateForCommit` and the canonical primary-field checks
 * (`ScenarioValidator+CanonicalFields.swift`) are **not** ported yet — they land
 * in a follow-up PR. Everything `validate(_:)` runs is here.
 *
 * ## Not wired into the engine
 *
 * Nothing in `shared/engine` calls this yet, deliberately. ADR-023 §4 has the
 * preflight gate on the validator **and** `ScenarioSemanticLinter` (ADR-024)
 * together — the linter's `.error` findings block a run just as this gate's
 * throws do. The linter is unported, so wiring this half into
 * [SimulationEngine] now would split one preflight across two languages, which
 * is exactly the shape ADR-023 §4 rejects. Wiring happens once both halves
 * exist.
 *
 * ## Known rendering divergences from Swift
 *
 * All four are **documented, not ledgered**. They are the same family as
 * `DivergenceLedger.DivergenceClass.NUMBER_LITERAL_FORMATTING` and
 * `SCOREBOARD_ORDERING` — cross-language differences in how a value becomes
 * text — but none is a ledger entry, because validation errors never reach a
 * parity transcript at all: a scenario this gate rejects produces no run to
 * compare (the standing reason recorded on
 * `DivergenceClass.VALIDATOR_UNPORTED`).
 *
 * 1. **Probability rendering.** Swift `String(probability)` and Kotlin
 *    `Double.toString()` switch to exponent notation at different magnitudes and
 *    spell the exponent differently: `1e-7` renders `"1e-07"` in Swift and
 *    `"1.0E-7"` in Kotlin. Message text only — both sides reject the same
 *    values.
 * 2. **NaN / infinity rendering.** Swift renders `"nan"` / `"inf"` / `"-inf"`,
 *    Kotlin `"NaN"` / `"Infinity"` / `"-Infinity"`. Control flow agrees (both
 *    fall outside `0.0..1.0` and throw); only the message text differs. Unlike
 *    (1) this **is** reachable from authored YAML — `probability: .nan` and
 *    `probability: .inf` are legal YAML floats.
 * 3. **Whitespace trimming.** Swift trims `.whitespacesAndNewlines` (a Unicode
 *    character set); Kotlin `trim()` trims `Char.isWhitespace()`. The two sets
 *    disagree on a handful of exotic code points, so a source key or `if:`
 *    padded with one of them could trim on one side and not the other.
 * 4. **Output-key ordering.** `schema.keys.sorted()` is Unicode-scalar order in
 *    Swift and UTF-16 code-unit order in Kotlin. Only *which* invalid key is
 *    reported first can differ, and only when a schema has ≥2 invalid keys
 *    straddling the BMP boundary — accept/reject is identical either way.
 */
public class ScenarioValidator {

    /** The result of scenario validation. */
    public data class ValidationResult(
        /** Non-fatal warnings (e.g. high inference count). */
        public val warnings: List<String>,
        /** The estimated total number of LLM inferences. */
        public val estimatedInferences: Long,
    )

    /**
     * Validates [scenario] against execution limits.
     *
     * `@Throws` is load-bearing at the K/N boundary, not decoration: Kotlin
     * exceptions from an **un-annotated** function are not surfaced to Swift as
     * catchable errors — they terminate the process. Stage-5 iOS consumers call
     * this across that boundary, so the annotation is what makes a validation
     * failure a `catch`-able Swift error instead of a crash. This is the first
     * `@Throws` in commonMain; `ConditionEvaluator.parse` has the same gap and
     * is a follow-up, not this PR.
     *
     * @return a [ValidationResult] with any warnings and the inference estimate.
     * @throws SimulationException carrying
     *   [SimulationError.ScenarioValidationFailed] if a limit is exceeded.
     */
    @Throws(SimulationException::class)
    public fun validate(scenario: Scenario): ValidationResult {
        // Language values (ADR-010 D1 / D5 — programmatic-construction path
        // gate, mirrors `ScenarioLoader`'s YAML-parse path).
        if (scenario.language !in Scenario.ACCEPTED_LANGUAGES) {
            throw validationError(
                ScenarioValidationMessage.LanguageNotAccepted(
                    allowed = acceptedLanguagesList(),
                    got = scenario.language,
                ),
            )
        }
        val simulationLanguage = scenario.simulationLanguage
        if (simulationLanguage != null && simulationLanguage !in Scenario.ACCEPTED_LANGUAGES) {
            throw validationError(
                ScenarioValidationMessage.SimulationLanguageNotAccepted(
                    allowed = acceptedLanguagesList(),
                    got = simulationLanguage,
                ),
            )
        }

        // Agent count limits (checked first for clearer error messages)
        if (scenario.agentCount < 2) {
            throw validationError(
                ScenarioValidationMessage.AgentCountBelowMinimum(scenario.agentCount),
            )
        }
        if (scenario.agentCount > 10) {
            throw validationError(
                ScenarioValidationMessage.AgentCountExceedsMaximum(scenario.agentCount),
            )
        }

        // Persona count must match agentCount
        if (scenario.personas.size != scenario.agentCount) {
            throw validationError(
                ScenarioValidationMessage.PersonaCountMismatch(
                    personaCount = scenario.personas.size,
                    agentCount = scenario.agentCount,
                ),
            )
        }

        // Round count limit
        if (scenario.rounds > 30) {
            throw validationError(
                ScenarioValidationMessage.RoundCountExceedsMaximum(scenario.rounds),
            )
        }

        // Conversation-log window (#907): a prompt-side cap that must keep at
        // least one entry when set. `null` means "no window" (full log); `0` or
        // negative would silently strip the whole log, so reject it as a
        // misconfiguration.
        val logWindow = scenario.logWindow
        if (logWindow != null && logWindow < 1) {
            throw validationError(ScenarioValidationMessage.LogWindowBelowMinimum(logWindow))
        }

        // Inference count estimation
        val estimated = InferenceEstimator.estimateInferenceCount(scenario)

        if (estimated > 100) {
            // The clamp only affects the *displayed* number, and only above
            // `Int.MAX_VALUE` — the throw already fired on `> 100`. The Models
            // message mirror is 1:1 with the 53 Swift cases (#1464) and is
            // deliberately not widened to `Long` for this one arg, so a
            // scenario whose estimate overflows an `Int` reports a clamped
            // count in a message that already says "too many".
            throw validationError(
                ScenarioValidationMessage.EstimatedInferencesExceedsMaximum(estimated.clampToInt()),
            )
        }

        validatePhases(scenario)

        val warnings = mutableListOf<String>()
        if (estimated > 50) {
            // Unreachable clamp, kept purely defensively: this branch fires only
            // for 51…100, so the value always fits an `Int`. It exists so the
            // call shape matches the sibling above and cannot start truncating
            // if the band ever widens.
            warnings.add(
                ScenarioValidationMessage.HighInferenceCount(estimated.clampToInt()).render(),
            )
        }

        return ValidationResult(warnings = warnings, estimatedInferences = estimated)
    }

    /**
     * Per-phase semantic checks beyond execution-limit validation.
     *
     * Covers `assign` target/source shape compatibility and `conditional` branch
     * well-formedness. Unknown `target` values are caught earlier by
     * `ScenarioLoader` (compile-time enforced via [AssignTarget]).
     *
     * The `when` is deliberately `else`-free so a new [PhaseType] fails to
     * compile here rather than silently skipping its shape check.
     */
    private fun validatePhases(scenario: Scenario) {
        scenario.phases.forEachIndexed { index, phase ->
            val label = "Phase ${index + 1}"
            validateOutputFieldNames(phase, label)
            validateMaxSentences(phase, label)
            when (phase.type) {
                PhaseType.ASSIGN ->
                    validateAssignPhaseShape(phase, "$label (assign)", scenario)
                PhaseType.CONDITIONAL ->
                    validateConditionalPhase(phase, index, scenario, depth = 0)
                PhaseType.REFLECT -> validateReflectShape(phase, label)
                PhaseType.WHISPER -> validateWhisperShape(phase, label)
                // `NARRATE` needs no shape check: its output schema is
                // Engine-fixed (`{ commentary }`, built by `NarrateHandler`),
                // not author-declared, so there is no `output:` block or
                // `logic`/`source`/`target` to validate.
                PhaseType.SPEAK_ALL,
                PhaseType.SPEAK_EACH,
                PhaseType.VOTE,
                PhaseType.CHOOSE,
                PhaseType.SCORE_CALC,
                PhaseType.ELIMINATE,
                PhaseType.SUMMARIZE,
                PhaseType.NARRATE,
                -> Unit
                PhaseType.RELATIONSHIP_UPDATE -> validateRelationshipUpdateShape(phase, label)
                PhaseType.EVENT_INJECT ->
                    validateEventInjectShape(phase, "$label (event_inject)", scenario)
            }
        }
    }

    /**
     * Enforces the accepted range (1…6) for a phase's `max_sentences` override
     * (#881). Called at both traversal sites ([validatePhases] and
     * [validateBranch]) so a nested `then:` / `else:` sub-phase is checked too.
     * A `null` override (the common case) is a no-op. The upper bound doubles as
     * a latency / JSON-stability guard — the model tops out ~3–4 sentences even
     * at cap 6 (#881 Stage-0 spike), so higher values are meaningless.
     */
    private fun validateMaxSentences(phase: Phase, label: String) {
        val value = phase.maxSentences ?: return
        if (value !in 1..6) {
            throw validationError(
                ScenarioValidationMessage.MaxSentencesOutOfRange(label = label, value = value),
            )
        }
    }

    /**
     * Enforces the conditional-phase invariants that the construction-time
     * [Phase] constructor cannot express:
     * - `condition` must be non-empty (an empty expression would throw at
     *   evaluator parse time anyway, but failing fast here is clearer).
     * - At least one of `thenPhases` / `elsePhases` must be non-empty (otherwise
     *   the phase is a no-op with extra overhead).
     * - `depth > 0` blocks nested `conditional` — the loader has the same check
     *   on the YAML path, and this covers non-YAML construction (tests, editors,
     *   future migrations).
     */
    private fun validateConditionalPhase(
        phase: Phase,
        index: Int,
        scenario: Scenario,
        depth: Int,
    ) {
        val phaseLabel = "Phase ${index + 1} (conditional)"
        val trimmedCondition = (phase.condition ?: "").trim()
        if (trimmedCondition.isEmpty()) {
            throw validationError(ScenarioValidationMessage.ConditionalMissingIf(phaseLabel))
        }

        // Parse-only pre-flight: malformed `if:` (mismatched parens, dangling
        // combinator, empty operand) surfaces here at scenario-load time rather
        // than mid-simulation when the handler dispatches. Critical for gallery
        // curation — a bad `if:` in a curated scenario would otherwise only fail
        // when a user runs it.
        try {
            ConditionEvaluator().parse(trimmedCondition)
        } catch (e: SimulationException) {
            val error = e.error
            if (error is SimulationError.ScenarioValidationFailed) {
                // Raw interpolation is deliberate here (not a
                // `ScenarioValidationMessage` case): this only prefixes the
                // phase locator onto a string `ConditionEvaluator.parse` has
                // already rendered. There is no new translatable literal to
                // extract, so a future i18n sweep skips it.
                throw SimulationException(
                    SimulationError.ScenarioValidationFailed("$phaseLabel: ${error.message}"),
                )
            }
            throw e
        }

        val thenCount = phase.thenPhases?.size ?: 0
        val elseCount = phase.elsePhases?.size ?: 0
        if (thenCount == 0 && elseCount == 0) {
            throw validationError(ScenarioValidationMessage.ConditionalEmptyBranches(phaseLabel))
        }

        if (depth > 0) {
            throw validationError(
                ScenarioValidationMessage.NestedConditionalNotAllowed(phaseLabel),
            )
        }

        validateBranch(phase.thenPhases.orEmpty(), phaseLabel, "then", scenario)
        validateBranch(phase.elsePhases.orEmpty(), phaseLabel, "else", scenario)
    }

    /**
     * Recursively validates each sub-phase in a conditional branch.
     *
     * Rejects nested `conditional` (depth-1 rule), `reflect`, `whisper`,
     * `relationship_update`, and `narrate` (none supported inside a branch in
     * v1), and applies the same semantic checks we run at the top level — e.g.
     * an `assign` phase with mismatched target/source shape still errors when
     * buried inside a `then:` or `else:` branch. `event_inject` is allowed
     * inside a branch (consistent with assign / score_calc) and gets the same
     * shape-check it would receive at the top level.
     */
    private fun validateBranch(
        phases: List<Phase>,
        parentLabel: String,
        branchLabel: String,
        scenario: Scenario,
    ) {
        phases.forEachIndexed { subIndex, subPhase ->
            val subLabel = "$parentLabel $branchLabel[${subIndex + 1}]"
            validateOutputFieldNames(subPhase, subLabel)
            validateMaxSentences(subPhase, subLabel)
            when (subPhase.type) {
                PhaseType.CONDITIONAL ->
                    throw validationError(
                        ScenarioValidationMessage.BranchNestedConditional(subLabel),
                    )
                // `reflect` is not supported inside a conditional branch in v1.
                // Reject at load-time validation (mirroring the
                // nested-conditional rule above) so it fails here rather than at
                // `ConditionalHandler` dispatch.
                PhaseType.REFLECT ->
                    throw validationError(
                        ScenarioValidationMessage.BranchReflectNotAllowed(subLabel),
                    )
                // `whisper` is likewise not supported inside a conditional
                // branch in v1 (mirrors the reflect rejection above).
                PhaseType.WHISPER ->
                    throw validationError(
                        ScenarioValidationMessage.BranchWhisperNotAllowed(subLabel),
                    )
                // `relationship_update` is likewise not supported inside a
                // conditional branch in v1; it is also omitted from
                // `ConditionalHandler.subHandlers` as a structural backstop.
                PhaseType.RELATIONSHIP_UPDATE ->
                    throw validationError(
                        ScenarioValidationMessage.BranchRelationshipUpdateNotAllowed(subLabel),
                    )
                // `narrate` is likewise not supported inside a conditional
                // branch in v1 (#909): it is omitted from
                // `ConditionalHandler.subHandlers`, so without this load-gate
                // rejection a branch-nested narrate would pass all validation
                // and then throw mid-run at dispatch (deferred failure).
                PhaseType.NARRATE ->
                    throw validationError(
                        ScenarioValidationMessage.BranchNarrateNotAllowed(subLabel),
                    )
                PhaseType.ASSIGN -> validateAssignPhaseShape(subPhase, subLabel, scenario)
                PhaseType.EVENT_INJECT -> validateEventInjectShape(subPhase, subLabel, scenario)
                PhaseType.SPEAK_ALL,
                PhaseType.SPEAK_EACH,
                PhaseType.VOTE,
                PhaseType.CHOOSE,
                PhaseType.SCORE_CALC,
                PhaseType.ELIMINATE,
                PhaseType.SUMMARIZE,
                -> Unit
            }
        }
    }

    /**
     * Requires reflect phases to declare the canonical `note` output at the RUN
     * gate ([validate]), not just the commit gate.
     *
     * Other LLM phases run schema-less in degraded-but-visible form (their
     * primary text lands in the conversation log as empty prose), but a reflect
     * phase without `note` is a pure no-op inference — it burns one call per
     * agent per round and stores nothing, with no user-visible symptom to debug
     * from. Failing fast at the run gate is friendlier. Reuses the commit-gate
     * message so both gates read identically.
     */
    private fun validateReflectShape(phase: Phase, label: String) {
        if (phase.outputSchema.orEmpty()["note"] == null) {
            throw validationError(
                ScenarioValidationMessage.RequiresOutputField(
                    label = label,
                    type = phase.type.serialName(),
                    field = "note",
                ),
            )
        }
    }

    /**
     * Requires whisper phases to declare the canonical `statement` output at the
     * RUN gate ([validate]), mirroring [validateReflectShape]'s rationale.
     *
     * A whisper without `statement` burns one inference per participant per pair
     * per round and stores nothing user-visible — the same no-op-inference
     * failure mode reflect guards against, so it fails fast here at the run gate
     * rather than degrading silently. Reuses the shared missing-field message.
     */
    private fun validateWhisperShape(phase: Phase, label: String) {
        if (phase.outputSchema.orEmpty()["statement"] == null) {
            throw validationError(
                ScenarioValidationMessage.RequiresOutputField(
                    label = label,
                    type = phase.type.serialName(),
                    field = "statement",
                ),
            )
        }
    }

    /**
     * Requires relationship_update phases to declare at least one affinity rule
     * (`vote_against` and/or a non-empty `action_deltas`) at the RUN gate.
     *
     * A phase with neither rule is a pure no-op: it reads its vote / choose
     * signals, applies zero deltas, and injects an empty summary — burning a
     * phase slot with no user-visible effect (the same no-op failure mode
     * [validateReflectShape] guards against). Failing fast here surfaces the
     * authoring mistake instead of a silently inert phase (#910).
     */
    private fun validateRelationshipUpdateShape(phase: Phase, label: String) {
        val hasVoteRule = phase.voteAgainst != null
        val hasActionRule = phase.actionDeltas.orEmpty().isNotEmpty()
        if (!hasVoteRule && !hasActionRule) {
            throw validationError(
                ScenarioValidationMessage.RelationshipUpdateMissingRule(
                    label = label,
                    type = phase.type.serialName(),
                ),
            )
        }
    }

    /**
     * Shared shape-check for assign phases, callable from both the top-level and
     * the nested branch paths.
     *
     * The `when`s over [AnyCodableValue] are `else`-free so a new shape has to
     * be dispositioned here rather than silently accepted.
     */
    private fun validateAssignPhaseShape(phase: Phase, label: String, scenario: Scenario) {
        // Phases without a `source` reference persona indices instead of
        // extraData — nothing to shape-check.
        val sourceKey = phase.source ?: return

        // The Visual Editor round-trips extraData (#129), so a missing key here
        // means the scenario YAML genuinely lacks the referenced field — the
        // assign would silently no-op at runtime. Surface it early.
        val sourceValue = scenario.extraData[sourceKey]
            ?: throw validationError(
                ScenarioValidationMessage.SourceNotFound(label = label, source = sourceKey),
            )
        when (phase.target ?: AssignTarget.ALL) {
            AssignTarget.ALL -> when (sourceValue) {
                is AnyCodableValue.ArrayValue, is AnyCodableValue.StringValue -> Unit
                is AnyCodableValue.ArrayOfDictionariesValue,
                is AnyCodableValue.DictionaryValue,
                -> throw validationError(
                    ScenarioValidationMessage.AssignSourceGroupedForAll(
                        label = label,
                        source = sourceKey,
                    ),
                )
            }
            AssignTarget.RANDOM_ONE -> when (sourceValue) {
                is AnyCodableValue.ArrayOfDictionariesValue -> Unit
                is AnyCodableValue.ArrayValue,
                is AnyCodableValue.StringValue,
                is AnyCodableValue.DictionaryValue,
                -> throw validationError(
                    ScenarioValidationMessage.AssignSourceNotGroupedForRandomOne(
                        label = label,
                        source = sourceKey,
                    ),
                )
            }
        }
    }

    /**
     * Shared shape-check for event_inject phases, callable from both the
     * top-level path and from inside a conditional branch.
     *
     * Enforces:
     * - `source` must be present and non-empty (the handler's no-op fallback
     *   exists for the case where extraData lookup fails at runtime, but a
     *   curator who wrote `event_inject` clearly meant to fire — failing fast at
     *   validation is friendlier).
     * - `extraData[source]` must be [AnyCodableValue.ArrayValue] (a list of
     *   strings) or [AnyCodableValue.ArrayOfDictionariesValue] (a list of
     *   `{ text, favors }` mappings, #931 — each entry needs a non-empty `text`;
     *   `favors` is optional). String / dictionary shapes are rejected; the
     *   error message points at the workaround so curators don't get stuck.
     * - `probability` (when set) must lie in `[0.0, 1.0]`. The handler would
     *   still produce well-defined behavior outside this range (`< 0` never
     *   fires, `>= 1.0` always fires), but a curator who wrote
     *   `probability: 1.5` almost certainly mistyped — surfacing it early is
     *   friendlier than silent over-fire.
     */
    private fun validateEventInjectShape(phase: Phase, label: String, scenario: Scenario) {
        val sourceKey = (phase.source ?: "").trim()
        if (sourceKey.isEmpty()) {
            throw validationError(ScenarioValidationMessage.EventInjectMissingSource(label))
        }
        val sourceValue = scenario.extraData[sourceKey]
            ?: throw validationError(
                ScenarioValidationMessage.SourceNotFound(label = label, source = sourceKey),
            )
        when (sourceValue) {
            is AnyCodableValue.ArrayValue ->
                // An empty array silently produces probability-miss-equivalent
                // output at runtime (the handler writes "" and emits
                // `EventInjected(null)`), which a curator cannot distinguish
                // from a string of unlucky rolls. Reject early so the
                // misconfiguration surfaces at scenario load.
                if (sourceValue.value.isEmpty()) {
                    throw validationError(
                        ScenarioValidationMessage.EventInjectSourceEmptyStrings(
                            label = label,
                            source = sourceKey,
                        ),
                    )
                }
            is AnyCodableValue.ArrayOfDictionariesValue ->
                validateDictEventEntries(sourceValue.value, sourceKey, label)
            is AnyCodableValue.StringValue, is AnyCodableValue.DictionaryValue ->
                throw validationError(
                    ScenarioValidationMessage.EventInjectSourceWrongShape(
                        label = label,
                        source = sourceKey,
                    ),
                )
        }
        validateEventProbability(phase.probability, label)
    }

    /**
     * Dict-shaped events (`{ text, favors }`, #931). Same empty-list rejection
     * as the string shape, plus each entry must carry a non-empty `text` — an
     * entry without it injects "" (a silent no-op). `favors` is optional (an
     * untagged entry simply scores no reward).
     */
    private fun validateDictEventEntries(
        entries: List<Map<String, String>>,
        sourceKey: String,
        label: String,
    ) {
        if (entries.isEmpty()) {
            throw validationError(
                ScenarioValidationMessage.EventInjectSourceEmptyEvents(
                    label = label,
                    source = sourceKey,
                ),
            )
        }
        if (entries.any { (it["text"] ?: "").trim().isEmpty() }) {
            throw validationError(
                ScenarioValidationMessage.EventInjectEntryMissingText(
                    label = label,
                    source = sourceKey,
                ),
            )
        }
    }

    /**
     * `probability` (when set) must lie in `[0.0, 1.0]` — see the rationale on
     * [validateEventInjectShape].
     *
     * `!in 0.0..1.0` is a [ClosedFloatingPointRange] membership test, so NaN
     * falls outside and throws, matching Swift's `(0.0...1.0).contains`.
     */
    private fun validateEventProbability(probability: Double?, label: String) {
        val value = probability ?: return
        if (value !in 0.0..1.0) {
            throw validationError(
                ScenarioValidationMessage.EventInjectProbabilityOutOfRange(
                    label = label,
                    probability = value.toString(),
                ),
            )
        }
    }

    /**
     * Rejects any `output:` field name that is not an ASCII identifier
     * ([ScenarioConventions.isValidFieldName]).
     *
     * Every output key is emitted verbatim as a JSON-key literal into the
     * LLM-phase GBNF grammar by `GBNFGrammarBuilder`. A non-ASCII / multi-byte
     * key reaches llama.cpp's sampler as a literal and crashes it at accept-time
     * on-device — an uncatchable SIGABRT, the same mechanism that forced CJK
     * choose-option *values* out of the grammar in #599 (#607). Surfacing it
     * here (run gate + editor) gives a clear load-time error instead of a
     * mid-run grammar failure; the builder's own check stays as the
     * unconditional backstop for paths that skip this gate.
     *
     * Validates **every** key, not just the canonical primary — all output keys
     * reach the grammar, so a CJK *secondary* key (`inner_thought` / `reason`)
     * is just as dangerous as the primary. Keys are sorted so the surfaced error
     * is deterministic across runs.
     */
    private fun validateOutputFieldNames(phase: Phase, label: String) {
        val schema = phase.outputSchema ?: return
        val invalid = schema.keys.sorted().firstOrNull { !ScenarioConventions.isValidFieldName(it) }
            ?: return
        throw validationError(
            ScenarioValidationMessage.OutputFieldNameInvalid(label = label, name = invalid),
        )
    }

    private fun acceptedLanguagesList(): String =
        Scenario.ACCEPTED_LANGUAGES.sorted().joinToString(", ")
}

/**
 * Wraps a [ScenarioValidationMessage] in
 * [SimulationError.ScenarioValidationFailed], rendering it at the Models layer
 * so the Engine run path carries no string formatting of its own.
 *
 * File-scope rather than a method, mirroring the Swift original — which is
 * file-scope so it stays out of `ScenarioValidator`'s SwiftLint
 * `type_body_length` budget and does not collide with `ScenarioLoader`'s
 * same-named helper at module scope.
 */
private fun validationError(message: ScenarioValidationMessage): SimulationException =
    SimulationException(SimulationError.ScenarioValidationFailed(message.render()))

/**
 * Narrows a `Long` inference estimate to the `Int` the Models message mirror
 * carries. See the two call sites in [ScenarioValidator.validate] for what the
 * clamp does and does not affect in each case.
 */
private fun Long.clampToInt(): Int = coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
