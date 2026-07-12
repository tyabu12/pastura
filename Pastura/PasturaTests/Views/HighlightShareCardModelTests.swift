import Testing

@testable import Pastura

/// Data-shaping contract for ``HighlightShareCard/Model`` (issue #1070).
///
/// Per ADR-009 / `.claude/rules/view-testing.md`, the rendered card is not
/// tested — only the pure `Model` failable init is: content filtering,
/// empty→nil guards, avatar-slot resolution, and verbatim utterance storage.
/// The 5-line truncation is a render concern (depends on font/width) and is
/// intentionally out of scope here — it is covered by manual device QA.
///
/// `@MainActor` so the nonisolated test can compare `SheepAvatar.Character`
/// values (auto-synth `Equatable` conformance lookup is MainActor-isolated —
/// Pattern 5, `.claude/rules/swift-isolation.md`).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HighlightShareCardModelTests {

  private func model(
    agent: String = "Bob",
    agentPosition: Int? = 1,
    rawUtterance: String = "A memorable line.",
    rawThought: String? = nil,
    scenarioTitle: String? = "Prisoner's Dilemma",
    modelName: String? = "Gemma 4 E2B",
    contentFilter: ContentFilter = ContentFilter(blockedPatterns: [])
  ) -> HighlightShareCard.Model? {
    HighlightShareCard.Model(
      agent: agent, agentPosition: agentPosition, rawUtterance: rawUtterance,
      rawThought: rawThought, scenarioTitle: scenarioTitle, modelName: modelName,
      linkURL: HighlightShareCard.shareLink, contentFilter: contentFilter)
  }

  @Test("ContentFilter is applied to the utterance")
  func filterAppliedToUtterance() throws {
    let filter = ContentFilter(blockedPatterns: ["betray"], replacement: "***")
    let sut = try #require(
      model(rawUtterance: "I planned to betray you.", contentFilter: filter))
    #expect(!sut.utterance.contains("betray"))
    #expect(sut.utterance.contains("***"))
  }

  @Test("Whitespace-only utterance yields nil")
  func emptyUtteranceYieldsNil() {
    #expect(model(rawUtterance: "   \n\t ") == nil)
    #expect(model(rawUtterance: "") == nil)
  }

  @Test("An utterance fully redacted away still yields a model (redaction is visible content)")
  func fullyRedactedYieldsModel() throws {
    // "***" is visible content — only whitespace-emptiness drops the card.
    let filter = ContentFilter(blockedPatterns: ["hi"], replacement: "***")
    let sut = try #require(model(rawUtterance: "hi", contentFilter: filter))
    #expect(sut.utterance == "***")
  }

  @Test("Avatar character resolves by position, then by canonical name")
  func characterResolution() throws {
    // Position wins (allCases[1 % 4] == .bob) regardless of name.
    let byPosition = try #require(model(agent: "Zoe", agentPosition: 1))
    #expect(byPosition.character == .bob)
    // No position → canonical-name match.
    let byName = try #require(model(agent: "Alice", agentPosition: nil))
    #expect(byName.character == .alice)
  }

  @Test("Empty scenario title / model name collapse to nil (line omitted)")
  func emptyLabelsCollapseToNil() throws {
    let sut = try #require(model(scenarioTitle: "  ", modelName: ""))
    #expect(sut.scenarioTitle == nil)
    #expect(sut.modelName == nil)
  }

  @Test("Non-empty labels are trimmed but preserved")
  func labelsTrimmed() throws {
    let sut = try #require(model(scenarioTitle: "  Water Divination  ", modelName: " Gemma 4 E2B "))
    #expect(sut.scenarioTitle == "Water Divination")
    #expect(sut.modelName == "Gemma 4 E2B")
  }

  @Test("Utterance is edge-trimmed; internal spacing preserved")
  func utteranceEdgeTrimmed() throws {
    let sut = try #require(model(rawUtterance: "  keep  the   gaps  "))
    #expect(sut.utterance == "keep  the   gaps")
  }

  // MARK: - Inner thought (心の声, #1080)

  @Test("ContentFilter is applied to the inner thought")
  func filterAppliedToThought() throws {
    let filter = ContentFilter(blockedPatterns: ["betray"], replacement: "***")
    let sut = try #require(model(rawThought: "I will betray them.", contentFilter: filter))
    let thought = try #require(sut.thought)
    #expect(!thought.contains("betray"))
    #expect(thought.contains("***"))
  }

  @Test("Nil raw thought yields a nil thought (utterance-only card)")
  func nilThoughtYieldsNil() throws {
    let sut = try #require(model(rawThought: nil))
    #expect(sut.thought == nil)
  }

  @Test("A thought that filters/trims to empty collapses to nil; model still builds")
  func emptyThoughtCollapsesToNil() throws {
    // Whitespace-only thought → dropped, but the card is still produced.
    let blank = try #require(model(rawThought: "   \n\t "))
    #expect(blank.thought == nil)
    #expect(blank.utterance == "A memorable line.")
    // Thought fully removed by the filter (empty replacement) → dropped.
    let filter = ContentFilter(blockedPatterns: ["secret"], replacement: "")
    let redacted = try #require(model(rawThought: "secret", contentFilter: filter))
    #expect(redacted.thought == nil)
  }

  @Test("A thought redacted to visible content is kept (redaction is visible content)")
  func redactedThoughtKept() throws {
    let filter = ContentFilter(blockedPatterns: ["x"], replacement: "***")
    let sut = try #require(model(rawThought: "x", contentFilter: filter))
    #expect(sut.thought == "***")
  }

  @Test("Inner thought is edge-trimmed; internal spacing preserved")
  func thoughtEdgeTrimmed() throws {
    let sut = try #require(model(rawThought: "  I have   doubts  "))
    #expect(sut.thought == "I have   doubts")
  }
}
