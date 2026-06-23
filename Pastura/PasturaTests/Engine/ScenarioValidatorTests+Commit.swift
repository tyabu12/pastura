import Testing

@testable import Pastura

/// Strict-validation checks that fire only at commit-to-persist time
/// (`ScenarioEditorViewModel.save()`), not on every keystroke and not at
/// runtime. See `ScenarioConventions.swift` for the canonical-field
/// convention these checks enforce.
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

  // MARK: - Conditional sub-phases (canonical-field check recurses depth-1)

  @Test func validateForCommit_rejectsSpeakAllInsideThenBranchMissingStatement() {
    // Regression: `validateCanonicalPrimaryFields` originally walked only
    // `scenario.phases` and ignored `thenPhases` / `elsePhases`. A
    // conditional branch with a misnamed canonical field would slip past
    // the commit gate and recreate the exact "speak_all missing statement"
    // bug class #318 was meant to prevent. Recursion is depth-1 by validator
    // construction so termination is trivial.
    let nested = Phase(
      type: .speakAll, prompt: "Inner.",
      outputSchema: ["appeal": "string"])
    let conditional = Phase(
      type: .conditional, condition: "max_score >= 1",
      thenPhases: [nested])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [conditional])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_rejectsVoteInsideElseBranchMissingVoteField() {
    let nested = Phase(
      type: .vote, prompt: "Vote.",
      outputSchema: ["target": "string"])
    let conditional = Phase(
      type: .conditional, condition: "max_score >= 1",
      thenPhases: [Phase(type: .summarize, template: "ok")],
      elsePhases: [nested])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [conditional])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_acceptsSpeakAllInsideThenBranchWithStatement() throws {
    let nested = Phase(
      type: .speakAll, prompt: "Inner.",
      outputSchema: ["statement": "string"])
    let conditional = Phase(
      type: .conditional, condition: "max_score >= 1",
      thenPhases: [nested])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [conditional])
    _ = try validator.validateForCommit(scenario)
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
      // the canonical field, phase type, and 1-based phase index, not exact
      // wording. The phase-index part of the contract is what lets a user
      // disambiguate when several phases share a type.
      #expect(message.contains("statement"))
      #expect(message.contains("speak_all"))
      #expect(message.contains("Phase 1"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  // MARK: - Canonical thought (secondary) field
  //
  // Companion to the primary-field checks above. The secondary field is
  // OPTIONAL, but when a known secondary key (`inner_thought` / `reason`)
  // is declared it must be the phase's canonical one
  // (`ScenarioConventions.thoughtField(for:)`): vote→reason,
  // speak*/choose→inner_thought. This keeps the streaming THINKING source
  // (`OutputSchema.thoughtFieldName`, schema-driven) and the committed
  // source (`TurnOutput.secondaryText`, phase-hardcoded) reading the same
  // key — a choose authored with `reason` streamed live but went blank on
  // commit (#760).

  @Test func validateForCommit_acceptsChooseWithInnerThought() throws {
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string", "inner_thought": "string"],
      options: ["yes", "no"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validateForCommit(scenario)
  }

  @Test func validateForCommit_rejectsChooseWithReason() {
    // The #760 root case: choose authored `reason` (not canonical
    // `inner_thought`). Streaming surfaced it but the committed row read
    // the empty `inner_thought`, so the reasoning vanished on commit.
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string", "reason": "string"],
      options: ["kinoko", "takenoko"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_rejectsSpeakAllWithReason() {
    // Speak phases are canonical-`inner_thought` too, so a stray `reason`
    // is rejected — symmetric to the choose case.
    let phase = Phase(
      type: .speakAll, prompt: "Speak.",
      outputSchema: ["statement": "string", "reason": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_rejectsVoteWithInnerThought() {
    // Vote's canonical secondary is `reason`; `inner_thought` is the wrong
    // key for vote (the inverse of the choose/speak direction).
    let phase = Phase(
      type: .vote, prompt: "Vote.",
      outputSchema: ["vote": "string", "inner_thought": "string"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_rejectsChooseWithBothInnerThoughtAndReason() {
    // The rule must inspect EVERY declared known-secondary key, not just
    // `OutputSchema.thoughtFieldName`'s priority pick (which returns
    // `inner_thought` here and would miss the stray `reason`).
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: [
        "action": "string", "inner_thought": "string", "reason": "string"
      ],
      options: ["yes", "no"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_acceptsChooseWithNoSecondaryField() throws {
    // Secondary is optional — only the canonical primary (`action`) plus
    // no thought field still passes.
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string"],
      options: ["yes", "no"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validateForCommit(scenario)
  }

  @Test func validateForCommit_acceptsUnknownSecondaryKey() throws {
    // The rule keys only on `OutputSchema.knownSecondaryKeys`
    // (inner_thought / reason). A non-known extra field (`notes`) is not a
    // secondary key and must not trip the check.
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string", "notes": "string"],
      options: ["yes", "no"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validateForCommit(scenario)
  }

  @Test func validate_acceptsChooseWithReason() throws {
    // Runtime `validate(_:)` stays lenient — only `validateForCommit`
    // enforces the canonical thought-field rule, so a scenario authored
    // before this convention still runs.
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string", "reason": "string"],
      options: ["kinoko", "takenoko"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    _ = try validator.validate(scenario)
  }

  @Test func validateForCommit_rejectsChooseWithReasonInsideThenBranch() {
    // Recurses into conditional branches, same as the primary-field check.
    let nested = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string", "reason": "string"],
      options: ["yes", "no"])
    let conditional = Phase(
      type: .conditional, condition: "max_score >= 1",
      thenPhases: [nested])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [conditional])
    #expect(throws: SimulationError.self) {
      try validator.validateForCommit(scenario)
    }
  }

  @Test func validateForCommit_thoughtFieldErrorMentionsPhaseAndKeys() {
    let phase = Phase(
      type: .choose, prompt: "Choose.",
      outputSchema: ["action": "string", "reason": "string"],
      options: ["yes", "no"])
    let scenario = makeScenario(agents: 2, rounds: 1, phases: [phase])
    do {
      _ = try validator.validateForCommit(scenario)
      Issue.record("Expected validateForCommit to throw")
    } catch let SimulationError.scenarioValidationFailed(message) {
      // Partial-match per CLAUDE.md i18n rule — the message names the
      // canonical field, the offending field, the phase type, and the
      // 1-based phase index.
      #expect(message.contains("inner_thought"))
      #expect(message.contains("reason"))
      #expect(message.contains("choose"))
      #expect(message.contains("Phase 1"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }
}
