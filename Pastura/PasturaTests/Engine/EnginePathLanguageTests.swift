import Testing

@testable import Pastura

// MARK: - Helpers

/// Builds a system prompt for an English-language scenario with `speakAll` phase.
private func makeEnglishSystemPrompt(
  language: String = "en",
  phaseType: PhaseType = .speakAll,
  options: [String]? = nil,
  excludeSelf: Bool? = nil
) -> String {
  let scenario = makeTestScenario(
    agentNames: ["Alice", "Bob"],
    language: language,
    phases: [
      Phase(
        type: phaseType,
        prompt: "Go!",
        outputSchema: ["statement": "string"],
        options: options,
        excludeSelf: excludeSelf)
    ]
  )
  let persona = scenario.personas[0]
  let phase = scenario.phases[0]
  let state = SimulationState.initial(for: scenario)
  return PromptBuilder().buildSystemPrompt(
    scenario: scenario, persona: persona, phase: phase, state: state)
}

// MARK: - Suite

@Suite(.timeLimit(.minutes(1)))
struct EnginePathLanguageTests {

  // MARK: - PromptBuilder English path (DoD #3, #6)

  @Test func promptBuilderEmitsEnglishHeaderForEnLanguage() {
    let prompt = makeEnglishSystemPrompt()
    #expect(prompt.contains("You are a participant in a simulation"))
    #expect(!prompt.contains("あなたはシミュレーション"))
  }

  @Test func promptBuilderEmitsEnglishScenarioHeader() {
    let prompt = makeEnglishSystemPrompt()
    #expect(prompt.contains("## Scenario"))
    #expect(!prompt.contains("## シナリオ"))
  }

  @Test func promptBuilderEmitsEnglishPersonaHeader() {
    let prompt = makeEnglishSystemPrompt()
    #expect(prompt.contains("## Your Character"))
    #expect(prompt.contains("Name: "))
    #expect(!prompt.contains("## あなたのキャラクター"))
    #expect(!prompt.contains("名前: "))
  }

  @Test func promptBuilderEmitsEnglishResponseRules() {
    let prompt = makeEnglishSystemPrompt()
    #expect(prompt.contains("## Response Rules (strict)"))
    #expect(!prompt.contains("## 回答ルール"))
  }

  @Test func promptBuilderEmitsEnglishChooseConstraint() {
    let prompt = makeEnglishSystemPrompt(
      phaseType: .choose,
      options: ["cooperate", "betray"])
    #expect(prompt.contains("The action field must be one of:"))
    #expect(!prompt.contains("actionフィールド"))
  }

  @Test func promptBuilderEmitsEnglishVoteConstraint() {
    let prompt = makeEnglishSystemPrompt(
      phaseType: .vote,
      excludeSelf: true)
    #expect(prompt.contains("The vote field must be exactly one of these names:"))
    #expect(!prompt.contains("voteフィールド"))
  }

  @Test func promptBuilderEmitsEnglishOutputFormatHeader() {
    let prompt = makeEnglishSystemPrompt()
    #expect(prompt.contains("## Output Format (JSON)"))
    #expect(prompt.contains("Example:"))
    #expect(!prompt.contains("## 出力フォーマット"))
    #expect(!prompt.contains("例:"))
  }

  @Test func promptBuilderEmitsEnglishPlaceholderSyntax() {
    let prompt = makeEnglishSystemPrompt()
    #expect(prompt.contains("<insert "))
    #expect(!prompt.contains("<ここに"))
  }

  // MARK: - Conversation log (DoD #3)

  @Test func formatConversationLogEmptyEnReturnsNoneYet() {
    let result = PromptBuilder().formatConversationLog([], language: "en")
    #expect(result == "(none yet)")
  }

  // MARK: - WordwolfJudgeLogic English path (DoD #3)

  @Test func wordwolfJudgeEmitsEnglishMajorityWinSummary() {
    let logic = WordwolfJudgeLogic()
    var state = SimulationState()
    state.voteResults = ["Wolf": 3, "Innocent": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, language: "en", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("The wolf was found"))
    #expect(!summaries[0].contains("多数派の勝ち"))
  }

  @Test func wordwolfJudgeEmitsEnglishWolfWinSummary() {
    let logic = WordwolfJudgeLogic()
    var state = SimulationState()
    state.voteResults = ["Innocent": 3, "Wolf": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, language: "en", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("Escaped detection"))
    #expect(!summaries[0].contains("ウルフの勝ち"))
  }

