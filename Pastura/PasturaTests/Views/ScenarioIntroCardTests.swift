import Testing

@testable import Pastura

/// Pure-logic coverage for ``ScenarioIntroCard/Model`` — the opening-card
/// presentation model shown above the simulation log (issue #853).
///
/// Per ADR-009 / `.claude/rules/view-testing.md` rule 1, only the model's
/// visibility derivation is unit-tested; the card's layout / animation is
/// left to code review + manual device QA (rule 4).
///
/// The load-bearing behavior under test is the empty-premise guard: an
/// empty / whitespace-only premise must yield `nil` so the caller renders
/// nothing — the same "absent text renders no element" posture the scenario
/// rows take — rather than an empty card box above the log.
@Suite(.timeLimit(.minutes(1)))
struct ScenarioIntroCardTests {
  @Test("A non-empty premise yields a model preserving title and premise")
  func nonEmptyPremise() {
    let model = ScenarioIntroCard.Model(
      title: "ワードウルフ", premise: "5人の参加者に「お題」が配られる。")
    #expect(model != nil)
    #expect(model?.title == "ワードウルフ")
    #expect(model?.premise == "5人の参加者に「お題」が配られる。")
  }

  @Test("An empty premise yields nil so the card is hidden")
  func emptyPremise() {
    #expect(ScenarioIntroCard.Model(title: "X", premise: "") == nil)
  }

  @Test("A whitespace-only premise yields nil")
  func whitespacePremise() {
    #expect(ScenarioIntroCard.Model(title: "X", premise: "   \n\t ") == nil)
  }

  @Test("A nil title is allowed when a premise is present")
  func nilTitleWithPremise() {
    let model = ScenarioIntroCard.Model(title: nil, premise: "premise text")
    #expect(model != nil)
    #expect(model?.title == nil)
    #expect(model?.premise == "premise text")
  }

  @Test("The premise is preserved verbatim, including internal whitespace")
  func premiseVerbatim() {
    // Demo replay descriptions carry stray internal spaces from line-wrapping
    // (e.g. "全力の 珍回答"); the guard trims only for the emptiness check and
    // must not mutate the stored premise.
    let model = ScenarioIntroCard.Model(title: nil, premise: "  全力の 珍回答  ")
    #expect(model?.premise == "  全力の 珍回答  ")
  }
}
