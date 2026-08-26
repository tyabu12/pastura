import Foundation

/// A parameter-carrying description of an ADR-024 semantic-lint finding
/// message.
///
/// This is the ADR-024 linter counterpart of ``ScenarioValidationMessage``:
/// the four `ScenarioSemanticLinter+*.swift` extensions (Ordering, Config,
/// Placeholders, Conditions) build these instead of building user-facing
/// strings inline. Each case is a **portable structured payload** (enum case +
/// typed args, no Foundation), and ``localized`` is the single
/// **platform-specific rendering leaf** that turns a case into the display
/// string embedded in a ``LintFinding/message``.
///
/// This is the message-model split for the KMP Engine port (ADR-023 Stage 3):
/// the cases move to Kotlin `commonMain` 1:1 as a sealed class
/// (`shared/models/.../ScenarioLintMessage.kt`, landing in the same PR), while
/// `localized` becomes an `expect`/`actual` leaf.
///
/// Deliberately a **separate** type from ``ScenarioValidationMessage`` rather
/// than folded into it: the two model different surfaces — a lint finding
/// carries a severity and is collected alongside others for the same
/// scenario, while a validation message is thrown as the sole reason a load
/// or commit-gate check failed. Conflating them would force a shared shape
/// neither surface actually has.
///
/// The rendered text is byte-identical to the pre-refactor Engine literals so
/// `Localizable.xcstrings` keys are unchanged.
nonisolated public enum ScenarioLintMessage: Sendable {
  // MARK: Ordering (ScenarioSemanticLinter+Ordering.swift, R1–R6/R19)
  case eliminateNeedsVote
  case eliminateAfterVote
  case pdNeedsRoundRobinChoose
  case pairwisePayoffNeedsRoundRobinChoose
  case wordwolfNeedsAssignAndVote
  case eventReactiveNeedsEventInject
  case relationshipUpdatePlacement
  case voteTallyNeedsVote

  // MARK: Config (ScenarioSemanticLinter+Config.swift, R7/R8/R9/R17/R18/R20a/R20b)
  case chooseShouldDeclareOptions
  case assignSourceNonempty
  case summarizePairingPlaceholders
  case maxSentencesNoOp
  case pairwisePayoffNoScorableRow
  case pairwisePayoffDeadRow
  case logWindowBelowAgentCount

  // MARK: Placeholders (ScenarioSemanticLinter+Placeholders.swift, R10/R11/R12)
  case unresolvablePlaceholder(token: String)
  case placeholderPhaseAvailability(token: String)
  case perPersonaPlaceholderInSummarize(token: String)

  // MARK: Conditions (ScenarioSemanticLinter+Conditions.swift, R13/R14/R15)
  case singleQuotedLiteralInCondition(token: String)
  case bareIdentifierLooksLikeLiteral(token: String)
  case unknownConditionIdentifier(token: String)

  /// Every rule ID, in declaration order, one per case above. Stands in for
  /// `CaseIterable` — unavailable here because six cases carry an associated
  /// `token: String` value.
  public static let ruleIDs: [String] = [
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
  ]
}

