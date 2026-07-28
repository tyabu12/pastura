package com.pastura.engine

import com.pastura.models.Persona
import com.pastura.models.Phase
import com.pastura.models.PhaseType
import com.pastura.models.Scenario
import com.pastura.models.SimulationState
import com.pastura.models.TurnOutput
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Parity tests for the Wave-B reserved-namespace injection family
 * (`inject*` / [PromptBuilder.captureMood] / `appendPrivateSections` / `moodRule`),
 * ported from the Swift executable spec (ADR-023 §6): `PromptBuilderTests+Mood`,
 * `+Whispers`, `+Relationships`, and the notes cases in `+Hardening`. The
 * choose-options block has **no** Swift sibling — that rule is an inline block in
 * `PromptBuilder.swift` with no dedicated test — so those cases are authored here
 * against the Swift source directly, not ported from a Swift test.
 *
 * Unlike [PromptBuilderTests] (which disclaims parity for the still-incomplete
 * base slice), these DO assert parity: their landed units are the full Swift
 * behaviour. Every phase-specific answer rule is now in scope — `mood`,
 * `reflect`-brevity, vote-candidate, `whisper`, choose-options, and (with the
 * SpeakEachHandler PR) the #911 `addressRule`, so `moodRule`,
 * `reflectBrevityRule`, `voteCandidateRule`, `whisperRule`, `chooseOptionsRule`,
 * and `addressRule` are all asserted here. Nothing in the answer-rules block is
 * deferred any more.
 *
 * Split into its own file per the commonTest concern-per-file convention
 * (cf. [PromptBuilderParityTests]); these are pure, stateless `PromptBuilder`
 * calls, so no cross-class shared state applies.
 */
class PromptBuilderInjectionTests {

    private val builder = PromptBuilder()

    private val alice = Persona(name = "Alice", description = "A.")
    private val bob = Persona(name = "Bob", description = "B.")
    private val charlie = Persona(name = "Charlie", description = "C.")

    private val speakAll = Phase(
        type = PhaseType.SPEAK_ALL,
        prompt = "Speak.",
        outputSchema = mapOf("statement" to "string"),
    )

    // The Swift `makeScenario()` these specs use defaults to `ja`; mirror that so
    // the section-header assertions line up.
    private fun scenario(language: String = "ja") = Scenario(
        id = "t",
        name = "T",
        description = "d",
        language = language,
        simulationLanguage = null,
        agentCount = 3,
        rounds = 1,
        logWindow = null,
        context = "A test.",
        personas = listOf(alice, bob, charlie),
        phases = listOf(speakAll),
    )

    private fun stateOf(s: Scenario, variables: Map<String, String> = emptyMap()) =
        SimulationState.initial(s).copy(variables = variables)

    // A representative standard user template (references only public template
    // vars — never a raw `whispers_<name>` key), matching how the speak / vote /
    // choose handlers build their prompts. Used by the leak tests.
    private val standardUserTemplate =
        "Conversation: {conversation_log}\nScore: {scoreboard}\nYour whispers: {my_whispers}"

    // MARK: - injectAssigned (#890)

    @Test
    fun injectAssignedSetsAssignedAndAliasFromNamespacedKey() {
        val variables = mutableMapOf("assigned_Alice" to "wolf")
        builder.injectAssigned(variables, "Alice")
        assertEquals("wolf", variables["assigned"])
        assertEquals("wolf", variables["assigned_word"])
    }

    @Test
    fun injectAssignedSetsEmptyStringOnMiss() {
        val variables = mutableMapOf<String, String>()
        builder.injectAssigned(variables, "Alice")
        assertEquals("", variables["assigned"])
        assertEquals("", variables["assigned_word"])
    }

    // MARK: - injectNotes (#907)

    @Test
    fun injectNotesSetsMyNotesFromNamespacedKey() {
        val variables = mutableMapOf("notes_Alice" to "remember the clue")
        builder.injectNotes(variables, "Alice")
        assertEquals("remember the clue", variables["my_notes"])
    }

    @Test
    fun injectNotesSetsEmptyStringOnMiss() {
        val variables = mutableMapOf<String, String>()
        builder.injectNotes(variables, "Alice")
        assertEquals("", variables["my_notes"])
    }

    // MARK: - injectWhispers (#908)

