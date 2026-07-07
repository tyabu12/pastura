import Foundation

/// Placeholder-resolution rules R10/R11/R12 (ADR-022 D3), reading the
/// linter-owned ``PlaceholderAvailability`` map (D4).
///
/// A single scan over each LLM phase's `prompt` (and each `summarize` phase's
/// `template`) extracts `{token}` occurrences and classifies each **once**, so
/// the three rules never double-fire on the same occurrence. Precedence per
/// token: R12 (summarize-specific) > R11 (known but ordered wrong) > R10
/// (unknown):
///
/// - **R12 `per-persona-placeholder-in-summarize`** — a per-persona injected
///   token (`assigned`/`assigned_word`/`my_notes`/`my_whispers`/`relationships`)
///   in a `summarize` template. `SummarizeHandler` never calls the `inject*`
///   helpers, so the braces leak literally. More specific than R10/R11, so it
///   wins for these tokens in `summarize`.
/// - **R11 `placeholder-phase-availability`** — a *known* but producer-gated
///   token (per ``PlaceholderAvailability/producers(of:)``, plus a custom
///   `event_inject` `as:` name / its `__favors` companion) whose producing
///   phase runs at no earlier top-level index → resolves empty/stale.
/// - **R10 `unresolvable-placeholder`** — a token supplied by nothing: not in
///   the phase's supplied set, not an engine-reserved / producer-gated name,
///   not a per-persona reserved key, not a declared `extraData` key, not a
///   custom event variable → leaks verbatim to the LLM (typo or stray token).
///
/// Token shape is `\{[A-Za-z_][A-Za-z0-9_]*\}` — an identifier-only body. This
/// deliberately never matches a JSON example brace (`{"statement": …}`,
/// `{ "vote": … }`, `{…}`), whose first inner character is a quote / space /
/// dot, so prompt-embedded output-format examples don't false-positive.
nonisolated extension ScenarioSemanticLinter {

  /// Matches a `{token}` placeholder whose body is a single identifier. The
  /// identifier-only body is what excludes JSON-example braces (see type doc).
  static let placeholderRegex = try? NSRegularExpression(
    pattern: "\\{([A-Za-z_][A-Za-z0-9_]*)\\}")

  /// Placeholder-resolution findings (R10/R11/R12).
  func placeholderFindings(in scenario: Scenario) -> [LintFinding] {
    let known = globallyKnownTokens(in: scenario)
    var findings: [LintFinding] = []
    for ref in phaseRefs(in: scenario.phases, where: { scannedField(of: $0) != nil }) {
      guard let field = scannedField(of: ref.phase) else { continue }
      for token in placeholderTokens(in: field) {
        if let finding = placeholderFinding(
          token: token, phase: ref.phase, index: ref.topLevelIndex,
          known: known, scenario: scenario) {
          findings.append(finding)
        }
      }
    }
    return findings
  }

  // MARK: - Classification (single-fire)

  /// Classifies one distinct `token` in a phase into at most one finding,
  /// applying the R12 > R11 > R10 precedence (see type doc).
  private func placeholderFinding(
    token: String, phase: Phase, index: Int,
    known: Set<String>, scenario: Scenario
  ) -> LintFinding? {
    // R12: a per-persona token in a summarize template (most specific).
    if phase.type == .summarize, perPersonaTokens.contains(token) {
      return placeholderLintFinding(
        "per-persona-placeholder-in-summarize", .warning, token, index)
    }
    // R10: token supplied by nothing at all — not globally known and not in
    // this phase type's own supplied set.
    let supplied = PlaceholderAvailability.supplied(
      for: phase.type, chooseRoundRobin: phase.pairing == .roundRobin)
    guard known.contains(token) || supplied.contains(token) else {
      return placeholderLintFinding("unresolvable-placeholder", .warning, token, index)
    }
    // R11: known, but producer-gated and no producer runs at an earlier index.
    // Self-supplied tokens (a whisper's `{my_whispers}`, a reflect's
    // `{my_notes}`) are in the phase's own supplied set → never ordered-wrong.
    // `<=` (not `<`): a producer nested in a `conditional` branch anchors to the
    // conditional's index, so a consumer sub-phase ordered after it in the SAME
    // conditional shares that index (gallery kasei_sanso_touban: event_inject →
    // speak_all inside one else-branch). Same-index counts as satisfied — the
    // may-run leniency the ordering rules already apply (`<= idx` there).
    if let producers = producerIndicesForToken(token, in: scenario),
      !producerTypeMatchesPhase(token, phase),
      !producers.contains(where: { $0 <= index }) {
      return placeholderLintFinding("placeholder-phase-availability", .warning, token, index)
    }
    return nil
  }

  // MARK: - Token universes

  /// Every token resolvable *anywhere* in the scenario — engine-reserved names
  /// (`baseInjected` + every producer-gated token), per-persona reserved keys
  /// (`assigned_<name>` / `notes_<name>` / `whispers_<name>` /
  /// `relationships_<name>`), declared `extraData` keys, and each
  /// `event_inject` `as:` name plus its `__favors` companion. Deliberately
  /// generous — availability *ordering* is R11's lane, not R10's — so a token
  /// produced by any phase counts as "known" here even if it appears before
  /// its producer.
  private func globallyKnownTokens(in scenario: Scenario) -> Set<String> {
    var known = PlaceholderAvailability.baseInjected
    known.formUnion(PlaceholderAvailability.producerMap.keys)
    for persona in scenario.personas {
      known.insert("assigned_\(persona.name)")
      known.insert("notes_\(persona.name)")
      known.insert("whispers_\(persona.name)")
      known.insert("relationships_\(persona.name)")
    }
    known.formUnion(scenario.extraData.keys)
    for ref in phaseRefs(in: scenario.phases, where: { $0.type == .eventInject }) {
      let name = ref.phase.eventVariable ?? EventInjectHandler.defaultVariableName
      known.insert(name)
      known.insert(EventInjectHandler.favoredVariableName(for: name))
    }
    return known
  }

  /// The per-persona injected tokens (`inject{Assigned,Notes,Whispers,Relationships}`)
  /// that only LLM phases write — absent from `summarize`'s supplied set, so
  /// they leak literally there (R12's set).
  private var perPersonaTokens: Set<String> {
    PlaceholderAvailability.perPersonaInjected.union(PlaceholderAvailability.whisperSelfInjected)
  }

  // MARK: - Producer relation

  /// Top-level indices at which `token`'s producer phase runs, or `nil` when
  /// `token` is not producer-gated. Covers both the static ``PlaceholderAvailability``
  /// producer map and a scenario-specific custom `event_inject` `as:` variable
  /// (and its `__favors` companion).
  private func producerIndicesForToken(_ token: String, in scenario: Scenario) -> Set<Int>? {
    if let types = PlaceholderAvailability.producers(of: token) {
      return producerIndices(in: scenario.phases) { types.contains($0.type) }
    }
    let eventIndices = producerIndices(in: scenario.phases) {
      isEventInjectProducing(token, phase: $0)
    }
    return eventIndices.isEmpty ? nil : eventIndices
  }

  /// Whether `phase`'s own type produces `token` (self-supply): a `whisper`
  /// referencing `{my_whispers}` or a `reflect` referencing `{my_notes}` reads
  /// its own in-phase value, so R11 must not gate it on an *earlier* producer.
  private func producerTypeMatchesPhase(_ token: String, _ phase: Phase) -> Bool {
    PlaceholderAvailability.producers(of: token)?.contains(phase.type) ?? false
  }

  /// Whether an `event_inject` `phase` writes `token` — its resolved `as:`
  /// variable (`eventVariable ?? "current_event"`) or that variable's
  /// `__favors` companion.
  private func isEventInjectProducing(_ token: String, phase: Phase) -> Bool {
    guard phase.type == .eventInject else { return false }
    let name = phase.eventVariable ?? EventInjectHandler.defaultVariableName
    return token == name || token == EventInjectHandler.favoredVariableName(for: name)
  }

  // MARK: - Field scanning

  /// The template field scanned for placeholders: a `summarize` phase's
  /// `template`, or any LLM phase's `prompt`. `nil` (skip) for code phases and
  /// empty fields.
  private func scannedField(of phase: Phase) -> String? {
    let field = phase.type == .summarize ? phase.template : phase.prompt
    guard let field, !field.isEmpty else { return nil }
    return field
  }

  /// The distinct identifier bodies of every `{token}` in `field` (deduped so
  /// a repeated occurrence yields a single finding).
  private func placeholderTokens(in field: String) -> Set<String> {
    guard let regex = Self.placeholderRegex else { return [] }
    let range = NSRange(field.startIndex..., in: field)
    var tokens: Set<String> = []
    for match in regex.matches(in: field, range: range) {
      if let captured = Range(match.range(at: 1), in: field) {
        tokens.insert(String(field[captured]))
      }
    }
    return tokens
  }

  // MARK: - Findings

  /// Builds a placeholder finding with its token-interpolated fix-hint message.
  private func placeholderLintFinding(
    _ ruleID: String, _ severity: LintSeverity, _ token: String, _ index: Int
  ) -> LintFinding {
    LintFinding(
      ruleID: ruleID, severity: severity,
      message: placeholderMessage(ruleID, token: token), phaseIndex: index)
  }

  /// The user-facing fix-hint message for a placeholder `ruleID`, naming the
  /// offending `{token}`. Catalog `ja` fill is a later item.
  private func placeholderMessage(_ ruleID: String, token: String) -> String {
    switch ruleID {
    case "unresolvable-placeholder":
      return String(
        format: String(
          localized:
            "unresolvable-placeholder: the placeholder '{%@}' is supplied by no phase, so it leaks into the LLM prompt verbatim — check for a typo or remove it."
        ), token)
    case "placeholder-phase-availability":
      return String(
        format: String(
          localized:
            "placeholder-phase-availability: the placeholder '{%@}' is only populated by a producing phase, but none runs earlier in the phase list, so it resolves to an empty value — move the producing phase before this one."
        ), token)
    default:
      return String(
        format: String(
          localized:
            "per-persona-placeholder-in-summarize: the per-persona placeholder '{%@}' is never populated in a 'summarize' phase (summaries aren't per-agent), so it leaks literally — remove it or move it to an LLM phase."
        ), token)
    }
  }
}
