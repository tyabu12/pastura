package com.pastura.engine

import com.pastura.models.ConversationEntry
import com.pastura.models.OutputSchema
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.ScenarioConventions
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput

/**
 * Builds LLM prompts for simulation phases.
 *
 * Handles template variable expansion, system-prompt construction with persona
 * and scenario context, and conversation-log formatting for prompt injection.
 *
 * ## Scope: Stage-3 Wave B — injection family landed, handler rules pending
 *
 * ADR-023 §6 originally listed `PromptBuilder` as a Stage-2 "hard build-dep — in
 * the slice, or stubbed"; the gate measured boundary crossings, not prompt-content
 * fidelity. Wave B now closes that gap consumer-by-consumer, so this is **partial
 * parity**, not full: the reserved-namespace injection family is landed (its first
 * consumer, `SpeakAllHandler`, calls all of it), but the handler-specific answer
 * rules and the unwired helper types below are not.
 *
 * What is ported: [expandTemplate], [formatScoreboard], [formatConversationLog],
 * [getMainField]; [buildSystemPrompt] (header, scenario context, persona, secret,
 * private self-knowledge sections, base answer rules + mood rule + vote-candidate
 * rule, output format); the injection family ([injectAssigned] / [injectNotes] /
 * [injectWhispers] / [injectRelationships] / [injectMood]), [captureMood] +
 * `moodRule` + `reflectBrevityRule` + `voteCandidateRule` + `whisperRule` +
 * `chooseOptionsRule`, and `appendPrivateSections`.
 *
 * What is **knowingly absent** — each a *named* unit, tracked on #501 for its
 * Wave-B handler PR, never a silent drop:
 *
 * | Absent | Why |
 * |---|---|
 * | `addressRule` (#911, speak_each) | speak_each is a later Wave-B handler |
 * | `RelationshipVerbalizer`, `PromptPlaceholders`, `ErrorReadability` | types landed in PR-3 (#501 Stage 3); PromptBuilder still has no slice consumer for them (wiring deferred to their Wave-B handlers) |
 *
 * Each remaining unit lands with its handler against the Swift test files, which
 * ADR-023 §6 names as the executable spec.
 *
 * Swift original: `Pastura/Pastura/Engine/PromptBuilder.swift` (+`Injection`,
 * +`PrivateSections`).
 */
internal class PromptBuilder {

    companion object {
        /**
         * The global default statement brevity cap (sentences), applied when a
         * phase declares no `max_sentences` override (#881, #877).
         */
        const val DEFAULT_STATEMENT_MAX_SENTENCES: Int = 3
    }

    // MARK: - Template Expansion

    /**
     * Replaces `{key}` placeholders in [template] with values from [variables].
     * Unknown placeholders (no matching key) are left unchanged.
     *
     * **Iteration order is observable and diverges from Swift** — see
     * [formatScoreboard]'s note on ordering. Swift iterates a `Dictionary` in an
     * arbitrary, seed-dependent order; Kotlin iterates a `Map` in insertion
     * order. That is invisible whenever placeholder keys are disjoint (the normal
     * case, and every current scenario), because each replacement touches a
     * different span. It becomes visible only if one variable's *value* contains
     * another variable's `{placeholder}` — then whether it gets expanded depends
     * on which key ran first. Swift is already non-deterministic in that case, so
     * this port does not "fix" it; a Stage-3 hardening should decide the rule
     * once, for both languages.
     */
    fun expandTemplate(template: String, variables: Map<String, String>): String {
        var result = template
        for ((key, value) in variables) {
            result = result.replace("{$key}", value)
        }
        return result
    }

    // MARK: - Scoreboard