    @Test
    fun injectWhispersSetsMyWhispersFromNamespacedKey() {
        val variables = mutableMapOf("whispers_Alice" to "Whispering with Bob\n  Alice: secret")
        builder.injectWhispers(variables, "Alice")
        assertEquals("Whispering with Bob\n  Alice: secret", variables["my_whispers"])
    }

    @Test
    fun injectWhispersSetsEmptyStringOnMiss() {
        val variables = mutableMapOf<String, String>()
        builder.injectWhispers(variables, "Alice")
        assertEquals("", variables["my_whispers"])
    }

    // MARK: - injectRelationships (#910)

    @Test
    fun injectRelationshipsSetsRelationshipsFromNamespacedKey() {
        val variables = mutableMapOf("relationships_Alice" to "You are wary of Bob.")
        builder.injectRelationships(variables, "Alice")
        assertEquals("You are wary of Bob.", variables["relationships"])
    }

    @Test
    fun injectRelationshipsSetsEmptyStringOnMiss() {
        val variables = mutableMapOf<String, String>()
        builder.injectRelationships(variables, "Alice")
        assertEquals("", variables["relationships"])
    }

    // MARK: - injectMood (#913)

    @Test
    fun injectMoodSetsMyMoodFromNamespacedKey() {
        val variables = mutableMapOf("mood_Alice" to "苛立ち")
        builder.injectMood(variables, "Alice")
        assertEquals("苛立ち", variables["my_mood"])
    }

    @Test
    fun injectMoodSetsEmptyStringOnMiss() {
        val variables = mutableMapOf<String, String>()
        builder.injectMood(variables, "Alice")
        assertEquals("", variables["my_mood"])
    }

    // MARK: - captureMood (#913)

    @Test
    fun captureMoodPersistsNonEmptyMood() {
        val variables = mutableMapOf<String, String>()
        val output = TurnOutput(fields = mapOf("statement" to "hi", "mood" to "わくわく"))
        builder.captureMood(output, variables, "Alice")
        assertEquals("わくわく", variables["mood_Alice"])
    }

    @Test
    fun captureMoodEmptyDoesNotErasePrior() {
        // A failed/empty inference must NOT erase the prior mood — the non-empty
        // guard mirrors ReflectHandler's note save.
        val variables = mutableMapOf("mood_Alice" to "不安")
        val emptyOutput = TurnOutput(fields = mapOf("statement" to "hi", "mood" to ""))
        builder.captureMood(emptyOutput, variables, "Alice")
        assertEquals("不安", variables["mood_Alice"])
    }

    @Test
    fun captureMoodNoOpWhenAbsent() {
        // A phase that never declares mood produces no key → no-op capture.
        val variables = mutableMapOf<String, String>()
        val output = TurnOutput(fields = mapOf("statement" to "hi"))
        builder.captureMood(output, variables, "Alice")
        assertNull(variables["mood_Alice"])
    }

    // MARK: - System-prompt private-notes section (#907)

    @Test
    fun systemPromptContainsNotesSectionWhenSet() {
        val s = scenario()
        val state = stateOf(s, mapOf("notes_Alice" to "NOTE_SENTINEL"))
        val prompt = builder.buildSystemPrompt(s, alice, speakAll, state)
        assertTrue(prompt.contains("あなたの非公開メモ"))
        assertTrue(prompt.contains("NOTE_SENTINEL"))
    }

    @Test
    fun systemPromptOmitsNotesSectionWhenUnset() {
        val s = scenario()
        assertFalse(builder.buildSystemPrompt(s, alice, speakAll, stateOf(s)).contains("あなたの非公開メモ"))
    }

    @Test
    fun systemPromptNotesSectionEnHeader() {
        val s = scenario(language = "en")
        val state = stateOf(s, mapOf("notes_Alice" to "NOTE_SENTINEL"))
        val prompt = builder.buildSystemPrompt(s, alice, speakAll, state)
        assertTrue(prompt.contains("Your Private Notes"))
        assertTrue(prompt.contains("NOTE_SENTINEL"))
    }

    // MARK: - System-prompt private-whispers section (#908)

    private val whisperPhase = Phase(
        type = PhaseType.WHISPER,
        prompt = "Whisper!",
        outputSchema = mapOf("statement" to "string"),
    )

