import Testing

@testable import Pastura

// MARK: - Per-phase max_sentences range (#881)
//
// Sibling-file extension per the testing.md split convention — NOT a new
// @Suite (helpers `validator` / `makeScenario` stay internal in the main file).
extension ScenarioValidatorTests {

  @Test func rejectsMaxSentencesBelowRange() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .speakAll, maxSentences: 0)])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func rejectsMaxSentencesAboveRange() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .speakAll, maxSentences: 7)])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  @Test func acceptsMaxSentencesAtBounds() throws {
    for value in [1, 6] {
      let scenario = makeScenario(
        agents: 2, rounds: 1, phases: [Phase(type: .speakAll, maxSentences: value)])
      #expect(throws: Never.self) {
        try validator.validate(scenario)
      }
    }
  }

  @Test func acceptsNilMaxSentences() throws {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [Phase(type: .speakAll, maxSentences: nil)])
    #expect(throws: Never.self) {
      try validator.validate(scenario)
    }
  }

  /// The range check runs at the `validateBranch` traversal site too — an
  /// out-of-range value on a phase nested inside a conditional `then:` is
  /// rejected, not silently skipped.
  @Test func rejectsOutOfRangeInNestedBranch() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(
          type: .conditional, condition: "max_score >= 10",
          thenPhases: [Phase(type: .speakAll, maxSentences: 0)])
      ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }
}
