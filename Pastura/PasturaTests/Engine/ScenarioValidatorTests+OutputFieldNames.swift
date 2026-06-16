import Testing

@testable import Pastura

// #607: output `field NAMES` (the `output:` block keys) are emitted as GBNF
// JSON-key literals, so a CJK / multi-byte key crashes llama.cpp's sampler at
// accept-time on-device (same mechanism as the #599 CJK choose-option removal).
// `ScenarioValidator` surfaces the ASCII-identifier rule at the run-gate +
// editor as a clear load-time error; `GBNFGrammarBuilder` is the unconditional
// backstop. These tests exercise the validator (run-gate) path. Sibling
// extension of `ScenarioValidatorTests` (NOT a new @Suite) per
// `.claude/rules/testing.md` — reuses the suite's `makeScenario` helper.
extension ScenarioValidatorTests {
  @Test func rejectsCjkPrimaryOutputKey() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [Phase(type: .speakAll, prompt: "p", outputSchema: ["内なる思考": "string"])])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  /// Critic Axis 2: a valid canonical primary does NOT excuse a hostile
  /// *secondary* key — every output key reaches the grammar, so all keys are
  /// gated, not just the canonical primary.
  @Test func rejectsCjkSecondaryOutputKey() {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(
          type: .speakAll, prompt: "p",
          outputSchema: ["statement": "string", "内なる思考": "string"])
      ])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  /// Emoji / accented-Latin keys are equally rejected — the boundary is ASCII,
  /// not "CJK specifically".
  @Test func rejectsNonAsciiLatinAndEmojiOutputKeys() {
    for badKey in ["café", "emoji😀", "naïve"] {
      let scenario = makeScenario(
        agents: 2, rounds: 1,
        phases: [Phase(type: .speakAll, prompt: "p", outputSchema: [badKey: "string"])])
      #expect(
        throws: SimulationError.self, "key '\(badKey)' should be rejected"
      ) {
        try validator.validate(scenario)
      }
    }
  }

  /// Hostile keys buried inside a conditional `then:` / `else:` branch are
  /// caught by the same recursion that runs the canonical-field check.
  @Test func rejectsCjkOutputKeyInsideConditionalBranch() {
    let nested = Phase(type: .speakAll, prompt: "p", outputSchema: ["статус": "string"])
    let conditional = Phase(
      type: .conditional, condition: "max_score >= 1", thenPhases: [nested])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [conditional])
    #expect(throws: SimulationError.self) {
      try validator.validate(scenario)
    }
  }

  /// Control: ASCII snake_case keys (the shape every preset uses) pass clean.
  @Test func acceptsAsciiOutputKeys() throws {
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(
          type: .speakAll, prompt: "p",
          outputSchema: ["statement": "string", "inner_thought": "string"])
      ])
    let result = try validator.validate(scenario)
    #expect(result.warnings.isEmpty)
  }
}