    /**
     * Serializes [scores] into a compact JSON-like string for template injection.
     *
     * Keys are sorted so output is deterministic regardless of map order.
     *
     * **Cross-language ordering divergence — measured, accepted, NOT fixed here.**
     * Swift's `<` on `String` orders by Unicode scalar (code point) and treats
     * canonically-equivalent strings as equal; Kotlin's [String.compareTo] orders
     * by UTF-16 code unit with no normalization. Measured on this branch:
     *
     * | Input | Swift | Kotlin |
     * |---|---|---|
     * | `Alice`, `Bob`, `carol` | `Alice, Bob, carol` | same |
     * | `アリス`, `ボブ`, `太郎` | `アリス, ボブ, 太郎` | same |
     * | `🍎`, `U+FFFD`, `Zed` | `Zed, U+FFFD, 🍎` | `Zed, 🍎, U+FFFD` |
     * | `éclair` (NFC), `éclair` (NFD), `zebra` | `zebra, éclair, éclair` | `éclair, zebra, éclair` |
     *
     * The last row is measured on an array sort. Through a `Map` the gap is wider
     * still: Swift's `[String: Int]` COLLAPSES the two éclairs into one key
     * (last-write-wins) so its scoreboard emits 2 pairs, while Kotlin emits 3.
     * `PromptBuilderParityTests` pins the Map behaviour.
     *
     * BMP names — every bundled preset, and any ASCII or kana persona — agree.
     * The divergence needs a supplementary-plane (emoji) or decomposed-Unicode
     * persona name, and **it is reachable**: persona names carry no charset
     * constraint (`ScenarioConventions.isValidFieldName` gates *output field*
     * names, not persona names; the validator only checks persona count).
     *
     * Not normalized here because a code-point comparator would close only the
     * first row — the NFC row needs a Unicode normalizer that common Kotlin does
     * not have — and a half-fix reads as parity while still diverging. Pinned by
     * `PromptBuilderParityTests` and recorded on #501 as a Stage-4 landmine
     * instead, following the #1063 precedent (normalize what you can, pin the
     * accepted divergence).
     */
    fun formatScoreboard(scores: Map<String, Int>): String =
        scores.entries
            .sortedBy { it.key }
            .joinToString(separator = ", ") { "\"${it.key}\": ${it.value}" }
            .let { "{$it}" }

    // MARK: - Conversation Log

    /**
     * Serializes [entries] into plain text for prompt injection.
     *
     * The empty-log placeholder is `（まだなし）` (ja) / `(none yet)` (en), chosen via
     * the effective Engine language (callers pass `scenario.engineLanguage`,
     * ADR-010 D5 / D6 row 1).
     *
     * @param window Optional cap (`scenario.logWindow`, #907). When non-null, only
     *   the last `window` entries are formatted — a **prompt-side** trim; the full
     *   log is untouched in persistence. `null` keeps every entry.
     *
     *   Swift's doc reasons that "for any `window >= 1` (the validator's floor) the
     *   trimmed slice is non-empty whenever `entries` is". **That floor does not
     *   hold in Kotlin yet** — `ScenarioValidator` is a Stage-3 port, so nothing
     *   rejects `log_window: 0`. `takeLast(0)` returns empty, which would render
     *   the empty-log placeholder on a *non-empty* log — silently telling the model
     *   "no conversation yet" mid-round. Guarded explicitly below rather than
     *   inherited by assumption; see [Phase.maxSentences] for the same
     *   validator-gap pattern.
     */
    fun formatConversationLog(
        entries: List<ConversationEntry>,
        language: String,
        window: Int? = null,
    ): String {
        if (entries.isEmpty()) {
            return pickLanguage(language, ja = "（まだなし）", en = "(none yet)")
        }
        // coerceAtLeast(1): see the `window` doc — the Swift-side validator floor
        // is not yet portable, and a 0 window must not masquerade as an empty log.
        val windowed = window?.let { entries.takeLast(it.coerceAtLeast(1)) } ?: entries
        return windowed.joinToString(separator = "\n") { "  ${it.agentName}: ${it.content}" }
    }

    // MARK: - Main Field Detection

    /**
     * The canonical primary output field name for [phase], used as the key when
     * populating the conversation log from `TurnOutput.fields`.
     *
     * Defers to [ScenarioConventions.primaryField] — the single source of truth
     * ADR-023 §7 requires stay unforked across the port boundary — and falls back
     * to `"statement"` for code phases (which do not normally reach this method,
     * since the speak handlers are its only callers).
     */
    fun getMainField(phase: Phase): String =
        ScenarioConventions.primaryField(phase.type) ?: "statement"

    // MARK: - System Prompt

