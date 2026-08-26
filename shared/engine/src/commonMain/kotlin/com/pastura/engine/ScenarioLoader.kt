package com.pastura.engine

import com.pastura.models.AnyCodableValue
import com.pastura.models.AssignTarget
import com.pastura.models.PairingStrategy
import com.pastura.models.PayoffRule
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScenarioValidationMessage
import com.pastura.models.ScoreCalcLogic
import com.pastura.models.SimulationError
import com.pastura.models.YamlCodec
import com.pastura.models.YamlDecodeError
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Parses YAML scenario definitions into [Scenario] models.
 *
 * Kotlin port of the YAML-ingest and top-level-mapping half of
 * `Pastura/Pastura/Engine/ScenarioLoader.swift` (ADR-023 §4, the "Load +
 * validate" row). The Swift file's `estimateInferenceCount` / `estimatePhase`
 * pair landed separately as [InferenceEstimator], so `ScenarioLoader.swift` is a
 * **1 Swift file → 2+ Kotlin files** `SPLIT` row in
 * `shared/adr-023-port-ledger.tsv`; the coverage gate verifies those paths are
 * tracked, not that an edit on either side was mirrored.
 *
 * Like the Swift original, [load] enforces structural mapping plus a narrow band
 * of construct-time invariants (accepted-`language` / `simulation_language`
 * membership, `personas` count matching `agents`) and does **not** run
 * [ScenarioValidator]'s execution-limit / inference-cap / phase-semantic gate —
 * the returned scenario is well-formed but not yet known to be runnable.
 *
 * ## Not wired into the engine
 *
 * Nothing in `shared/engine` calls this, deliberately — the same posture as
 * [ScenarioValidator]. ADR-023 §4 puts the preflight gate on the validator
 * **and** `ScenarioSemanticLinter` (ADR-024) together, and the linter is
 * unported, so `DivergenceLedger.DivergenceClass.VALIDATOR_UNPORTED` still
 * stands.
 *
 * ## Why a hand-written walk over [JsonElement]
 *
 * The tree comes from `YamlCodec.default().decode(yaml)`; the mapping below is
 * hand-written rather than `Json.decodeFromJsonElement(Scenario.serializer(), …)`.
 * A serializer-driven decode would fork parity twice over: its wire keys are
 * camelCase (`Scenario`'s KDoc — preset YAML is snake_case), and its errors and
 * strictness are kotlinx's, not the Swift loader's
 * [ScenarioValidationMessage] vocabulary that the iOS UI renders today.
 *
 * ## Known divergences from Swift
 *
 * All are **documented, not ledgered**, on PR B1's standing reason: a scenario
 * this loader rejects produces no run and therefore no parity transcript to
 * compare (`DivergenceClass.VALIDATOR_UNPORTED`).
 *
 * 1. **Two YAML-1.1 typed scalars resolve differently.** Measured on both
 *    engines: `12:30:00` (sexagesimal) resolves to `Int 45000` under Yams and
 *    stays a `String` under snakeyaml-engine's YAML 1.2 core schema;
 *    `2026-08-26` resolves to a `Date` under Yams and stays a `String` here.
 *    The consequences are **not** symmetric, so state them per scalar rather
 *    than as one rule: in a `String`-typed field both are rejected by Swift and
 *    accepted here; in an `Int`-typed field `12:30:00` is accepted by Swift and
 *    rejected here, while `2026-08-26` is rejected by **both** (a `Date` fails
 *    `as? Int` too) and only the `got:` fragment differs. Deliberately **not**
 *    closed: closing it means regex-sniffing every plain scalar for ISO dates
 *    and sexagesimals, which risks rejecting legitimate curator text, for an
 *    input shape no bundled preset or gallery scenario uses.
 * 2. **YAML-1.1 boolean tokens are re-accepted loader-locally.** `yes` / `no` /
 *    `on` / `off` (and their `Yes` / `YES` case variants) resolve to `Bool`
 *    under Yams and to `String` here, so [YamlType.BOOL] maps that token set
 *    back to a boolean where a boolean is expected. `y` / `n` are **excluded**:
 *    both engines already agree they are `String` (libyaml's bool set does not
 *    contain them), so accepting them would open a *new* divergence rather than
 *    close one. This is the loader's decision alone — `YamlCodec`'s YAML 1.2
 *    contract and its `LoadSettings` are untouched.
 *
 *    The cost is two over-acceptances, in **opposite** directions, because the
 *    token map is consulted only by [YamlType.BOOL]:
 *    - a **quoted** `"yes"` in a `Bool` field reads as a boolean here (snakeyaml
 *      erases the quoted/plain distinction for a token it resolves to `String`)
 *      while Swift keeps it a `String` and rejects;
 *    - a **plain** `yes` in a `String`-typed field — `narrator: no`,
 *      `options: [yes, no]` — stays a string here and is accepted, while Yams
 *      hands Swift a `Bool` whose `as? String` / `as? [String]` fails and the
 *      scenario is rejected. This is the likelier one in real curator YAML.
 *
 *    `ScenarioLoaderTests.divergesOnQuotedYesExcludeSelf` pins the first of the
 *    two, so the behaviour cannot drift without this entry being revisited.
 * 3. **Type-name rendering.** The `expected:` / `got:` fragments come from
 *    [YamlType.rendered] and [renderActualType] — see [renderActualType] for
 *    where they part company with Swift's `String(describing: type(of:))`.
 * 4. **`Int` is 32-bit here and 64-bit in Swift.** An integral scalar inside
 *    `Long` range but outside `Int.MIN_VALUE..Int.MAX_VALUE` is a
 *    [ScenarioValidationMessage.FieldWrongType] rather than an accepted value.
 *    Truncating instead would be worse than a divergence — it would silently run
 *    a different scenario. Every field reusing [YamlType.INT]'s cast inherits
 *    this, so it reaches the phase-level integral fields too, only under a
 *    different message: an out-of-range `payoff:` row `points` element reports
 *    [ScenarioValidationMessage.PayoffRowInvalid] and an out-of-range
 *    `action_deltas` value reports
 *    [ScenarioValidationMessage.ActionDeltasValueNotInt], because those two
 *    helpers own their own vocabulary rather than routing through
 *    [parseOptional]. **Beyond `Long` range the failure changes shape**:
 *    `YamlCodec`'s `yamlValueToJson` handles `Int` / `Long` / `Float` / `Double`
 *    and nothing else, so the value raises `YamlDecodeError.UnsupportedScalar`,
 *    which [load] folds into
 *    [ScenarioValidationMessage.InvalidYAMLFormat] — a whole-document rejection
 *    that names no field, where Swift reports a field-level error.
 *    `ScenarioLoaderTests.throwsOnIntegerBeyondLongRange` pins that.
 * 5. **Whitespace trimming.** Swift trims `.whitespacesAndNewlines` (a Unicode
 *    character set), Kotlin `trim()` trims `Char.isWhitespace()`. The two
 *    disagree on a handful of exotic code points, so a persona `secret:` padded
 *    with one of them could normalize to `null` on one side only. Same family as
 *    [ScenarioValidator]'s divergence 3. [stripCodeFences] is a second trim site
 *    with a *narrower* Swift set — `.whitespaces`, no `\v` / `\f` / `` —
 *    so a fence line indented with one of those is stripped here and kept there.
 * 6. **Which offending key gets reported.** `collectExtraData` throws on the
 *    first offending key in `JsonObject` insertion order; Swift iterates a
 *    `Dictionary`, whose order is unspecified. Both reject the same scenarios;
 *    only the key named in the message can differ.
 *
 * ## `validationError` is re-declared here on purpose
 *
 * `ScenarioValidator.kt` has its own file-private `validationError`, and so does
 * this file — mirroring the Swift originals, where each of `ScenarioLoader.swift`
 * and `ScenarioValidator.swift` declares a file-private helper of that name. It
 * is duplication by design, not a missed extraction: a shared module-scope
 * helper would be a third public-ish surface in `com.pastura.engine` for two call
 * sites of one line.
 */
public class ScenarioLoader {

    /**
     * Parses [yaml] into a [Scenario].
     *
     * The **only** `public` member of this file. Every helper below is
     * `internal` or `private`, so no `kotlinx.serialization` type reaches the
     * exported Obj-C header — which nothing would otherwise catch: a leaked
     * type does not fail the K/N link (see `shared/engine/build.gradle.kts` on
     * the 48 leaked coroutine symbols measured under BUILD SUCCESSFUL) and
     * `verifyEngineFrameworkSurface` inspects coroutine types only.
     *
     * `@Throws` is load-bearing at the K/N boundary, not decoration: a Kotlin
     * exception thrown from an **un-annotated** exported function is not
     * surfaced to Swift as a catchable error — it terminates the calling
     * process (`.claude/rules/kmp-interop.md` Pattern 5). This declaration's
     * `swift_name("load(yaml:)")` is pinned in `exportedThrowingSelectors`,
     * which asserts the generated header really carries the `error:` parameter.
     *
     * Code fences are stripped first, so LLM-generated YAML wrapped in
     * ```` ```yaml ```` parses without pre-cleaning by the caller.
     *
     * @param yaml raw YAML text, possibly wrapped in markdown code fences.
     * @return a structurally-mapped [Scenario] (not run-validated).
     * @throws SimulationException carrying
     *   [SimulationError.ScenarioValidationFailed] on a YAML parse error or a
     *   construct-time invariant violation (wrong field type, unknown
     *   `language`, persona/agent mismatch, malformed phase shape).
     */
    @Throws(SimulationException::class)
    public fun load(yaml: String): Scenario {
        val stripped = stripCodeFences(yaml)

        // Both halves of Swift's `guard let raw = try? Yams.load(...), let dict
        // = raw as? [String: Any]` fold to the same message: a decode failure,
        // and a root that is not a mapping. An empty or blank document decodes
        // to JsonNull and a sequence root to JsonArray, so both land here too.
        // The parser's own reason is deliberately dropped:
        // `InvalidYAMLFormat` is a fixed localized string on both sides, so
        // folding a snakeyaml-specific message into it would diverge from Swift
        // while telling the curator nothing they can act on.
        val root: JsonElement = try {
            YamlCodec.default().decode(stripped)
        } catch (@Suppress("SwallowedException") ignored: YamlDecodeError) {
            throw validationError(ScenarioValidationMessage.InvalidYAMLFormat)
        }
        val dict = root as? JsonObject
            ?: throw validationError(ScenarioValidationMessage.InvalidYAMLFormat)

        return mapToScenario(dict)
    }

    // MARK: - Private

    /** Removes markdown code fences that LLMs sometimes wrap around YAML. */
    private fun stripCodeFences(text: String): String =
        text.split("\n").filterNot { it.trim().startsWith("```") }.joinToString("\n")

    /**
     * Extracts a required field of exact type [T] from a YAML mapping.
     *
     * Distinguishes *missing* from *present-but-wrong-type* so users can tell
     * whether to add the field or re-type it, and names the actual decoded type
     * so `agents: "2"` reports `field 'agents' must be Int, got String` instead
     * of a misleading "missing required field".
     *
     * An **explicit** `key: ~` / `key: null` / bare `key:` decodes to [JsonNull],
     * which is a present key holding a value of the wrong type — never an absent
     * one. That asymmetry is the point: reading it as absent is exactly the
     * silent-coerce class tracked in #130, and it matches Swift, where `NSNull`
     * fails every `as? T`.
     *
     * No type coercion beyond the one [YamlType.BOOL] documents.
     */
    private fun <T> parseRequired(
        dict: JsonObject,
        key: String,
        label: String,
        type: YamlType<T>,
    ): T {
        val raw = dict[key]
            ?: throw validationError(
                ScenarioValidationMessage.MissingRequiredField(label = label, key = key),
            )
        return type.cast(raw) ?: throw validationError(
            ScenarioValidationMessage.FieldWrongType(
                label = label,
                key = key,
                expected = type.rendered,
                got = renderActualType(raw),
            ),
        )
    }

    /**
     * Extracts an optional field of exact type [T] from a YAML mapping.
     *
     * Returns `null` when the key is **absent**. Throws when it is
     * present-but-wrong-type — unlike a bare `as?`, which would coerce to `null`
     * and let the caller's default silently kick in (#130). See [parseRequired]
     * for why an explicit `key: ~` throws rather than reading as absent.
     */
    private fun <T> parseOptional(
        dict: JsonObject,
        key: String,
        label: String,
        type: YamlType<T>,
    ): T? {
        val raw = dict[key] ?: return null
        return type.cast(raw) ?: throw validationError(
            ScenarioValidationMessage.FieldWrongType(
                label = label,
                key = key,
                expected = type.rendered,
                got = renderActualType(raw),
            ),
        )
    }

    /**
     * Extracts an optional `Double` field, accepting an integral scalar and
     * widening it.
     *
     * Intentional exception to the project-wide #130 strict-no-coerce stance.
     * The `event_inject` phase's `probability` is the first natural-decimal
     * `Double?` field on [Phase], and in YAML the boundary cases are most
     * ergonomically written `0` / `1`; forcing `0.0` / `1.0` would surface a
     * parser bridging quirk for no curator-visible benefit.
     *
     * The window is strictly integral → `Double`, not "anything resembling a
     * number": a quoted scalar, a boolean, or any collection throws
     * [ScenarioValidationMessage.FieldNotDoubleOrInt]. Booleans are excluded
     * explicitly because Swift's `as? Int` launders one, which is the
     * type-laundering bug this whole helper family exists to prevent.
     */
    private fun parseOptionalDoubleAcceptingInt(
        dict: JsonObject,
        key: String,
        label: String,
    ): Double? {
        val raw = dict[key] ?: return null
        val number = (raw as? JsonPrimitive)
            ?.takeIf { it !is JsonNull && !it.isString && !it.isYamlBooleanLiteral() }
            ?.content
            ?.toDoubleOrNull()
        return number ?: throw validationError(
            ScenarioValidationMessage.FieldNotDoubleOrInt(
                label = label,
                key = key,
                got = renderActualType(raw),
            ),
        )
    }

    /** Maps a raw YAML mapping to a [Scenario]. */
    private fun mapToScenario(dict: JsonObject): Scenario {
        val id = parseRequired(dict, "id", SCENARIO_LABEL, YamlType.STRING)
        val name = parseRequired(dict, "name", SCENARIO_LABEL, YamlType.STRING)
        val description = parseRequired(dict, "description", SCENARIO_LABEL, YamlType.STRING)
        val language = parseRequired(dict, "language", SCENARIO_LABEL, YamlType.STRING)
        if (language !in Scenario.ACCEPTED_LANGUAGES) {
            throw validationError(
                ScenarioValidationMessage.LanguageNotAccepted(
                    allowed = acceptedLanguagesList(),
                    got = language,
                ),
            )
        }
        val simulationLanguage =
            parseOptional(dict, "simulation_language", SCENARIO_LABEL, YamlType.STRING)
        if (simulationLanguage != null && simulationLanguage !in Scenario.ACCEPTED_LANGUAGES) {
            throw validationError(
                ScenarioValidationMessage.SimulationLanguageYAMLNotAccepted(
                    allowed = acceptedLanguagesList(),
                    got = simulationLanguage,
                ),
            )
        }
        val agentCount = parseRequired(dict, "agents", SCENARIO_LABEL, YamlType.INT)
        val rounds = parseRequired(dict, "rounds", SCENARIO_LABEL, YamlType.INT)
        val context = parseRequired(dict, "context", SCENARIO_LABEL, YamlType.STRING)
        // Optional prompt-side conversation-log cap (#907). Strict-Int parse
        // (mirrors `agents` / `rounds`): a quoted number or other type errors
        // rather than silently coercing. The `>= 1` bound is ScenarioValidator's.
        val logWindow = parseOptional(dict, "log_window", SCENARIO_LABEL, YamlType.INT)

        val personasRaw = parseRequired(dict, "personas", SCENARIO_LABEL, YamlType.OBJECT_LIST)
        val phasesRaw = parseRequired(dict, "phases", SCENARIO_LABEL, YamlType.OBJECT_LIST)

        val personas = personasRaw.map { mapPersona(it) }
        if (personas.size != agentCount) {
            throw validationError(
                ScenarioValidationMessage.AgentsPersonasCountMismatch(
                    agentCount = agentCount,
                    personaCount = personas.size,
                ),
            )
        }

        val phases = phasesRaw.mapIndexed { index, raw -> mapPhase(raw, index) }

        return Scenario(
            id = id,
            name = name,
            description = description,
            language = language,
            simulationLanguage = simulationLanguage,
            agentCount = agentCount,
            rounds = rounds,
            logWindow = logWindow,
            context = context,
            personas = personas,
            phases = phases,
            extraData = collectExtraData(dict),
        )
    }

    /**
     * Collects non-standard top-level keys as extra data. Throws on unsupported
     * shapes rather than silently dropping them — a typo like `count: 42`
     * (auto-typed integral) used to disappear from the returned map.
     */
    private fun collectExtraData(dict: JsonObject): Map<String, AnyCodableValue> =
        dict.entries
            .filterNot { it.key in STANDARD_KEYS }
            .associate { (key, value) -> key to convertToAnyCodableValue(value, key) }

    private fun mapPersona(dict: JsonObject): Persona {
        val name = parseRequired(dict, "name", PERSONA_LABEL, YamlType.STRING)
        val description =
            parseOptional(dict, "description", PERSONA_LABEL, YamlType.STRING) ?: ""
        // Empty ≡ absent everywhere (#914): normalizing here keeps the Swift
        // patcher's `reparsed == visual` safety net from permanently falling
        // back on a scenario authored with `secret: ""`. Trim before the check
        // so this matches the editor boundary's rule (`EditablePersona
        // .toPersona()`) — a whitespace-only secret would otherwise survive here
        // but map to null there, rendering a header-only prompt section.
        val secret = parseOptional(dict, "secret", PERSONA_LABEL, YamlType.STRING)?.trim()
        return Persona(
            name = name,
            description = description,
            secret = if (secret.isNullOrEmpty()) null else secret,
        )
    }

    /**
     * Resolves the `assign` phase's `target:` against [AssignTarget]'s
     * `@SerialName` values. Strict-throw on an unknown value, mirroring
     * [parsePhaseType] (issue #108 / #211).
     *
     * A **wrong-typed** value routes through [parseOptional] first, exactly as
     * Swift's `parseOptional<String>` does, so `target: 3` reports the unified
     * [ScenarioValidationMessage.FieldWrongType] message and only a well-typed
     * but unrecognised string reaches
     * [ScenarioValidationMessage.InvalidTarget]. The order is the message the
     * curator sees; do not fold the two steps together.
     */
    private fun parseAssignTarget(dict: JsonObject, label: String): AssignTarget? {
        val str = parseOptional(dict, "target", label, YamlType.STRING) ?: return null
        return ASSIGN_TARGETS_BY_YAML_NAME[str]
            ?: throw validationError(
                ScenarioValidationMessage.InvalidTarget(label = label, value = str),
            )
    }

    /** Same shape as [parseAssignTarget], for a `choose` phase's `pairing:`. */
    private fun parsePairing(dict: JsonObject, label: String): PairingStrategy? {
        val str = parseOptional(dict, "pairing", label, YamlType.STRING) ?: return null
        return PAIRING_STRATEGIES_BY_YAML_NAME[str]
            ?: throw validationError(
                ScenarioValidationMessage.InvalidPairing(label = label, value = str),
            )
    }

    /**
     * Same shape as [parseAssignTarget], for a `score_calc` phase's `logic:`,
     * plus the `allowed:` fragment listing every accepted value.
     *
     * That fragment is **derived from the lookup map, never hand-written**:
     * [serialNameLookup]'s `associate` yields a `LinkedHashMap` in enum
     * declaration order, so this reaches the same string as Swift's
     * `ScoreCalcLogic.allCases.map(\.rawValue).joined(separator: ", ")`. A
     * hand-written list would be a second mirror no compiler checks; derived,
     * a sixth case joins the lookup and this message in one edit.
     */
    private fun parseLogic(dict: JsonObject, label: String): ScoreCalcLogic? {
        val str = parseOptional(dict, "logic", label, YamlType.STRING) ?: return null
        return SCORE_CALC_LOGICS_BY_YAML_NAME[str]
            ?: throw validationError(
                ScenarioValidationMessage.InvalidLogic(
                    label = label,
                    value = str,
                    allowed = SCORE_CALC_LOGICS_BY_YAML_NAME.keys.joinToString(", "),
                ),
            )
    }

    private fun mapPhase(dict: JsonObject, index: Int): Phase =
        mapPhase(dict, label = "Phase $index", depth = 0)

    /**
     * Maps one phase mapping.
     *
     * [label] is used in error messages: top-level calls pass `"Phase K"`, and
     * the nested calls from [mapBranch] pass `"Phase K.then[N]"` /
     * `"Phase K.else[N]"` so the user can locate the offending sub-phase in
     * their YAML. [depth] is `0` at top level; `>= 1` rejects a nested
     * `conditional` at parse time, which defends the depth-1 rule before
     * [ScenarioValidator] sees the scenario.
     */
    private fun mapPhase(dict: JsonObject, label: String, depth: Int): Phase {
        val phaseType = parsePhaseType(dict, label, depth)

        val prompt = parseOptional(dict, "prompt", label, YamlType.STRING)
        val template = parseOptional(dict, "template", label, YamlType.STRING)
        val source = parseOptional(dict, "source", label, YamlType.STRING)
        val excludeSelf = parseOptional(dict, "exclude_self", label, YamlType.BOOL)
        val options = parseOptional(dict, "options", label, YamlType.STRING_LIST)

        val target = parseAssignTarget(dict, label)
        val outputSchema = parseOutputSchema(dict, label)
        val pairing = parsePairing(dict, label)
        val logic = parseLogic(dict, label)

        // speak_each `rounds:` → subRounds (the scenario-level `rounds` is a
        // different key on a different mapping).
        val subRounds = parseOptional(dict, "rounds", label, YamlType.INT)

        // Conditional-specific fields (`if:` expression + `then:` / `else:`
        // sub-phase arrays). The branches descend with depth+1, so a nested
        // `conditional` is rejected by `parsePhaseType`.
        val condition = parseOptional(dict, "if", label, YamlType.STRING)
        val thenPhases = mapBranch(dict["then"], "then", label, depth)
        val elsePhases = mapBranch(dict["else"], "else", label, depth)

        // event_inject-specific fields. `probability` accepts an integral scalar
        // so the boundary literals `0` / `1` round-trip naturally; `as:` names
        // the variable the handler writes.
        val probability = parseOptionalDoubleAcceptingInt(dict, "probability", label)
        val eventVariable = parseOptional(dict, "as", label, YamlType.STRING)
        // Draw-without-replacement opt-in (#1006). Generic Bool path like
        // `exclude_self`; no validation needed — a bool is always well-formed.
        val noRepeat = parseOptional(dict, "no_repeat", label, YamlType.BOOL)

        // relationship_update-specific (#910). Both YAML-only — no visual
        // editing UI in v1 — but they round-trip through the editor's dual
        // buffer.
        val voteAgainst = parseOptional(dict, "vote_against", label, YamlType.INT)
        val actionDeltas = parseActionDeltas(dict, label)

        // Per-phase statement brevity override (#881). The 1..6 range is
        // ScenarioValidator's, not the loader's — `load` stays non-validating.
        val maxSentences = parseOptional(dict, "max_sentences", label, YamlType.INT)

        // narrate-specific (#909): a short voice/persona descriptor for the
        // commentator. Absent falls back to the Engine-owned default template.
        val narrator = parseOptional(dict, "narrator", label, YamlType.STRING)

        // pairwise_payoff table (ADR-027). YAML-only, round-tripping through
        // the editor's dual buffer like `narrator` / `action_deltas`. An absent
        // `payoff:` stays null — a guaranteed-no-op phase is the linter's to
        // flag, not a load throw; only a malformed *present* table throws.
        val payoff = parsePayoff(dict, label)

        // Every argument is named, mirroring the Swift original's call.
        return Phase(
            type = phaseType,
            prompt = prompt,
            outputSchema = outputSchema,
            options = options,
            pairing = pairing,
            logic = logic,
            template = template,
            source = source,
            target = target,
            excludeSelf = excludeSelf,
            subRounds = subRounds,
            maxSentences = maxSentences,
            condition = condition,
            thenPhases = thenPhases,
            elsePhases = elsePhases,
            probability = probability,
            eventVariable = eventVariable,
            voteAgainst = voteAgainst,
            actionDeltas = actionDeltas,
            noRepeat = noRepeat,
            narrator = narrator,
            payoff = payoff,
        )
    }

    /**
     * Parses the `payoff:` table for a `pairwise_payoff` `score_calc` phase — a
     * list of `{when: [String], points: [Int]}` rows (ADR-027). Strict on
     * arity: each `when` / `points` must hold exactly two elements. A malformed
     * row throws rather than silently scoring a wrong verdict at runtime.
     *
     * Mixed semantics, matching Swift's cast ladder: `payoff:` itself is
     * whole-collection ([YamlType.OBJECT_LIST], so a non-list names the key),
     * while each row is checked individually and reports its own index. The
     * `points` elements go through [YamlType.INT], which supplies the
     * boolean and quoted-scalar exclusions Swift's `as? Int` guards spell out
     * by hand (`!(value is Bool)`), plus the 32-bit range check of the class
     * KDoc's divergence 4.
     */
    private fun parsePayoff(dict: JsonObject, label: String): List<PayoffRule>? {
        val raw = dict["payoff"] ?: return null
        val list = YamlType.OBJECT_LIST.cast(raw)
            ?: throw validationError(
                ScenarioValidationMessage.PayoffNotList(
                    label = label,
                    got = renderActualType(raw),
                ),
            )
        return list.mapIndexed { index, row ->
            val actions = row["when"]
                ?.let { YamlType.STRING_LIST.cast(it) }
                ?.takeIf { it.size == 2 }
                ?: throw validationError(
                    ScenarioValidationMessage.PayoffRowInvalid(
                        label = label,
                        detail = "row $index 'when' must be 2 strings",
                    ),
                )
            val pointsRaw = (row["points"] as? JsonArray)?.takeIf { it.size == 2 }
                ?: throw validationError(
                    ScenarioValidationMessage.PayoffRowInvalid(
                        label = label,
                        detail = "row $index 'points' must be 2 ints",
                    ),
                )
            val points = pointsRaw.map { element ->
                YamlType.INT.cast(element)
                    ?: throw validationError(
                        ScenarioValidationMessage.PayoffRowInvalid(
                            label = label,
                            detail = "row $index 'points' has a non-Int value",
                        ),
                    )
            }
            PayoffRule(`when` = actions, points = points)
        }
    }

    /**
     * Parses the `action_deltas:` map for `relationship_update` phases — a
     * mapping of choose-action value → affinity delta. Strict per #130: a
     * non-Int value (`cooperate: "one"`) throws rather than silently coercing,
     * and [YamlType.INT] excludes booleans and quoted scalars for the same
     * reason Swift writes `!(value is Bool)` — `as? Int` launders one.
     *
     * **Deliberately not a [YamlType] whole-collection cast**, unlike the
     * `STRING_LIST` / `OBJECT_LIST` sites a few lines up: Swift's
     * `raw as? [String: Any]` succeeds on any mapping and then throws *per
     * offending key*, so the message names the key the curator must fix. Only a
     * non-mapping `raw` is whole-collection here.
     */
    private fun parseActionDeltas(dict: JsonObject, label: String): Map<String, Int>? {
        val raw = dict["action_deltas"] ?: return null
        val map = raw as? JsonObject
            ?: throw validationError(
                ScenarioValidationMessage.ActionDeltasNotDict(
                    label = label,
                    got = renderActualType(raw),
                ),
            )
        return map.entries.associate { (key, value) ->
            key to (
                YamlType.INT.cast(value)
                    ?: throw validationError(
                        ScenarioValidationMessage.ActionDeltasValueNotInt(
                            label = label,
                            key = key,
                            got = renderActualType(value),
                        ),
                    )
                )
        }
    }

    /**
     * Resolves the `type:` key against [PhaseType]'s `@SerialName` values.
     *
     * A missing key and a non-string one deliberately collapse to the same
     * [ScenarioValidationMessage.PhaseMissingType], mirroring the Swift
     * original's single `guard let … as? String` — the loader's only place where
     * missing and wrong-type are *not* distinguished.
     */
    private fun parsePhaseType(dict: JsonObject, label: String, depth: Int): PhaseType {
        val typeString = YamlType.STRING.cast(dict["type"] ?: JsonNull)
            ?: throw validationError(ScenarioValidationMessage.PhaseMissingType(label))
        val phaseType = PHASE_TYPES_BY_YAML_NAME[typeString]
            ?: throw validationError(
                ScenarioValidationMessage.PhaseInvalidType(label = label, value = typeString),
            )
        if (phaseType == PhaseType.CONDITIONAL && depth > 0) {
            throw validationError(ScenarioValidationMessage.NestedConditionalNotAllowed(label))
        }
        return phaseType
    }

    /**
     * Parses the `output:` schema mapping. Values must be strings — the schema
     * is an LLM prompt hint, and a non-string value (e.g. `count: 1`) is a typo
     * rather than a type shorthand worth preserving. It used to be stringified
     * silently.
     *
     * **Deliberately not a [YamlType] whole-collection cast**, for the same
     * reason as [parseActionDeltas]: Swift's `raw as? [String: Any]` succeeds on
     * any mapping and then throws *per offending key*, so the message names the
     * key. Only a non-mapping `raw` is whole-collection here.
     */
    private fun parseOutputSchema(dict: JsonObject, label: String): Map<String, String>? {
        val raw = dict["output"] ?: return null
        val output = raw as? JsonObject
            ?: throw validationError(
                ScenarioValidationMessage.OutputNotDict(
                    label = label,
                    got = renderActualType(raw),
                ),
            )
        return output.entries.associate { (key, value) ->
            key to (
                value.stringContentOrNull()
                    ?: throw validationError(
                        ScenarioValidationMessage.OutputValueNotString(
                            label = label,
                            key = key,
                            got = renderActualType(value),
                        ),
                    )
                )
        }
    }

    /**
     * Maps a conditional's `then:` / `else:` sub-phase array, recursing into
     * [mapPhase] at `depth + 1` so a nested `conditional` is rejected there.
     *
     * Whole-collection ([YamlType.OBJECT_LIST]), matching Swift's
     * `as? [[String: Any]]`: one non-mapping element makes the branch
     * wrong-shaped as a whole.
     */
    private fun mapBranch(
        raw: JsonElement?,
        branchLabel: String,
        parentLabel: String,
        depth: Int,
    ): List<Phase>? {
        val phasesRaw = raw ?: return null
        val list = YamlType.OBJECT_LIST.cast(phasesRaw)
            ?: throw validationError(
                ScenarioValidationMessage.BranchNotArray(
                    label = parentLabel,
                    branch = branchLabel,
                ),
            )
        return list.mapIndexed { subIndex, subRaw ->
            mapPhase(subRaw, label = "$parentLabel.$branchLabel[$subIndex]", depth = depth + 1)
        }
    }

    /**
     * Converts a raw YAML value to an [AnyCodableValue], throwing on an
     * unsupported shape rather than dropping the field or coercing it into a
     * surprising string. [AnyCodableValue] is String-leaf; a curator wanting a
     * numeric top-level scalar quotes it (`count: "42"`).
     *
     * Shape order mirrors Swift's cast ladder, and the first rung is
     * load-bearing for the empty case: Swift's `arr as? [[String: String]]`
     * succeeds on `[]`, so an empty list becomes
     * [AnyCodableValue.ArrayOfDictionariesValue], not [AnyCodableValue.ArrayValue].
     * The vacuous `all` below reproduces that.
     */
    private fun convertToAnyCodableValue(value: JsonElement, key: String): AnyCodableValue {
        if (value is JsonPrimitive && value !is JsonNull && value.isString) {
            return AnyCodableValue.StringValue(value.content)
        }
        if (value is JsonArray) {
            if (value.all { it is JsonObject }) {
                val rows = value.map { element ->
                    val row = element as JsonObject
                    row.entries.associate { (rowKey, rowValue) ->
                        rowKey to (
                            rowValue.stringContentOrNull()
                                // Array of dicts where a value is not a String —
                                // this used to stringify silently, hiding typos
                                // like `majority: 1`.
                                ?: throw validationError(
                                    ScenarioValidationMessage
                                        .ExtraDataArrayOfDictNotString(key),
                                )
                            )
                    }
                }
                return AnyCodableValue.ArrayOfDictionariesValue(rows)
            }
            val strings = value.map { it.stringContentOrNull() }
            if (strings.all { it != null }) {
                return AnyCodableValue.ArrayValue(strings.filterNotNull())
            }
            throw validationError(ScenarioValidationMessage.ExtraDataMixedArray(key))
        }
        if (value is JsonObject) {
            return AnyCodableValue.DictionaryValue(
                value.entries.associate { (entryKey, entryValue) ->
                    entryKey to (
                        entryValue.stringContentOrNull()
                            ?: throw validationError(
                                ScenarioValidationMessage.ExtraDataDictNotString(key),
                            )
                        )
                },
            )
        }
        throw validationError(
            ScenarioValidationMessage.ExtraDataUnsupportedType(
                key = key,
                got = renderActualType(value),
                shapes = SUPPORTED_EXTRA_DATA_SHAPES,
            ),
        )
    }

    private fun acceptedLanguagesList(): String =
        Scenario.ACCEPTED_LANGUAGES.sorted().joinToString(", ")

    private companion object {
        private const val SCENARIO_LABEL = "Scenario"
        private const val PERSONA_LABEL = "Persona"

        /** Byte-identical to the Swift original's `supportedExtraDataShapes`. */
        private const val SUPPORTED_EXTRA_DATA_SHAPES =
            "String, [String], [String: String], or [[String: String]]"

        /** Top-level keys mapped onto [Scenario] rather than collected as extra data. */
        private val STANDARD_KEYS: Set<String> = setOf(
            "id", "name", "description", "language", "simulation_language",
            "agents", "rounds", "context", "personas", "phases", "log_window",
        )

        private val PHASE_TYPES_BY_YAML_NAME: Map<String, PhaseType> =
            serialNameLookup(PhaseType.serializer(), PhaseType.entries)

        private val ASSIGN_TARGETS_BY_YAML_NAME: Map<String, AssignTarget> =
            serialNameLookup(AssignTarget.serializer(), AssignTarget.entries)

        private val PAIRING_STRATEGIES_BY_YAML_NAME: Map<String, PairingStrategy> =
            serialNameLookup(PairingStrategy.serializer(), PairingStrategy.entries)

        /**
         * Also the source of [ScenarioValidationMessage.InvalidLogic]'s
         * `allowed:` fragment — see [parseLogic] for why it is derived from the
         * key order rather than written out.
         */
        private val SCORE_CALC_LOGICS_BY_YAML_NAME: Map<String, ScoreCalcLogic> =
            serialNameLookup(ScoreCalcLogic.serializer(), ScoreCalcLogic.entries)
    }
}

/**
 * A YAML value shape the loader accepts, pairing the name it renders in an
 * `expected:` fragment with the cast that produces it.
 *
 * One type per Swift generic argument the loader instantiates `parseRequired` /
 * `parseOptional` with. `cast` returns `null` for "not this shape" and lets the
 * caller build the error, so the missing-vs-wrong-type distinction stays in one
 * place.
 *
 * `internal`, like every helper here: only [ScenarioLoader.load] is `public`, so
 * no `kotlinx.serialization` type reaches the exported Obj-C header.
 */
internal class YamlType<T> private constructor(
    /** The `expected:` fragment, mirroring Swift's `String(describing: T.self)`. */
    val rendered: String,
    /** Returns the typed value, or `null` when [element] is a different shape. */
    val cast: (JsonElement) -> T?,
) {
    internal companion object {
        val STRING: YamlType<String> = YamlType("String") { it.stringContentOrNull() }

        /**
         * A **32-bit** integral scalar. A value that parses as a `Long` but falls
         * outside `Int` range casts to `null` and therefore throws — Swift's
         * `Int` is 64-bit and accepts it, but truncating here would run a
         * different scenario than the author wrote. [renderActualType] renders
         * such a value `Int64` so the resulting message is not the bewildering
         * "must be Int, got Int".
         */
        val INT: YamlType<Int> = YamlType("Int") { element ->
            (element as? JsonPrimitive)
                ?.takeIf { it !is JsonNull && !it.isString && !it.isYamlBooleanLiteral() }
                ?.content
                ?.toLongOrNull()
                ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
                ?.toInt()
        }

        /**
         * A boolean, including the YAML 1.1 tokens snakeyaml-engine's 1.2 core
         * schema leaves as strings. See the class KDoc of [ScenarioLoader],
         * divergence 2, for why the token set stops where it does.
         */
        val BOOL: YamlType<Boolean> = YamlType("Bool") { element ->
            val primitive = (element as? JsonPrimitive)?.takeIf { it !is JsonNull }
            when {
                primitive == null -> null
                primitive.isString -> YAML_11_BOOLEAN_TOKENS[primitive.content]
                else -> primitive.content.toBooleanStrictOrNull()
            }
        }

        /**
         * A list of strings — **whole-collection** semantics, matching Swift's
         * `as? [String]`: one non-string element fails the entire cast, so the
         * error names the list's key rather than the offending element's.
         */
        val STRING_LIST: YamlType<List<String>> = YamlType("Array<String>") { element ->
            (element as? JsonArray)
                ?.map { it.stringContentOrNull() }
                ?.takeIf { values -> values.all { it != null } }
                ?.filterNotNull()
        }

        /**
         * A list of mappings — whole-collection semantics like [STRING_LIST].
         * One non-mapping element makes `personas:` / `phases:` wrong-typed as a
         * whole, exactly as Swift's `as? [[String: Any]]` does.
         */
        val OBJECT_LIST: YamlType<List<JsonObject>> =
            YamlType("Array<Dictionary<String, Any>>") { element ->
                (element as? JsonArray)
                    ?.takeIf { list -> list.all { it is JsonObject } }
                    ?.map { it as JsonObject }
            }

        /**
         * The YAML 1.1 boolean tokens re-accepted loader-locally. `y` / `n` are
         * deliberately absent — both engines already agree they are strings.
         */
        private val YAML_11_BOOLEAN_TOKENS: Map<String, Boolean> = mapOf(
            "yes" to true, "Yes" to true, "YES" to true,
            "on" to true, "On" to true, "ON" to true,
            "no" to false, "No" to false, "NO" to false,
            "off" to false, "Off" to false, "OFF" to false,
        )
    }
}

/**
 * Builds a `@SerialName` → enum-entry lookup from [serializer]'s descriptor.
 *
 * Kotlin enums carry their YAML spelling **only** as `@SerialName` — there is no
 * `rawValue` to reverse the way Swift's `PhaseType(rawValue:)` does. Deriving the
 * table from the descriptor rather than hand-writing a `when` keeps it
 * mechanically tied to the annotation, so a renamed or newly added case cannot
 * drift out of the loader (`.claude/rules/engine.md` § "Kotlin enum mirror" — the
 * mirrors that no compiler catches). Same source and same reasoning as the
 * forward direction, `PhaseType.serialName()` in `PhaseDispatcher.kt`; this is
 * generic because the loader needs it for four enums — [PhaseType],
 * `AssignTarget`, `PairingStrategy` and `ScoreCalcLogic` — only the first of
 * which has a `serialName()` extension.
 *
 * [entries] must be the enum's `entries` list: an enum serial descriptor names
 * its elements in declaration order, so index *i* is `entries[i]`. The
 * [require] guards the one way that could stop being true.
 *
 * Declaration order is load-bearing for one caller beyond lookup: the returned
 * `LinkedHashMap`'s key order is what `ScenarioLoader.parseLogic` joins into
 * [ScenarioValidationMessage.InvalidLogic]'s `allowed:` fragment.
 */
internal fun <T : Enum<T>> serialNameLookup(
    serializer: KSerializer<T>,
    entries: List<T>,
): Map<String, T> {
    val descriptor = serializer.descriptor
    // `require` throws IllegalArgumentException, which `load`'s
    // `@Throws(SimulationException::class)` does not cover — from Swift that
    // terminates the process rather than raising (`kmp-interop.md` Pattern 5).
    // Acceptable only because this is a build-time invariant of the enum and its
    // descriptor, unreachable from any input. Do not widen this helper to a path
    // where a caller's data can trip it without giving it a checked failure.
    require(descriptor.elementsCount == entries.size) {
        "${descriptor.serialName}: descriptor has ${descriptor.elementsCount} elements " +
            "but the enum has ${entries.size} entries"
    }
    return entries.indices.associate { index -> descriptor.getElementName(index) to entries[index] }
}

/**
 * Renders the `got:` fragment for [element].
 *
 * The **single** place a decoded YAML value becomes a type name, so the loader's
 * whole error vocabulary moves together. It targets Swift's
 * `String(describing: type(of:))` output over the Yams-bridged values, and
 * reaches it for every shape but three:
 *
 * - an explicit `null` renders `Null` here and `NSNull` in Swift;
 * - an integral scalar outside 32-bit range renders `Int64` here, where Swift
 *   simply says `Int` and accepts the value;
 * - the two YAML-1.1 typed scalars of the class KDoc's divergence 1 render
 *   `String` here, where Yams has already bridged them to `Int` / `Date`.
 *
 * All three are message text only, and message text from a *rejected* scenario,
 * which is why this is documented rather than ledgered (see the class KDoc of
 * [ScenarioLoader]).
 */
internal fun renderActualType(element: JsonElement): String = when (element) {
    is JsonNull -> "Null"
    is JsonObject -> "Dictionary<String, Any>"
    is JsonArray -> "Array<Any>"
    is JsonPrimitive -> when {
        element.isString -> "String"
        element.isYamlBooleanLiteral() -> "Bool"
        element.content.toLongOrNull()
            ?.let { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() } == true -> "Int"
        element.content.toLongOrNull() != null -> "Int64"
        element.content.toDoubleOrNull() != null -> "Double"
        // Unreachable for snakeyaml output — an unquoted scalar it could not
        // resolve arrives as a string primitive, caught by the first branch.
        else -> "String"
    }
}

/**
 * The value of a **quoted-or-plain YAML string** scalar, or `null` for every
 * other shape.
 *
 * `isString` is the quoted/plain fidelity both engines preserve: a plain `3`
 * arrives as a non-string primitive and fails this, matching Swift's `as? String`
 * on the `Int` Yams bridges it to. Guarding on it is not optional —
 * `JsonPrimitive.content` is defined for numbers and booleans too, so omitting
 * the check would re-introduce exactly the silent coercion of #130.
 */
private fun JsonElement.stringContentOrNull(): String? =
    (this as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content

/**
 * Whether this primitive is an unquoted `true` / `false`.
 *
 * Kotlin's `booleanOrNull` ignores `isString`, so it would report a **quoted**
 * `"true"` as a boolean; this is the `isString`-aware form the loader needs to
 * keep `exclude_self: "true"` a type error.
 */
private fun JsonPrimitive.isYamlBooleanLiteral(): Boolean =
    !isString && (content == "true" || content == "false")

/**
 * Wraps a [ScenarioValidationMessage] in
 * [SimulationError.ScenarioValidationFailed], rendering it at the Models layer so
 * the loader carries no string formatting of its own.
 *
 * File-scope rather than a method, mirroring the Swift original — and
 * deliberately a *second* declaration of this name in `com.pastura.engine`:
 * `ScenarioValidator.kt` has its own file-private one, exactly as the two Swift
 * files do. See the class KDoc of [ScenarioLoader].
 */
private fun validationError(message: ScenarioValidationMessage): SimulationException =
    SimulationException(SimulationError.ScenarioValidationFailed(message.render()))