  @Test func wordwolfJudgeEmitsEnglishNoVoteSummary() {
    let logic = WordwolfJudgeLogic()
    var state = SimulationState()
    // empty voteResults
    let collector = EventCollector()
    logic.calculate(state: &state, language: "en", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("No votes recorded"))
    #expect(!summaries[0].contains("投票結果がありません"))
  }

  // MARK: - No Japanese codepoints in English prompt (DoD critic Axis 7)

  @Test func noJapaneseCodepointsInEnglishSystemPrompt() {
    let prompt = makeEnglishSystemPrompt()
    let hasJapanese = prompt.unicodeScalars.contains { scalar in
      // Hiragana (U+3040–U+30FF) + Katakana + CJK Unified (U+4E00–U+9FFF)
      (scalar.value >= 0x3040 && scalar.value <= 0x30FF)
        || (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF)
    }
    #expect(!hasJapanese, "English prompt must not contain Japanese codepoints: \(prompt)")
  }

  // MARK: - simulationLanguage override drives PromptBuilder (ADR-010 D5 / D6 row 1)

  /// Helper: build a prompt for an arbitrary `(language, simulationLanguage)` pair.
  private func makeOverridePrompt(language: String, simulationLanguage: String?) -> String {
    let scenario = ScenarioFixture.make(
      language: language,
      simulationLanguage: simulationLanguage,
      phases: [
        Phase(
          type: .speakAll,
          prompt: "Go!",
          outputSchema: ["statement": "string"])
      ]
    )
    let persona = scenario.personas[0]
    let phase = scenario.phases[0]
    let state = SimulationState.initial(for: scenario)
    return PromptBuilder().buildSystemPrompt(
      scenario: scenario, persona: persona, phase: phase, state: state)
  }

  /// Canonical Step E case: a Japanese-authored scenario rendered in English via
  /// `simulation_language: en`. Engine MUST emit English; Japanese MUST be absent.
  @Test func promptBuilderHonorsSimulationLanguageOverrideJaToEn() {
    let prompt = makeOverridePrompt(language: "ja", simulationLanguage: "en")
    #expect(prompt.contains("You are a participant in a simulation"))
    #expect(prompt.contains("## Scenario"))
    #expect(!prompt.contains("あなたはシミュレーション"))
    #expect(!prompt.contains("## シナリオ"))
  }

  /// Reverse direction: English-authored scenario rendered in Japanese via
  /// `simulation_language: ja`.
  @Test func promptBuilderHonorsSimulationLanguageOverrideEnToJa() {
    let prompt = makeOverridePrompt(language: "en", simulationLanguage: "ja")
    #expect(prompt.contains("あなたはシミュレーション"))
    #expect(prompt.contains("## シナリオ"))
    #expect(!prompt.contains("You are a participant in a simulation"))
    #expect(!prompt.contains("## Scenario"))
  }

  /// Regression guard: with no override, `language` still drives the Engine.
  /// Without this, an `engineLanguage` implementation that always read
  /// `simulationLanguage` (forgetting the `?? language` fallback) would
  /// pass the override tests but silently break every existing scenario.
  @Test func promptBuilderFallsThroughToLanguageWhenSimulationLanguageNil() {
    let jaPrompt = makeOverridePrompt(language: "ja", simulationLanguage: nil)
    #expect(jaPrompt.contains("あなたはシミュレーション"))
    #expect(!jaPrompt.contains("You are a participant in a simulation"))

    let enPrompt = makeOverridePrompt(language: "en", simulationLanguage: nil)
    #expect(enPrompt.contains("You are a participant in a simulation"))
    #expect(!enPrompt.contains("あなたはシミュレーション"))
  }
}

// MARK: - ContentFilter cross-language (DoD #7)

// ContentFilter tests for cross-language coverage. The production
// ContentFilter applies blocklist patterns as regex regardless of language,
// so Japanese-pattern hits also apply to English-context output.
// The existing ContentFilterTests cover this path implicitly via
// `filterReplacesBlockedEnglishWordsCaseInsensitive` (English patterns work)
// and `filterReplacesBlockedJapaneseWords` (Japanese patterns work). Those
// tests use custom blocklists; the production blocklist from
// `ContentBlocklist.json` is exercised in ContentBlocklistTests.
// A dedicated cross-language test (Japanese-blocklist hit on English scenario
// output) is omitted here because ContentFilter is language-agnostic by
// construction — there is no language parameter to test against.