    private val choosePhaseWithOptions = Phase(
        type = PhaseType.CHOOSE,
        prompt = "Choose!",
        outputSchema = mapOf("action" to "string"),
        options = listOf("cooperate", "betray"),
    )

    @Test
    fun systemPromptContainsPrivateWhispersSectionWhenSet() {
        val s = scenario()
        val state = stateOf(s, mapOf("whispers_Alice" to "密談相手: Bob\n  Alice: SENTINEL_AB"))
        val prompt = builder.buildSystemPrompt(s, alice, whisperPhase, state)
        assertTrue(prompt.contains("あなたの密談"))
        assertTrue(prompt.contains("SENTINEL_AB"))
    }

    @Test
    fun systemPromptOmitsPrivateWhispersSectionWhenUnset() {
        val s = scenario()
        assertFalse(builder.buildSystemPrompt(s, alice, whisperPhase, stateOf(s)).contains("あなたの密談"))
    }

    @Test
    fun systemPromptPrivateWhispersSectionEnHeader() {
        val s = scenario(language = "en")
        val state = stateOf(s, mapOf("whispers_Alice" to "Whispering with Bob\n  Alice: SENTINEL_AB"))
        val prompt = builder.buildSystemPrompt(s, alice, whisperPhase, state)
        assertTrue(prompt.contains("Your Private Whispers"))
        assertTrue(prompt.contains("SENTINEL_AB"))
    }

    // MARK: - Whisper privacy answer-rule (whisper phases only, #908)

    @Test
    fun whisperRuleAppendedForWhisperPhaseJa() {
        val s = scenario()
        val prompt = builder.buildSystemPrompt(s, alice, whisperPhase, stateOf(s))
        assertTrue(prompt.contains("これは密談相手ひとりだけへの秘密の耳打ち"))
    }

    @Test
    fun whisperRuleAppendedForWhisperPhaseEn() {
        val s = scenario(language = "en")
        val prompt = builder.buildSystemPrompt(s, alice, whisperPhase, stateOf(s))
        assertTrue(prompt.contains("This is a private whisper to your one partner only"))
    }

    @Test
    fun whisperRuleOmittedForNonWhisperPhase() {
        // A non-whisper phase (speak_all) never gets the whisper privacy rule, even
        // though it shares the same base answer-rule block.
        val s = scenario()
        assertFalse(
            builder.buildSystemPrompt(s, alice, speakAll, stateOf(s))
                .contains("これは密談相手ひとりだけへの秘密の耳打ち"),
        )
    }

    // MARK: - Address answer-rule (#911, speak_each phases only)

    private val speakEach = Phase(
        type = PhaseType.SPEAK_EACH,
        prompt = "Talk.",
        outputSchema = mapOf("statement" to "string"),
    )

    @Test
    fun addressRuleAppendedForSpeakEachPhaseJa() {
        val s = scenario()
        val prompt = builder.buildSystemPrompt(s, alice, speakEach, stateOf(s))
        assertTrue(prompt.contains("そのうち1人の発言に必ず触れてから自分の意見を述べること"))
        // The rule's KDoc calls this clause load-bearing — it is what blocks the
        // agreement-formulae collapse mode. Asserted here so the unit test stands
        // on its own; the parity gate only proves the two engines AGREE.
        assertTrue(prompt.contains("（同意でも反論でも疑問でもよい）"))
        assertTrue(prompt.contains("まだ誰も発言していなければ自由に話してよい"))
    }

    @Test
    fun addressRuleAppendedForSpeakEachPhaseEn() {
        val s = scenario(language = "en")
        val prompt = builder.buildSystemPrompt(s, alice, speakEach, stateOf(s))
        assertTrue(prompt.contains("refer to one of their statements before giving your own opinion"))
        assertTrue(prompt.contains("(agreement, disagreement, or a question all count)"))
        assertTrue(prompt.contains("If no one has spoken yet, speak freely."))
    }

    @Test
    fun addressRuleOmittedForSpeakAllPhase() {
        // NOT a generic "non-speak_each" check — speak_all specifically. The #911
        // harness A/B measured the rule as inert-to-harmful under simultaneous
        // broadcast framing, so this omission is a tuned decision, not an
        // accident of the gate's shape (`PromptBuilder.swift:197-200`).
        val s = scenario()
        assertFalse(
            builder.buildSystemPrompt(s, alice, speakAll, stateOf(s))
                .contains("そのうち1人の発言に必ず触れてから"),
        )
    }

