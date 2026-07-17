package com.pastura.engine

import com.pastura.models.ConversationEntry
import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.SimulationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Behaviour tests for the ported subset of [PromptBuilder].
 *
 * **These do NOT assert parity with Swift's `PromptBuilder`.** The port is
 * knowingly behaviour-incomplete (see the class doc's absence table), so a
 * "parity" claim here would be false and would mislead Stage 3, which treats the
 * Swift test files as the executable spec. What is pinned instead: the ported
 * functions' own behaviour, plus the two places the Kotlin port must *not* inherit
 * a Swift assumption that no longer holds (the missing validator floors).
 *
 * Cross-language ordering divergence lives in [PromptBuilderParityTests].
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
class PromptBuilderTests {

    private val builder = PromptBuilder()

    private val alice = Persona(name = "Alice", description = "Bold cooperator.")
    private val speakAll = Phase(
        type = PhaseType.SPEAK_ALL,
        prompt = "Speak.",
        outputSchema = mapOf("statement" to "string"),
    )

    private fun scenario(
        language: String = "en",
        simulationLanguage: String? = null,
        logWindow: Int? = null,
    ) = com.pastura.models.Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = simulationLanguage,
        agentCount = 1,
        rounds = 1,
        logWindow = logWindow,
        context = "A test.",
        personas = listOf(alice),
        phases = listOf(speakAll),
    )

    // MARK: - expandTemplate

    @Test
    fun expandTemplateReplacesKnownPlaceholders() {
        assertEquals(
            "Hello Alice, round 2",
            builder.expandTemplate("Hello {name}, round {round}", mapOf("name" to "Alice", "round" to "2")),
        )
    }

    @Test
    fun expandTemplateLeavesUnknownPlaceholdersIntact() {
        // Not a no-op contract to break lightly: a scenario author's typo must
        // render visibly rather than silently vanish.
        assertEquals("Hi {nope}", builder.expandTemplate("Hi {nope}", mapOf("name" to "x")))
    }

    @Test
    fun expandTemplateReplacesEveryOccurrence() {
        assertEquals("a a", builder.expandTemplate("{x} {x}", mapOf("x" to "a")))
    }

    // MARK: - formatScoreboard

    @Test
    fun scoreboardIsSortedAndCompact() {
        assertEquals(
            """{"Alice": 3, "Bob": 1}""",
            builder.formatScoreboard(mapOf("Bob" to 1, "Alice" to 3)),
        )
    }

    @Test
    fun scoreboardIsDeterministicRegardlessOfMapOrder() {
        // The reason the sort exists at all.
        val a = builder.formatScoreboard(linkedMapOf("Bob" to 1, "Alice" to 3, "Carol" to 2))
        val b = builder.formatScoreboard(linkedMapOf("Carol" to 2, "Alice" to 3, "Bob" to 1))
        assertEquals(a, b)
    }

    @Test
    fun emptyScoreboardRendersEmptyObject() {
        assertEquals("{}", builder.formatScoreboard(emptyMap()))
    }

    // MARK: - formatConversationLog

    private fun entry(agent: String, content: String, round: Int = 1) =
        ConversationEntry(agentName = agent, content = content, phaseType = PhaseType.SPEAK_ALL, round = round)

    @Test
    fun emptyLogRendersLanguageSpecificPlaceholder() {
        assertEquals("(none yet)", builder.formatConversationLog(emptyList(), "en"))
        assertEquals("（まだなし）", builder.formatConversationLog(emptyList(), "ja"))
    }

    @Test
    fun logRendersIndentedAgentLines() {
        assertEquals(
            "  Alice: hi\n  Bob: yo",
            builder.formatConversationLog(listOf(entry("Alice", "hi"), entry("Bob", "yo")), "en"),
        )
    }

    @Test
    fun windowKeepsOnlyTheLastNEntries() {
        val log = listOf(entry("A", "1"), entry("B", "2"), entry("C", "3"))
        assertEquals("  B: 2\n  C: 3", builder.formatConversationLog(log, "en", window = 2))
    }

    @Test
    fun nullWindowKeepsEveryEntry() {
        val log = listOf(entry("A", "1"), entry("B", "2"))
        assertEquals(builder.formatConversationLog(log, "en"), builder.formatConversationLog(log, "en", window = null))
    }

    @Test
    fun windowLargerThanTheLogIsHarmless() {
        assertEquals("  A: 1", builder.formatConversationLog(listOf(entry("A", "1")), "en", window = 99))
    }

    @Test
    fun zeroWindowDoesNotMasqueradeAsAnEmptyLog() {
        // THE Kotlin-specific hazard. Swift's doc reasons from "window >= 1, the
        // validator's floor" — but ScenarioValidator is a Stage-3 port, so nothing
        // rejects `log_window: 0` on this side yet. Un-guarded, takeLast(0) would
        // render "(none yet)" on a NON-EMPTY log, silently telling the model the
        // conversation had not started. Delete the coerceAtLeast(1) and this fires.
        val log = listOf(entry("A", "1"), entry("B", "2"))
        val rendered = builder.formatConversationLog(log, "en", window = 0)
        assertFalse(rendered.contains("none yet"), "a 0 window must not render the empty-log placeholder")
        assertEquals("  B: 2", rendered)
    }

    // MARK: - getMainField

    @Test
    fun mainFieldDefersToScenarioConventions() {
        // ADR-023 §7 requires this rule stay unforked across the port boundary —
        // it must resolve THROUGH Models, not via a Kotlin copy.
        assertEquals("statement", builder.getMainField(Phase(type = PhaseType.SPEAK_ALL)))
        assertEquals("vote", builder.getMainField(Phase(type = PhaseType.VOTE)))
        assertEquals("action", builder.getMainField(Phase(type = PhaseType.CHOOSE)))
    }

    @Test
    fun mainFieldFallsBackToStatementForCodePhases() {
        assertEquals("statement", builder.getMainField(Phase(type = PhaseType.SCORE_CALC)))
    }

    // MARK: - buildSystemPrompt

    @Test
    fun systemPromptCarriesContextPersonaRulesAndFormat() {
        val p = builder.buildSystemPrompt(scenario(), alice, speakAll, SimulationState.initial(scenario()))
        assertTrue(p.contains("Stay in character"))
        assertTrue(p.contains("## Scenario"))
        assertTrue(p.contains("A test."))
        assertTrue(p.contains("## Your Character"))
        assertTrue(p.contains("Name: Alice"))
        assertTrue(p.contains("Bold cooperator."))
        assertTrue(p.contains("## Response Rules (strict)"))
        assertTrue(p.contains("## Output Format (JSON)"))
        assertTrue(p.contains("""{"statement": "string"}"""))
        assertTrue(p.contains("""<insert statement>"""))
    }

    @Test
    fun systemPromptDispatchesOnEngineLanguage() {
        val ja = builder.buildSystemPrompt(
            scenario(language = "ja"), alice, speakAll, SimulationState.initial(scenario(language = "ja")),
        )
        assertTrue(ja.contains("## シナリオ"))
        assertTrue(ja.contains("## 回答ルール（厳守）"))
        assertTrue(ja.contains("## 出力フォーマット（JSON）"))
        assertTrue(ja.contains("<ここにstatement>"))
        assertFalse(ja.contains("Response Rules"))
    }

    @Test
    fun simulationLanguageOverridesLanguage() {
        // ADR-010 D6 row 1: the Engine reads engineLanguage, not language.
        val s = scenario(language = "ja", simulationLanguage = "en")
        val p = builder.buildSystemPrompt(s, alice, speakAll, SimulationState.initial(s))
        assertTrue(p.contains("## Response Rules (strict)"))
        assertFalse(p.contains("## 回答ルール（厳守）"))
    }

    // MARK: - secret (#914)

    @Test
    fun secretSectionAppearsOnlyForAPersonaThatHasOne() {
        val s = scenario()
        assertFalse(builder.buildSystemPrompt(s, alice, speakAll, SimulationState.initial(s)).contains("Your Secret"))

        val spy = Persona(name = "Alice", description = "Bold.", secret = "I am the wolf.")
        val p = builder.buildSystemPrompt(s, spy, speakAll, SimulationState.initial(s))
        assertTrue(p.contains("## Your Secret (the other participants do not know this)"))
        assertTrue(p.contains("I am the wolf."))
        assertTrue(p.contains("Never reveal this secret"))
    }

    @Test
    fun blankSecretRendersNoSectionEvenThoughTheTypeAllowsIt() {
        // Swift guards on nil and relies on "every ingest path normalizes empty ->
        // nil". Kotlin HAS no ingest path yet (ScenarioLoader is Stage 3), so a
        // directly-constructed `secret = ""` is reachable and must not emit a
        // header with an empty body.
        val s = scenario()
        val blank = Persona(name = "Alice", description = "Bold.", secret = "   ")
        assertFalse(builder.buildSystemPrompt(s, blank, speakAll, SimulationState.initial(s)).contains("Your Secret"))
    }

    // MARK: - maxSentences (#881)

    @Test
    fun anOutOfRangeBrevityCapIsClampedNotRenderedVerbatim() {
        // Swift's validator enforces 1..6; it is a Stage-3 port, so `max_sentences:
        // 0` reaches here. Un-clamped it renders "at most 0 sentences" — an
        // unsatisfiable instruction handed to the model. Same class as log_window: 0.
        val s = scenario()
        val zero = Phase(type = PhaseType.SPEAK_ALL, outputSchema = mapOf("statement" to "string"), maxSentences = 0)
        val p = builder.buildSystemPrompt(s, alice, zero, SimulationState.initial(s))
        assertTrue(p.contains("at most 1 sentence,"), "expected clamp to the 1 floor, got: $p")
        assertFalse(p.contains("at most 0"))

        val huge = Phase(type = PhaseType.SPEAK_ALL, outputSchema = mapOf("statement" to "string"), maxSentences = 99)
        assertTrue(builder.buildSystemPrompt(s, alice, huge, SimulationState.initial(s)).contains("at most 6 sentences"))
    }

    @Test
    fun defaultBrevityCapIsThree() {
        val s = scenario()
        val p = builder.buildSystemPrompt(s, alice, speakAll, SimulationState.initial(s))
        assertTrue(p.contains("at most 3 sentences"))
    }

    @Test
    fun phaseOverridesTheBrevityCap() {
        val s = scenario()
        val capped = Phase(type = PhaseType.SPEAK_ALL, outputSchema = mapOf("statement" to "string"), maxSentences = 6)
        assertTrue(builder.buildSystemPrompt(s, alice, capped, SimulationState.initial(s)).contains("at most 6 sentences"))
    }

    @Test
    fun singularSentenceNounAtCapOne() {
        // Swift pluralizes the en noun; a port that always said "sentences" would
        // render "at most 1 sentences".
        val s = scenario()
        val one = Phase(type = PhaseType.SPEAK_ALL, outputSchema = mapOf("statement" to "string"), maxSentences = 1)
        val p = builder.buildSystemPrompt(s, alice, one, SimulationState.initial(s))
        assertTrue(p.contains("at most 1 sentence,"), "expected singular noun, got: $p")
    }

    @Test
    fun japaneseBrevityRuleInterpolatesTheCap() {
        val s = scenario(language = "ja")
        val capped = Phase(type = PhaseType.SPEAK_ALL, outputSchema = mapOf("statement" to "string"), maxSentences = 2)
        assertTrue(builder.buildSystemPrompt(s, alice, capped, SimulationState.initial(s)).contains("2文以内"))
    }

    // MARK: - Output format

    @Test
    fun codePhaseWithNoSchemaGetsNoOutputFormatBlock() {
        val s = scenario()
        val code = Phase(type = PhaseType.SCORE_CALC)
        val p = builder.buildSystemPrompt(s, alice, code, SimulationState.initial(s))
        assertFalse(p.contains("Output Format"))
        assertNull(com.pastura.models.OutputSchema.from(code))
    }

    @Test
    fun enumerationFieldsAreSpecifiedAsStringNotAsOptionLiterals() {
        // Load-bearing, not cosmetic: the grammar constrains STRUCTURE only.
        // Emitting option literals is the llama.cpp sampler-crash class
        // (ADR-002 §12.9) — closed-set values are constrained at runtime instead.
        val s = scenario()
        val choose = Phase(
            type = PhaseType.CHOOSE,
            outputSchema = mapOf("action" to "string"),
            options = listOf("cooperate", "betray"),
        )
        val p = builder.buildSystemPrompt(s, alice, choose, SimulationState.initial(s))
        assertTrue(p.contains("""{"action": "string"}"""))
        // Scoped to the FORMAT BLOCK, not the whole prompt. Swift's buildAnswerRules
        // deliberately appends "The action field must be one of: cooperate, betray"
        // — OutputSchema.Kind.choice's doc says the model learns the options FROM
        // the prompt. Asserting absence prompt-wide goes red when Stage 3 lands that
        // rule, with a message inviting deletion of the rule that makes `choose` work.
        // What must never carry literals is the grammar-shaped spec.
        val formatBlock = p.substringAfter("## Output Format (JSON)")
        assertFalse(
            formatBlock.contains("cooperate"),
            "option literals must never reach the format spec (ADR-002 § Amendment 2026-06-14)",
        )
    }
}
