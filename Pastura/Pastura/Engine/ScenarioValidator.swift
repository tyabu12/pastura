import Foundation

/// Validates a ``Scenario`` against execution limits before running.
///
/// Enforces agent count (2–10), round count (≤30), estimated inference
/// count (warn >50, error >100), and phase-field semantics (e.g.,
/// assign-phase target/source compatibility) to prevent runaway or
/// misconfigured simulations.
nonisolated public struct ScenarioValidator: Sendable {

  /// Creates a validator.
  public init() {}

  /// The result of scenario validation.
  public struct ValidationResult: Sendable {
    /// Non-fatal warnings (e.g., high inference count).
    let warnings: [String]

    /// The estimated total number of LLM inferences.
    let estimatedInferences: Int
  }

  /// Validates a scenario against execution limits.
  ///
  /// - Parameter scenario: The scenario to validate.
  /// - Returns: A ``ValidationResult`` with any warnings and the inference estimate.
  /// - Throws: ``SimulationError/scenarioValidationFailed(_:)`` if limits are exceeded.
  public func validate(_ scenario: Scenario) throws -> ValidationResult {
    // Language values (ADR-010 D1 / D5 — programmatic-construction path
    // gate, mirrors `ScenarioLoader`'s YAML-parse path).
    if !Scenario.acceptedLanguages.contains(scenario.language) {
      let allowed = Scenario.acceptedLanguages.sorted().joined(separator: ", ")
      throw validationError(.languageNotAccepted(allowed: allowed, got: scenario.language))
    }
    if let simulationLanguage = scenario.simulationLanguage,
      !Scenario.acceptedLanguages.contains(simulationLanguage) {
      let allowed = Scenario.acceptedLanguages.sorted().joined(separator: ", ")
      throw validationError(
        .simulationLanguageNotAccepted(allowed: allowed, got: simulationLanguage))
    }

    // Agent count limits (checked first for clearer error messages)
    if scenario.agentCount < 2 {
      throw validationError(.agentCountBelowMinimum(scenario.agentCount))
    }
    if scenario.agentCount > 10 {
      throw validationError(.agentCountExceedsMaximum(scenario.agentCount))
    }

    // Persona count must match agentCount
    if scenario.personas.count != scenario.agentCount {
      throw validationError(
        .personaCountMismatch(
          personaCount: scenario.personas.count, agentCount: scenario.agentCount))
    }

    // Round count limit
    if scenario.rounds > 30 {
      throw validationError(.roundCountExceedsMaximum(scenario.rounds))
    }

    // Conversation-log window (#907): a prompt-side cap that must keep at least
    // one entry when set. `nil` means "no window" (full log); `0` or negative
    // would silently strip the whole log, so reject it as a misconfiguration.
    if let logWindow = scenario.logWindow, logWindow < 1 {
      throw validationError(.logWindowBelowMinimum(logWindow))
    }

    // Inference count estimation
    let estimated = ScenarioLoader.estimateInferenceCount(scenario)

    if estimated > 100 {
      throw validationError(.estimatedInferencesExceedsMaximum(estimated))
    }

    try validatePhases(scenario)

    var warnings: [String] = []
    if estimated > 50 {
      warnings.append(ScenarioValidationMessage.highInferenceCount(estimated).localized)
    }

    return ValidationResult(warnings: warnings, estimatedInferences: estimated)
  }

  /// Strict validation gate for commit-to-persist callsites
  /// (`ScenarioEditorViewModel.save()`).
  ///
  /// Runs every check `validate(_:)` runs, then adds the canonical
  /// primary-field requirement: every LLM phase must declare its
  /// ``ScenarioConventions/primaryField(for:)`` key in `output:`. The
  /// engine and UI key on those canonical fields, so a scenario that
  /// omits them silently breaks (empty conversation log, blank UI rows,
  /// `options[0]` fallback for choose). Surfacing the error at commit
  /// time keeps already-persisted scenarios runnable while preventing
  /// new ones from entering the database in the broken shape.
  func validateForCommit(_ scenario: Scenario) throws -> ValidationResult {
    let result = try validate(scenario)
    try validateCanonicalFields(scenario)
    return result
  }

  /// Per-phase semantic checks beyond execution-limit validation.
  ///
  /// Covers `assign` target/source shape compatibility and `conditional`
  /// branch well-formedness. Unknown `target` values are caught earlier by
  /// `ScenarioLoader` (compile-time enforced via `AssignTarget`).
  private func validatePhases(_ scenario: Scenario) throws {
    for (index, phase) in scenario.phases.enumerated() {
      try validateOutputFieldNames(in: phase, label: "Phase \(index + 1)")
      try validateMaxSentences(in: phase, label: "Phase \(index + 1)")
      switch phase.type {
      case .assign:
        try validateAssignPhaseShape(
          phase, label: "Phase \(index + 1) (assign)", scenario: scenario)
      case .conditional:
        try validateConditionalPhase(phase, index: index, scenario: scenario, depth: 0)
      case .reflect:
        try validateReflectShape(phase, label: "Phase \(index + 1)")
      case .whisper:
        try validateWhisperShape(phase, label: "Phase \(index + 1)")
      // `.narrate` needs no shape check: its output schema is Engine-fixed
      // (`{ commentary }`, built by `NarrateHandler`), not author-declared, so
      // there is no `output:` block or `logic`/`source`/`target` to validate.
      case .speakAll, .speakEach, .vote, .choose, .scoreCalc, .eliminate, .summarize, .narrate:
        break
      case .relationshipUpdate:
        try validateRelationshipUpdateShape(phase, label: "Phase \(index + 1)")
      case .eventInject:
        try validateEventInjectShape(
          phase, label: "Phase \(index + 1) (event_inject)", scenario: scenario)
      }
    }
  }

  /// Enforces the accepted range (1…6) for a phase's `max_sentences` override
  /// (#881). Called at both traversal sites (`validatePhases` and
  /// `validateBranch`) so a nested `then:` / `else:` sub-phase is checked too.
  /// A `nil` override (the common case) is a no-op. The upper bound doubles as
  /// a latency / JSON-stability guard — the model tops out ~3–4 sentences even
  /// at cap 6 (#881 Stage-0 spike), so higher values are meaningless.
  private func validateMaxSentences(in phase: Phase, label: String) throws {
    guard let value = phase.maxSentences else { return }
    guard (1...6).contains(value) else {
      throw validationError(.maxSentencesOutOfRange(label: label, value: value))
    }
  }

  /// Enforces the conditional-phase invariants that the construction-time
  /// `Phase` initializer cannot express:
  /// - `condition` must be non-empty (empty expression would throw at
  ///   evaluator parse time anyway, but failing fast here is clearer).
  /// - At least one of `thenPhases` / `elsePhases` must be non-empty
  ///   (otherwise the phase is a no-op with extra overhead).
  /// - `depth > 0` blocks nested `.conditional` — the loader has the same
  ///   check on the YAML path, and this covers non-YAML construction (tests,
  ///   editors, future migrations).
  private func validateConditionalPhase(
    _ phase: Phase, index: Int, scenario: Scenario, depth: Int
  ) throws {
    let phaseLabel = "Phase \(index + 1) (conditional)"
    let trimmedCondition = (phase.condition ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    if trimmedCondition.isEmpty {
      throw validationError(.conditionalMissingIf(label: phaseLabel))
    }

    // Parse-only pre-flight: malformed `if:` (mismatched parens, dangling
    // combinator, empty operand) surfaces here at scenario-load time
    // rather than mid-simulation when the handler dispatches. Critical
    // for gallery curation — a bad `if:` in a curated scenario would
    // otherwise only fail when a user runs it.
    do {
      try ConditionEvaluator().parse(trimmedCondition)
    } catch let SimulationError.scenarioValidationFailed(message) {
      // Raw interpolation is deliberate here (not a `ScenarioValidationMessage`
      // case): this only prefixes the phase locator onto `message`, an
      // already-rendered string emitted by `ConditionEvaluator.parse`. There is
      // no new translatable literal to extract, so a future i18n sweep skips it.
      throw SimulationError.scenarioValidationFailed("\(phaseLabel): \(message)")
    }

    let thenCount = phase.thenPhases?.count ?? 0
    let elseCount = phase.elsePhases?.count ?? 0
    if thenCount == 0 && elseCount == 0 {
      throw validationError(.conditionalEmptyBranches(label: phaseLabel))
    }

    if depth > 0 {
      throw validationError(.nestedConditionalNotAllowed(label: phaseLabel))
    }

    try validateBranch(
      phase.thenPhases ?? [], parentLabel: phaseLabel, branchLabel: "then",
      scenario: scenario)
    try validateBranch(
      phase.elsePhases ?? [], parentLabel: phaseLabel, branchLabel: "else",
      scenario: scenario)
  }

  /// Recursively validates each sub-phase in a conditional branch.
  ///
  /// Rejects nested `.conditional` (depth-1 rule), `.reflect`, `.whisper`, and
  /// `.relationshipUpdate` (none supported inside a branch in v1), and applies the same semantic checks
  /// we run at the top level — e.g., an `assign` phase with mismatched
  /// target/source shape still errors when buried inside a `then:` or
  /// `else:` branch. `event_inject` is allowed inside a branch (consistent
  /// with assign / score_calc) and gets the same shape-check it would
  /// receive at the top level.
  private func validateBranch(
    _ phases: [Phase], parentLabel: String, branchLabel: String, scenario: Scenario
  ) throws {
    for (subIndex, subPhase) in phases.enumerated() {
      let subLabel = "\(parentLabel) \(branchLabel)[\(subIndex + 1)]"
      try validateOutputFieldNames(in: subPhase, label: subLabel)
      try validateMaxSentences(in: subPhase, label: subLabel)
      if subPhase.type == .conditional {
        throw validationError(.branchNestedConditional(label: subLabel))
      }
      // `reflect` is not supported inside a conditional branch in v1. Reject
      // at load-time validation (mirroring the nested-conditional rule above)
      // so it fails here rather than at `ConditionalHandler` dispatch.
      if subPhase.type == .reflect {
        throw validationError(.branchReflectNotAllowed(label: subLabel))
      }
      // `whisper` is likewise not supported inside a conditional branch in v1
      // (mirrors the reflect rejection above) — it fails here at load-time
      // validation rather than at `ConditionalHandler` dispatch.
      if subPhase.type == .whisper {
        throw validationError(.branchWhisperNotAllowed(label: subLabel))
      }
      // `relationship_update` is likewise not supported inside a conditional
      // branch in v1 (mirrors the reflect/whisper rejections above); it is also
      // omitted from `ConditionalHandler.subHandlers` as a structural backstop.
      if subPhase.type == .relationshipUpdate {
        throw validationError(.branchRelationshipUpdateNotAllowed(label: subLabel))
      }
      // `narrate` is likewise not supported inside a conditional branch in v1
      // (#909): it is omitted from `ConditionalHandler.subHandlers`, so without
      // this load-gate rejection a branch-nested narrate would pass all
      // validation and then throw mid-run at dispatch (deferred failure).
      if subPhase.type == .narrate {
        throw validationError(.branchNarrateNotAllowed(label: subLabel))
      }
      if subPhase.type == .assign {
        try validateAssignPhaseShape(subPhase, label: subLabel, scenario: scenario)
      }
      if subPhase.type == .eventInject {
        try validateEventInjectShape(subPhase, label: subLabel, scenario: scenario)
      }
    }
  }

  /// Requires reflect phases to declare the canonical `note` output at the
  /// RUN gate (`validate`), not just the commit gate.
  ///
  /// Other LLM phases run schema-less in degraded-but-visible form (their
  /// primary text lands in the conversation log as empty prose), but a
  /// reflect phase without `note` is a pure no-op inference — it burns one
  /// call per agent per round and stores nothing, with no user-visible
  /// symptom to debug from. Failing fast at the run gate is friendlier.
  /// Reuses the commit-gate message so both gates read identically.
  private func validateReflectShape(_ phase: Phase, label: String) throws {
    if (phase.outputSchema ?? [:])["note"] == nil {
      throw validationError(
        .requiresOutputField(label: label, type: phase.type.rawValue, field: "note"))
    }
  }

  /// Requires whisper phases to declare the canonical `statement` output at the
  /// RUN gate (`validate`), mirroring `validateReflectShape`'s rationale.
  ///
  /// A whisper without `statement` burns one inference per participant per pair
  /// per round and stores nothing user-visible — the same no-op-inference
  /// failure mode reflect guards against, so it fails fast here at the run gate
  /// rather than degrading silently. Reuses the shared missing-field message.
  private func validateWhisperShape(_ phase: Phase, label: String) throws {
    if (phase.outputSchema ?? [:])["statement"] == nil {
      throw validationError(
        .requiresOutputField(label: label, type: phase.type.rawValue, field: "statement"))
    }
  }

  /// Requires relationship_update phases to declare at least one affinity rule
  /// (`vote_against` and/or a non-empty `action_deltas`) at the RUN gate.
  ///
  /// A phase with neither rule is a pure no-op: it reads its vote / choose
  /// signals, applies zero deltas, and injects an empty summary — burning a
  /// phase slot with no user-visible effect (the same no-op failure mode
  /// `validateReflectShape` guards against). Failing fast here surfaces the
  /// authoring mistake instead of a silently inert phase (#910).
  private func validateRelationshipUpdateShape(_ phase: Phase, label: String) throws {
    let hasVoteRule = phase.voteAgainst != nil
    let hasActionRule = !(phase.actionDeltas ?? [:]).isEmpty
    if !hasVoteRule && !hasActionRule {
      throw validationError(
        .relationshipUpdateMissingRule(label: label, type: phase.type.rawValue))
    }
  }

  /// Shared shape-check for assign phases, callable from both the top-level
  /// and the nested branch paths.
  private func validateAssignPhaseShape(
    _ phase: Phase, label: String, scenario: Scenario
  ) throws {
    // Phases without a `source` reference persona indices instead of extraData
    // — nothing to shape-check.
    guard let sourceKey = phase.source else { return }

    // The Visual Editor now round-trips extraData (#129), so a missing key
    // here means the scenario YAML genuinely lacks the referenced field —
    // the assign would silently no-op at runtime. Surface it early.
    guard let sourceValue = scenario.extraData[sourceKey] else {
      throw validationError(.sourceNotFound(label: label, source: sourceKey))
    }
    let effectiveTarget = phase.target ?? .all
    switch effectiveTarget {
    case .all:
      switch sourceValue {
      case .array, .string:
        return
      case .arrayOfDictionaries, .dictionary:
        throw validationError(.assignSourceGroupedForAll(label: label, source: sourceKey))
      }
    case .randomOne:
      switch sourceValue {
      case .arrayOfDictionaries:
        return
      case .array, .string, .dictionary:
        throw validationError(.assignSourceNotGroupedForRandomOne(label: label, source: sourceKey))
      }
    }
  }
}

/// Wraps a ``ScenarioValidationMessage`` in
/// ``SimulationError/scenarioValidationFailed(_:)``, rendering it at the Models
/// layer so the Engine run path stays free of Foundation string localization
/// and formatting (KMP Phase 3.0 port prep, #501).
///
/// File-scope (not a method) so it stays out of `ScenarioValidator`'s
/// `type_body_length` budget; `nonisolated` because top-level functions inherit
/// `MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION` and the `nonisolated`
/// validator calls it synchronously. `private` (file-scope) so it does not
/// collide with `ScenarioLoader`'s same-named helper at module scope — the
/// sibling `ScenarioValidator+*.swift` extensions carry their own copies.
nonisolated private func validationError(_ message: ScenarioValidationMessage) -> SimulationError {
  .scenarioValidationFailed(message.localized)
}