    @Test
    fun addressRulePrecedesTheMoodRuleInTheAnswerRulesBlock() {
        // The rules concatenate into one string, so append ORDER is prompt
        // content. Every other appendix is phase-type-gated and therefore mutually
        // exclusive with `addressRule`; the schema-gated `moodRule` is the only one
        // that can coexist with it. So this is the only shape in which
        // **addressRule's** relative position is observable. (Other type-gated
        // rules pair with `moodRule` the same way — that is not unique to
        // speak_each; what is unique is that it is addressRule's only pairing.)
        val s = scenario()
        val moodySpeakEach = Phase(
            type = PhaseType.SPEAK_EACH,
            prompt = "Talk.",
            outputSchema = mapOf("statement" to "string", "mood" to "string"),
        )
        val prompt = builder.buildSystemPrompt(s, alice, moodySpeakEach, stateOf(s))
        val addressAt = prompt.indexOf("そのうち1人の発言に必ず触れてから")
        val moodAt = prompt.indexOf("moodには今の気分を短い言葉で書くこと")
        assertTrue(addressAt >= 0, "address rule missing")
        assertTrue(moodAt >= 0, "mood rule missing")
        assertTrue(addressAt < moodAt, "address rule must precede the mood rule")
    }

    // MARK: - Choose options answer-rule (choose phases declaring options)

    @Test
    fun chooseOptionsRuleAppendedForChoosePhaseJa() {
        val s = scenario()
        val prompt = builder.buildSystemPrompt(s, alice, choosePhaseWithOptions, stateOf(s))
        assertTrue(prompt.contains("actionフィールドは必ず次のいずれかを書くこと: cooperate, betray"))
    }

    @Test
    fun chooseOptionsRuleAppendedForChoosePhaseEn() {
        val s = scenario(language = "en")
        val prompt = builder.buildSystemPrompt(s, alice, choosePhaseWithOptions, stateOf(s))
        assertTrue(prompt.contains("The action field must be one of: cooperate, betray"))
    }

    @Test
    fun chooseOptionsRuleOmittedForNonChoosePhase() {
        // A non-choose phase never gets the option-list rule, even though it shares
        // the same base answer-rule block.
        val s = scenario()
        assertFalse(
            builder.buildSystemPrompt(s, alice, speakAll, stateOf(s))
                .contains("actionフィールドは必ず次のいずれかを書くこと"),
        )
    }

