import Foundation

/// Silently-inert configuration rules R7/R8/R9/R17/R18 (ADR-024 D3).
///
/// Unlike the ordering rules (`ScenarioSemanticLinter+Ordering.swift`), these
/// rules don't compare producer/consumer phase indices — each phase (or the
/// scenario as a whole, for R17) is inert on its own terms because of a
/// missing/empty field, an out-of-place field (a `max_sentences` on a code
/// phase, for R18), or because a *different* producer relation (a round-robin
/// `choose` gating pairing-placeholder resolution, for R9) never ran earlier.
/// R9/R18 reuse the same "producer inside a `conditional` branch counts as
/// present at the conditional's index" imprecision documented on the ordering
/// rules.
nonisolated extension ScenarioSemanticLinter {

  /// Silently-inert-configuration findings (R7/R8/R9/R17/R18/R20a/R20b).
  func configFindings(in scenario: Scenario) -> [LintFinding] {
    chooseOptionsFindings(in: scenario.phases)
      + assignSourceFindings(in: scenario.phases, scenario: scenario)
      + summarizePairingFindings(in: scenario.phases)
      + logWindowFindings(in: scenario)
      + maxSentencesNoOpFindings(in: scenario.phases)
      + payoffTokenFindings(in: scenario.phases)
  }

  // MARK: - R7 choose-should-declare-options (warning)

  /// A `choose` phase with nil/empty `options` leaves the action unconstrained
  /// — `ChooseHandler.validateAction` returns the raw model output verbatim
  /// when `options` is empty, and `PromptBuilder` has no option list to steer
  /// the model with. Uniformly `.warning` (never escalated) — with `options`
  /// absent the prompt wording may still elicit the intended values, so
  /// "wrong" is probable, not statically provable (unlike R2's empty
  /// `pairings`).
  private func chooseOptionsFindings(in phases: [Phase]) -> [LintFinding] {
    phaseRefs(in: phases, where: { $0.type == .choose && ($0.options ?? []).isEmpty })
      .map { configFinding("choose-should-declare-options", .warning, at: $0.topLevelIndex) }
  }

  // MARK: - R8 assign-source-nonempty (error)

  /// An `assign` phase whose source resolves to an empty list assigns nothing
  /// (`target: random_one`) or `""` to every agent (`target: all` with an
  /// empty array) — `AssignHandler`'s per-target branches both no-op on an
  /// empty collection. Mirrors `AssignHandler`'s shape branches exactly
  /// rather than duplicating `ScenarioValidator.validateAssignPhaseShape`'s
  /// shape errors (missing key / mismatched shape stay that gate's lane):
  /// this rule only adds the emptiness check on top of an already-resolved,
  /// correctly-shaped source.
  private func assignSourceFindings(in phases: [Phase], scenario: Scenario) -> [LintFinding] {
    phaseRefs(
      in: phases, where: { $0.type == .assign && isAssignSourceEmpty($0, scenario: scenario) }
    )
    .map { configFinding("assign-source-nonempty", .error, at: $0.topLevelIndex) }
  }

  /// Whether an `assign` phase's resolved source is empty for its `target`
  /// mode. Returns `false` (no finding) when the source is missing or shaped
  /// incompatibly with `target` — those are `ScenarioValidator`'s errors, not
  /// this rule's to duplicate.
  private func isAssignSourceEmpty(_ phase: Phase, scenario: Scenario) -> Bool {
    guard let sourceKey = phase.source, let sourceValue = scenario.extraData[sourceKey] else {
      return false
    }
    switch phase.target ?? .all {
    case .randomOne:
      guard case .arrayOfDictionaries(let topics) = sourceValue else { return false }
      return topics.isEmpty
    case .all:
      switch sourceValue {
      case .array(let items):
        return items.isEmpty
      case .string:
        // A single-string source is a legitimate `.all` shape — never empty
        // in the "nothing to iterate" sense `AssignHandler.assignAll` cares
        // about (ADR-024 Rule-precision notes).
        return false
      case .arrayOfDictionaries, .dictionary:
        return false
      }
    }
  }

  // MARK: - R9 summarize-pairing-placeholders (warning)

  /// A `summarize` phase whose template references any `{agent1}`-family
  /// token without a round-robin `choose` phase earlier in the round: those
  /// tokens are only populated in `SummarizeHandler`'s per-pairing branch
  /// (gated on `state.pairings` being non-empty, which only a round-robin
  /// `choose` populates), so the braces leak literally into the summary text.
  private func summarizePairingFindings(in phases: [Phase]) -> [LintFinding] {
    let roundRobinChoose = producerIndices(in: phases) {
      $0.type == .choose && $0.pairing == .roundRobin
    }
    return phaseRefs(
      in: phases,
      where: { $0.type == .summarize && containsPairingPlaceholder($0.template) }
    )
    .filter { ref in !roundRobinChoose.contains(where: { $0 <= ref.topLevelIndex }) }
    .map { configFinding("summarize-pairing-placeholders", .warning, at: $0.topLevelIndex) }
  }

  /// Whether `template` references any pairing-only token
  /// (`PlaceholderAvailability.pairingInjected`: `agent1`/`action1`/`agent2`/
  /// `action2`/`score1`/`score2`).
  private func containsPairingPlaceholder(_ template: String?) -> Bool {
    guard let template else { return false }
    return PlaceholderAvailability.pairingInjected.contains { template.contains("{\($0)}") }
  }

  // MARK: - R17 log-window-below-agent-count (warning)

  /// `log_window < agentCount` with a `speak_each` phase present truncates
  /// same-round earlier speakers out of the addressee pool the accumulating
  /// `speak_each` prompt reads (documented in `.claude/rules/engine.md`, not
  /// enforced anywhere at load time until now). Scenario-level finding
  /// (`phaseIndex: nil`) — the mismatch is between two scenario-wide fields,
  /// not any single phase.
  private func logWindowFindings(in scenario: Scenario) -> [LintFinding] {
    guard let logWindow = scenario.logWindow, logWindow < scenario.agentCount else { return [] }
    guard hasSpeakEach(in: scenario.phases) else { return [] }
    return [
      LintFinding(
        ruleID: "log-window-below-agent-count", severity: .warning,
        message: configMessage("log-window-below-agent-count"), phaseIndex: nil)
    ]
  }

  /// Whether any `speak_each` phase is present, top-level or nested in a
  /// `conditional` branch (may-run counts as present, same as the ordering
  /// rules' producer check).
  private func hasSpeakEach(in phases: [Phase]) -> Bool {
    !phaseRefs(in: phases, where: { $0.type == .speakEach }).isEmpty
  }

  // MARK: - R18 max-sentences-no-op (warning)

  /// A `max_sentences` set on a phase that emits no LLM statement is a silent
  /// no-op: it is parsed, round-tripped, and serialized, but never reaches a
  /// prompt. The brevity bullet it feeds is emitted only by
  /// `PromptBuilder.buildAnswerRules`, which is called from `buildSystemPrompt`
  /// — reached solely by the six `requiresLLM` handlers. So `requiresLLM`
  /// is exactly the "cap reaches the prompt" predicate, and its inverse is the
  /// provable no-op set. Reusing the existing no-default exhaustive switch
  /// (`PhaseType.requiresLLM`) keeps a single source of truth: a new phase type
  /// forces a decision there and R18 follows automatically. `reflect` is
  /// **excluded** (it is `requiresLLM`) even though its cap semantics are fuzzy
  /// (it emits a `note`, not a `statement`) — the bullet is still emitted, so
  /// it is not a *silent* no-op. Uniformly `.warning` — never blocks a run.
  private func maxSentencesNoOpFindings(in phases: [Phase]) -> [LintFinding] {
    phaseRefs(in: phases, where: { $0.maxSentences != nil && !$0.type.requiresLLM })
      .map { configFinding("max-sentences-no-op", .warning, at: $0.topLevelIndex) }
  }

  // MARK: - R20a pairwise-payoff-no-scorable-row (error) / R20b dead-row (warning)

  /// R20a/R20b (ADR-024 § Amendment 2026-07-17): a `pairwise_payoff` `payoff`
  /// table whose `when` tokens are checked against the round-robin `choose`
  /// options that populate its pairings. A `when` token outside the option set
  /// can never match a real (canonicalized) action, so its row is dead.
  ///
  /// - **R20a** (`.error`): *no* row is satisfiable (incl. an absent/empty
  ///   `payoff:`) → every pairing scores nothing, a guaranteed no-op.
  /// - **R20b** (`.warning`): some rows fire but at least one is dead → the
  ///   phase still scores; leaving combinations unlisted is a legitimate choice.
  ///
  /// Skipped when no options-bearing round-robin `choose` precedes: R19 owns the
  /// "no round-robin choose" case and R7 owns "choose with no options", so R20
  /// has no closed set to check and must not double-report.
  private func payoffTokenFindings(in phases: [Phase]) -> [LintFinding] {
    let chooseOptions = roundRobinChooseOptions(in: phases)
    return phaseRefs(in: phases, where: { $0.type == .scoreCalc && $0.logic == .pairwisePayoff })
      .compactMap { payoffFinding(for: $0, chooseOptions: chooseOptions) }
  }

  /// Round-robin `choose` phases carrying a non-empty `options` list, paired with
  /// the top-level index their pairings anchor to (a branch choose counts at its
  /// conditional's index — the may-run imprecision shared with the ordering rules).
  private func roundRobinChooseOptions(in phases: [Phase]) -> [(index: Int, options: Set<String>)] {
    var result: [(index: Int, options: Set<String>)] = []
    for (index, phase) in phases.enumerated() {
      for candidate in [phase] + branchPhases(of: phase)
      where candidate.type == .choose && candidate.pairing == .roundRobin {
        let options = candidate.options ?? []
        if !options.isEmpty { result.append((index, Set(options))) }
      }
    }
    return result
  }

  /// The R20a/R20b finding for one `pairwise_payoff` `score_calc`, or `nil` when
  /// it has no options-bearing round-robin `choose` producer (R19/R7 territory)
  /// or every row is satisfiable.
  private func payoffFinding(
    for ref: PhaseRef, chooseOptions: [(index: Int, options: Set<String>)]
  ) -> LintFinding? {
    let idx = ref.topLevelIndex
    guard
      let options = chooseOptions.filter({ $0.index <= idx })
        .max(by: { $0.index < $1.index })?.options
    else { return nil }
    let rows = ref.phase.payoff ?? []
    let satisfiable = rows.filter {
      $0.when.count == 2 && options.contains($0.when[0]) && options.contains($0.when[1])
    }
    if satisfiable.isEmpty {
      return configFinding("pairwise-payoff-no-scorable-row", .error, at: idx)
    }
    if satisfiable.count < rows.count {
      return configFinding("pairwise-payoff-dead-row", .warning, at: idx)
    }
    return nil
  }

  // MARK: - Shared

  /// Builds the single-element findings array for a config `ruleID`,
  /// resolving its fix-hint message via ``configMessage(_:)``.
  private func configFinding(
    _ ruleID: String, _ severity: LintSeverity, at idx: Int
  ) -> LintFinding {
    LintFinding(ruleID: ruleID, severity: severity, message: configMessage(ruleID), phaseIndex: idx)
  }

  /// The user-facing fix-hint message for a config `ruleID` (one sentence
  /// naming the rule + a concrete fix).
  private func configMessage(_ ruleID: String) -> String {
    switch ruleID {
    case "choose-should-declare-options":
      return String(
        localized:
          "choose-should-declare-options: this 'choose' phase has no 'options' list, so the agent's action is unconstrained free text — add an 'options' list to steer the choice."
      )
    case "assign-source-nonempty":
      return String(
        localized:
          "assign-source-nonempty: this 'assign' phase's source resolves to an empty list, so nothing is assigned (or every agent gets an empty value) — add at least one entry to the referenced source data."
      )
    case "summarize-pairing-placeholders":
      return String(
        localized:
          "summarize-pairing-placeholders: this 'summarize' template references {agent1}-family placeholders, but no round-robin 'choose' phase runs earlier in the round, so the placeholders leak literally into the summary — add a round-robin 'choose' phase before this 'summarize', or remove the pairing placeholders."
      )
    case "max-sentences-no-op":
      return String(
        localized:
          "max-sentences-no-op: this phase emits no LLM statement, so its 'max_sentences' cap never reaches a prompt and has no effect — remove it, or move it to a phase that emits a statement (speak_all / speak_each / whisper)."
      )
    case "pairwise-payoff-no-scorable-row":
      return String(
        localized:
          "pairwise-payoff-no-scorable-row: no 'payoff' row's 'when' tokens match the round-robin 'choose' options, so no pairing is ever scored — add a 'payoff' table whose 'when' rows use the 'choose' option tokens."
      )
    case "pairwise-payoff-dead-row":
      return String(
        localized:
          "pairwise-payoff-dead-row: one or more 'payoff' rows use 'when' tokens that aren't in the round-robin 'choose' options, so those rows never fire — fix the tokens to match the 'choose' options, or remove the unused rows."
      )
    default:
      return String(
        localized:
          "log-window-below-agent-count: 'log_window' is smaller than the agent count while a 'speak_each' phase is present, so same-round earlier speakers vanish from the addressee pool — raise 'log_window' to at least the agent count."
      )
    }
  }
}