// `nonisolated` on the extension is load-bearing: the enum is a `nonisolated`
// Models type, but a sibling `extension` inherits the project's default
// MainActor isolation unless annotated (`docs/swift-isolation-compile-time-patterns.md`
// Pattern 3), which would break the synchronous `nonisolated` Engine callers.
nonisolated extension ScenarioLintMessage {

  /// Renders the case to its user-facing string.
  ///
  /// The **only** Foundation-touching member — the KMP `expect`/`actual` leaf
  /// (see the type doc). Literals are byte-identical to the pre-refactor
  /// Engine callsites so `Localizable.xcstrings` keys stay stable. No-arg
  /// cases use `String(localized:)` directly (never `String(format:)`, which
  /// would misread a stray `%` in a future literal); the single-`%@`
  /// token-bearing cases use `String(format:)` with exactly one argument.
  ///
  /// **These literals are dual-landed with `ScenarioLintMessage.kt`'s
  /// `render()`** (`shared/models`, ADR-023) — reword here and the Kotlin twin
  /// plus its expected-string pins stay stale *and agree with each other*, so
  /// nothing reddens. No gate covers it: `check-prompt-literal-parity.py` only
  /// looks at `Engine/` + `LLM/` files containing `pickLanguage`, which never
  /// reaches `Models/`.
  public var localized: String {
    switch self {
    case .eliminateNeedsVote:
      return String(
        localized:
          "eliminate-needs-vote: an 'eliminate' phase does nothing without a 'vote' phase in the same round — add a 'vote' phase before it."
      )
    case .eliminateAfterVote:
      return String(
        localized:
          "eliminate-after-vote: this 'eliminate' runs before every 'vote' phase, so it acts on the previous round's stale tally — move it after the 'vote' phase."
      )
    case .pdNeedsRoundRobinChoose:
      return String(
        localized:
          "pd-needs-round-robin-choose: 'prisoners_dilemma' scoring needs a round-robin 'choose' phase earlier in the round to populate pairings, or scores never change — add one before this 'score_calc'."
      )
    case .pairwisePayoffNeedsRoundRobinChoose:
      return String(
        localized:
          "pairwise-payoff-needs-round-robin-choose: 'pairwise_payoff' scoring needs a round-robin 'choose' phase earlier in the round to populate pairings, or scores never change — add one before this 'score_calc'."
      )
    case .wordwolfNeedsAssignAndVote:
      return String(
        localized:
          "wordwolf-needs-assign-and-vote: 'wordwolf_judge' scoring needs both an 'assign' phase with target 'random_one' and a 'vote' phase earlier in the round, or it judges nothing — add the missing phase(s) before this 'score_calc'."
      )
    case .eventReactiveNeedsEventInject:
      return String(
        localized:
          "event-reactive-needs-event-inject: 'event_reactive' scoring needs an earlier 'event_inject' phase with a dictionary event source and the default 'as: current_event', or the favored action is never scored — fix the 'event_inject' before this 'score_calc'."
      )
    case .relationshipUpdatePlacement:
      return String(
        localized:
          "relationship-update-placement: this 'relationship_update' cannot see its vote/choose signals — place it after the producing 'vote'/'choose' phase and before any 'prisoners_dilemma' 'score_calc', with no 'speak'/'choose' phase between the vote and it."
      )
    case .voteTallyNeedsVote:
      return String(
        localized:
          "vote-tally-needs-vote: 'vote_tally' scoring has no 'vote' phase earlier in the round, so it scores nothing or re-adds a stale tally — add a 'vote' phase before this 'score_calc'."
      )
    case .chooseShouldDeclareOptions:
      return String(
        localized:
          "choose-should-declare-options: this 'choose' phase has no 'options' list, so the agent's action is unconstrained free text — add an 'options' list to steer the choice."
      )
    case .assignSourceNonempty:
      return String(
        localized:
          "assign-source-nonempty: this 'assign' phase's source resolves to an empty list, so nothing is assigned (or every agent gets an empty value) — add at least one entry to the referenced source data."
      )
    case .summarizePairingPlaceholders:
      return String(
        localized:
          "summarize-pairing-placeholders: this 'summarize' template references {agent1}-family placeholders, but no round-robin 'choose' phase runs earlier in the round, so the placeholders leak literally into the summary — add a round-robin 'choose' phase before this 'summarize', or remove the pairing placeholders."
      )
    case .maxSentencesNoOp:
      return String(
        localized:
          "max-sentences-no-op: this phase emits no LLM statement, so its 'max_sentences' cap never reaches a prompt and has no effect — remove it, or move it to a phase that emits a statement (speak_all / speak_each / whisper)."
      )
    case .pairwisePayoffNoScorableRow:
      return String(
        localized:
          "pairwise-payoff-no-scorable-row: no 'payoff' row's 'when' tokens match the round-robin 'choose' options, so no pairing is ever scored — add a 'payoff' table whose 'when' rows use the 'choose' option tokens."
      )
    case .pairwisePayoffDeadRow:
      return String(
        localized:
          "pairwise-payoff-dead-row: one or more 'payoff' rows use 'when' tokens that aren't in the round-robin 'choose' options, so those rows never fire — fix the tokens to match the 'choose' options, or remove the unused rows."
      )
    case .logWindowBelowAgentCount:
      return String(
        localized:
          "log-window-below-agent-count: 'log_window' is smaller than the agent count while a 'speak_each' phase is present, so same-round earlier speakers vanish from the addressee pool — raise 'log_window' to at least the agent count."
      )
    case .unresolvablePlaceholder(let token):
      return String(
        format: String(
          localized:
            "unresolvable-placeholder: the placeholder '{%@}' is supplied by no phase, so it leaks into the LLM prompt verbatim — check for a typo or remove it."
        ), token)
    case .placeholderPhaseAvailability(let token):
      return String(
        format: String(
          localized:
            "placeholder-phase-availability: the placeholder '{%@}' is only populated by a producing phase, but none runs earlier in the phase list, so it resolves to an empty value — move the producing phase before this one."
        ), token)
    case .perPersonaPlaceholderInSummarize(let token):
      return String(
        format: String(
          localized:
            "per-persona-placeholder-in-summarize: the per-persona placeholder '{%@}' is never populated in a 'summarize' phase (summaries aren't per-agent), so it leaks literally — remove it or move it to an LLM phase."
        ), token)
    case .singleQuotedLiteralInCondition(let token):
      return String(
        format: String(
          localized:
            "single-quoted-literal-in-condition: the operand %@ is single-quoted, but the condition evaluator treats only double quotes as string literals — it is read as an undefined identifier and the comparison is always false. Use double quotes instead."
        ), token)
    case .bareIdentifierLooksLikeLiteral(let token):
      return String(
        format: String(
          localized:
            "bare-identifier-looks-like-literal: the operand '%@' matches a persona name but is unquoted, so the condition evaluator reads it as an undefined identifier and the comparison is always false — wrap it in double quotes to compare against the name."
        ), token)
    case .unknownConditionIdentifier(let token):
      return String(
        format: String(
          localized:
            "unknown-condition-identifier: '%@' is not a known condition variable (a derived variable, score, persona, extraData key, or engine-injected name), so it resolves to no value at runtime — check for a typo."
        ), token)
    }
  }
}