    /**
     * Builds the system prompt for an agent's LLM call.
     *
     * Includes scenario context, persona description, the persona's secret (#914),
     * base answer rules, and the output-format specification. All user-facing
     * strings dispatch on `scenario.engineLanguage` per ADR-010 D7.
     *
     * See the class doc for the phase-specific rules this slice omits.
     */
    fun buildSystemPrompt(
        scenario: Scenario,
        persona: Persona,
        phase: Phase,
        state: SimulationState,
    ): String {
        val language = scenario.engineLanguage
        val sections = mutableListOf<String>()

        sections += pickLanguage(
            language,
            ja = "あなたはシミュレーションの参加者です。キャラクターになりきってください。",
            en = "You are a participant in a simulation. Stay in character.",
        )

        val scenarioHeader = pickLanguage(language, ja = "## シナリオ", en = "## Scenario")
        sections += "$scenarioHeader\n${scenario.context}"

        val personaHeader = pickLanguage(language, ja = "## あなたのキャラクター", en = "## Your Character")
        val nameLabel = pickLanguage(language, ja = "名前", en = "Name")
        sections += "$personaHeader\n$nameLabel: ${persona.name}\n${persona.description}"

        appendSecretSection(sections, persona, language)
        appendPrivateSections(sections, persona, state, language)
        sections += buildAnswerRules(scenario, persona, phase, state)
        formatOutputSchema(OutputSchema.from(phase), language)?.let { sections += it }

        return sections.joinToString(separator = "\n\n")
    }

    /**
     * Appends the hidden-agenda section (#914) for a persona that has one.
     *
     * **Secrecy invariant** (see [Persona.secret]): this text reaches only the
     * owning agent's system prompt. It is never written to the conversation log,
     * `lastOutputs`, or a shared state variable.
     *
     * Swift guards on `persona.secret != nil` and documents that "non-nil implies
     * non-empty (every ingest path normalizes empty -> nil)". **Kotlin has no
     * ingest path yet** (`ScenarioLoader` is Stage 3), so that convention is
     * unenforced here and a directly-constructed `secret = ""` would render an
     * empty section. Guarded on blankness instead of nullity — stricter than
     * Swift, and it converges on the same behaviour once the normalizing loader
     * lands.
     */
    private fun appendSecretSection(sections: MutableList<String>, persona: Persona, language: String) {
        val secret = persona.secret?.takeIf { it.isNotBlank() } ?: return
        val header = pickLanguage(
            language,
            ja = "## あなたの秘密（他の参加者は知りません）",
            en = "## Your Secret (the other participants do not know this)",
        )
        val guidance = pickLanguage(
            language,
            ja = "この秘密は、他の参加者に聞こえる発言（statement）では決して明かしてはいけません。" +
                "心の声（inner_thought）では率直に触れてかまいません。あなたの判断や態度はこの秘密に左右されます。",
            en = "Never reveal this secret in anything the other participants can hear (your statement). " +
                "You may reflect on it frankly in your inner_thought. It shapes your judgement and attitude.",
        )
        sections += "$header\n$secret\n\n$guidance"
    }

