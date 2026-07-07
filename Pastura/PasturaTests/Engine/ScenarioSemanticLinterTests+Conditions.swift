// Condition-expression rules R13/R14/R15/R16 (ADR-022 D3). Extension of the
// existing suite (not a new @Suite) per .claude/rules/testing.md splitting
// pattern — reuses `linter` / `makeScenario` / `makeEventScenario` from the
// base file / the Ordering split. Rule findings are asserted through the
// `conditionFindings(in:)` group entry point (internal, `@testable`-visible) so
// the condition rules are isolated from the ordering/config/placeholder groups.
import Testing

@testable import Pastura

extension ScenarioSemanticLinterTests {

  // MARK: - R13 single-quoted-literal-in-condition (error)

  @Test func singleQuotedLiteralFiresR13() {
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [conditionalPhase("vote_winner == 'Alice'")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "single-quoted-literal-in-condition")
    #expect(findings.first?.severity == .error)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func doubleQuotedLiteralPassesR13() {
    // The evaluator treats `"` as the string delimiter, so this is a legitimate
    // string comparison — must not trip R13.
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [conditionalPhase("vote_winner == \"Alice\"")])
    #expect(linter.conditionFindings(in: scenario).isEmpty)
  }

  // MARK: - R14 bare-identifier-looks-like-literal (error)

  @Test func barePersonaNameFiresR14() {
    // `A0` is a declared persona name (makeScenario names personas A0…An).
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [conditionalPhase("vote_winner == A0")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "bare-identifier-looks-like-literal")
    #expect(findings.first?.severity == .error)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func unknownNonPersonaEqualityFiresR15NotR14() {
    // An unknown identifier that is NOT a persona name is R15's lane even in an
    // equality comparison — R14 is the persona-name match only.
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [conditionalPhase("vote_winner == foobar")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "unknown-condition-identifier")
    #expect(findings.first?.severity == .warning)
  }

  // MARK: - R15 unknown-condition-identifier (warning)

  @Test func typoDerivedVarFiresR15() {
    // `max_scores` is a typo of the derived `max_score`; `>` is non-equality so
    // R14 never applies.
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [conditionalPhase("max_scores > 5")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "unknown-condition-identifier")
    #expect(findings.first?.severity == .warning)
    #expect(findings.first?.phaseIndex == 0)
  }

  @Test func scoresNonPersonaFiresR15() {
    // `scores.Nobody` — a dotted score access for a non-declared name resolves
    // absent at runtime, so it is unknown (R15), not a valid `scores.<persona>`.
    let scenario = makeScenario(
      agents: 2, rounds: 1, phases: [conditionalPhase("scores.Nobody > 3")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "unknown-condition-identifier")
    #expect(findings.first?.severity == .warning)
  }

  @Test func knownIdentifiersProduceNoFindings() {
    // Derived vars, extraData key (`events`), scores.<persona>, engine-injected
    // reserved names (wolf_name), and a custom `event_inject` `as:` name (storm)
    // are all resolvable → zero findings.
    let scenario = makeEventScenario(
      phases: [
        Phase(type: .eventInject, source: "events", eventVariable: "storm"),
        conditionalPhase("current_round >= total_rounds"),
        conditionalPhase("eliminated_count > active_count"),
        conditionalPhase("max_score >= min_score"),
        conditionalPhase("vote_winner == wolf_name"),
        conditionalPhase("scores.A0 > 3"),
        conditionalPhase("events != \"\""),
        conditionalPhase("storm != \"\"")
      ],
      events: .array(["a"]))
    #expect(linter.conditionFindings(in: scenario).isEmpty)
  }

  // MARK: - Dedup: one token → one finding

  @Test func repeatedUnknownTokenFiresOnce() {
    // `foobar` appears twice (equality + non-equality) but yields one finding.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [conditionalPhase("foobar == vote_winner || foobar > 3")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "unknown-condition-identifier")
  }

  @Test func personaTokenDedupsToSingleR14() {
    // A persona name in two equality comparisons dedups to a single R14 error —
    // never both R14 and R15 on the same token.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [conditionalPhase("A0 == vote_winner || vote_winner == A0")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "bare-identifier-looks-like-literal")
  }

  // MARK: - R16 short-circuit-hidden-typo (info, no-op)

  @Test func shortCircuitTypoCaughtByR15WithoutSeparateR16() {
    // R13–R15 statically resolve BOTH sides of `&&`, so a typo in a
    // runtime-short-circuitable sub-expression is already caught by R15; R16
    // emits no separate finding (documented no-op).
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [conditionalPhase("current_round > 999 && max_scores > 5")])
    let findings = linter.conditionFindings(in: scenario)
    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == "unknown-condition-identifier")
    #expect(!findings.contains { $0.ruleID == "short-circuit-hidden-typo" })
  }

  // MARK: - word_wolf sanity anchor

  @Test func wordWolfConditionsProduceZeroFindings() {
    // The shipped word_wolf conditions (`current_event != ""`,
    // `vote_winner == wolf_name`) against an assign + default event_inject must
    // produce zero condition findings.
    let scenario = makeScenario(
      agents: 2, rounds: 1,
      phases: [
        Phase(type: .assign, target: .randomOne),
        Phase(type: .eventInject),
        conditionalPhase("current_event != \"\""),
        conditionalPhase("vote_winner == wolf_name")
      ])
    #expect(linter.conditionFindings(in: scenario).isEmpty)
  }
}

// A depth-1 `conditional` phase carrying `ifExpr`, with a trivial then-branch
// (a `summarize` with a placeholder-free template so no other rule fires).
private func conditionalPhase(_ ifExpr: String) -> Phase {
  Phase(
    type: .conditional, condition: ifExpr,
    thenPhases: [Phase(type: .summarize, template: "done")])
}
