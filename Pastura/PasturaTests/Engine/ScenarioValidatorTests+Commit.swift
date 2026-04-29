import Testing

@testable import Pastura

/// Strict-validation checks that fire only at commit-to-persist time
/// (`ImportViewModel.save()` / `ScenarioEditorViewModel.save()`), not on
/// every keystroke and not at runtime. See `ScenarioConventions.swift`
/// for the canonical-field convention these checks enforce.
extension ScenarioValidatorTests {

  // MARK: - Speak phases (canonical: statement)

  @Test func validateForCommit_acceptsSpeakAllWithStatement() throws {
    let phase = Phase(
      type: .speakAll, prompt: "Speak.",
      outputSchema: ["statement": "string", "inner_thought": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validateForCommit(scenario)
  }

  @Test func validateForCommit_acceptsSpeakEachWithStatement() throws {
    let phase = Phase(
      type: .speakEach, prompt: "Speak.",
      outputSchema: ["statement": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validateForCommit(scenario)
  }

  @Test func validateForCommit_rejectsSpeakAllWithoutStatement() {
    let phase = Phase(
      type: .speakAll, prompt: "Speak.",
      outputSchema: ["appeal": "string", "inner_thought": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_rejectsSpeakEachWithBokeAlias() {
    // The legacy `boke:` alias was dropped in #309 — must now error.
    let phase = Phase(
      type: .speakEach, prompt: "Speak.",
      outputSchema: ["boke": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_rejectsSpeakAllWithMissingOutputSchema() {
    let phase = Phase(type: .speakAll, prompt: "Speak.")
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  // MARK: - Choose (canonical: action)

  @Test func validateForCommit_acceptsChooseWithAction() throws {
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string"],
      options: ["yes", "no"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validateForCommit(scenario)
  }

  @Test func validateForCommit_rejectsChooseWithFactionAlias() {
    // The kinoko gallery scenario was previously broken by `faction:` —
    // OutputSchema.from binds the GBNF enum constraint only on field name
    // `action`, and ChooseHandler reads `output.action` directly, so any
    // other name silently defaults every agent to options[0]. The
    // canonical check at commit time is the structural fix.
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["faction": "string"],
      options: ["kinoko", "takenoko"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  // MARK: - Vote (canonical: vote)

  @Test func validateForCommit_acceptsVoteWithVoteField() throws {
    let phase = Phase(
      type: .vote, prompt: "Vote.",
      outputSchema: ["vote": "string", "reason": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validateForCommit(scenario)
  }

  @Test func validateForCommit_rejectsVoteWithoutVoteField() {
    let phase = Phase(
      type: .vote, prompt: "Vote.",
      outputSchema: ["target": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  // MARK: - Code phases (no canonical field — exempt)

  @Test func validateForCommit_acceptsCodePhases() throws {
    // Code phases (score_calc / summarize / assign / eliminate) emit no
    // LLM output and have no canonical primary field — they should pass
    // the commit gate without an `output:` schema.
    let phases: [Phase] = [
      Phase(
        type: .speakAll, prompt: "Speak.",
        outputSchema: ["statement": "string"]),
      Phase(type: .summarize, template: "Round done"),
      Phase(type: .eliminate)
    ]
    let scenario = makeScenario(agents: 2, rounds: 1, phases: phases)
    _ = try validator.validateForCommit(scenario)
  }

  // MARK: - Composes with `validate(_:)`

  @Test func validateForCommit_runsValidateChecksFirst() {
    // A scenario that fails the agent-count check should still throw —
    // validateForCommit composes by calling validate(_:) before adding
    // the canonical-field check.
    let phase = Phase(
      type: .speakAll, prompt: "Speak.",
      outputSchema: ["statement": "string"])
    let scenario = makeScenario(agents: 0, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  // MARK: - Runtime path is lenient (regression guard)

  @Test func validate_acceptsScenarioMissingCanonicalSpeakField() throws {
    // The regular `validate(_:)` path (used by `SimulationRunner`) must
    // NOT enforce the canonical-field rule — only `validateForCommit`
    // does. Otherwise a scenario authored before this convention landed
    // could refuse to run.
    let phase = Phase(
      type: .speakAll, prompt: "Speak.",
      outputSchema: ["appeal": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validate(scenario)
  }

  // MARK: - Error message includes phase index + canonical field name

  @Test func validateForCommit_errorMentionsPhaseAndCanonicalField() {
    let phase = Phase(
      type: .speakAll, prompt: "Speak.",
      outputSchema: ["appeal": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    do {
      _ = try validator.validateForCommit(scenario)
      Issue.record("Expected validateForCommit to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      // Partial-match per CLAUDE.md i18n rule — assert the message names
      // the canonical field and the phase, not exact wording.
      #expect(message.contains("statement"))
      #expect(message.contains("speak_all"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }
}