    /**
     * The `## 回答ルール / ## Response Rules` block: the base rules, plus the
     * mood-writing rule ([moodRule], schema-gated), the reflect-note brevity rule
     * ([reflectBrevityRule], `REFLECT`-gated), the whisper privacy rule
     * ([whisperRule], `WHISPER`-gated), the choose-options rule
     * ([chooseOptionsRule], `CHOOSE`-gated), and the vote-candidate rule
     * ([voteCandidateRule], `VOTE`-gated). One phase-specific appendix remains a
     * Stage-3 unit — the speak_each address rule; see the class doc.
     *
     * Takes the full `(scenario, persona, state)` — not just `language` — because
     * [voteCandidateRule] enumerates candidates from the persona + elimination
     * state. Matches Swift's already-wide `buildAnswerRules(scenario:persona:phase:state:)`.
     */
    private fun buildAnswerRules(
        scenario: Scenario,
        persona: Persona,
        phase: Phase,
        state: SimulationState,
    ): String {
        val language = scenario.engineLanguage
        // coerceIn: the THIRD site inheriting a Swift validator guarantee that does
        // not exist on this side yet. `ScenarioValidator.swift:136-145` enforces
        // `max_sentences` in 1..6; that validator is a Stage-3 port, so nothing
        // rejects `max_sentences: 0` here — and un-clamped it renders "at most 0
        // sentences" / "0文以内", an unsatisfiable instruction handed to the model.
        // Same class as the `log_window: 0` guard in formatConversationLog.
        val maxSentences =
            (phase.maxSentences ?: DEFAULT_STATEMENT_MAX_SENTENCES).coerceIn(1, 6)
        val sentenceNoun = if (maxSentences == 1) "sentence" else "sentences"
        var rules = pickLanguage(
            language,
            ja = """
                ## 回答ルール（厳守）
                - 必ず日本語で回答すること
                - 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
                - 発言（statement などの本文フィールド）は${maxSentences}文以内で簡潔に書くこと（長い独白は禁止）
                - JSONは必ず1行で書くこと（改行を入れない）
                - JSON以外のテキストやコードブロック(```)は書かないこと
                - JSONに構文エラーがあると失敗扱いになる（カッコ・引用符・カンマを正しく閉じること）
                - {で始まり}で終わる単一オブジェクトのみ出力し、前後にテキストを付けないこと
            """.trimIndent(),
            en = """
                ## Response Rules (strict)
                - Respond in English only.
                - Every field must contain a sentence (no empty "..." values).
                - Keep your statement (the main text field) concise: at most $maxSentences $sentenceNoun, no long monologues.
                - The JSON output must be a single line (no newlines).
                - Do not include any text or code fences (```) outside the JSON.
                - JSON syntax errors are treated as failure: close every bracket, quote, and comma correctly.
                - Output exactly one object starting with { and ending with }, with no surrounding text.
            """.trimIndent(),
        )

        // Reflect notes get a tighter 2-sentence cap (see [reflectBrevityRule]).
        // Type-gated, unlike the schema-gated mood rule below.
        if (phase.type == PhaseType.REFLECT) {
            rules += reflectBrevityRule(language)
        }

        // Whisper turns get partner-directed privacy guidance (see [whisperRule]).
        // Type-gated like reflect. Placed here to match Swift's rule order
        // (PromptBuilder.swift: whisper precedes the choose/vote slots).
        if (phase.type == PhaseType.WHISPER) {
            rules += whisperRule(language)
        }

        // Choose phases that declare options get the option-list constraint (see
        // [chooseOptionsRule]). Placed between the whisper and vote rules to match
        // Swift's rule order — anchored on the SYMBOLS (`whisperRule` then the choose
        // block then `voteCandidateRule` in PromptBuilder.swift, around :208-:220),
        // because nothing gates a cross-language line reference against drift.
        // `options` is bound to a local first — `phase.options` is a public property
        // of another module (shared/models), which Kotlin refuses to smart-cast to
        // non-null, so passing `phase.options` inside the guard does not compile.
        val chooseOptions = phase.options
        if (phase.type == PhaseType.CHOOSE && chooseOptions != null) {
            rules += chooseOptionsRule(chooseOptions, language)
        }

        // Vote phases get the candidate-list constraint (see [voteCandidateRule]).
        // Placed BEFORE the mood gate to match Swift's rule order
        // (PromptBuilder.swift:220 precedes :226): the injection tests assert rule
        // *membership* via `.contains`, not order, so a vote+mood ordering
        // divergence would be silent — this placement pins it.
        if (phase.type == PhaseType.VOTE) {
            rules += voteCandidateRule(scenario, persona, phase, state)
        }

        // Mood-opting phases (#913) get the mood-writing guidance. Gated on the
        // schema, not the phase type — any LLM phase can declare `mood`.
        if (phase.outputSchemaKeys.contains("mood")) {
            rules += moodRule(language)
        }
        return rules
    }

