import Foundation

/// A copyable prompt for generating YAML scenarios via an external LLM.
///
/// Surfaced by the ScenarioEditor YAML-mode toolbar's "Copy Gen Prompt"
/// affordance. Kept as a free namespace (rather than a static on
/// ``ScenarioEditorViewModel``) so the editor file stays focused on
/// dual-mode state management.
///
/// The phase-type and scoring-logic lists are **generated** from
/// ``PhaseType/allCases`` and ``ScoreCalcLogic/allCases`` through no-default
/// switches (`phaseDescription` / `logicDescription`), so a new case cannot
/// ship without extending this prompt — the compiler-caught arm of the
/// ADR-022 "declare once, projections follow" contract. The one-line
/// descriptions are the only hand-authored part; canonical output field names
/// come from ``ScenarioConventions`` so they never drift from the validator.
/// The full always-current reference lives at ``formatReferenceURL`` (web
/// `format.md`, drift-gated by a separate CI grep), which browse-capable LLMs
/// should prefer; the generated summary here is the offline fallback.
///
/// `nonisolated` because it only reads nonisolated Models enums and builds a
/// string — no UI state — so both the (MainActor) editor callsite and the
/// nonisolated test callsite can read `text` synchronously.
nonisolated enum ScenarioGenerationPrompt {
  /// URL of the complete, always-current format reference (raw Markdown,
  /// LLM-friendly). Kept in sync with the web page by the coverage gate.
  static let formatReferenceURL = "https://pastura.app/docs/scenario/format.md"

  /// The full prompt text, assembled at read time from the canonical enums.
  static var text: String {
    """
    Generate a YAML scenario for Pastura (AI multi-agent simulation).

    The complete format reference is at \(formatReferenceURL) — read it if you
    can open URLs. If you cannot, the summary below is enough to write a valid
    scenario.

    Required top-level structure:

    id: unique_snake_case_id
    language: ja|en   # authoring language; drives Engine output
    name: Scenario Name
    description: Brief description
    agents: <2-10>
    rounds: <1-30>
    context: Shared context for all agents
    personas:
      - name: Agent Name
        description: Character description
    phases:
      - type: <one of the phase types below>
        prompt: Prompt template (LLM phases only)
        output:
          <canonical field>: string

    Phase types:
    \(phaseLines)

    Scoring logics for score_calc (set as `logic:`):
    \(logicLines)

    Output field names are NOT free-form. Use each LLM phase's canonical field
    names exactly as shown above, or the scenario is rejected when saved. Field
    names must be ASCII; field values may be any language.

    Do not add a top-level min_engine_version key. It is not part of the
    scenario schema and a bare integer value fails to load.

    Write all user-facing strings (name, description, context, prompt, template,
    persona name/description) in the language you set.
    """
  }

  /// One generated line per phase type, each carrying its `rawValue`, a short
  /// description, and its canonical output fields (from ``ScenarioConventions``).
  private static var phaseLines: String {
    PhaseType.allCases.map { phase in
      "- \(phase.rawValue): \(phaseDescription(phase))\(fieldSuffix(for: phase))"
    }
    .joined(separator: "\n")
  }

  /// One generated line per scoring logic.
  private static var logicLines: String {
    ScoreCalcLogic.allCases.map { logic in
      "- \(logic.rawValue): \(logicDescription(logic))"
    }
    .joined(separator: "\n")
  }

  /// The `(output: ...)` suffix describing a phase's canonical fields, derived
  /// from ``ScenarioConventions`` so it tracks the commit-time validator.
  private static func fieldSuffix(for phase: PhaseType) -> String {
    if let primary = ScenarioConventions.primaryField(for: phase) {
      if let thought = ScenarioConventions.thoughtField(for: phase) {
        return " (output: \(primary), \(thought))"
      }
      return " (output: \(primary))"
    }
    // No canonical author field. An LLM phase here (narrate today) has an
    // engine-fixed output shape and declares no author `output:` block; a
    // non-LLM phase is a code phase. Deriving from `requiresLLM` (not a
    // hardcoded `.narrate`) keeps a future engine-fixed LLM phase correct.
    return phase.requiresLLM
      ? " (LLM; engine-fixed output, declare no output block)"
      : " (code phase, no output block)"
  }

  // Pure name-mapping switch (one line per phase type). The 14-case count
  // exceeds SwiftLint's cyclomatic threshold but carries no branching logic.
  // swiftlint:disable cyclomatic_complexity
  /// A one-line description per phase type. No `default` case: adding a new
  /// ``PhaseType`` forces a new arm here (the ADR-022 compiler-caught gate).
  private static func phaseDescription(_ phase: PhaseType) -> String {
    switch phase {
    case .speakAll: return "every agent addresses the group"
    case .speakEach: return "agents speak one at a time, each seeing the last"
    case .vote: return "each agent names another agent"
    case .choose:
      return "each agent picks from `options` (add `pairing: round_robin` to pair everyone)"
    case .reflect: return "each agent privately updates a short note"
    case .whisper: return "pairs of agents exchange a private line"
    case .narrate: return "a commentator narrates the round highlight, once per round"
    case .scoreCalc: return "apply a built-in scoring logic (see below)"
    case .assign: return "distribute values from a `source` list (`target: all` or `random_one`)"
    case .eliminate: return "remove the most-voted agent; needs a vote earlier in the round"
    case .summarize: return "emit a recap line from a `template` string"
    case .conditional: return "run `then`/`else` sub-phases based on an `if` expression"
    case .eventInject:
      return "inject a random event string (stored under `as:`, default current_event)"
    case .relationshipUpdate: return "update an affinity matrix from vote and choose history"
    }
  }
  // swiftlint:enable cyclomatic_complexity

  /// A one-line description per scoring logic. No `default` case: adding a new
  /// ``ScoreCalcLogic`` forces a new arm here (the ADR-022 compiler-caught gate).
  private static func logicDescription(_ logic: ScoreCalcLogic) -> String {
    switch logic {
    case .prisonersDilemma: return "cooperate/betray payoff; needs a round_robin choose before it"
    case .voteTally: return "one point per vote received; needs a vote before it"
    case .wordwolfJudge:
      return "did the group vote out the odd-one-out; needs assign target: random_one and a vote"
    case .eventReactive:
      return
        "reward agents whose last choose matched the injected event; needs event_inject before it"
    }
  }
}