    @Test
    fun chooseOptionsRuleOmittedWhenTheChoosePhaseDeclaresNoOptions() {
        // The gate is `options != null`, not the phase type alone: an options-less
        // choose has nothing to enumerate, and `ChooseHandler.validateAction` treats
        // it as unconstrained. Reverting the gate to a type-only check renders a
        // dangling "must be one of:" with no list — this test goes red then.
        val s = scenario()
        val optionless = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose!",
            outputSchema = mapOf("action" to "string"),
        )
        assertFalse(
            builder.buildSystemPrompt(s, alice, optionless, stateOf(s))
                .contains("actionフィールドは必ず次のいずれかを書くこと"),
        )
    }

    @Test
    fun anEmptyOptionsListStillRendersTheRuleWithNoOptions() {
        // Pins the documented `options != null` (rule) vs `options.isEmpty()`
        // (ChooseHandler.validateAction) asymmetry: an `options: []` phase passes the
        // rule's gate and renders a dangling list, while the handler treats the same
        // phase as unconstrained. It is Swift-faithful — `PromptBuilder.swift` binds
        // with `let options = phase.options`, the same null-only check — and reachable
        // (no loader/validator rejection; ADR-024 R7 is warning-only). Pinned rather
        // than fixed so the two engines stay byte-comparable; a fix belongs on the
        // Swift side first, in both engines at once.
        val s = scenario()
        val emptyOptions = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose!",
            outputSchema = mapOf("action" to "string"),
            options = emptyList(),
        )
        val prompt = builder.buildSystemPrompt(s, alice, emptyOptions, stateOf(s))
        assertTrue(prompt.contains("actionフィールドは必ず次のいずれかを書くこと: \n"))
    }

    @Test
    fun chooseOptionsRulePrecedesTheMoodRuleMatchingSwiftRuleOrder() {
        // Swift's rule order is speakEach -> reflect -> whisper -> CHOOSE -> vote ->
        // mood. The other rule-membership tests assert via `contains`, which is
        // order-blind, so a silent ordering divergence would survive them all.
        //
        // The choose/VOTE boundary is structurally untestable — a phase cannot be
        // both CHOOSE and VOTE — so this pins the nearest reachable boundary instead:
        // the mood rule is schema-gated (any LLM phase can declare `mood`) and sits
        // LAST in Swift's order, so choose-before-mood transitively pins choose out
        // of the two trailing slots.
        val s = scenario()
        val choosePlusMood = Phase(
            type = PhaseType.CHOOSE,
            prompt = "Choose!",
            outputSchema = mapOf("action" to "string", "mood" to "string"),
            options = listOf("cooperate", "betray"),
        )
        val prompt = builder.buildSystemPrompt(s, alice, choosePlusMood, stateOf(s))
        val chooseAt = prompt.indexOf("actionフィールドは必ず次のいずれかを書くこと")
        val moodAt = prompt.indexOf("moodには今の気分を短い言葉で書くこと")
        assertTrue(chooseAt >= 0, "choose rule missing")
        assertTrue(moodAt >= 0, "mood rule missing")
        assertTrue(chooseAt < moodAt, "choose rule must precede the mood rule")
    }

    // MARK: - System-prompt private-relationships section (#910)

    @Test
    fun systemPromptContainsRelationshipsSectionWhenSet() {
        val s = scenario()
        val state = stateOf(s, mapOf("relationships_Alice" to "SENTINEL_REL_WARY"))
        val prompt = builder.buildSystemPrompt(s, alice, speakAll, state)
        assertTrue(prompt.contains("あなたの人間関係"))
        assertTrue(prompt.contains("SENTINEL_REL_WARY"))
    }

    @Test
    fun systemPromptOmitsRelationshipsSectionWhenUnset() {
        val s = scenario()
        assertFalse(builder.buildSystemPrompt(s, alice, speakAll, stateOf(s)).contains("あなたの人間関係"))
    }

    @Test
    fun systemPromptOmitsRelationshipsSectionWhenEmpty() {
        // An empty summary (no relationship crossed the verbalizer threshold) must
        // not render an empty header, mirroring the reflect / whisper guards.
        val s = scenario()
        val state = stateOf(s, mapOf("relationships_Alice" to ""))
        assertFalse(builder.buildSystemPrompt(s, alice, speakAll, state).contains("あなたの人間関係"))
    }

    @Test
    fun systemPromptRelationshipsSectionEnHeader() {
        val s = scenario(language = "en")
        val state = stateOf(s, mapOf("relationships_Alice" to "SENTINEL_REL_WARY"))
        val prompt = builder.buildSystemPrompt(s, alice, speakAll, state)
        assertTrue(prompt.contains("Your Read on the Others"))
        assertTrue(prompt.contains("SENTINEL_REL_WARY"))
    }

    // MARK: - System-prompt mood section (#913)

    private val moodSpeakPhase = Phase(
        type = PhaseType.SPEAK_ALL,
        prompt = "Speak!",
        outputSchema = mapOf("statement" to "string", "mood" to "string"),
    )

    @Test
    fun systemPromptContainsMoodSectionWhenSet() {
        val s = scenario()
        val state = stateOf(s, mapOf("mood_Alice" to "MOOD_SENTINEL"))
        val prompt = builder.buildSystemPrompt(s, alice, moodSpeakPhase, state)
        assertTrue(prompt.contains("あなたの今の気分"))
        assertTrue(prompt.contains("MOOD_SENTINEL"))
    }

    @Test
    fun systemPromptOmitsMoodSectionWhenUnset() {
        val s = scenario()
        assertFalse(builder.buildSystemPrompt(s, alice, moodSpeakPhase, stateOf(s)).contains("あなたの今の気分"))
    }

    @Test
    fun systemPromptMoodSectionEnHeader() {
        val s = scenario(language = "en")
        val state = stateOf(s, mapOf("mood_Alice" to "MOOD_SENTINEL"))
        val prompt = builder.buildSystemPrompt(s, alice, moodSpeakPhase, state)
        assertTrue(prompt.contains("Your Current Mood"))
        assertTrue(prompt.contains("MOOD_SENTINEL"))
    }

    @Test
    fun systemPromptMoodSurfacesInNonDeclaringPhase() {
        // Mood inertia must survive an intervening non-declaring phase: the mood
        // section surfaces even when the current phase does not declare `mood`.
        val s = scenario()
        val votePhase = Phase(type = PhaseType.VOTE, prompt = "Vote!", outputSchema = mapOf("vote" to "string"))
        val state = stateOf(s, mapOf("mood_Alice" to "MOOD_SENTINEL"))
        assertTrue(builder.buildSystemPrompt(s, alice, votePhase, state).contains("MOOD_SENTINEL"))
    }

    @Test
    fun systemPromptMoodCoexistsWithNotes() {
        // Mood coexists with the reflect-note section (both surface together).
        val s = scenario()
        val state = stateOf(s, mapOf("mood_Alice" to "MOOD_SENTINEL", "notes_Alice" to "NOTE_SENTINEL"))
        val prompt = builder.buildSystemPrompt(s, alice, moodSpeakPhase, state)
        assertTrue(prompt.contains("MOOD_SENTINEL"))
        assertTrue(prompt.contains("NOTE_SENTINEL"))
    }

    // MARK: - Mood answer-rule guidance (declaring phases only)

    @Test
    fun moodAnswerRuleAppendedForDeclaringPhaseJa() {
        val s = scenario()
        val prompt = builder.buildSystemPrompt(s, alice, moodSpeakPhase, stateOf(s))
        assertTrue(prompt.contains("moodには今の気分を短い言葉"))
    }

    @Test
    fun moodAnswerRuleAppendedForDeclaringPhaseEn() {
        val s = scenario(language = "en")
        val prompt = builder.buildSystemPrompt(s, alice, moodSpeakPhase, stateOf(s))
        assertTrue(prompt.contains("Write your current mood in the mood field"))
    }

    @Test
    fun moodAnswerRuleOmittedForNonDeclaringPhase() {
        // A phase that does not declare `mood` never gets the mood-writing rule,
        // even if a carried-over mood is being surfaced in the section above.
        val s = scenario()
        val votePhase = Phase(type = PhaseType.VOTE, prompt = "Vote!", outputSchema = mapOf("vote" to "string"))
        val state = stateOf(s, mapOf("mood_Alice" to "MOOD_SENTINEL"))
        assertFalse(builder.buildSystemPrompt(s, alice, votePhase, state).contains("moodには今の気分を短い言葉"))
    }

    // MARK: - Cross-pair whisper leak guard (default path only, #908)

    @Test
    fun nonParticipantNeverSeesAnotherPairsWhisper() {
        // A NON-participant (Charlie) must never see another pair's whisper sentinel,
        // in NEITHER the system prompt NOR an expanded standard user template, for
        // the speak_all / vote / choose phases. The section is gated on the reader's
        // own `whispers_<name>` key, and `{my_whispers}` resolves empty for Charlie.
        val s = scenario()
        val state = stateOf(
            s,
            mapOf(
                "whispers_Alice" to "密談相手: Bob\n  Alice: SENTINEL_AB",
                "whispers_Bob" to "密談相手: Alice\n  Bob: SENTINEL_AB",
            ),
        )
        val phases = listOf(
            Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak!", outputSchema = mapOf("statement" to "string")),
            Phase(type = PhaseType.VOTE, prompt = "Vote!", outputSchema = mapOf("vote" to "string")),
            Phase(type = PhaseType.CHOOSE, prompt = "Choose!", outputSchema = mapOf("action" to "string")),
        )
        for (phase in phases) {
            val system = builder.buildSystemPrompt(s, charlie, phase, state)
            assertFalse(system.contains("SENTINEL_AB"), "system prompt leaked whisper for ${phase.type}")

            val variables = state.variables.toMutableMap()
            builder.injectWhispers(variables, charlie.name)
            val user = builder.expandTemplate(standardUserTemplate, variables)
            assertFalse(user.contains("SENTINEL_AB"), "user prompt leaked whisper for ${phase.type}")
        }
    }

    @Test
    fun participantSeesOwnWhisper() {
        // The participant (Alice) DOES see her own whisper — in the system-prompt
        // section AND via `{my_whispers}` on a standard template.
        val s = scenario()
        val state = stateOf(s, mapOf("whispers_Alice" to "密談相手: Bob\n  Alice: SENTINEL_AB"))
        val phase = Phase(type = PhaseType.SPEAK_ALL, prompt = "Speak!", outputSchema = mapOf("statement" to "string"))

        val system = builder.buildSystemPrompt(s, alice, phase, state)
        assertTrue(system.contains("SENTINEL_AB"))

        val variables = state.variables.toMutableMap()
        builder.injectWhispers(variables, alice.name)
        val user = builder.expandTemplate(standardUserTemplate, variables)
        assertTrue(user.contains("SENTINEL_AB"))
    }

    // MARK: - Reflect-note brevity answer-rule (reflect phases only, #907)

    private val reflectPhase = Phase(
        type = PhaseType.REFLECT,
        prompt = "Reflect!",
        outputSchema = mapOf("note" to "string"),
    )

    @Test
    fun reflectBrevityRuleAppendedForReflectPhaseJa() {
        val s = scenario()
        val prompt = builder.buildSystemPrompt(s, alice, reflectPhase, stateOf(s))
        assertTrue(prompt.contains("メモ（note）は2文以内"))
    }

    @Test
    fun reflectBrevityRuleAppendedForReflectPhaseEn() {
        val s = scenario(language = "en")
        val prompt = builder.buildSystemPrompt(s, alice, reflectPhase, stateOf(s))
        assertTrue(prompt.contains("Keep your note to at most 2 sentences"))
    }

    @Test
    fun reflectBrevityRuleOmittedForNonReflectPhase() {
        // A non-reflect phase (speak_all) never gets the note-brevity rule, even
        // though it shares the same base answer-rule block.
        val s = scenario()
        assertFalse(builder.buildSystemPrompt(s, alice, speakAll, stateOf(s)).contains("メモ（note）は2文以内"))
    }

    // MARK: - Vote candidate answer-rule (vote phases only)

    private val votePhase = Phase(
        type = PhaseType.VOTE,
        prompt = "Vote!",
        outputSchema = mapOf("vote" to "string"),
    )

    @Test
    fun voteCandidateRuleListsOthersExcludingSelfJa() {
        // exclude_self defaults to true, so Alice's candidate list is the other two
        // in persona order — never herself.
        val s = scenario()
        val prompt = builder.buildSystemPrompt(s, alice, votePhase, stateOf(s))
        assertTrue(prompt.contains("voteフィールドは必ず次の名前のいずれかを正確に書くこと: Bob, Charlie"))
    }

    @Test
    fun voteCandidateRuleListsOthersExcludingSelfEn() {
        val s = scenario(language = "en")
        val prompt = builder.buildSystemPrompt(s, alice, votePhase, stateOf(s))
        assertTrue(prompt.contains("The vote field must be exactly one of these names: Bob, Charlie"))
    }

    @Test
    fun voteCandidateRuleExcludesEliminatedAgents() {
        // Bob eliminated + Alice self-excluded → only Charlie remains a candidate.
        val s = scenario()
        val state = SimulationState.initial(s).copy(eliminated = mapOf("Bob" to true))
        val prompt = builder.buildSystemPrompt(s, alice, votePhase, state)
        assertTrue(prompt.contains("voteフィールドは必ず次の名前のいずれかを正確に書くこと: Charlie"))
    }

    @Test
    fun voteCandidateRuleIncludesSelfWhenExcludeSelfFalse() {
        // exclude_self = false → the voter may vote for herself, so Alice appears in
        // her own candidate list.
        val s = scenario()
        val includeSelf = Phase(
            type = PhaseType.VOTE,
            prompt = "Vote!",
            outputSchema = mapOf("vote" to "string"),
            excludeSelf = false,
        )
        val prompt = builder.buildSystemPrompt(s, alice, includeSelf, stateOf(s))
        assertTrue(prompt.contains("voteフィールドは必ず次の名前のいずれかを正確に書くこと: Alice, Bob, Charlie"))
    }

    @Test
    fun voteCandidateRuleOmittedForNonVotePhase() {
        // A non-vote phase (speak_all) never gets the candidate-list rule.
        val s = scenario()
        assertFalse(builder.buildSystemPrompt(s, alice, speakAll, stateOf(s)).contains("voteフィールドは必ず"))
    }
}