    /**
     * The `vote` candidate-list constraint appended for vote phases only
     * ([buildAnswerRules] gates on `phase.type == VOTE`). Lists the valid vote
     * targets — all personas minus self (under `exclude_self`, default true) and
     * any eliminated agent.
     *
     * The candidate set is derived the same way `VoteHandler` derives it for the
     * `{candidates}` template variable and its tally filter, so the prompt's "valid
     * names" and the handler's accepted votes stay in lockstep. Keep ja/en
     * scope-parallel when editing.
     */
    private fun voteCandidateRule(
        scenario: Scenario,
        persona: Persona,
        phase: Phase,
        state: SimulationState,
    ): String {
        val excludeSelf = phase.excludeSelf ?: true
        val candidates = scenario.personas
            .map { it.name }
            .filter { name ->
                if (excludeSelf && name == persona.name) return@filter false
                if (state.eliminated[name] == true) return@filter false
                true
            }
        val candidatesList = candidates.joinToString(separator = ", ")
        return pickLanguage(
            scenario.engineLanguage,
            ja = "\n- voteフィールドは必ず次の名前のいずれかを正確に書くこと: $candidatesList",
            en = "\n- The vote field must be exactly one of these names: $candidatesList",
        )
    }

    /**
     * The #907 brevity rule appended for `reflect` phases only ([buildAnswerRules]
     * gates on `phase.type == REFLECT`). Caps the private note at 2 sentences — the
     * same constraint family as the #877 statement brevity rule. Keep ja/en
     * scope-parallel when editing.
     */
    private fun reflectBrevityRule(language: String): String =
        pickLanguage(
            language,
            ja = "\n- メモ（note）は2文以内で簡潔に書くこと（長文・箇条書きの羅列は禁止）",
            en = "\n- Keep your note to at most 2 sentences (no long paragraphs or bullet lists).",
        )

    /**
     * The #908 privacy guidance appended for `whisper` phases only ([buildAnswerRules]
     * gates on `phase.type == WHISPER`). A whisper is a secret one-to-one exchange:
     * nobody except the partner can hear it, so the agent should address the partner
     * directly, stay candid/strategic, and keep it conversational. Keep ja/en
     * scope-parallel when editing.
     */
    private fun whisperRule(language: String): String =
        pickLanguage(
            language,
            ja = "\n- これは密談相手ひとりだけへの秘密の耳打ちです（他の参加者には聞こえません）。" +
                "相手に直接呼びかけ、本音で戦略的に、短い会話として話すこと",
            en = "\n- This is a private whisper to your one partner only (no one else can hear). " +
                "Address them directly, be candid and strategic, and keep it conversational.",
        )

    /**
     * The `choose` option-list constraint appended for choose phases that declare
     * `options` ([buildAnswerRules] gates on `phase.type == CHOOSE && options != null`).
     *
     * This rule is the *only* steer toward the option set on the prompt side: the
     * `action` field is a payload-free `.choice` in the grammar (structure-only, no
     * value enumeration — the CJK sampler-crash trap, ADR-002 §Amendment 2026-06-14),
     * so the runtime check in `ChooseHandler.validateAction` is the sole hard
     * constraint and this list is what keeps rejections rare.
     *
     * **`options != null` here vs `options.isEmpty()` in the handler — a deliberate
     * asymmetry carried over from Swift, not an oversight.** An `options: []` phase
     * passes this gate and renders a rule with an empty list, while `validateAction`
     * treats the same phase as *unconstrained* and passes the raw action through.
     * The shape is reachable: neither `ScenarioLoader` nor `ScenarioValidator`
     * rejects an empty `options`, and ADR-024's R7 lint rule is warning-only. It is
     * preserved rather than "fixed" so the two engines stay byte-comparable; a fix
     * belongs on the Swift side first, in both engines at once.
     *
     * Keep ja/en scope-parallel when editing.
     */
    private fun chooseOptionsRule(options: List<String>, language: String): String {
        val optionsList = options.joinToString(separator = ", ")
        return pickLanguage(
            language,
            ja = "\n- actionフィールドは必ず次のいずれかを書くこと: $optionsList",
            en = "\n- The action field must be one of: $optionsList",
        )
    }

    /**
     * The #913 mood-writing guidance, appended only for phases that opt into a
     * `mood` output field ([buildAnswerRules] gates on the schema). A short-word
     * cap plus an explicit "change naturally, don't force-maintain or abruptly
     * reset" instruction is the primary lever against echo-fixation (the same
     * mood every turn) and unmotivated slashing (flips unrelated to events). Keep
     * ja/en scope-parallel; wording is harness-A/B-tunable. The reserved-namespace
     * inject/capture side lives in [captureMood] / [injectMood].
     */
    private fun moodRule(language: String): String =
        pickLanguage(
            language,
            ja = "\n- moodには今の気分を短い言葉で書くこと（例: わくわく、苛立ち、不安）。" +
                "気分は出来事に応じて自然に変化してよく、無理に維持も急変もしないこと",
            en = "\n- Write your current mood in the mood field as a short phrase " +
                "(e.g. excited, irritated, uneasy). Let it shift naturally with what happens — " +
                "neither forced to stay the same nor snapped to something unrelated.",
        )

