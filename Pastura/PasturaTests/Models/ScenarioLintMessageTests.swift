import Testing

@testable import Pastura

/// Locks ``ScenarioLintMessage/localized`` rendering to the byte-identical
/// strings the four `ScenarioSemanticLinter+*.swift` extensions emitted before
/// this message-model split. One rendering test per group (Ordering / Config /
/// Placeholders / Conditions), including both token-bearing groups with a
/// token containing a quote and a `%` sign, plus a `ruleIDs` coverage pin.
/// English base locale (CI default).
@Suite(.timeLimit(.minutes(1)))
struct ScenarioLintMessageTests {

  // MARK: Ordering (no-arg cases)

  @Test func eliminateNeedsVoteRendersLiteral() {
    #expect(
      ScenarioLintMessage.eliminateNeedsVote.localized
        == "eliminate-needs-vote: an 'eliminate' phase does nothing without a 'vote' phase "
        + "in the same round — add a 'vote' phase before it.")
  }

  @Test func voteTallyNeedsVoteRendersLiteral() {
    // The `orderingMessage` `default:` arm's rule.
    #expect(
      ScenarioLintMessage.voteTallyNeedsVote.localized
        == "vote-tally-needs-vote: 'vote_tally' scoring has no 'vote' phase earlier in the "
        + "round, so it scores nothing or re-adds a stale tally — add a 'vote' phase before "
        + "this 'score_calc'.")
  }

  // MARK: Config (no-arg cases)

  @Test func chooseShouldDeclareOptionsRendersLiteral() {
    #expect(
      ScenarioLintMessage.chooseShouldDeclareOptions.localized
        == "choose-should-declare-options: this 'choose' phase has no 'options' list, so the "
        + "agent's action is unconstrained free text — add an 'options' list to steer the "
        + "choice.")
  }

  @Test func logWindowBelowAgentCountRendersLiteral() {
    // The `configMessage` `default:` arm's rule.
    #expect(
      ScenarioLintMessage.logWindowBelowAgentCount.localized
        == "log-window-below-agent-count: 'log_window' is smaller than the agent count while "
        + "a 'speak_each' phase is present, so same-round earlier speakers vanish from the "
        + "addressee pool — raise 'log_window' to at least the agent count.")
  }

  // MARK: Placeholders (token-bearing — %@ substitution)

  @Test func unresolvablePlaceholderInterpolatesToken() {
    #expect(
      ScenarioLintMessage.unresolvablePlaceholder(token: "typo_token").localized
        == "unresolvable-placeholder: the placeholder '{typo_token}' is supplied by no phase, "
        + "so it leaks into the LLM prompt verbatim — check for a typo or remove it.")
  }

  @Test func perPersonaPlaceholderInSummarizeInterpolatesQuoteAndPercentToken() {
    // The `placeholderMessage` `default:` arm's rule. Token contains an
    // embedded quote and a `%` — proves the substitution is not itself run
    // through a second `String(format:)` pass (which would misread `%`).
    #expect(
      ScenarioLintMessage.perPersonaPlaceholderInSummarize(token: "my\"notes%1").localized
        == "per-persona-placeholder-in-summarize: the per-persona placeholder "
        + "'{my\"notes%1}' is never populated in a 'summarize' phase (summaries aren't "
        + "per-agent), so it leaks literally — remove it or move it to an LLM phase.")
  }

  // MARK: Conditions (token-bearing — %@ substitution)

  @Test func singleQuotedLiteralInConditionInterpolatesToken() {
    #expect(
      ScenarioLintMessage.singleQuotedLiteralInCondition(token: "'Alice'").localized
        == "single-quoted-literal-in-condition: the operand 'Alice' is single-quoted, but "
        + "the condition evaluator treats only double quotes as string literals — it is "
        + "read as an undefined identifier and the comparison is always false. Use double "
        + "quotes instead.")
  }

  @Test func unknownConditionIdentifierInterpolatesQuoteAndPercentToken() {
    // The `conditionMessage` `default:` arm's rule. Token contains an embedded
    // quote and a `%` for the same reason as the Placeholders case above.
    #expect(
      ScenarioLintMessage.unknownConditionIdentifier(token: "weird\"name%2").localized
        == "unknown-condition-identifier: 'weird\"name%2' is not a known condition variable "
        + "(a derived variable, score, persona, extraData key, or engine-injected name), so "
        + "it resolves to no value at runtime — check for a typo.")
  }

  // MARK: ruleIDs coverage

  @Test func ruleIDsHasExactlyTwentyOneEntries() {
    #expect(ScenarioLintMessage.ruleIDs.count == 21)
    #expect(Set(ScenarioLintMessage.ruleIDs).count == 21)
  }

  /// Pins the declaration order the doc comment promises — the Kotlin twin
  /// hand-copies this list in the same order, so a Swift-side reorder must
  /// redden here rather than only in `shared/models`.
  @Test func ruleIDsAreInDeclarationOrder() {
    #expect(
      ScenarioLintMessage.ruleIDs == [
        "eliminate-needs-vote",
        "eliminate-after-vote",
        "pd-needs-round-robin-choose",
        "pairwise-payoff-needs-round-robin-choose",
        "wordwolf-needs-assign-and-vote",
        "event-reactive-needs-event-inject",
        "relationship-update-placement",
        "vote-tally-needs-vote",
        "choose-should-declare-options",
        "assign-source-nonempty",
        "summarize-pairing-placeholders",
        "max-sentences-no-op",
        "pairwise-payoff-no-scorable-row",
        "pairwise-payoff-dead-row",
        "log-window-below-agent-count",
        "unresolvable-placeholder",
        "placeholder-phase-availability",
        "per-persona-placeholder-in-summarize",
        "single-quoted-literal-in-condition",
        "bare-identifier-looks-like-literal",
        "unknown-condition-identifier"
      ])
  }

  @Test func everyMessageStartsWithItsOwnRuleID() {
    let byRuleID: [String: ScenarioLintMessage] = [
      "eliminate-needs-vote": .eliminateNeedsVote,
      "eliminate-after-vote": .eliminateAfterVote,
      "pd-needs-round-robin-choose": .pdNeedsRoundRobinChoose,
      "pairwise-payoff-needs-round-robin-choose": .pairwisePayoffNeedsRoundRobinChoose,
      "wordwolf-needs-assign-and-vote": .wordwolfNeedsAssignAndVote,
      "event-reactive-needs-event-inject": .eventReactiveNeedsEventInject,
      "relationship-update-placement": .relationshipUpdatePlacement,
      "vote-tally-needs-vote": .voteTallyNeedsVote,
      "choose-should-declare-options": .chooseShouldDeclareOptions,
      "assign-source-nonempty": .assignSourceNonempty,
      "summarize-pairing-placeholders": .summarizePairingPlaceholders,
      "max-sentences-no-op": .maxSentencesNoOp,
      "pairwise-payoff-no-scorable-row": .pairwisePayoffNoScorableRow,
      "pairwise-payoff-dead-row": .pairwisePayoffDeadRow,
      "log-window-below-agent-count": .logWindowBelowAgentCount,
      "unresolvable-placeholder": .unresolvablePlaceholder(token: "t"),
      "placeholder-phase-availability": .placeholderPhaseAvailability(token: "t"),
      "per-persona-placeholder-in-summarize": .perPersonaPlaceholderInSummarize(token: "t"),
      "single-quoted-literal-in-condition": .singleQuotedLiteralInCondition(token: "t"),
      "bare-identifier-looks-like-literal": .bareIdentifierLooksLikeLiteral(token: "t"),
      "unknown-condition-identifier": .unknownConditionIdentifier(token: "t")
    ]
    #expect(byRuleID.count == 21)
    for ruleID in ScenarioLintMessage.ruleIDs {
      let message = byRuleID[ruleID]
      #expect(message?.localized.hasPrefix("\(ruleID): ") == true)
    }
  }
}
