import Testing

@testable import Pastura

/// Locks ``ScenarioValidationMessage/localized`` rendering to the byte-identical
/// strings the Engine emitted before the S0.1 de-localization refactor (#501).
/// Focus: argument order + multi-arg / shared / no-arg / multi-line-wrapped
/// literals — a `.contains` substring test cannot catch an arg-order swap, so
/// these assert the full rendered string. English base locale (CI default).
@Suite(.timeLimit(.minutes(1)))
struct ScenarioValidationMessageTests {

  // MARK: %lld formatting (Int arg → %lld, matching pre-refactor CVarArg behavior)

  @Test func agentCountBelowMinimumRendersInt() {
    #expect(
      ScenarioValidationMessage.agentCountBelowMinimum(1).localized
        == "Agent count (1) is below minimum of 2")
  }

  @Test func personaCountMismatchOrdersBothInts() {
    // Two %lld — arg order is personaCount then agentCount.
    #expect(
      ScenarioValidationMessage.personaCountMismatch(personaCount: 3, agentCount: 5).localized
        == "Persona count (3) does not match agent count (5)")
  }

  @Test func agentsPersonasCountMismatchOrdersBothInts() {
    #expect(
      ScenarioValidationMessage.agentsPersonasCountMismatch(agentCount: 5, personaCount: 3)
        .localized
        == "agents (5) does not match personas count (3)")
  }

  @Test func highInferenceWarningRendersMultiLineLiteral() {
    // The `rg 'String(localized:'` blind spot — literal was multi-line-wrapped.
    #expect(
      ScenarioValidationMessage.highInferenceCount(72).localized
        == "High inference count (72). Simulation may take several minutes.")
  }

  // MARK: Shared / multi-arg literals (arg order is load-bearing)

  @Test func languageNotAcceptedOrdersAllowedThenGot() {
    #expect(
      ScenarioValidationMessage.languageNotAccepted(allowed: "en, ja", got: "fr").localized
        == "Scenario: field 'language' must be one of {en, ja}, got 'fr'")
  }

  @Test func requiresOutputFieldOrdersThreeArgs() {
    #expect(
      ScenarioValidationMessage.requiresOutputField(
        label: "Phase 1", type: "reflect", field: "note"
      ).localized == "Phase 1 (reflect) requires field 'note' in output.")
  }

  @Test func secondaryFieldMismatchOrdersFourArgs() {
    #expect(
      ScenarioValidationMessage.secondaryFieldMismatch(
        label: "Phase 2", type: "vote", canonical: "reason", key: "inner_thought"
      ).localized == "Phase 2 (vote) secondary field must be 'reason', not 'inner_thought'.")
  }

  @Test func fieldWrongTypeOrdersFourArgs() {
    #expect(
      ScenarioValidationMessage.fieldWrongType(
        label: "Scenario", key: "agents", expected: "Int", got: "String"
      ).localized == "Scenario: field 'agents' must be Int, got String")
  }

  @Test func sourceNotFoundRepeatsSourceArgTwice() {
    // Literal has three %@; `source` is substituted into positions 2 and 3.
    #expect(
      ScenarioValidationMessage.sourceNotFound(label: "Phase 3", source: "roles").localized
        == "Phase 3: source 'roles' not found in scenario data. "
        + "Add a top-level 'roles' field to the scenario YAML.")
  }

  @Test func nestedConditionalRendersSharedLiteral() {
    #expect(
      ScenarioValidationMessage.nestedConditionalNotAllowed(label: "Phase 4").localized
        == "Phase 4: nested 'conditional' inside another conditional is not allowed (depth-1 rule)."
    )
  }

  // MARK: No-arg case renders via String(localized:) directly

  @Test func invalidYAMLFormatRendersNoArgLiteral() {
    #expect(ScenarioValidationMessage.invalidYAMLFormat.localized == "Invalid YAML format")
  }

  // MARK: Literals with embedded backticks / escaped quotes stay byte-identical

  @Test func extraDataArrayOfDictPreservesBacktickAndQuotes() {
    #expect(
      ScenarioValidationMessage.extraDataArrayOfDictNotString(key: "teams").localized
        == "Top-level field 'teams': array-of-dict values must all be String. "
        + "Quote non-string values (e.g. `majority: \"1\"`).")
  }

  // MARK: Extension-file (out-of-original-5-scope) cases

  @Test func eventInjectProbabilityOutOfRangeOrdersArgs() {
    #expect(
      ScenarioValidationMessage.eventInjectProbabilityOutOfRange(
        label: "Phase 5", probability: "1.5"
      ).localized
        == "Phase 5: probability 1.5 is out of range. Must be between 0.0 and 1.0 inclusive.")
  }

  @Test func outputFieldNameInvalidOrdersArgs() {
    #expect(
      ScenarioValidationMessage.outputFieldNameInvalid(label: "Phase 6", name: "感想").localized
        == "Phase 6: output field name '感想' must be an ASCII identifier "
        + "(letters, digits, and underscore, not starting with a digit or underscore). "
        + "Agent text values may be any language.")
  }
}
