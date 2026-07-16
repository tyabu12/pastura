package com.pastura.engine

import com.pastura.models.ConversationEntry
import com.pastura.models.OutputSchema
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.Scenario
import com.pastura.models.ScenarioConventions
import com.pastura.models.SimulationState

/**
 * Builds LLM prompts for simulation phases.
 *
 * Handles template variable expansion, system-prompt construction with persona
 * and scenario context, and conversation-log formatting for prompt injection.
 *
 * ## Scope: the ADR-023 §6 Stage-2 gate slice's *minimal* subset
 *
 * ADR-023 §6 lists `PromptBuilder` as a "hard build-dep — in the slice, or
 * stubbed", i.e. prompt-content fidelity is explicitly **not** what the gate
 * measures; the boundary crossings are. This port is therefore deliberately
 * behaviour-incomplete against Swift, and **must not be read as parity**.
 *
 * What is ported: [expandTemplate], [formatScoreboard], [formatConversationLog],
 * [getMainField], and a [buildSystemPrompt] covering the speak_all path (header,
 * scenario context, persona, secret, base answer rules, output format).
 *
 * What is **knowingly absent** — each a *named* unit, tracked on #501 for Stage
 * 3, never a silent drop:
 *
 * | Absent | Why |
 * |---|---|
 * | `injectAssigned` / `injectNotes` / `injectWhispers` / `injectRelationships` / `injectMood` | their producer phases (assign / reflect / whisper / relationship_update) are Stage-3 freight |
 * | `captureMood` (#913) + `moodRule` | ditto — no slice phase declares `mood` |
 * | `addressRule` (#911, speak_each) | speak_each is Stage 3 |
 * | `reflectBrevityRule` / `whisperRule` | reflect / whisper are Stage 3 |
 * | choose-options rule / `voteCandidateRule` | choose / vote are Stage 3 |
 * | `RelationshipVerbalizer`, `PromptPlaceholders`, `ErrorReadability` | no slice consumer |
 *
 * A Stage-3 port completes these against the Swift test files, which ADR-023 §6
 * names as the executable spec.
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
        sections += buildAnswerRules(language, phase)
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
                "内心（inner_thought）では率直に触れてかまいません。あなたの判断や態度はこの秘密に左右されます。",
            en = "Never reveal this secret in anything the other participants can hear (your statement). " +
                "You may reflect on it frankly in your inner_thought. It shapes your judgement and attitude.",
        )
        sections += "$header\n$secret\n\n$guidance"
    }

    /**
     * The base `## 回答ルール / ## Response Rules` block.
     *
     * Only the base rules — the phase-specific appendices (speak_each address,
     * reflect brevity, whisper privacy, choose options, vote candidates, mood) are
     * Stage-3 units; see the class doc.
     */
    private fun buildAnswerRules(language: String, phase: Phase): String {
        val maxSentences = phase.maxSentences ?: DEFAULT_STATEMENT_MAX_SENTENCES
        val sentenceNoun = if (maxSentences == 1) "sentence" else "sentences"
        return pickLanguage(
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
    }

    /**
     * The `## 出力フォーマット（JSON）/ ## Output Format (JSON)` block, or `null` for a
     * code phase (no declared schema).
     *
     * Every field is specified as `"string"` regardless of its
     * [OutputSchema.Kind] — including `Kind.Enumeration`. That is Swift's
     * behaviour verbatim, and it is deliberate rather than a simplification: the
     * grammar constrains *structure only*, never value enumerations, because
     * enumerated literals crash llama.cpp's sampler at accept-time on
     * multi-byte / CJK values (ADR-002 §12.9). Closed-set values are constrained
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
}
