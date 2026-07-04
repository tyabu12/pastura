import Foundation
import Testing

@testable import Pastura

// MARK: - Prompt Hardening (#194 PR#a Item 3) + Brevity Rule (#877)
//
// Sibling-file extension per the testing.md split convention — NOT a new
// @Suite (a second suite would run in parallel against the same shared
// state class; see PR #157). Helpers (`builder`, `makeScenario`) stay at
// internal access in PromptBuilderTests.swift so this file can see them.
extension PromptBuilderTests {

  // Two new rule lines added in PR#a Item 3 — assert both are present
  // so a future refactor doesn't silently drop the structural-validity
  // emphasis that reduces Hyp A frequency.
  @Test func systemPromptIncludesAugmentedSyntaxRules() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("JSONに構文エラーがあると失敗扱いになる"))
    #expect(prompt.contains("単一オブジェクトのみ出力"))
  }

  // Brevity soft-rule (#877): the base rules must cap the primary
  // statement field at 3 sentences in BOTH languages, so phase-rich
  // scenarios stay readable in playback. Scope is the main text field
  // only — inner_thought is intentionally unconstrained (critic Axis 6).
  @Test func systemPromptIncludesBrevityRuleJa() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("3文以内で簡潔に"))
  }

  @Test func systemPromptIncludesBrevityRuleEn() {
    let scenario = makeScenario(language: "en")
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("at most 3 sentences"))
  }

  // Address rule (#911, harness-A/B-tuned): turn-based speak_each otherwise
  // produces parallel monologues (0 % cross-reference at baseline). The rule
  // lifted word_wolf address-rate to ~0.2–0.33 in BOTH ja and en with no
  // agreement-formulae collapse. Scoped to speak_each ONLY.
  @Test func systemPromptIncludesAddressRuleForSpeakEachJa() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakEach,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("必ず触れてから"))
  }

  @Test func systemPromptIncludesAddressRuleForSpeakEachEn() {
    let scenario = makeScenario(language: "en")
    let phase = Phase(
      type: .speakEach,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("refer to one of their statements"))
  }

  // Load-bearing scope guard: the A/B showed the address rule is inert on
  // speak_all (simultaneous broadcast framing dominates) and mildly harmful
  // there (parse-failure + boke-copying), so `buildAnswerRules` must NOT
  // append it for .speakAll. If this fails, the scope guard regressed (#911).
  @Test func systemPromptOmitsAddressRuleForSpeakAll() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(!prompt.contains("必ず触れてから"))
  }

  // The scope guard is language-independent (a `phase.type` check ahead of
  // pickLanguage), so speak_all omits the rule in en as well as ja.
  @Test func systemPromptOmitsAddressRuleForSpeakAllEn() {
    let scenario = makeScenario(language: "en")
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(!prompt.contains("refer to one of their statements"))
  }

  // Placeholder example must appear when outputSchema is set, AND must
  // use placeholder syntax (`<ここに...>`) — concrete Japanese values
  // would risk Gemma 2B parroting the demonstrated content (round 2
  // Axis 5 finding).
  @Test func systemPromptIncludesPlaceholderExampleWhenSchemaSet() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string", "inner_thought": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    let exampleLine =
      prompt.components(separatedBy: "\n")
      .first { $0.hasPrefix("例:") } ?? ""
    #expect(!exampleLine.isEmpty, "expected an `例:` line in the output format section")
    #expect(exampleLine.contains("<ここに"), "placeholder convention must be `<ここに{key}>`")
    #expect(exampleLine.contains(">"))
    #expect(exampleLine.contains("statement"))
    #expect(exampleLine.contains("inner_thought"))
  }

  @Test func systemPromptOmitsExampleWhenNoOutputSchema() {
    let scenario = makeScenario()
    let phase = Phase(type: .speakAll, prompt: "Speak!")  // no outputSchema
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(!prompt.contains("例:"))
  }

  // Char-count regression guard — total prompt growth from PR#a Item 3
  // must stay within +300 chars of the equivalent pre-PR prompt for the
  // largest preset schema (2 keys per phase across current presets).
  // Loose upper bound: well under 7K chars for an 8K context model.
  @Test func systemPromptCharCountStaysWithinBudget() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["statement": "string", "inner_thought": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    // Budget reasoning: scenario + persona + 7 rule lines + format spec
    // (~2 short lines) for a 2-key schema fits comfortably under 1500
    // chars on the test scenario; CI bound at 2000 leaves room for
    // future minor additions without rebaselining the test.
    #expect(prompt.count < 2000, "prompt grew larger than expected: \(prompt.count) chars")
  }

  // Primary-first ordering (#194 PR#b): the placeholder example and the
  // output-format spec line must both list `statement` before
  // `inner_thought` — alphabetical would invert this and break
  // PartialOutputExtractor's streaming UX (user sees nothing until
  // inner_thought finishes). Source of truth: OutputSchema.fields.
  // MARK: - Reflect private-notes injection (#907)

  // The agent's own prior-round memo is surfaced in the system prompt
  // (invisible to other participants) so subsequent LLM calls are
  // grounded in what the agent privately concluded.
  @Test func systemPromptContainsPrivateNotesSectionWhenSet() {
    let scenario = makeScenario()
    let phase = Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])
    var state = SimulationState.initial(for: scenario)
    state.variables["notes_Alice"] = "I suspect Bob is the wolf."

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("あなたの内心メモ"))
    #expect(prompt.contains("I suspect Bob is the wolf."))
  }

  @Test func systemPromptOmitsPrivateNotesSectionWhenUnset() {
    let scenario = makeScenario()
    let phase = Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(!prompt.contains("あなたの内心メモ"))
  }

  @Test func systemPromptPrivateNotesSectionEnHeader() {
    let scenario = makeScenario(language: "en")
    let phase = Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])
    var state = SimulationState.initial(for: scenario)
    state.variables["notes_Alice"] = "Bob seems nervous."

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("Your Private Notes"))
    #expect(prompt.contains("Bob seems nervous."))
  }

  @Test func injectNotesSetsMyNotesFromNamespacedKey() {
    var variables = ["notes_Alice": "remember the clue"]
    builder.injectNotes(into: &variables, personaName: "Alice")
    #expect(variables["my_notes"] == "remember the clue")
  }

  @Test func injectNotesSetsEmptyStringOnMiss() {
    var variables: [String: String] = [:]
    builder.injectNotes(into: &variables, personaName: "Alice")
    #expect(variables["my_notes"] == "")
  }

  // The reflect-specific brevity rule caps the note at 2 sentences, matching
  // the #877 constraint family. It must appear ONLY for reflect phases.
  @Test func reflectAnswerRulesIncludeTwoSentenceBrevityJa() {
    let scenario = makeScenario()
    let phase = Phase(type: .reflect, prompt: "Reflect!", outputSchema: ["note": "string"])
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("2文以内"))
  }

  @Test func reflectAnswerRulesIncludeTwoSentenceBrevityEn() {
    let scenario = makeScenario(language: "en")
    let phase = Phase(type: .reflect, prompt: "Reflect!", outputSchema: ["note": "string"])
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(prompt.contains("at most 2 sentences"))
  }

  @Test func nonReflectPhaseOmitsTwoSentenceBrevityRule() {
    let scenario = makeScenario()
    let phase = Phase(type: .speakAll, prompt: "Speak!", outputSchema: ["statement": "string"])
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    #expect(!prompt.contains("2文以内"))
  }

  @Test func systemPromptExampleUsesPrimaryFirstOrder() {
    let scenario = makeScenario()
    let phase = Phase(
      type: .speakAll,
      prompt: "Speak!",
      outputSchema: ["inner_thought": "string", "statement": "string"]
    )
    let state = SimulationState.initial(for: scenario)

    let prompt = builder.buildSystemPrompt(
      scenario: scenario, persona: scenario.personas[0], phase: phase, state: state
    )
    // Both the spec line (`{"statement": ...}`) and the `例:` line must
    // have statement appear before inner_thought.
    let specLine =
      prompt.components(separatedBy: "\n")
      .first { $0.hasPrefix("{\"") } ?? ""
    let exampleLine =
      prompt.components(separatedBy: "\n")
      .first { $0.hasPrefix("例:") } ?? ""
    for line in [specLine, exampleLine] {
      guard
        let sIdx = line.range(of: "statement")?.lowerBound,
        let tIdx = line.range(of: "inner_thought")?.lowerBound
      else {
        Issue.record("expected both keys in line: \(line)")
        continue
      }
      #expect(
        sIdx < tIdx,
        "statement must precede inner_thought in primary-first order: \(line)")
    }
  }
}