    /**
     * The `## 出力フォーマット（JSON）/ ## Output Format (JSON)` block, or `null` for a
     * code phase (no declared schema).
     *
     * Every field is specified as `"string"` regardless of its
     * [OutputSchema.Kind] — including `Kind.Enumeration`. That is Swift's
     * behaviour verbatim, and it is deliberate rather than a simplification: the
     * grammar constrains *structure only*, never value enumerations, because
     * enumerated literals crash llama.cpp's sampler at accept-time on
     * multi-byte / CJK values (ADR-002 § Amendment 2026-06-14, #599). Closed-set values are constrained
     * at runtime by their handlers instead. A port that "improved" this by
     * emitting option literals would reintroduce that crash class.
     */
    private fun formatOutputSchema(schema: OutputSchema?, language: String): String? {
        if (schema == null) return null
        val spec = schema.fields.joinToString(separator = ", ") { "\"${it.name}\": \"string\"" }
        val example = schema.fields.joinToString(separator = ", ") { field ->
            val placeholder =
                pickLanguage(language, ja = "<ここに${field.name}>", en = "<insert ${field.name}>")
            "\"${field.name}\": \"$placeholder\""
        }
        val header = pickLanguage(
            language,
            ja = "## 出力フォーマット（JSON）",
            en = "## Output Format (JSON)",
        )
        val examplePrefix = pickLanguage(language, ja = "例", en = "Example")
        return "$header\n{$spec}\n$examplePrefix: {$example}"
    }

    // MARK: - Reserved-namespace injection (#890 / #907 / #908 / #910 / #913)

    // Each `inject*` reads a per-persona `<prefix>_<name>` key from the caller's
    // local prompt-variable map and surfaces it to only the current speaker under
    // a public `{token}`. They mutate [variables] IN PLACE (the local prompt map,
    // seeded from `state.variables` and discarded after the prompt is built) — NOT
    // persisted state; this mirrors Swift's `inout [String: String]`. The matching
    // system-prompt *sections* live in [appendPrivateSections]; the mood answer-rule
    // in [moodRule]. A missing key resolves to empty string, never a literal
    // placeholder — the shared miss posture.

    /**
     * Injects the current speaker's `assign`-phase value under the canonical
     * `{assigned}` key and its backward-compat alias `{assigned_word}`.
     *
     * `AssignHandler` stores each agent's value under `assigned_<name>`; this reads
     * it back for the speaker so per-persona prompt templates resolve (#890 —
     * before this `{assigned_word}` leaked literally and Word Wolf's secret-word
     * mechanic never worked).
     *
     * Note: a persona literally named `word` would produce key `assigned_word`,
     * colliding with this alias — the alias then reflects the current speaker's
     * value, not that persona's assignment. Contrived and absent from all bundled
     * presets; the `assigned_` prefix is effectively a reserved namespace.
     */
    fun injectAssigned(variables: MutableMap<String, String>, personaName: String) {
        val mine = variables["assigned_$personaName"] ?: ""
        variables["assigned"] = mine
        variables["assigned_word"] = mine
    }

    /**
     * Injects the current speaker's `reflect`-phase memo under `{my_notes}`.
     * `ReflectHandler` stores each agent's private note under `notes_<name>` (#907).
     */
    fun injectNotes(variables: MutableMap<String, String>, personaName: String) {
        variables["my_notes"] = variables["notes_$personaName"] ?: ""
    }

    /**
     * Injects the current speaker's `whisper` channel under `{my_whispers}`.
     * `WhisperHandler` stores each participant's private view of their pair's
     * exchange under `whispers_<name>` (#908).
     */
    fun injectWhispers(variables: MutableMap<String, String>, personaName: String) {
        variables["my_whispers"] = variables["whispers_$personaName"] ?: ""
    }

    /**
     * Injects the current speaker's `relationship_update` affinity summary under
     * `{relationships}`. `RelationshipUpdateHandler` stores each agent's prose read
     * on the others under `relationships_<name>` (#910).
     */
    fun injectRelationships(variables: MutableMap<String, String>, personaName: String) {
        variables["relationships"] = variables["relationships_$personaName"] ?: ""
    }

    /**
     * Injects the current speaker's carried-over `mood` under `{my_mood}`.
     *
     * [captureMood] persists the value under `mood_<name>` (#913); a miss (scenario
     * never opts in, or round 1 before any mood is set) renders no mood text.
     * Unlike notes/whispers, an agent never sees another's mood — it is
     * self-referential emotional inertia, so there is no cross-agent leak surface.
     */
    fun injectMood(variables: MutableMap<String, String>, personaName: String) {
        variables["my_mood"] = variables["mood_$personaName"] ?: ""
    }

    /**
     * Persists a turn's `mood` output field under the reserved per-persona key
     * `mood_<name>` so it carries into the same agent's next prompt (#913).
     *
     * Writes only a **non-empty** mood: a failed/empty inference must not erase the
     * prior turn's mood (the same non-empty guard `ReflectHandler` applies to its
     * note); last-write-wins. A phase whose schema does not declare `mood` never
     * produces the key, so this is a no-op there — called from every LLM handler
     * for symmetry.
     *
     * Mutates [variables] IN PLACE. The handler threads the **persisted**
     * `state.variables` here (via a copy folded into its success-path
     * `state.copy`), NOT the local prompt map used by the `inject*` family — that
     * map is discarded after the prompt is built, so a capture into it would be
     * lost. Mirrors Swift's `inout &state.variables`.
     */
    fun captureMood(output: TurnOutput, variables: MutableMap<String, String>, personaName: String) {
        val mood = output.fields["mood"] ?: ""
        if (mood.isNotEmpty()) {
            variables["mood_$personaName"] = mood
        }
    }

    /**
     * Appends each agent's private self-knowledge sections to [sections]: the
     * reflect note (`notes_<name>`, #907), the whisper channel (`whispers_<name>`,
     * #908), the relationship read (`relationships_<name>`, #910), and — placed
     * LAST for recency and surfaced in EVERY phase so the inertia survives an
     * intervening vote/choose — the carried-over mood (`mood_<name>`, #913).
     *
     * Each is derived only for that agent and never enters the conversation log,
     * so every header stresses its privacy. An absent or empty value renders no
     * section (no empty header). Reads the **persisted** `state.variables`
     * directly — independent of the `inject*` local prompt map.
     */
    private fun appendPrivateSections(
        sections: MutableList<String>,
        persona: Persona,
        state: SimulationState,
        language: String,
    ) {
        state.variables["notes_${persona.name}"]?.takeIf { it.isNotEmpty() }?.let { note ->
            val header = pickLanguage(
                language,
                ja = "## あなたの心の声メモ（他の参加者には見えません）",
                en = "## Your Private Notes (invisible to other participants)",
            )
            sections += "$header\n$note"
        }

        state.variables["whispers_${persona.name}"]?.takeIf { it.isNotEmpty() }?.let { whispers ->
            val header = pickLanguage(
                language,
                ja = "## あなたの密談（密談相手以外には見えません）",
                en = "## Your Private Whispers (invisible to everyone except your whisper partner)",
            )
            sections += "$header\n$whispers"
        }

        state.variables["relationships_${persona.name}"]?.takeIf { it.isNotEmpty() }?.let { relationships ->
            val header = pickLanguage(
                language,
                ja = "## あなたの人間関係（他の参加者には見えません）",
                en = "## Your Read on the Others (invisible to other participants)",
            )
            sections += "$header\n$relationships"
        }

        // Mood placed LAST (#913): nearest the answer rules for recency, and shown
        // in EVERY phase (not just declaring ones) so the inertia survives.
        state.variables["mood_${persona.name}"]?.takeIf { it.isNotEmpty() }?.let { mood ->
            val header = pickLanguage(
                language,
                ja = "## あなたの今の気分",
                en = "## Your Current Mood",
            )
            sections += "$header\n$mood"
        }
    }
}
